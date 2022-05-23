#!/bin/env julia

if length(ARGS) != 1
    println(stderr, "Usage: ./build.jl <infile>")
    exit(1)
end

import Pkg
Pkg.activate(".")

include("arduino.jl")

function build(@nospecialize(fun), @nospecialize(types))
    outfile = replace(ARGS[1], r".jl" => ".o")
    @info "Output will be: '$outfile'"
    obj = build_obj(fun, types)

    @info "Writing output to '$outfile'"
    open(joinpath(@__DIR__, "output", outfile), "w") do io
        write(io, obj)
    end

    exit(0)
end

#include(ARGS[1])

#build(main, Tuple{})
