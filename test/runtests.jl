using TrackingTimers
using Test
using Aqua

@testset "TrackingTimers.jl" begin
    # Write your tests here.
end

@testset "Aqua tests" begin
    Aqua.test_all(TrackingTimers; ambiguities=false)
end
