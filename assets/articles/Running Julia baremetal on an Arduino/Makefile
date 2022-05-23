DEVICE := /dev/ttyACM0
CC := avr-gcc
CFLAGS := -Os -DF_CPU=16000000UL -mmcu=atmega328p -c
LFLAGS := -mmcu=atmega328p

.SUFFIXES:
.SUFFIXES: .c .o
.PHONY: all clean build build-c build-jl flash

%.o: %.c
	$(CC) $(CFLAGS) -o $@ $<

%.elf: %.jl
	julia build.jl $<
	avr-ld -o jl_blink.elf jl_blink.o

%.elf: %.o
	$(CC) $(LFLAGS) -o $@ $<

%.hex: %.elf
	avr-objcopy -O ihex $< $@

build-c: blink_led.hex

build-jl: jl_blink.hex

build: build-jl build-c

flash: $(TARGET)
	avrdude -V -c arduino -p ATMEGA328P -P $(DEVICE) -U flash:w:$<

all: clean build

clean:
	rm -f *.o *.elf *.hex *.disasm
