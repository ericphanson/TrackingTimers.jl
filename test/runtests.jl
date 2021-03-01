using Test
using Aqua
using Tables
using Transducers

using Distributed
nprocs() > 1 || addprocs(1)

@everywhere using TrackingTimers

@time @testset "Basics + `show`" begin
    t = TrackingTimer()
    @test sprint(show, t) == "TrackingTimer(…)"
    @test occursin("No entries.", sprint(show, MIME"text/plain"(), t))

    TrackingTimers.@timeit t "timeit" sleep(1)
    @test occursin("timeit", sprint(show, MIME"text/plain"(), t))
    TrackingTimers.synchronize!(t) # in case it evaluates the RHS first
    @test Tables.rows(t) == t.results
    @test length(t.results) == 1
    @test t.results[1].pid == 1
end

@time @testset "Distributed" begin
    t = TrackingTimer()

    @everywhere slp(s) = (sleep(s / 100); s)
    slp_t = t(slp)

    slp_t(1)
    @test length(Tables.rows(t)) == 1
    slp_t(2)
    @test length(Tables.rows(t)) == 2

    @test pmap(slp_t, 1:10) == 1:10
    @test length(t.results) == 2 # haven't synchronized yet
    @test length(Tables.rows(t)) == 12 # have synchronized

    pids = Tables.getcolumn(Tables.columns(t), :pid)
    @test pids isa AbstractVector{Int}
    @test 2 ∈ pids
end

@time @testset "Threaded" begin
    t = TrackingTimer()

    sqrt_t = t(sqrt)
    result = @sync [Threads.@spawn sqrt_t(i) for i in 1:10]
    @test fetch.(result) == sqrt.(1:10)
    TrackingTimers.synchronize!(t)
    @test length(t.results) == 10

    tids = Tables.getcolumn(Tables.columns(t), :thread_id)
    @test tids isa AbstractVector{Int}
    @test 2 ∈ tids
end

@time @testset "Transducers" begin
    t = TrackingTimer()
    xs = 1:1000
    sin_t = t(sin)
    t_result = foldxt(+, Map(sin_t), xs)
    tids = Tables.getcolumn(Tables.columns(t), :thread_id)

    @test (1:Threads.nthreads()) ⊆ tids
    @test length(Tables.rows(t)) == length(xs)

    d_result = foldxd(+, Map(sin_t), xs)
    pids = Tables.getcolumn(Tables.columns(t), :pid)
    @test procs() ⊆ pids

    TrackingTimers.synchronize!(t)
    @test length(Tables.rows(t)) == 2 * length(xs) == length(t.results)
end

@time @testset "Tables interface" begin
    t = TrackingTimer()
    xs = 1:10000
    sin_t = t(sin)
    foldxt(+, Map(sin_t), xs)

    @test Tables.istable(t)
    @test Tables.rowaccess(typeof(t))
    @test !Tables.columnaccess(typeof(t))
    TrackingTimers.synchronize!(t) # in case it evaluates the RHS first
    @test Tables.rows(t) == t.results

    col_tbl = Tables.columns(t)
    @test Tables.columnnames(col_tbl) ==
          (:name, :time, :gctime, :n_allocs, :bytes, :thread_id, :pid)
    @test col_tbl.name isa AbstractVector{String}
    @test col_tbl.time isa AbstractVector{Float64}
    @test Tables.getcolumn(col_tbl, :time) == col_tbl.time
end

@time @testset "Aqua tests" begin
    Aqua.test_all(TrackingTimers; ambiguities=false)
end
