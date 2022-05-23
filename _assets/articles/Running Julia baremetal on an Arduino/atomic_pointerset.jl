import Pkg # hide
Pkg.activate(@__DIR__) # hide

include("arduino.jl") # hide
const DDRB  = Ptr{UInt8}(36) # 0x25, but julia only provides conversion methods for `Int`
const PORTB = Ptr{UInt8}(37) # 0x26

# The bits we're interested in are the same bit as in the datasheet
#                76543210
const DDB1   = 0b00000010
const PORTB1 = 0b00000010

function main_atomic()
    ddrb = unsafe_load(PORTB)
    Core.Intrinsics.atomic_pointerset(DDRB, ddrb | DDB1, :sequentially_consistent)

    while true
        pb = unsafe_load(PORTB)
        Core.Intrinsics.atomic_pointerset(PORTB, pb | PORTB1, :sequentially_consistent) # enable LED

        for _ in 1:500000
            # busy loop
        end

        pb = unsafe_load(PORTB)
        Core.Intrinsics.atomic_pointerset(PORTB, pb & ~PORTB1, :sequentially_consistent) # disable LED

        for _ in 1:500000
            # busy loop
        end
    end
end
builddump(main_atomic, Tuple{}) # hide
