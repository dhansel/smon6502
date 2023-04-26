;;; ----------------------------------------------------------------------------
;;; ----------------------  C64 KERNAL routines and stubs   --------------------
;;; ----------------------------------------------------------------------------

TERMCOL         = $01           ; cursor column on terminal
STOPFLAG        = $91           ; flag for "STOP" key pressed
LASTRECV        = $93           ; previous received char
ROWLIMIT        = $9C           ; number of rows currently in buffer
TMPBUF          = $9E           ; temporary storage
LASTCOL         = $C8           ; last cursor column for input
ESCFLAG         = $D0           ; ESC sequence flag (shared with CRFLAG)
CRFLAG          = $D0           ; <>0 => there is input ready to read
LINEPTR         = $D1           ; pointer to screen buffer for current line
CSRCOL          = $D3           ; current cursor column
CSRROW          = $D6           ; current cursor row
LASTPRNT        = $D7           ; last character printed to screen

        
        ;; get/set bottom-of-memory address
KRWMEMB:BCC     WMEMB
        LDX     $0281
        LDY     $0282
WMEMB:  STX     $0281
        STY     $0282
        RTS

        ;; get/set top-of-memory address
KRWMEMT:BCC     WMEMT
        LDX     $0283
        LDY     $0284
WMEMT:  STX     $0283
        STY     $0284
        RTS

        ;; set flag for kernal output messages
KMSGFLG:STA     $9D
        RTS

        ;; stub routine for I/O functions
KIOSTUB:LDA     #$05            ; "device not present" error 
        SEC                     ; signal error
KSTUB:  RTS
        
        ;; STOP (FFE1): test stop key (Z set if stop key pressed)
KSTOP:  LDA     STOPFLAG
        CMP     #$7F            ; have STOP flag?
        BEQ     STOPL1          ; jump if so
        JSR     GETIN1
        BEQ     STOPL2          ; done if nothing
        STA     $0277           ; save received character
        INC     $C6
        LDA     STOPFLAG
        CMP     #$7F            ; have STOP flag now?
        BNE     STOPR           ; done if not
STOPL1: LDA     #$FF            ; clear STOP flag
        STA     STOPFLAG
        LDA     #$7F
        CMP     #$7F            ; set Z flag
        RTS
STOPL2: LDA     #$FF            ; clear Z flag
STOPR:  RTS
        
        ;; GETIN (FFE4): get input character (0 if none)
KGETIN: LDA     $C6
        BEQ     GETIN1
        DEC     $C6
        LDA     $0277
        RTS
GETIN1: JSR     UAGET           ; get char from UART, zero if none
        CMP	#$00		; did we receive a character?
        BEQ     GETINR          ; if not, return with 0
        CMP     #27             ; is it ESC (stop)?
        BEQ     SETSF           ; set STOP flag if so
        CMP     #3              ; is it CTRL-C (stop)?
        BEQ     SETSF           ; set STOP flag if so
        JMP     MAPCHR
SETSF:  LDA     #$7F            ; set stop flag
        STA     STOPFLAG
GETINR: RTS

        ;; CHRIN (FFCF): get next input character (read until CR if none)
KCHRIN: TXA                     ; save X
        PHA
        TYA                     ; save Y
        PHA
        LDA     CRFLAG          ; have we received a CR?
        BNE     CHRIN1          ; if yes then get next char
        JSR     GETLIN          ; no => get input from UART until CR
        BCC     CHRIN4          ; jump if there was no input at all
        LDA     #$80            ; now have received CR
        STA     CRFLAG
CHRIN1: LDY     CSRCOL          ; current cursor (read) position
        CPY     LASTCOL         ; have we reached the end?
        BCS     CHRIN3          ; jump if so
        LDA     (LINEPTR),Y     ; get next character
        INC     CSRCOL          ; move cursor position
        JMP     CHRIN2          ; done
CHRIN3: LDA     #$00            ; turn off CR flag
        STA     CRFLAG
        INC     CSRCOL          ; still increment CSRCOL
CHRIN4: LDA     #13             ; return CR
CHRIN2: STA     TMPBUF   
        PLA                     ; restore Y
        TAY
        PLA                     ; restor X
        TAX
        LDA     TMPBUF          ; get character back
        CLC                     ; no error
        RTS

        ;; read UART input into line buffer up to but not including CR
        ;; returns with carry set if there was any input
        ;; (I flag gets set by BRK and C64 kernal clears it in CHRIN so
        ;; we need to do that too)
