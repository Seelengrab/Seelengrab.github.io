#####
# utilities
#####

function volatile_store(x::Ptr{UInt8}, v::UInt8)
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
        x % Int16
    )
end

#######
# blink_led
#######

const DDRB  = Ptr{UInt8}(36) # 0x24
const PORTB = Ptr{UInt8}(37) # 0x25

function main()
    # Enable output on our LED pin
    ddrb = unsafe_load(DDRB)
    Core.Intrinsics.atomic_pointerset(DDRB, ddrb | 0b00000010, :sequentially_consistent)
    #volatile_store(DDRB, 0b00000010)

    while true
        # Set LED pin high
        d = unsafe_load(PORTB)
        Core.Intrinsics.atomic_pointerset(PORTB, d | 0b00000010, :sequentially_consistent)
        #volatile_store(PORTB, 0b00000010)

        # Busy loop so we can see the LED on for a bit
        for y in 1:500000
            #keep(y)
        end

        # Set LED pin low
        d = unsafe_load(PORTB)
        Core.Intrinsics.atomic_pointerset(PORTB, d & ~0b00000010, :sequentially_consistent)
        #volatile_store(PORTB, ~0b00000010)

        # Busy loop so we can see the LED off for a bit
        for y in 1:500000
            #keep(y)
        end
    end

    return 0
end
