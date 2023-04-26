;;; This code was taken and adapted from the VIC-20 kernal RS232 routines,
;;; using the commented disassembly from Lee Davidson:
;;; https://www.mdawson.net/vic20chrome/vic20/docs/kernel_disassembly.txt
;;;
;;; This code assumes that the VIA interrupt output is connected to the CPU's
;;; IRQ input pin.
;;; 
;;; Note that the bit timings assume a 1Mhz clock. To use a different clock
;;; speed, adapt the values in the baud rate table at the bottom of this file.
;;;

;;; if DATAPORT=0, DATABIT=x:
;;;    VIA serial TX (output) pin : CA2 (39)
;;;    VIA serial RX (input)  pin : CA1 (40) _and_ PAx (2+x) (must connect RX signal to both pins!)
;;; if DATAPORT=1, DATABIT=x:
;;;    VIA serial TX (output) pin : CB2 (19)
;;;    VIA serial RX (input)  pin : CB1 (18) _and_ PBx (10+x) (must connect RX signal to both pins!)
DATAPORT   = 0          ; 0=use port A (CA1, CA2, PAx), 1=use port B (CB1, CB2, PBx)
DATABIT    = 0          ; data bit (0 or 7) to use for RX input from selected port

;;; serial parameters (with a 1MHz clock, baud rates above 1200 may cause data corruption on receive)
BAUDRATE   = 8          ; 1=50, 2=75, 3=110, 4=134.5, 5=150, 6=300, 7=600, 8=1200, 9=1800, 10=2400, 11=3600
PARITY     = 0          ; 0=none, 1=odd, 3=even, 5=mark, 7=space
STOPBITS   = 1          ; 1 or 2
DATABITS   = 8          ; 5, 6, 7 or 8

;;; serial port buffer memory location and size
RXBUF      = $0334      ; memory location of RX buffer
RXBUFLEN   = 8          ; length of RX buffer (0 means 256)
TXBUF      = $03FC      ; memory location of TX buffer
TXBUFLEN   = 4          ; length of TX buffer (0 means 256)

;;; pins used for serial port
 .if DATAPORT==1
Cx1CTRL    = $10        ; VIA PCR CB1 control bit (input edge control)
Cx2CTRL    = $20        ; VIA PCR CB2 control bit (output value control)
Cx1FLAG    = $10        ; VIA IER CB1 interrupt enable bit
DDRxREG    = VIA_DDRB   ; VIA DDRB register
DRxREG     = VIA_DRB    ; VIA DRB register
 .else
Cx1CTRL    = $01        ; VIA PCR CA1 control bit (input edge control)
Cx2CTRL    = $02        ; VIA PCR CA2 control bit (output value control)
Cx1FLAG    = $02        ; VIA IER CA1 interrupt enable bit
DDRxREG    = VIA_DDRA   ; VIA DDRA register
DRxREG     = VIA_DRA    ; VIA DRA register
 .endif
 
 .if DATABIT != 0 && DATABIT != 7
        .err "DATABIT must be 0 or 7!"
 .endif
                
;;; variables used in RS232 code
RXBYTE	   = $92	; receiver byte buffer/assembly location
RXCNT	   = $95	; receiver bit count in
RXBIT	   = $96	; receiver input bit temp storage
RXSBIT	   = $98	; receiver start bit check flag (inverted, 0 means start bit received)
RXPBIT	   = $9A	; receiver parity bit storage
RXBUFPTR   = $A0	; RX buffer pointer (two sequential bytes)
TXBYTE     = $9B	; transmitter byte buffer/disassembly location
TXCNT	   = $9F	; transmitter bit count out
TXBIT	   = $BF	; transmitter next bit to be sent        
TXPBIT	   = $C0	; parity byte
TXBUFPTR   = $A2        ; TX buffer pointer (two sequential bytes)
TMP        = $97        ; temporary storage
REGCTRL	   = $0293 	; pseudo 6551 control register
REGCMD 	   = $0294	; pseudo 6551 command register
REGSTAT	   = $0297	; RS232 status register
NBITS	   = $0298	; number of bits to be sent/received
BITTL	   = $0299	; time of one bit cell low byte
BITTH	   = $029A	; time of one bit cell high byte
RXBUFEND   = $029B	; index to Rx buffer end
RXBUFSTART = $029C	; index to Rx buffer start
TXBUFSTART = $029D	; index to Tx buffer start
TXBUFEND   = $029E	; index to Tx buffer end

 .if VIA==0
   .err "Need VIA to use VIA UART"
 .endif

