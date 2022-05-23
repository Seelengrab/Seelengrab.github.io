using GPUCompiler
using LLVM

#####
# Compiler Target
#####

struct Arduino <: GPUCompiler.AbstractCompilerTarget end

GPUCompiler.llvm_triple(::Arduino) = "avr-unknown-unkown"
GPUCompiler.runtime_slug(::GPUCompiler.CompilerJob{Arduino}) = "native_avr-jl_blink"

module StaticRuntime
    # the runtime library
    signal_exception() = return
    malloc(sz) = C_NULL
    report_oom(sz) = return
    report_exception(ex) = return
    report_exception_name(ex) = return
    report_exception_frame(idx, func, file, line) = return
end

struct ArduinoParams <: GPUCompiler.AbstractCompilerParams end

GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:Any,ArduinoParams}) = StaticRuntime
GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{Arduino}) = StaticRuntime
GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{Arduino,ArduinoParams}) = StaticRuntime

function native_job(@nospecialize(func), @nospecialize(types))
    @info "Creating compiler job for '$func($types)'"
    source = GPUCompiler.FunctionSpec(func, Base.to_tuple_type(types), false, GPUCompiler.safe_name(repr(func)))
    target = Arduino()
    params = ArduinoParams()
    GPUCompiler.CompilerJob(target, source, params)
end

function build_ir(job, @nospecialize(func), @nospecialize(types))
    @info "Bulding LLVM IR for '$func($types)'"
    mi, _ = GPUCompiler.emit_julia(job)
    ir, ir_meta = GPUCompiler.emit_llvm(job, mi; libraries=false, deferred_codegen=false, optimize=true, only_entry=false, ctx=JuliaContext())
end

function build_obj(@nospecialize(func), @nospecialize(types))
    job = native_job(func, types)
    ir, ir_meta = build_ir(job, func, types)
    @info "Compiling AVR ASM for '$func($types)'"
    obj, _ = GPUCompiler.emit_asm(job, ir; strip=true, validate=true, format=LLVM.API.LLVMObjectFile)
    obj
end

function builddump(fun, args)
    obj = build_obj(fun, args)
    mktemp() do path, io
        write(io, obj)
        flush(io)
        run(pipeline(`avr-objdump -dr $path`, stdout=joinpath(@__DIR__, "output/$fun.out")))
    end
end