GETLIN: CLI
        JSR     CHKCOL          ; check terminal cursor column
        LDY     CSRCOL
        LDA     CSRROW
        PHA                     ; save current row
        LDA     #0
        STA     STOPFLAG
        STA     ESCFLAG
WTCHR:  JSR     UAGETW          ; wait for character from UART
        BIT     ESCFLAG         ; are we in an ESC sequence?
        BMI     ESCHDL          ; go to ESC handler
        CMP     #27             ; is it ESC?
        BEQ     ESCS            ; go to ESC start handler
        CMP     #8              ; is it backspace?
        BEQ     CHRBS           ; go to DELETE handler
        CMP     #127            ; is it delete?
        BEQ     CHRBS           ; go to DELETE handler
        JSR     MAPCHR          ; map ASCII
        BEQ     WTCHR           ; ignore character if we can not map it
        CMP     #13             ; was character CR (or LF)?
        BEQ     GLDONE          ; if yes then we're done
        CPY     #NUMCOLS        ; are we at the end of the line buffer?
        BCS     WTCHR           ; if so then ignore input
        STA     (LINEPTR),Y     ; store character
        INY
        JSR     UAPUTW          ; output character
        JMP     WTCHR           ; wait for more input
GLDONE: LDY     #NUMCOLS-1      ; start Y at line length
GLL1:   LDA     (LINEPTR),Y     ; get character from buffer
        CMP     #' '            ; is it "space"
        BNE     GLL2            ; jump if not
        DEY                     ; next position
        BNE     GLL1            ; repeat until 0
GLL2:   INY                     ; Y now is first space character pos
        STY     LASTCOL         ; set column for end-of-input
        STY     TERMCOL         ; set terminal cursor column
        PLA                     ; get original cursor row back
        CMP     CSRROW          ; compare to current
        BEQ     GLL3            ; jump if same
        LDY     #0              ; cursor row changed
        STY     CSRCOL          ; => input start at first column
        SEC
        RTS
GLL3    CPY     CSRCOL          ; do we have any non-space characters
        BEQ     GLRETC          ; jump if CSRCOL==TERMCOL, i.e. no input
        BCS     GLRET           ; after initial cursor position?
        STY     CSRCOL          ; no => set beginning=end of input
GLRETC: CLC                     ; no input => clear carry
GLRET:  RTS

        ;; backspace handling
CHRBS:  CPY     #0              ; is cursor at start of line?
        BEQ     WTCHR           ; if so then we cannot backspace any more
        DEY                     ; cursor one back
        LDA     #8              ; send backspace-space-backspace
        JSR     UAPUTW
        LDA     #' '
        STA     (LINEPTR),Y     ; clear out character in line buffer
        JSR     UAPUTW
        LDA     #8
        JSR     UAPUTW
        JMP     WTCHR           ; wait for more input
                
        ;; ESC (cursor) sequence handling
ESCS:   LDA     #$80            ; start ESC mode
        .byte   $2C             ; skip next 2-byte instruction
ESCCLR: LDA     #$00            ; clear ESC flag
        STA     ESCFLAG
        JMP     WTCHR
ESCHDL: BIT     ESCFLAG
        BVS     ESCL1           ; jump if we are waiting for char #3
        CMP     #'['            ; did we receive expected second char?
        BNE     ESCCLR          ; if not, end ESC sequence
        LDA     #$C0            ; set flag to wait for third char
        STA     ESCFLAG
        JMP     WTCHR           ; wait for next input character
ESCL1:  CMP     #'A'            ; ESC [ A (cursor up)?
        BEQ     ESCCU           ; jump if so
        CMP     #'B'            ; ESC [ A (cursor down)?
        BEQ     ESCCD           ; jump if so
        CMP     #'C'            ; ESC [ C (cursor right)?
        BEQ     ESCCR           ; jump if so
        CMP     #'D'            ; ESC [ D (cursor left)?
        BEQ     ESCCL           ; jump if so
        BNE     ESCCLR          ; end ESC sequence
ESCCU:  LDA     CSRROW
        CMP     ROWLIMIT        ; is cursor in first row?
        BEQ     ESCCLR          ; if so then we cannot go up any more
        JSR     ROWUP           ; move cursor pointer up one row
        LDA     #'A'
        JMP     ESCPS           ; send "cursor up" sequence
ESCCD:  LDA     CSRROW
        CMP     #NUMROWS-1      ; is cursor in last row?
        BEQ     ESCCD1          ; if so then we cannot go down any more
        JSR     ROWDN           ; move cursor pointer down one row
        LDA     #'B'
        JMP     ESCPS           ; send "cursor down" sequence
