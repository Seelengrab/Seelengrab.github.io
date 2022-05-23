# This file was generated, do not modify it. # hide
function native_job(@nospecialize(func), @nospecialize(types))
    @info "Creating compiler job for '$func($types)'"
    source = GPUCompiler.FunctionSpec(
                func, # our function
                Base.to_tuple_type(types), # its signature
                false, # whether this is a GPU kernel
                GPUCompiler.safe_name(repr(func))) # the name to use in the asm
    target = Arduino()
    params = ArduinoParams()
    job = GPUCompiler.CompilerJob(target, source, params)
end