;***********************************************************************************;
;
; open RS232


UAINIT: ;; pseudo UART control register:
        ;; bit    7: stop bits: 0=1 stop bit, 1=2 stop bits
        ;; bits 6-5: word length: 00=8 bits, 01=7 bits, 10=6 bits, 11=5 bits
        ;; bit    4: not used
        ;; bits 3-0: baud rate: 0001=50, 0010=75, 0011=110, 0100=134.5, 0101=150, 0110=300, 0111=600
        ;;                      1000=1200, 1001=1800, 1010=2400, 1011=3600
        LDA     #(BAUDRATE + ((8-DATABITS)*32) + ((STOPBITS-1)*128))
        STA     REGCTRL           ; set pseudo UART control register
        ;; pseudo UART command register:
        ;; bits 7-5: parity: xx0=none, 001=odd, 011=even, 101=mark, 111=space
        ;; bits 4-0: not used
        LDA     #(PARITY*32)
        STA     REGCMD          ; set pseudo UART command register
        SEI                     ; prevent interrupts
        LDA	#$7F		; disable all VIA interrupts
	STA	VIA_IER		; on VIA 1 IER
	LDA	#$40		; set T1 free run, T2 clock ?2, SR disabled, latches disabled
	STA	VIA_ACR 	; set VIA 1 ACR
	LDA	#~Cx1CTRL	; Cx2 high, Cx1 -ve edge
	STA	VIA_PCR		; set VIA 1 PCR
	LDA	DDRxREG         ; get VIA 1 DDRx
        AND	#~(1<<DATABIT) & $FF ; set bit 7 as input
	STA	DDRxREG         ; set VIA 1 DDRx
	LDY	#$00		; clear index
	STY	REGSTAT		; clear RS232 status byte
        LDX	#$09		; set bit count to 9 (8 data + 1 stop bit)
	LDA	#$20		; mask for 8 or 6 data bits
	BIT	REGCTRL		; test pseudo 6551 control register
	BEQ	LF031		; branch if 8 or 6 bits
	DEX			; else decrement count
LF031:  BVC	LF035		; branch if 8 or 7 bits
	DEX			; else decrement count ..
	DEX			; .. to 7 or 5 data bits
LF035:  STX	NBITS		; save bit count
	LDA	REGCTRL		; get pseudo 6551 control register
	AND	#$0F		; mask 0000 xxxx, baud rate
        ASL			; * 2
	TAX			; copy to index
	LDA	BRTAB-2,X	; get timer constant low byte
	ASL			; * 2
	TAY			; copy to Y
	LDA	BRTAB-1,X	; get timer constant high byte
	ROL			; * 2
	PHA			; save it
	TYA			; get timer constant low byte back
	ADC	#$C8		; + $C8, carry cleared by previous ROL
	STA	BITTL		; save bit cell time low byte
	PLA			; restore high  byte
	ADC	#$00		; add carry
	STA	BITTH		; save bit cell time high byte
LF51B:  LDA     #0              ; initialize send and receive buffer pointers
        STA	RXBUFEND
	STA	RXBUFSTART
	STA	TXBUFEND
	STA	TXBUFSTART
        LDA     #<RXBUF         ; set RX buffer address
        STA     RXBUFPTR
        LDA     #>RXBUF
        STA     RXBUFPTR+1
        LDA     #<TXBUF         ; set TX buffer address
        STA     TXBUFPTR
        LDA     #>TXBUF
        STA     TXBUFPTR+1
        LDA     #<UAIRQ         ; set interrupt handler address
        STA     $0314
        LDA     #>UAIRQ
        STA     $0315
        JSR     LF05B           ; prepare to receive a byte
        CLI                     ; allow interrupts
        RTS