ESCCD1: JSR     SCRL            ; scroll line buffer down
        LDA     #10             ; send line feed
        JSR     UAPUTW
        JMP     ESCCLR          ; end ESC mode
ESCCL:  CPY     #0              ; is cursor at start of line?
        BEQ     ESCCLR          ; if so then we cannot go left any more
        DEY                     ; move cursor pointer left
        JMP     ESCPS
ESCCR:  CPY     #NUMCOLS-1      ; is cursor at end of line?
        BEQ     ESCCLR          ; if so then we cannot go right any more
        INY                     ; move cursor pointer right
ESCPS:  PHA                     ; save final character
        LDA     #27             ; send cursor sequence back to terminal
        JSR     UAPUTW
        LDA     #'['
        JSR     UAPUTW
        PLA
        JSR     UAPUTW
        JMP     ESCCLR          ; clear ESC mode and wait for next char

        ;; map input char:
        ;; - clear bit 7 of character
        ;; - ignore character codes < 32 (space)
        ;; - map LF to CR, ignore LF after CR
        ;; - return with Z bit set if invalid character
MAPCHR: PHA
        LDA     LASTRECV        ; transfer previous character
        STA     TMPBUF          ; to TMPBUF
        PLA
        STA     LASTRECV        ; rememver new character
        AND     #$7F            ; clear bit 7
        CMP     #13             ; is character CR?
        BEQ     MCICR           ; jump if so
        CMP     #10             ; is character NL?
        BNE     MC1             ; jump if not
        LDA     #13
        CMP     TMPBUF          ; was previous character CR?
        BEQ     MCINUL          ; if so then ignore NL
        BNE     MCICR           ; return CR
MC1:            
        .if     INPUT_UCASE
        CMP     #'a'
        BCC     MC2
        CMP     #'z'+1
        BCS     MC2
        AND     #$DF
MC2:
        .endif
        CMP     #' '            ; character < ' '?
        BCC     MCINUL          ; skip if so
        ORA     #0              ; clear Z flag
        RTS
MCINUL: LDA     #00
        RTS
MCICR:  LDA     #13
MCIR:   RTS

        ;; process CR output
PROCCR: TYA
        PHA
        TXA
        PHA
        LDA     #13             ; output CR
        JSR     UAPUTW
        LDA     #10             ; output LF
        JSR     UAPUTW
        LDA     #0              ; beginning of line
        STA     TERMCOL         ; reset terminal cursor position
        STA     CSRCOL          ; reset cursor pointer
        STA     LASTCOL         ; reset last input column
        STA     CRFLAG          ; no input waiting
        LDA     CSRROW
        CMP     #NUMROWS-1      ; cursor in last row?
        BNE     PROC1
        JSR     SCRL            ; scroll buffer
        JMP     PROC2
PROC1:  JSR     ROWDN           ; move cursor one row down
PROC2:  PLA
        TAX
        PLA
        TAY
        RTS

        ;; move cursor row (and line pointer) down
ROWDN:  INC     CSRROW
        CLC
        LDA     LINEPTR
        ADC     #NUMCOLS
        STA     LINEPTR
        LDA     LINEPTR+1
        ADC     #0
        STA     LINEPTR+1
        RTS

        ;; move cursor row (and line pointer) up
ROWUP:  DEC     CSRROW
        SEC
        LDA     LINEPTR
        SBC     #NUMCOLS
        STA     LINEPTR
        LDA     LINEPTR+1
        SBC     #0
        STA     LINEPTR+1
        RTS

        ;; scroll screen buffer
SCRL:   PHA
        TXA
        PHA
        TYA
        PHA
        LDA     CSRROW
        PHA
        LDA     LINEPTR
        PHA
        LDA     LINEPTR+1
        PHA
        LDA     #<LINEBUF       ; set pointer to first row
        STA     LINEPTR
        LDA     #>LINEBUF
        STA     LINEPTR+1
        LDX     #NUMROWS-1
SCRL1:  LDA     LINEPTR
        STA     $C1
        LDA     LINEPTR+1
        STA     $C2
        JSR     ROWDN           ; go one row down
        LDY     #NUMCOLS-1      ; fill line buffer
SCRL2:  LDA     (LINEPTR),Y     ; move character
        STA     ($C1),Y         ; one row up
        DEY
        BPL     SCRL2           ; repeat for all columns
        DEX
        BNE     SCRL1
        JSR     CLRL            ; clear bottom row
        LDA     ROWLIMIT
        BEQ     SCRL3
        DEC     ROWLIMIT
SCRL3:  PLA
        STA     LINEPTR+1
        PLA
        STA     LINEPTR
        PLA
        STA     CSRROW
        PLA
        TAY
        PLA
        TAX
        PLA
        RTS
                                
        ;; clear current row
