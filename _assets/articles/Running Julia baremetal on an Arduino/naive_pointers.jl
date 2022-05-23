import Pkg # hide
Pkg.activate(@__DIR__) # hide

include("arduino.jl") # hide

const DDRB  = Ptr{UInt8}(36) # 0x25, but julia only provides conversion methods for `Int`
const PORTB = Ptr{UInt8}(37) # 0x26

# The bits we're interested in are the same bit 1
#                76543210
const DDB1   = 0b00000010
const PORTB1 = 0b00000010

function main_pointers()
    unsafe_store!(DDRB, DDB1)

    while true
        pb = unsafe_load(PORTB)
        unsafe_store!(PORTB, pb | PORTB1) # enable LED

        for _ in 1:500000
            # busy loop
        end

        pb = unsafe_load(PORTB)
        unsafe_store!(PORTB, pb & ~PORTB1) # disable LED

        for _ in 1:500000
            # busy loop
        end
    end
end
builddump(main_pointers, Tuple{})
open("output/elf_pointers.out", "w") do io # hide
    print(io, escape_string(build_obj(main_pointers, Tuple{}))) # hide
end# hide
