; Base address of the VIA chip in the system. The VIA is only
; necessary if you
; - want to use the trace (TW/TQ/TS) functions in SMON
; and/or
; - want to use the VIA UART driver
; If neither of these applies, set the VIA address to 0
VIA = $6000

; Highest address of installed RAM - all RAM is assumed to be
; in one consecutive range from 0-RAMTOP
RAMTOP = $3FFF

; main CPU clock rate (used for UART timing)
CPU_CLOCK_RATE  = 1000000

; Currently supported UART options are:
;   6522: MOS 6522 (VIA)
;   6551: MOS 6551 or WDC 65C51N (ACIA)
;   6850: Motorola MC6850 UART
UART_TYPE = 6551
                
;;; ------------------------------------------------------------------

VIA_DRB  = VIA +  0    ; VIA port B data register
VIA_DRA  = VIA +  1    ; VIA port A data register
VIA_DDRB = VIA +  2    ; VIA port B data direction register
VIA_DDRA = VIA +  3    ; VIA port A data direction register
VIA_T1CL = VIA +  4    ; VIA timer 1 counter low register
VIA_T1CH = VIA +  5    ; VIA timer 1 counter high register
VIA_T1LL = VIA +  6    ; VIA timer 1 latch low register
VIA_T1LH = VIA +  7    ; VIA timer 1 latch high register
VIA_T2CL = VIA +  8    ; VIA timer 2 counter low register
VIA_T2CH = VIA +  9    ; VIA timer 2 counter low register
VIA_SR   = VIA + 10    ; VIA shift register
VIA_ACR  = VIA + 11    ; VIA peripheral control register
VIA_PCR  = VIA + 12    ; VIA peripheral control register
VIA_IFR  = VIA + 13    ; VIA interrupt flag register
VIA_IER  = VIA + 14    ; VIA interrupt enable register