CLRL:   LDY     #NUMCOLS-1      ; fill line buffer
        LDA     #' '            ; with SPACE
CLRL1:  STA     (LINEPTR),Y
        DEY
        BPL     CLRL1           ; repeat for all columns
        RTS

        ;; clear line buffer
CLRLB:  LDA     #<LINEBUF       ; set pointer to first row
        STA     LINEPTR
        LDA     #>LINEBUF
        STA     LINEPTR+1
        LDA     #0
        STA     CSRROW
        LDX     #NUMROWS
CLRLB1: JSR     CLRL            ; clear row
        JSR     ROWDN           ; next row
        DEX
        BNE     CLRLB1          ; repeat for all rows
        JSR     ROWUP           ; gone one too far
        RTS
                        
        ;; CHROUT (FFD2): write output character
KCHROUT:STA     LASTPRNT
        TYA
        PHA
        LDA     LASTPRNT
        CMP     #13             ; was it CR?
        BNE     CHROL3          ; jump if not
        JSR     PREOL           ; print characters in line buffer after cursor
        JSR     PROCCR          ; print CR/LF and clear line buffer
        JMP     CHRODN          ; done
CHROL3:
        .if     SUPPRESS_NP
        CMP     #$80            ; ignore
        BCS     CHRODN          ; non-printable
        CMP     #$20            ; characters
        BCC     CHRODN
        .endif
        JSR     CHKCOL
        ;; output character
        LDA     LASTPRNT
        JSR     UAPUTW          ; output character
        LDY     CSRCOL
        STA     (LINEPTR),Y     ; write output character to line buffer
        INY
        STY     CSRCOL
        STY     TERMCOL         ; remember previous column
        LDA     #0              ; outputting character stops...
        STA     CRFLAG          ; ...input sequence (CRFLAG=0)
        CPY     #NUMCOLS        ; are we at the end of the line buffer?
        BCC     CHRODN          ; jump if not
        JSR     PROCCR          ; go to next line
CHRODN: PLA                     ; restore Y
        TAY
        LDA     LASTPRNT        ; get printed character back
        CLC                     ; no error
        RTS

        ;; make sure terminal cursor position agrees with CSRCOL
CHKCOL: LDY     CSRCOL
        CPY     TERMCOL
        BCS     CHROL5          ; jump if CSRCOL>=TERMCOL
        ;; cursor has moved back => output CR followed by
        ;; all characters from the line buffer up to new cursor pos
        LDA     #13             ; output CR
        JSR     UAPUTW
        LDY     #0
CHROL4: CPY     CSRCOL
        BEQ     CHROL5
        LDA     (LINEPTR),Y
        JSR     UAPUTW
        INY
        JMP     CHROL4
CHROL5: BEQ     CHROL7          ; jump if CSRCOL==TERMCOL
        ;; cursor has moved forward => output line buffer up to new position
CHROL6: LDA     (LINEPTR),Y
        JSR     UAPUTW
        DEY
        CPY     TERMCOL
        BNE     CHROL6
CHROL7: STY     TERMCOL
        RTS

        ;; re-print the current line
PRLINE: LDA     #13             ; print CR
        JSR     UAPUTW          ; (move terminal cursor to beginning of line)
        LDA     #0              ; set terminal cursor position to 0
        STA     TERMCOL         ; fall through to print line buffer
        
        ;; print characters in line buffer after terminal cursor position
PREOL:  LDY     #NUMCOLS-1      ; start at end of line buffer
PREOL0: CPY     TERMCOL         ; have we reached the cursor column yet?
        BEQ     PREOL2          ; jump if Y<=TERMCOL
        BCC     PREOL2
        LDA     (LINEPTR),Y     ; get character
        DEY     
        CMP     #$20            ; is it SPACE?
        BEQ     PREOL0          ; repeat if so
        INY                     ; remember one more than last
        STY     TMPBUF          ; non-space column after cursor
        LDY     TERMCOL
        DEY
PREOL1: INY
        LDA     (LINEPTR),Y     ; get character
        .if     SUPPRESS_NP
        CMP     #$80            ; ignore
        BCS     PREOL3          ; non-printable
        CMP     #$20            ; characters
        BCS     PREOL4
PREOL3: LDA     #$20
PREOL4: .endif
        JSR     UAPUTW          ; output character
        CPY     TMPBUF
        BNE     PREOL1
        STY     TERMCOL         ; set new cursor position
PREOL2: RTS
        
        ;; NMI handler