;***********************************************************************************;
;
; Send byte to UART, wait until UART is ready to transmit
; A, X and Y register contents remain unchanged

UAPUTW: STA     TMP             ; save data byte
        PHA
        TXA
        PHA
        TYA
        PHA
        LDA     TMP             ; get data byte back
        LDY     TXBUFEND        ; get index to Tx buffer end in Y
        LDX	TXBUFEND	; get index to Tx buffer end in X
	INX			; + 1
        .if TXBUFLEN>0
        CPX     #TXBUFLEN       ; have we reached TXBUFLEN?
        BNE     UAPL1           ; jump if not
        LDX     #0              ; wrap to 0
        .endif
UAPL1:  CPX	TXBUFSTART	; compare with index to Tx buffer start
        BEQ     UAPL1           ; wait if buffer full
        STX	TXBUFEND	; set new Tx buffer end
        STA	(TXBUFPTR),Y	; store data byte in buffer (using previous index)
	SEI                     ; prevent interrupts
        BIT	VIA_IER		; test VIA 1 IER
	BVS	LF102		; branch if T1 already enabled
        LDA	BITTL		; get baud rate bit time low byte
	STA	VIA_T1CL	; set VIA 1 T1C_l
	LDA	BITTH		; get baud rate bit time high byte
	STA	VIA_T1CH	; set VIA 1 T1C_h
	LDA	#$C0		; enable T1 interrupt
	STA	VIA_IER		; set VIA 1 IER
	JSR	LEFEE		; setup next RS232 Tx byte
LF102:  CLI                     ; allow interrupts
        PLA
        TAY
        PLA
        TAX
        PLA
        RTS

;***********************************************************************************;
;
; Get received byte from UART, result returned in A,
; returns A=0 if no character available for reading
; X and Y register contents remain unchanged

UAGET:  STY     TMP             ; save Y
        LDY	RXBUFSTART	; get index to Rx buffer start
	CPY	RXBUFEND	; compare with index to Rx buffer end
	BNE	UAGW2 		; if not empty, get byte from buffer and exit
        LDY     TMP             ; restore Y
        LDA	#$00		; return null
	RTS

;***********************************************************************************;
;
; Get received byte from UART, result returned in A,
; waits until a received character is available
; X and Y register contents remain unchanged
        
UAGETW: STY     TMP             ; save Y
        LDY	RXBUFSTART	; get index to Rx buffer start
UAGW1:  CPY	RXBUFEND	; compare with index to Rx buffer end
	BEQ	UAGW1 		; wait if buffer empty
UAGW2:  LDA	(RXBUFPTR),Y	; get byte from Rx buffer
        INY                     ; increment index
        .if RXBUFLEN>0
        CPY     #RXBUFLEN       ; have we reached RXBUFLEN?
        BNE     UAGW3           ; jump if not
        LDY     #0              ; wrap to 0
        .endif
UAGW3:  STY     RXBUFSTART      ; set new Rx buffer start
        LDY     TMP             ; restore Y
	RTS

;***********************************************************************************;
;
; RS232 interrupt handler

UAIRQ:  LDA	VIA_IFR		; get VIA 1 IFR
	BPL	LFEFF		; if no interrupt restore registers and exit
	AND	VIA_IER 	; AND with VIA 1 IER (mask out disabled interrupts)
	TAX			; copy to X
        LDA	VIA_IER		; get VIA 1 IER
	ORA	#$80		; set enable bit, this bit should be set according to the
				; Rockwell 6522 datasheet but clear acording to the MOS
				; datasheet. best to assume it's not in the state required
				; and set it so
	PHA			; save to re-enable interrupts
	LDA	#$7F		; disable all interrupts
	STA	VIA_IER		; set VIA 1 IER
	TXA			; get active interrupts back
	AND	#$40		; mask T1 interrupt
	BEQ	LFF02		; branch if not T1 interrupt

        ;; handle VIA T1 interrupt (TX)
	LDA	#~(Cx1CTRL|Cx2CTRL)	; Cx2 low, Cx1 -ve edge
	ORA	TXBIT		; OR RS232 next bit to send, sets Cx2 high if set
	STA	VIA_PCR		; set VIA 1 PCR
	LDA	VIA_T1CL	; get VIA 1 T1C_l
	PLA			; restore interrupt enable byte to restore previously enabled interrupts
	STA	VIA_IER		; set VIA 1 IER
	JSR	LEFA3		; call RS232 Tx routine
