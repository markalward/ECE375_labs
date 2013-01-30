;***********************************************************
;*
;*	lab4_Tests.asm
;*
;*	Contains unit tests for the lab4 project. Lab 4 should not
;*	be checked in to the github repository until all tests relevant
;*  to the currently written code pass.
;*
;*
;***********************************************************
;*
;*	 Author: Mark Alward
;*	   Date: Jan 29, 2013
;*
;***********************************************************

;-----------------------------------------------------------
;	Test of handler for external interrupt 4. Tests that the 
;	following conditions are met:
;		The value of SREG is the same before and after the interrupt
;		The value of all GPR's is the same before and after the interrupt
;		That PORTB goes through the following sequence when the routine is
;		called:
;			0000xxxx		for 1sec (approx)			(backing up)
;			0010xxxx		for 1sec (approx)			(turning left)
;
;
;

.DEF alarm_prescale = R16
.DEF alarm_maxcountL = R17
.DEF alarm_maxcountH = R18
.DEF alarm_curcountL = R19
.DEF alarm_curcountH = R20
.DEF alarm_funcL = R30
.DEF alarm_funcH = R31

.DSEG
//global variables that hold alarm info
ALARM_FUNC_GLOBAL:	.BYTE 2

.CSEG

.ORG $0000
RJMP INIT

.ORG $0018
RJMP ALARM_INT_HANDLER

.ORG $0045

INIT:
	LDI R16, LOW(RAMEND)
	OUT SPL, R16
	LDI R16, HIGH(RAMEND)
	OUT SPH, R16
	RJMP ALARM_TEST


/*
	A function to test the ALARM function. Toggles an LED on PORTB every 2 seconds
	if everything is working correctly.
*/
ALARM_TEST:
	//setup data direction
	LDI R16, 0xff
	OUT DDRB, R16
	LDI R16, 0
	OUT PORTB, R16

	LDI alarm_prescale, 101
	LDI alarm_maxcountL, 0x7f
	LDI alarm_maxcountH, 0xff
	LDI ZL, low(ALARM_TEST_LISTENER)
	LDI ZH, high(ALARM_TEST_LISTENER)
	RCALL ALARM

ALARM_TEST_LOOP:
	RJMP ALARM_TEST_LOOP

/*
	The listener that is invoked when the alarm goes off.
	Toggles PORTD
*/
ALARM_TEST_LISTENER:
	PUSH R16
	PUSH R17
	IN R16, PORTB
	LDI R17, 0xff
	EOR R16, R17
	OUT PORTB, R16
	POP R17
	POP R16
	RET


/*
	Asynchronously invokes a subroutine specified by the user when a given
	time period has elapsed. Calling this function with a non-zero alarm_maxcount
	overrides any alarm that was previously set and has not yet been triggered.

	Calling this function with both alarm_maxcountL and alarm_maxcountH set to
	zero causes the timer's current count to be returned in alarm_maxcountL and
	alarm_maxcountH. Additionally, the prescale setting is returned in alarm_prescale
	and the function registered to be invoked is returned in alarm_func. No changes
	are made to the scheduled alarm. If no alarm was scheduled, 

	Note: This function should not be called when Timer 1 is being used for
	other purposes elsewhere, b/c this function internally makes use of Timer
	1 and its interrupts.

	Parameters:
		alarm_prescale (R16):		clock prescale constant
		alarm_maxcountL (R17):		maximum number of clock ticks to wait until alarm
		alarm_maxcountH (R18):
		alarm_func:					program memory address of the subroutine to be invoked
									upon alarm expiration

	pseudocode:
		disable interrupts

		if(alarm_maxcount == 0) {
			if(ALARM_FUNC_GLOBAL == 0) {
				return 0 for every field
			}

			return values for each field, getting alarm_func from ALARM_FUNC_GLOBAL
		}

		set timer according to user settings
		setup timer interrupt
		return

		enable interrupts	
*/
ALARM:
	PUSH R21
	PUSH R22

	CLI

	CPI alarm_maxcountL, 0
	IN R21, SREG
	ANDI R21, 0x02

	CPI alarm_maxcountH, 0
	IN R22, SREG
	ANDI R22, 0x02
	AND R21, R22
	//if(alarm_maxcount == 0)
	BRNE ALARM_IF1_END

		LDS R21, ALARM_FUNC_GLOBAL
		CPI R21, 0
		IN R21, SREG
		ANDI R21, 0x02

		LDS R22, (ALARM_FUNC_GLOBAL+1)
		CPI R22, 0
		IN R22, SREG
		ANDI R22, 0x02
		AND R21, R22
		//if(ALARM_FUNC_GLOBAL == 0) return all 0's
		BRNE ALARM_IF2_END
			
			LDI alarm_prescale, 0
			LDI alarm_maxcountL, 0
			LDI alarm_maxcountH, 0
			LDI alarm_curcountL, 0
			LDI alarm_curcountH, 0
			LDI ZL, 0
			LDI ZH, 0
			POP R22
			POP R21
			SEI
			RET
		
		//else return appropriate values for each field
			IN alarm_prescale, TCCR1B
			ANDI alarm_prescale, 0b00000111
			IN alarm_maxcountL, OCR1AL
			IN alarm_maxcountH, OCR1AH
			IN alarm_curcountL, TCNT1L
			IN alarm_curcountH, TCNT1H
			LDS ZH, ALARM_FUNC_GLOBAL
			LDS ZL, (ALARM_FUNC_GLOBAL + 1)

			POP R22
			POP R21
			SEI
			RET
ALARM_IF2_END:
ALARM_IF1_END:

	//sets low bits of WGM for CTC
	LDI R21, 0
	OUT TCCR1A, R21

	//set high bits of WGM for CTC and set prescale
	LDI R21, (1 << WGM13) | (0 << WGM12)
	MOV R22, alarm_prescale
	ANDI R22, 0b00000111
	OR R21, R22
	OUT TCCR1B, R21

	//init TCNT1 to 0
	LDI R21, 0
	OUT TCNT1H, R16
	OUT TCNT1L, R16

	//init OCR1A to user-supplied value
	OUT OCR1AH, alarm_maxcountH
	OUT OCR1AL, alarm_maxcountL

	//set TIMSK to allow interrupt
	IN R21, TIMSK
	ORI R21, (1 << OCIE1A)
	OUT TIMSK, R21

	//set ALARM_FUNC_GLOBAL (high then low)
	STS ALARM_FUNC_GLOBAL, R31
	STS (ALARM_FUNC_GLOBAL+1), R30

	SEI
	POP R22
	POP R21
	RET


/*
	The interrupt handler for the ALARM function. Invokes the function at address
	ALARM_FUNC_GLOBAL, then disables timer 1 and clears the function address at
	ALARM_FUNC_GLOBAL
*/
ALARM_INT_HANDLER:
	PUSH R16
	PUSH ZL
	PUSH ZH
	IN R16, SREG
	PUSH R16

	LDS ZH, ALARM_FUNC_GLOBAL
	LDS ZL, (ALARM_FUNC_GLOBAL+1)
	ICALL

	//disable the timer interrupt
	IN R16, TIMSK
	ANDI R16, ~(1 << OCIE1A)
	OUT TIMSK, R16

	//clear ALARM_FUNC_GLOBAL
	LDI R16, 0
	STS ALARM_FUNC_GLOBAL, R16
	STS (ALARM_FUNC_GLOBAL+1), R16

	POP ZH
	POP ZL
	POP R16
	OUT SREG, R16
	POP R16
	RETI