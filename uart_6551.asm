;============================================================================
;
;   6551 Asynchronous Communication Interface Adapter driver for 6502
;   Based on config and xmit delay code from the excellent videos by Adrien Kohlbecker
;   <https://www.youtube.com/@akohlbecker/about>
;   Written by Chris McBrien and David Hansel
;
;============================================================================

; The 65C51 ACIA has some serious bugs (from the datasheet errata):
; 
; Transmitter Parity
; The transmitter of this part functions differently than previous 6551/65C51 devices. For
; all Parity Mode Control (PMC) settings (Bits 7, 6 of the Command Register), the
; transmitter will transmit a MARK (1) for Parity (When enabled with Bit 5 of the
; Command Register set to  1 ). Previous versions would transmit Even, Odd, Mark or
; Space parity depending on the PMC bits.
; 
; Transmitter Data Register Empty
; The W65C51N will not properly set Bit 4 of the Status Register to indicate the
; Transmitter Data Register is empty. Determining when to send the next byte would
; need to be done by using the transmit interrupt or having a software delay loop based
; on the baud rate used.
;
; Also see:
; http://forum.6502.org/viewtopic.php?f=4&t=2543&sid=6c50db0270c03a2ca487dec97666d1f8&start=15#p28935
;
; For this driver those bugs mean the following:
; 1) Only "no parity" setting is supported
; 2) When transmitting we cannot query the ACIA whether it is ready but instead
;    have to use a timed loop to wait until the character is sent
        

; Base memory address of the 6551 ACIA
ACIA_ADDRESS   = $5000

; serial parameters
BAUD_RATE_CTRL = ACIA_CONTROL_BAUD_RATE_9600
BAUD_RATE      = 9600    ; must match the ACIA_CONTROL_BAUD_RATE setting above
DATABITS       = 8       ; 5, 6, 7 or 8
STOPBITS       = 1       ; 1 or 2

        
ACIA_CONTROL_BAUD_RATE_50     = 0b0001
ACIA_CONTROL_BAUD_RATE_75     = 0b0010
ACIA_CONTROL_BAUD_RATE_109_92 = 0b0011
ACIA_CONTROL_BAUD_RATE_134_58 = 0b0100
ACIA_CONTROL_BAUD_RATE_150    = 0b0101
ACIA_CONTROL_BAUD_RATE_300    = 0b0110
ACIA_CONTROL_BAUD_RATE_600    = 0b0111
ACIA_CONTROL_BAUD_RATE_1200   = 0b1000
ACIA_CONTROL_BAUD_RATE_1800   = 0b1001
ACIA_CONTROL_BAUD_RATE_2400   = 0b1010
ACIA_CONTROL_BAUD_RATE_3600   = 0b1011
ACIA_CONTROL_BAUD_RATE_4800   = 0b1100
ACIA_CONTROL_BAUD_RATE_7200   = 0b1101
ACIA_CONTROL_BAUD_RATE_9600   = 0b1110
ACIA_CONTROL_BAUD_RATE_19200  = 0b1111
ACIA_CONTROL_BAUD_RATE_115200 = 0b0000

ACIA_COMMAND_DATA_TERMINAL_READY_DEASSERT = 0b0 << 0
ACIA_COMMAND_DATA_TERMINAL_READY_ASSERT   = 0b1 << 0
ACIA_COMMAND_RECEIVER_ECHO_ENABLED  = 0b1 << 4
ACIA_COMMAND_RECEIVER_IRQ_DISABLED  = 0b1 << 1    
ACIA_COMMAND_TRANSMITTER_CONTROL_REQUEST_TO_SEND_ASSERT_INTERRUPT_DISABLED = 0b10 << 2  