LFEFF:  JMP	LFF56		; restore registers and exit interrupt

LFF02:  TXA			; get active interrupts back
	AND	#$20		; mask T2 interrupt
	BEQ	LFF2C		; branch if not T2 interrupt

        ;; handle VIA T2 interrupt (RX)
	LDA	DRxREG  	; get VIA 1 DRx
	AND	#(1<<DATABIT)	; mask RS232 data in
	STA	RXBIT		; save received bit
	LDA	VIA_T2CL	; get VIA 1 T2C_l
	SBC	#$16		; ?
	ADC	BITTL		; add baud rate bit time low byte
	STA	VIA_T2CL	; set VIA 1 T2C_l
	LDA	VIA_T2CH	; get VIA 1 T2C_h
	ADC	BITTH		; add baud rate bit time high byte
	STA	VIA_T2CH	; set VIA 1 T2C_h
	PLA			; restore interrupt enable byte to restore previously enabled interrupts
	STA	VIA_IER		; set VIA 1 IER, restore interrupts
	JSR	LF036		; call RS232 Rx routine
	JMP	LFF56		; restore registers and exit interrupt

        ;; handle VIA Cx1 interrupt (RX start bit)
LFF2C:  TXA			; get active interrupts back
	AND	#Cx1FLAG	; mask Cx1 interrupt, Rx data bit transition
	BEQ	LFEFF		; if no bit restore registers and exit interrupt
	LDA	REGCTRL		; get pseudo 6551 control register
	AND	#$0F		; clear non baud bits
        ASL			; *2, 2 bytes per baud count
	TAX			; copy to index
	LDA	BRTAB-2,X	; get baud count low byte
	STA	VIA_T2CL	; set VIA 1 T2C_l
	LDA	BRTAB-1,X	; get baud count high byte
	STA	VIA_T2CH	; set VIA 1 T2C_h
	LDA	DRxREG          ; read VIA 1 DRx, clear interrupt flag
	PLA			; restore interrupt enable byte to restore previously enabled interrupts
	ORA	#$20		; enable T2 interrupt
	AND	#~Cx1FLAG       ; disable Cx1 interrupt
	STA	VIA_IER		; set VIA 1 IER
	LDX	NBITS		; get number of bits to be sent/received
	STX	RXCNT		; set receiver bit count

        ;; exit interrupt handler
LFF56:  PLA			; pull Y
	TAY			; restore Y
	PLA			; pull X
	TAX			; restore X
	PLA			; restore A
	RTI        

;***********************************************************************************;
;
; RS232 TX timer interrupt subroutine

LEFA3:  LDA	TXCNT		; get RS232 bit count
	BEQ	LEFEE           ; if zero go setup next RS232 Tx byte and return
	BMI	LEFE8           ; if -ve go do stop bit(s) else bit count is non zero and +ve
	LSR	TXBYTE		; shift RS232 output byte buffer
	LDX	#$00            ; set $00 for bit = 0
	BCC	LEFB0           ; branch if bit was 0
	DEX			; set $FF for bit = 1
LEFB0:  TXA                     ; copy bit to A
	EOR	TXPBIT		; EOR with RS232 parity byte
	STA	TXPBIT		; save RS232 parity byte
	DEC	TXCNT		; decrement RS232 bit count
	BEQ	LEFBF		; if RS232 bit count now zero go do parity bit
        ;; save bit and exit
LEFB9:  TXA			; copy bit to A
	AND	#Cx2CTRL	; mask for Cx2 control bit
	STA	TXBIT		; save RS232 next bit to send
	RTS
        
        ;; do RS232 parity bit, enters with RS232 bit count = 0
