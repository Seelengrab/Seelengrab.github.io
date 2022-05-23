#include <avr/io.h>
#include <util/delay.h>

#define MS_DELAY 3000

int main (void) {
	DDRB |= _BV(DDB1);

	while(1) {
		//PORTB |= _BV(PORTB1);

		_delay_ms(MS_DELAY);

		PORTB &= ~_BV(PORTB1);

		_delay_ms(MS_DELAY);
	}
}
