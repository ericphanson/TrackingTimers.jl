# TrackingTimers

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://ericphanson.github.io/TrackingTimers.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ericphanson.github.io/TrackingTimers.jl/dev)
[![Build Status](https://github.com/ericphanson/TrackingTimers.jl/workflows/CI/badge.svg)](https://github.com/ericphanson/TrackingTimers.jl/actions)
[![Coverage](https://codecov.io/gh/ericphanson/TrackingTimers.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/ericphanson/TrackingTimers.jl)

Provides a simple utility for collecting timing information from functions even in the presence of parallelism.
Inspired by [TimerOutputs.jl](https://github.com/KristofferC/TimerOutputs.jl), which I recommend for serial code.

`TrackingTimers.@timeit` supports the same API as `TimerOutputs.@timeit`, providing a simple way to store the timing results from executing an expression in a timer object, a `TrackingTimer` (which is the sole export of this package). However, `TrackingTimer`s are very simple; while calls to log to the same timer may be nested, the `TrackingTimer` simply logs each call in a flat table. This makes it easy to support multiprocess and multithreaded code. `TrackingTimer`s supports the Tables.jl interface (as a row table), which provides a simple means for the user to take a closer look at the timing data, and e.g. aggregate over calls to the same function.

`TrackingTimer`s also support a call syntax, allowing one to easily instrument a function, so that any call to the instrumented version of the function automatically logs a timing entry to the timer object. See the examples below.

## Examples

```julia
julia> using TrackingTimers

julia> t = TrackingTimer()
TrackingTimer: 0.00 s since creation (0% measured).
No entries.

julia> TrackingTimers.@timeit t "testing: sleep" sleep(1)

julia> t
TrackingTimer: 1.05 s since creation (96% measured).
      name        time   gctime  n_allocs   allocs    thread ID  proc ID 
─────────────────────────────────────────────────────────────────────────
 testing: sleep  1.00 s      0%         4  128 bytes          1        1

julia> func(x) = x+1
func (generic function with 1 method)

julia> func_inst = t(func)
(::TrackingTimers.InstrumentedFunction{typeof(func)}) (generic function with 1 method)

julia> func_inst(5)
6

julia> t
TrackingTimer: 1.08 s since creation (93% measured).
      name        time   gctime  n_allocs   allocs    thread ID  proc ID 
─────────────────────────────────────────────────────────────────────────
 testing: sleep  1.00 s      0%         4  128 bytes          1        1
 func            0.00 s      0%         0    0 bytes          1        1
```

### Threaded example

```julia
julia> using TrackingTimers, ThreadsX, LinearAlgebra

julia> t = TrackingTimer()

TrackingTimer: 1.14 s since creation (0% measured).
No entries.

julia> xs = 1:2
1:2

julia> expensive_function(i) = norm(big.(randn(i, i)))
expensive_function (generic function with 1 method)

julia> instrumented_fun = t(expensive_function)
(::TrackingTimers.InstrumentedFunction{typeof(expensive_function)}) (generic function with 1 method)

julia> result = ThreadsX.map(instrumented_fun, 1000:100:1500)
6-element Vector{BigFloat}:
 1000.044535870264540807714716029272380072359744688303289140287700941397780730317
 1099.621613467886456092200351321349092989369319781554075855193975305734925337306
 1200.160425251366463083085189603332616730336307297852815966102953629237891121993
 1300.109241847853807385664372197135060201125417086855868596616484800661239594506
 1399.572257779217012297991715825651075215168607390190375753707375897223959998925
 1499.967376120230484827902676300684847759014653732263746767025105628459031638143

julia> t
TrackingTimer: 5.69 s since creation (99% measured).
        name          time   gctime  n_allocs    allocs     thread ID  proc ID 
───────────────────────────────────────────────────────────────────────────────
 expensive_function  1.34 s     72%  37334279    1.999 GiB          2        1
 expensive_function  1.20 s     39%  31436022    1.702 GiB          1        1
 expensive_function  1.15 s     34%  24886121    1.360 GiB          2        1
 expensive_function  0.71 s     18%  15721283  880.679 MiB          1        1
 expensive_function  0.66 s     36%  18870866    1.024 GiB          1        1
 expensive_function  0.58 s     16%  14264890  784.059 MiB          2        1

```

### Distributed example

```julia
julia> using Distributed

julia> addprocs(2)
2-element Vector{Int64}:
 2
 3

julia> @everywhere using TrackingTimers, LinearAlgebra

julia> t = TrackingTimer()
TrackingTimer: 1.13 s since creation (0% measured).
No entries.

julia> @everywhere expensive_function(i) = norm(big.(randn(i, i)))

julia> instrumented_fun = t(expensive_function)
(::TrackingTimers.InstrumentedFunction{typeof(expensive_function)}) (generic function with 1 method)

julia> result = pmap(instrumented_fun, 1000:100:1500)
6-element Vector{BigFloat}:
  999.3400434505995581074342593748743616158636434344468541490681472178697961023743
 1099.00165758571901999414118783850318868603547862200331037349314999751473860877
 1200.665671521870570295977221776311554666404776867075257827116985832523690068542
 1299.098003099051425268090436142914593167431536776385646086568449446658084891494
 1400.026473159472270359947791624394367075116800578307064157908754557301584756459
 1498.256323158788435294406273058988870732250411479016050182811541955477979434318

julia> t
TrackingTimer: 5.70 s since creation (93% measured).
        name          time   gctime  n_allocs    allocs     thread ID  proc ID 
───────────────────────────────────────────────────────────────────────────────
 expensive_function  1.35 s     69%  18000012  995.637 MiB          1        2
 expensive_function  1.11 s     49%  15680012  867.310 MiB          1        3
 expensive_function  1.00 s     31%  13520012  747.834 MiB          1        2
 expensive_function  0.75 s     14%  11520012  637.208 MiB          1        3
 expensive_function  0.70 s     18%   9680012  535.431 MiB          1        3
 expensive_function  0.61 s     13%   8000012  442.505 MiB          1        2
```

## Table interface

Continuing the previous example, we can use the fact that `TimingTracker`'s support
the Tables.jl interface to do further analysis of the results.

```julia
julia> cheap_fn(x) = x+1
cheap_fn (generic function with 1 method)

julia> map(t(cheap_fn), 10:15)
6-element Vector{Int64}:
 11
 12
 13
 14
 15
 16

julia> using DataFrames, Statistics

julia> df = DataFrame(t)
12×7 DataFrame
 Row │ name                time      gctime    n_allocs  bytes       thread_id  pid   
     │ String              Float64   Float64   Int64     Int64       Int64      Int64 
─────┼────────────────────────────────────────────────────────────────────────────────
   1 │ expensive_function  0.612077  0.176828   8000012   464000560          1      2
   2 │ expensive_function  0.701691  0.200751   9680012   561440560          1      3
   3 │ expensive_function  0.748993  0.139915  11520012   668160560          1      3
   4 │ expensive_function  0.99935   0.234239  13520012   784160560          1      2
   5 │ expensive_function  1.11177   0.343141  15680012   909440560          1      3
   6 │ expensive_function  1.34677   0.422423  18000012  1044000560          1      2
   7 │ cheap_fn            1.67e-7   0.0              0           0          1      1
   8 │ cheap_fn            4.1e-8    0.0              0           0          1      1
   9 │ cheap_fn            0.0       0.0              0           0          1      1
  10 │ cheap_fn            4.1e-8    0.0              0           0          1      1
  11 │ cheap_fn            0.0       0.0              0           0          1      1
  12 │ cheap_fn            4.2e-8    0.0              0           0          1      1

julia> combine(groupby(df, :name), :time => mean)
2×2 DataFrame
 Row │ name                time_mean 
     │ String              Float64   
─────┼───────────────────────────────
   1 │ expensive_function   0.920108
   2 │ cheap_fn             4.85e-8

```

Similarly, the timing results can be serialized by e.g. `CSV.write(path, t)` or `Arrow.write(path, t)`, thanks again to the Tables.jl interface.