NMI:    SEI
        JMP     ($0318)         ; jump to NMI vector
        
        ;; IRQ and BRK handler
IRQ:    PHA
        TXA
        PHA
        TYA
        PHA
        TSX
        LDA     $0104,X         ; get status byte from stack
        AND     #$10            ; "B" (BRK) flag set
        BEQ     BRK             ; jump if not
        JMP     ($0316)         ; jump to BREAK vector
BRK:    JMP     ($0314)         ; jump to IRQ vector

        ;; interrupt stub function
ISTUB:  RTI
                
        ;; RESET handler
RESET:  SEI                     ; prevent IRQ interrupts
        CLD                     ; clear decimal mode flag
        LDX     #$FF            ; initialize stack pointer
        TXS
        LDA     #<ISTUB         ; initialize interrupt vectors
        STA     $0314
        STA     $0316
        STA     $0318
        LDA     #>ISTUB
        STA     $0315
        STA     $0317
        STA     $0319
        JSR     UAINIT          ; init UART
        LDA     #0
        STA     LASTPRNT
        STA     LASTRECV
        STA     CSRCOL
        LDA     #NUMROWS-1
        STA     CSRROW
        STA     ROWLIMIT
        LDA     #$FF            ; clear stop flag
        STA     STOPFLAG
        JSR     CLRLB           ; clear line buffer
        JSR     PROCCR          ; set cursor to start of line
        JMP     ENTRY   
        
;;; ----------------------------------------------------------------------------
;;; ---------------------- UART communication functions  -----------------------
;;; ----------------------------------------------------------------------------

 .if UART_TYPE==6522
   .include "uart_6522.asm"
 .else 
   .if UART_TYPE==6551
     .include "uart_6551.asm"
   .else
     .if UART_TYPE==6850
       .include "uart_6850.asm"
     .else
       .err "invalid UART_TYPE"
     .endif
   .endif
 .endif
        
;;; ----------------------------------------------------------------------------
;;; -------------------------  C64 kernal jump table  --------------------------
;;; ----------------------------------------------------------------------------

        .org    $FF81
        JMP     KSTUB           ; FF81:
        JMP     KSTUB           ; FF84:
        JMP     KSTUB           ; FF87:
        JMP     KSTUB           ; FF8A:
        JMP     KSTUB           ; FF8D:
        JMP     KMSGFLG         ; FF90: set kernal message output flag
        JMP     KSTUB           ; FF93:
        JMP     KSTUB           ; FF96:
        JMP     KRWMEMT         ; FF99: get or set memory top address
        JMP     KRWMEMB         ; FF9C: get or set memory bottom address
        JMP     KSTUB           ; FF9F:
        JMP     KSTUB           ; FFA2:
        JMP     KSTUB           ; FFA5:
        JMP     KSTUB           ; FFA8:
        JMP     KSTUB           ; FFAB:
        JMP     KSTUB           ; FFAE:
        JMP     KSTUB           ; FFB1:
        JMP     KSTUB           ; FFB4:
        JMP     KIOSTUB         ; FFB7: read I/O status word
        JMP     KIOSTUB         ; FFBA: set logical, first and second address
        JMP     KIOSTUB         ; FFBD: set file name
        JMP     KIOSTUB         ; FFC0: open loical file
        JMP     KIOSTUB         ; FFC3: close logical file
        JMP     KIOSTUB         ; FFC6: open channel for input
        JMP     KIOSTUB         ; FFC9: open channel for output
        JMP     KIOSTUB         ; FFCC: close channels
        JMP     KCHRIN          ; FFCF: get input character
        JMP     KCHROUT         ; FFD2: print output character
        JMP     KIOSTUB         ; FFD5: load data from device
        JMP     KIOSTUB         ; FFD8: save data to device
        JMP     KSTUB           ; FFDB: set the real time clock
        JMP     KSTUB           ; FFDB: get the real time clock
        JMP     KSTOP           ; FFE1: check stop key
        JMP     KGETIN          ; FFE4: get character from keyboard
        JMP     KIOSTUB         ; FFE7: close all channels
        JMP     KSTUB           ; FFEA:
        JMP     KSTUB           ; FFED:
        JMP     KSTUB           ; FFF0:
        JMP     KSTUB           ; FFF3:

;;; ----------------------------------------------------------------------------
;;; -------------------------  6502 hardware vectors   -------------------------
;;; ----------------------------------------------------------------------------
        
        .org    $FFFA
        .word   NMI             ; hardware NMI vector
        .word   RESET           ; hardware RESET vector
        .word   IRQ             ; hardware IRQ/BRK vector