ACIA_STATUS_FRAMING_ERROR_DETECTED          = 0b1 << 1
ACIA_STATUS_OVERRUN_HAS_OCCURRED            = 0b1 << 2
ACIA_STATUS_RECEIVER_DATA_REGISTER_FULL     = 0b1 << 3
ACIA_STATUS_DATA_CARRIER_DETECT_HIGH        = 0b1 << 5
ACIA_STATUS_DATA_SET_READY_HIGH             = 0b1 << 6
ACIA_STATUS_INTERRUPT_OCCURRED              = 0b1 << 7

; Memory mapped registers
ACIA_REG_DATA     = ACIA_ADDRESS+0
ACIA_REG_STATUS   = ACIA_ADDRESS+1
ACIA_REG_COMMAND  = ACIA_ADDRESS+2
ACIA_REG_CONTROL  = ACIA_ADDRESS+3

; Transmit delay
ACIA_CHAR_CYCLES = ((DATABITS+STOPBITS+1)*CPU_CLOCK_RATE)/BAUD_RATE


;================================================================================
;
;   ACIA__init - initializes the serial port
;
;   Preparatory Ops: none
;   Returned Values: none
;                    
;   Destroys:        .A, .X, .Y
;
;================================================================================
ACIA__init:
UAINIT:
    ; programmatically reset the chip by writing the status register
    sta ACIA_REG_STATUS

    ; set up the ACIA with baud rate, word length and stop bits defined above
    lda #(BAUD_RATE_CTRL + ((8-DATABITS)*32) + ((STOPBITS-1)*128))
    sta ACIA_REG_CONTROL
        
    ; further set up the ACIA with
    ; - /DTR and /RTS both low
    ; - Receiver and transmitter IRQ off
    ; - Echo mode disabled
    ; - Parity disabled
    lda #(ACIA_COMMAND_DATA_TERMINAL_READY_ASSERT | ACIA_COMMAND_RECEIVER_IRQ_DISABLED | ACIA_COMMAND_TRANSMITTER_CONTROL_REQUEST_TO_SEND_ASSERT_INTERRUPT_DISABLED)
    sta ACIA_REG_COMMAND        
    rts


;================================================================================
;
;   Send a single character to the serial port blocking until character sent
;
;   Preparatory Ops: A.  contains the character to send
;   Returned Values: none
;   Destroys:        none
;
;================================================================================

; because of the 65C51 ACIA TX bug (see top of this file) we must use 
; a timed loop to wait until the 65C51 is finished sending the current character
; (instead of waiting until the ACIA reports that the send register is empty)
UAPUTW:
    sta ACIA_REG_DATA           ; transmit data byte

    ; wait until ACIA is done sending the byte
    pha                         ; save registers
    txa
    pha
    tya
    ldx #<(ACIA_CHAR_CYCLES/9)+1
    ldy #>(ACIA_CHAR_CYCLES/9)+1
L1: nop                         ; these NOPs are here to even out the timing
    nop                         ; for the inner and outer loop (9 cycles each)
L2: dex
    bne L1
    dey
    bne L2
    tay                         ; restore registers
    pla
    tax
    pla
        
    rts
        
    
;================================================================================
;
;   Get a single character from the serial port blocking until character received
;
;   Preparatory Ops: none
;   Returned Values: A.  Received character
;   Destroys:        .A
;
;================================================================================
ACIA__getchar_wait:
UAGETW:
    ; wait until a byte is available
    lda #ACIA_STATUS_RECEIVER_DATA_REGISTER_FULL
.get_char_poll:    
    bit ACIA_REG_STATUS
    beq .get_char_poll
    ; get received byte and return
    lda ACIA_REG_DATA
    rts


;================================================================================
;
;   Get a single character from the serial port non-blocking return 0 is none available
;
;   Preparatory Ops: none
;   Returned    Values:     A.  Received character, or 0
;               Destroys:   A.
;
;================================================================================
ACIA__getchar:
UAGET:
    ; check if byte is available
    lda ACIA_REG_STATUS
    and #ACIA_STATUS_RECEIVER_DATA_REGISTER_FULL
    beq .done
    ; get received byte and return
    lda ACIA_REG_DATA
.done
    rts    
