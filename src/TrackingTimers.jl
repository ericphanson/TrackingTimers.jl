module TrackingTimers

export TrackingTimer

using Printf
using Distributed # for myid()
using Tables, PrettyTables

#####
##### Implementation
#####

const TrackingTimerElType = @NamedTuple{name::String,time::Float64,gctime::Float64,
                                        n_allocs::Int,bytes::Int,thread_id::Int,pid::Int}

"""
    TrackingTimer

Stores the results of `@timed` calls in a `RemoteChannel` to provide a
distributed and thread-friendly way to collect timing results. Construct
a `TrackingTimer` by `t = TrackingTimer()`. Populate it by
[`TrackingTimers.@timeit`](@ref) or call `t` on a function (optionally providing a name)
to obtain an `InstrumentedFunction`, which automatically populates `t` with
timing results whenever it is called.

TrackingTimer's support the Tables.jl row table interface. Call `Tables.rows(t)`
to obtain a `Vector{$(TrackingTimerElType)}` of the timing results obtained so far.
Note that this uses a lock (via [`synchronize!`](@ref)) so it should be thread-safe
albeit may cause contention if called from multiple threads simultaneously.

## Example

```julia
julia> using Distributed

julia> addprocs(2);

julia> @everywhere using TrackingTimers

julia> t = TrackingTimer()
TrackingTimer: 1.09 s since creation (0% measured).
No entries.

julia> @everywhere function f(i)
           v = 1:(1000*myid())
           return sum( v .^ (1/π))
       end

julia> f_inst = t(f) # instrument `f` with TrackingTimer `t`
(::TrackingTimers.InstrumentedFunction{typeof(f)}) (generic function with 1 method)

julia> pmap(f_inst, 1:10)
10-element Vector{Float64}:
 17056.850202253918
 29106.968991882364
 29106.968991882364
 17056.850202253918
 17056.850202253918
 29106.968991882364
 17056.850202253918
 29106.968991882364
 17056.850202253918
 29106.968991882364

julia> t
TrackingTimer: 2.54 s since creation (0% measured).
 name   time   gcfraction  n_allocs    allocs    thread ID  proc ID 
────────────────────────────────────────────────────────────────
 f     0.00 s      0%         2  23.516 KiB          1        3
 f     0.00 s      0%         1  15.750 KiB          1        2
 f     0.00 s      0%         2  23.516 KiB          1        3
 f     0.00 s      0%         2  23.516 KiB          1        3
 f     0.00 s      0%         2  23.516 KiB          1        3
 f     0.00 s      0%         2  23.516 KiB          1        3
 f     0.00 s      0%         1  15.750 KiB          1        2
 f     0.00 s      0%         1  15.750 KiB          1        2
 f     0.00 s      0%         1  15.750 KiB          1        2
 f     0.00 s      0%         1  15.750 KiB          1        2
```
"""
struct TrackingTimer
    start_nanosecond::Int64
    chan::RemoteChannel{Channel{TrackingTimerElType}}
    results::Vector{TrackingTimerElType}
    results_lock::ReentrantLock
    function TrackingTimer()
        return new(time_ns(),
                   RemoteChannel(() -> Channel{TrackingTimerElType}(typemax(Int))),
                   TrackingTimerElType[], ReentrantLock())
    end
end

Base.put!(t::TrackingTimer, val) = put!(t.chan, val)

"""
    synchronize!(t::TrackingTimer)

Populates `t.results` with any timing results collected so far.
This uses a lock so it is safe to call from multiple threads, but
may cause contention. Called automatically by `Tables.rows(::TrackingTimer)`.
"""
function synchronize!(t::TrackingTimer)
    lock(t.results_lock)
    try
        while isready(t.chan)
            push!(t.results, take!(t.chan))
        end
    finally
        unlock(t.results_lock)
    end
    return nothing
end

"""
    @timeit(t::TrackingTimer, name, expr)

Evaluates `expr` under `@timed`, storing the results in the [`TrackingTimer`](@ref) `t`.
"""
macro timeit(t, name, expr)
    quote
        local results = @timed $(esc(expr))
        put!($(esc(t)),
             (; name=$(esc(name)), results.time, results.gctime,
              n_allocs=Base.gc_alloc_count(results.gcstats), results.bytes,
              thread_id=Threads.threadid(), pid=myid()))
        results.value
    end
end

#####
##### Tables interface
#####

Tables.istable(::TrackingTimer) = true
function Tables.rows(t::TrackingTimer)
    synchronize!(t)
    return t.results
end
Tables.rowaccess(::Type{TrackingTimer}) = true
Tables.columnaccess(::Type{TrackingTimer}) = false

#####
##### Instrumented functions
#####

# implemented as a callable type to get better error messages
# (i.e. you see `F` explictly, which might be `typeof(f)` telling
# you that `f` is involved).
struct InstrumentedFunction{F} <: Function
    func::F
    t::TrackingTimer
    name::String
end

InstrumentedFunction(f, t) = InstrumentedFunction(f, t, string(repr(f)))

function (inst::InstrumentedFunction)(args...; kwargs...)
    @timeit inst.t inst.name inst.func(args...; kwargs...)
end

"""
    (t::TrackingTimer)(f, name=string(repr(f))) -> InstrumentedFunction

Instruments `f` by the [`TrackingTimer`](@ref) `t` returning an `InstrumentedFunction`.
This function can be used just like `f`, but whenever it is called it stores timing
results in `t`.
"""
(t::TrackingTimer)(f, name=string(repr(f))) = InstrumentedFunction(f, t, name)

#####
##### Display
#####

nt_keys(::Type{NamedTuple{K,V}}) where {K,V} = K

function formatter(tbl)
    return function (v, i, j)
        col = nt_keys(TrackingTimerElType)[j]
        col == :time && return @sprintf("%.2f s", v)
        col == :gctime && return string(@sprintf("%.0f", (v / tbl[i].time) * 100), "%")
        col == :bytes && return Base.format_bytes(v)
        return v
    end
end

one_line_show(io::IO, ::TrackingTimer) = print(io, "TrackingTimer(…)")

Base.show(io::IO, t::TrackingTimer) = one_line_show(io, t)

function Base.show(io::IO, ::MIME"text/plain", t::TrackingTimer)
    get(io, :compact, false) === true && return one_line_show(io, t)
    total_time_in_seconds = (time_ns() - t.start_nanosecond) * 1e-9
    tbl = Tables.rows(t)
    tot_measured_time = isempty(tbl) ? 0.0 : sum(x.time for x in tbl)
    println(io, "TrackingTimer: ", @sprintf("%.2f", total_time_in_seconds),
            " s since creation (",
            @sprintf("%.0f", tot_measured_time / total_time_in_seconds * 100),
            "% measured).")
    if isempty(tbl)
        print(io, "No entries.")
    else
        tbl_sorted = sort(tbl; by=x -> x.time, rev=true)
        pretty_table(io, tbl_sorted,
                     ["name", "time", "gctime", "n_allocs", "allocs", "thread ID",
                      "proc ID"]; newline_at_end=false, formatters=formatter(tbl_sorted),
                     hlines=[1], vlines=[],
                     alignment=[:l, (:r for _ in 1:(length(tbl_sorted[1]) - 1))...],
                     header_alignment=:c)
    end
    return nothing
end

end # module
