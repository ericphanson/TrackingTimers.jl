using TrackingTimers
using Documenter

DocMeta.setdocmeta!(TrackingTimers, :DocTestSetup, :(using TrackingTimers); recursive=true)

makedocs(; modules=[TrackingTimers], authors="Eric P. Hanson",
         repo="https://github.com/ericphanson/TrackingTimers.jl/blob/{commit}{path}#{line}",
         sitename="TrackingTimers.jl",
         format=Documenter.HTML(; prettyurls=get(ENV, "CI", "false") == "true",
                                canonical="https://ericphanson.github.io/TrackingTimers.jl",
                                assets=String[]), pages=["Home" => "index.md"])

deploydocs(; repo="github.com/ericphanson/TrackingTimers.jl", push_preview=true,
           devbranch="main")
