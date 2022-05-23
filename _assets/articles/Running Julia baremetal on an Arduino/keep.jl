import Pkg # hide
Pkg.activate(@__DIR__) # hide

include("arduino.jl") # hide
const DDRB  = Ptr{UInt8}(36)
const PORTB = Ptr{UInt8}(37)
const DDB1   = 0b00000010
const PORTB1 = 0b00000010
const PORTB_none = 0b00000000 # We don't need any other pin - set everything low

function volatile_store!(x::Ptr{UInt8}, v::UInt8)
    return Base.llvmcall(
        """
        %ptr = inttoptr i64 %0 to i8*
        store volatile i8 %1, i8* %ptr, align 1
        ret void
        """,
        Cvoid,
        Tuple{Ptr{UInt8},UInt8},
        x,
        v
    )
end

function keep(x)
    return Base.llvmcall(
        """
        call void asm sideeffect "", "X,~{memory}"(i16 %0)
        ret void
        """,
        Cvoid,
        Tuple{Int16},
        x
)
end

function main_keep()
    volatile_store!(DDRB, DDB1)

    while true
        volatile_store!(PORTB, PORTB1) # enable LED

        for y in Int16(1):Int16(3000)
            keep(y)
        end

        volatile_store!(PORTB, PORTB_none) # disable LED

        for y in Int16(1):Int16(3000)
            keep(y)
        end
    end
end
builddump(main_keep, Tuple{}) # hide