LEFBF:  LDA	#$20		; mask 00x0 0000, parity enable bit
	BIT	REGCMD 		; test pseudo 6551 command register
	BEQ	LEFDA		; branch if parity disabled
	BMI	LEFE4		; branch if fixed mark or space parity
	BVS	LEFDE		; branch if even parity else odd parity
	LDA	TXPBIT		; get RS232 parity byte
	BNE	LEFCF		; if parity not zero leave parity bit = 0
LEFCE:  DEX			; make parity bit = 1
LEFCF:  DEC	TXCNT		; decrement RS232 bit count, 1 stop bit
	LDA	REGCTRL		; get pseudo 6551 control register
	BPL	LEFB9		; if 1 stop bit save parity bit and exit else two stop bits ..
	DEC	TXCNT		; decrement RS232 bit count, 2 stop bits
	BNE	LEFB9		; save bit and exit, branch always
        
        ;; parity is disabled so the parity bit becomes the first,
        ;; and possibly only, stop bit. to do this increment the bit
	;; count which effectively decrements the stop bit count.
LEFDA:  INC	TXCNT		; increment RS232 bit count, = -1 stop bit
	BNE	LEFCE		; set stop bit = 1 and exit
	;; do even parity
LEFDE:  LDA	TXPBIT		; get RS232 parity byte
	BEQ	LEFCF		; if parity zero leave parity bit = 0
	BNE	LEFCE		; else make parity bit = 1, branch always
        ;; fixed mark or space parity
LEFE4:  BVS	LEFCF		; if fixed space parity leave parity bit = 0
	BVC	LEFCE		; else fixed mark parity make parity bit = 1, branch always
        ;; decrement stop bit count, set stop bit = 1 and exit. $FF is one stop bit, $FE is two stop bits
LEFE8:  INC	TXCNT		; decrement RS232 bit count
	LDX	#$FF		; set stop bit = 1
	BNE	LEFB9		; save stop bit and exit, branch always
        
        ;; setup next RS232 Tx byte
LEFEE:  LDA	#$00		; clear A
	STA	TXPBIT		; clear RS232 parity byte
	STA	TXBIT		; clear RS232 next bit to send
	LDX	NBITS		; get number of bits to be sent/received
	STX	TXCNT		; set RS232 bit count
	LDY	TXBUFSTART	; get index to Tx buffer start
	CPY	TXBUFEND	; compare with index to Tx buffer end
	BEQ	LF021		; if all done go disable T1 interrupt and return
	LDA	(TXBUFPTR),Y	; else get byte from buffer
	STA	TXBYTE		; save to RS232 output byte buffer
        INY                     ; increment index
        .if TXBUFLEN>0
        CPY     #TXBUFLEN       ; have we reached TXBUFLEN?
        BNE     LEFFC           ; jump if not
        LDY     #0              ; wrap to 0
        .endif
LEFFC:  STY     TXBUFSTART      ; set new Tx buffer start
	RTS

        ;; done sending
LF021:  LDA	#$40		; disable T1 interrupt
	STA	VIA_IER		; set VIA 1 IER
	RTS

;***********************************************************************************;
;
; RS232 RX timer interrupt subroutine

LF036:  LDX	RXSBIT		; get start bit check flag
	BNE	LF068		; branch if no start bit received yet
	DEC	RXCNT		; decrement receiver bit count in
	BEQ	LF06F		; branch if complete byte was received
	BMI	LF04D		; branch if this is a stop bit
	LDA	RXBIT		; get received bit
	EOR	RXPBIT		; exclusive or with parity bit
	STA	RXPBIT		; store as new parity bit
 .if DATABIT==7        
	ASL	RXBIT		; shift received bit into carry
 .else        
	LSR	RXBIT		; shift received bit into carry
 .endif
	ROR	RXBYTE		; shift carry into received byte
LF04A:  RTS

        ;; no start bit received (yet)
LF068:  LDA	RXBIT		; get received bit
	BNE	LF05B		; if bit was 1 (no start bit) then go idle
	STA	RXSBIT		; set start bit flag (start bit received)
        LDA     #$00            ; clear received parity bit
        STA     RXPBIT
	RTS
 
        ;; complete byte received (received bit is bit AFTER last data bit)
        ;; if receiving less than 8 data bits, shift received byte accordingly
LF06F:	LDA	RXBYTE		; get assembled byte
        LDX	NBITS		; NBITS is (number of data bits)+1
LF081:  CPX	#$09		; have we shifted enough yet?
	BEQ	LF089		; branch if so
	LSR			; else shift byte
	INX			; increment bit count
	BNE	LF081		; loop, branch always
LF089:  LDY     RXBUFEND        ; get index into Y
        LDX	RXBUFEND        ; get index into X
        INX                     ; increment index
        .if RXBUFLEN>0
        CPX     #RXBUFLEN       ; have we reached RXBUFLEN?
        BNE     LF070           ; jump if not
        LDX     #0              ; wrap to 0
        .endif
LF070:  CPX	RXBUFSTART	; compare with index to Rx buffer start
	BEQ	LF0A2		; if buffer full, go do Rx overrun error
	STX	RXBUFEND	; set new Rx buffer end
	STA	(RXBUFPTR),Y	; save received byte to Rx buffer (using previous index)
	LDA	#$20		; mask 00x0 0000, parity enable bit
	BIT	REGCMD 		; test pseudo 6551 command register
	BEQ	LF04B		; jump if parity is disabled
	BMI	LF04A		; done (ok) if MARK or SPACE parity
	LDA	RXBIT		; get received bit (parity)
	EOR	RXPBIT		; exclusive or with computed parity bit
	BNE	LF09D		; branch if computed parity is odd
	BVS	LF04A		; branch (ok) if EVEN parity expected
	.byte	$2C		; skip next opcode (fall through into parity error)
LF09D:  BVC	LF04A		; branch (ok) if ODD parity expected

        ;; error codes
	LDA	#$01		; set Rx parity error
	.byte	$2C		; skip next 2-byte opcode
LF0A2:  LDA	#$04		; set Rx overrun error
	.byte	$2C		; skip next 2-byte opcode
LF0A5:  LDA	#$80		; set Rx break condition
	.byte	$2C		; skip next 2-byte opcode
LF0A8:  LDA	#$02		; set Rx framing error
	ORA	REGSTAT		; OR with RS232 status byte
	STA	REGSTAT		; save RS232 status byte
                
        ;; prepare to receive next byte
LF05B:  LDA	#$80|Cx1FLAG	; enable Cx1 interrupt
	STA	VIA_IER		; set VIA 1 IER
	STA	RXSBIT		; set start bit check flag (no start bit received)
	LDA	#$20		; disable T2 interrupt
	STA	VIA_IER		; set VIA 1 IER
        STA     RXBYTE          ; zero-out received byte
	RTS

        ;; received bit is expected to be a stop bit (1)
LF04B:  DEC	RXCNT		; decrement receiver bit count in
LF04D:  LDA	RXBIT		; get received bit
	BNE	LF05B		; if bit was 1 then prepare for next byte
LF0B3:  LDA	RXBYTE		; get assembled byte
	BNE	LF0A8		; if non-zero then do frame error
	BEQ	LF0A5		; else do break error (branch always)
        

;***********************************************************************************;
;
; baud rate word is calculated from ..
; (system clock / 2 / baud rate) - 100

; baud rate table
BRTAB:  .word	(CPU_CLOCK_RATE/2/50)-100       ;   50   baud
	.word	(CPU_CLOCK_RATE/2/75)-100 	;   75   baud
	.word	(CPU_CLOCK_RATE/2/110)-100 	;  110   baud
	.word	(CPU_CLOCK_RATE  /269)-100 	;  134.5 baud
	.word	(CPU_CLOCK_RATE/2/150)-100 	;  150   baud
	.word	(CPU_CLOCK_RATE/2/300)-100      ;  300   baud
	.word	(CPU_CLOCK_RATE/2/600)-100      ;  600   baud
	.word	(CPU_CLOCK_RATE/2/1200)-100     ; 1200   baud
	.word	(CPU_CLOCK_RATE/2/1800)-100     ; 1800   baud
	.word	(CPU_CLOCK_RATE/2/2400)-100     ; 2400   baud
	.word	(CPU_CLOCK_RATE/2/3600)-100     ; 3600   baud
