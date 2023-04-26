;;; The SMON machine language monitor was originally published
;;; in the November/December/January 1984/85 issues of German magazine "64er":
;;; https://archive.org/details/64er_1984_11/page/n59/mode/2up
;;; https://archive.org/details/64er_1984_12/page/n59/mode/2up
;;; https://archive.org/details/64er_1985_01/page/n68/mode/2up
;;; SMON was written for the Commodore 64 by Norfried Mann and Dietrich Weineck
;;;
;;; For an English description of SMON capabilities see: 
;;;     https://www.c64-wiki.com/wiki/SMON
;;; The following original SMON commands are NOT included in this version:
;;;   B (BASIC data), L (disk load), S (disk save), P (printer), I (set I/O device)
;;; The following commands were added in this version:
;;;   H  - print help screen
;;;   L  - load Intel HEX data through terminal
;;;   MS - check and print memory (RAM) size
;;;   MT xxxx yyyy nn - test memory (RAM) xxxx-yyyy nn times (default 1)
;;; 
;;; This code is an adaptation of SMON to a minimal 6502 system by David Hansel (2023).
;;; Minimum system requirements:
;;;   - MOS 6502 CPU
;;;   - MOS 6522 VIA (necessary only if "trace" functions are used)
;;;     The VIA interrupt output must be attached to the 6502 IRQ input
;;;   - 8K of ROM at address E000-F000 (for SMON)
;;;   - 4K of RAM at address 0000-1000
;;;   - UART for communication. As presented here, a MC6850 UART
;;;     at address $8200 is expected. However, this can easily
;;;     be adapted by modifying the code in file "uart.asm"
;;;
;;; This code is based on the SMON disassembly found at:
;;; https://github.com/cbmuser/smon-reassembly

 .include "config.asm"        

PCHSAVE         = $02A8         ; PC hi
PCLSAVE         = $02A9         ; PC lo
SRSAVE          = $02AA         ; SR
AKSAVE          = $02AB         ; A
XRSAVE          = $02AC         ; XR
YSAVE           = $02AD         ; YR
SPSAVE          = $02AE         ; SP
IRQ_LO          = $0314         ; Vector: Hardware IRQ Interrupt Address Lo
IRQ_HI          = $0315         ; Vector: Hardware IRQ Interrupt Address Hi
BRK_LO          = $0316         ; Vector: BRK Lo
BRK_HI          = $0317         ; Vector: BRK Hi
CHRIN           = $FFCF         ; Kernal input routine
CHROUT          = $FFD2         ; Kernal output routine
STOP            = $FFE1         ; Kernal test STOP routine
GETIN           = $FFE4         ; Kernal get input routine

        .org    $8000
        .org    $e000

ENTRY:  lda     #<SMON                        ; set break-vector to program start
        sta     BRK_LO
        lda     #>SMON    
        sta     BRK_HI
        brk

        ;; help message
HLPMSG: .byte   "A xxxx - Assemble starting at x (end assembly with 'f', use Mxx for label)",0
        .byte   "C xxxx yyyy zzzz aaaa bbbb - Convert (execute V followed by W)",0
        .byte   "D xxxx (yyyy) - Disassemble from x (to y)",0
        .byte   "F aa bb cc ..., xxxxx yyyyy - Find byte sequence a b c in x-y",0
        .byte   "FAaaaa, xxxx yyyy - Find absolute address used in opcode",0
        .byte   "FRaaaa, xxxx yyyy - Find relative address used in opcode",0
        .byte   "FTxxxx yyyy - Find table (non-opcode bytes) in x-y",0
        .byte   "FZaa, xxxx yyyy - Find zero-page address used in opcode",0
        .byte   "FIaa, xxxx yyyy - Find immediate argument used in opcode",0
        .byte   "G (xxxx) - Run from x (or current PC)",0
        .byte   "K xxxx (yyyy) - Dump memory from x (to y) as ASCII",0
        .byte   "L - Load Intel HEX data from terminal",0
        .byte   "M xxxx (yyyy) - Dump memory from x (to y) as HEX",0
        .byte   "MS - Check and print memory size",0
        .byte   "MT xxxx yyyy (nn) - Test memory x-y (repeat n times)",0
        .byte   "O xxxx yyyy aa - Fill memory x-y with a",0
        .if     VIA > 0
        .byte   "TW xxxx - Trace walk (single step)",0
        .byte   "TB xxxx nn - Trace break (set break point at x, stop when hit n times)",0
        .byte   "TQ xxxx - Trace quick (run to break point)",0
        .byte   "TS xxxx - Trace stop (run to x)",0
        .endif
        .byte   "V xxxx yyyy zzzz aaaa bbbb - Within a-b, convert addresses referencing x-y to z",0
        .byte   "W xxxx yyyy zzzz - Copy memory x-y to z",0
        .byte   "= xxxx yyyy - compare memory starting at x to memory starting at y",0
        .byte   "#ddd - convert DEC to HEX and BIN",0
        .byte   "$xx - convert HEX to DEC and BIN",0
        .byte   "%bbbbbbbb - convert BIN to DEC and HEX",0
        .byte   0
        
        ;; commands
ICMD:   .byte "'#$%,:;=?ACDFGHKLMORTVW"
ICMDE:  .byte $00,$00,$00,$00,$00

        ;; command entry point addresses
IOFS:   .byte   <(TICK-1),>(TICK-1)             ; '
        .byte   <(BEFDEC-1),>(BEFDEC-1)         ; #
        .byte   <(BEFHEX-1),>(BEFHEX-1)         ; $
        .byte   <(BEFBIN-1),>(BEFBIN-1)         ; %
        .byte   <(COMMA-1),>(COMMA-1)           ; ,
        .byte   <(COLON-1),>(COLON-1)           ; :     
        .byte   <(SEMI-1),>(SEMI-1)             ; ; 
        .byte   <(EQUALS-1),>(EQUALS-1)         ; =
        .byte   <(ADDSUB-1),>(ADDSUB-1)         ; ?
        .byte   <(ASSEMBLER-1),>(ASSEMBLER-1)   ; A
        .byte   <(CONVERT-1),>(CONVERT-1)       ; C
        .byte   <(DISASS-1),>(DISASS-1)         ; D
        .byte   <(FIND-1),>(FIND-1)             ; F
        .byte   <(GO-1),>(GO-1)                 ; G
        .byte   <(HELP-1),>(HELP-1)             ; H
        .byte   <(KONTROLLE-1),>(KONTROLLE-1)   ; K
        .byte   <(LOAD-1),>(LOAD-1)             ; L
        .byte   <(MEMDUMP-1),>(MEMDUMP-1)       ; M
        .byte   <(OCCUPY-1),>(OCCUPY-1)         ; O
        .byte   <(REGISTER-1),>(REGISTER-1)     ; R
        .byte   <(TRACE-1),>(TRACE-1)           ; T
        .byte   <(MOVE-1),>(MOVE-1)             ; V
        .byte   <(WRITE-1),>(WRITE-1)           ; W

        ;; output line start characters
LC061:  .byte   "':;,()!"
        .byte   $00,$00,$00
        
LC06B:  .byte   $FF,$FF,$01,$00

        ;; sub-commands for "find" (F)
FSCMD:  .byte   "AZIRT"
        ;; "find" sub-command
LC074:  .byte   $80,$20,$40,$10,$00
        ;; "find" sub-command data length (2=word,1=byte,0=none)
LC079:  .byte   $02,$01,$01,$02,$00
        
REGHDR: .byte   $0D,$0D,"  PC  SR AC XR YR SP  NV-BDIZC",$00
LC0AD:  .byte   $02,$04,$01
LC0B0:  .byte   $2C,$00,$2C
LC0B3:  .byte   $59,$29,$58
LC0B6:  .byte   $9D,$1F,$FF,$1C,$1C,$1F,$1F
        .byte   $1F,$1C,$DF,$1C,$1F,$DF,$FF,$FF
        .byte   $03,$1F
LC0C7:  .byte   $80,$09,$20,$0C,$04,$10,$01
        .byte   $11,$14,$96,$1C,$19,$94,$BE,$6C
        .byte   $03,$13,$01
LC0D9:  .byte   $02,$02,$03,$03,$02,$02,$02
        .byte   $02,$02,$02,$03,$03,$02,$03,$03
        .byte   $03,$02,$00
LC0EB:  .byte   $40,$40,$80,$80,$20,$10,$25
        .byte   $26,$21,$22,$81,$82,$21,$82,$84
        .byte   $08,$08
LC0FC:  .byte   $E7,$E7,$E7,$E7,$E3,$E3,$E3
        .byte   $E3,$E3,$E3,$E3,$E3,$E3,$E3,$E7
        .byte   $A7,$E7,$E7,$F3,$F3,$F7,$DF
        
        ;; opcodes (in same order as mnemonics below)
OPC:    .byte   $26,$46,$06,$66,$41,$81,$E1
        .byte   $01,$A0,$A2,$A1,$C1,$21,$61,$84
        .byte   $86,$E6,$C6,$E0,$C0,$24,$4C,$20
        .byte   $90,$B0,$F0,$30,$D0,$10,$50,$70
        .byte   $78,$00,$18,$D8,$58,$B8,$CA,$88
        .byte   $E8,$C8,$EA,$48
        
LC13D:  .byte   $08,$68,$28,$40,$60,$AA,$A8
        .byte   $BA,$8A,$9A,$98,$38,$F8
LC14A:  .byte   $89,$9C,$9E,$B2
LC14E:  .byte   $2A,$4A,$0A,$6A,$4F,$23,$93
        .byte   $B3,$F3,$33,$D3,$13,$53,$73

        ;; first, second and third characters of opcode mnemonics
OPMN1:   .byte "RLARESSOLLLCAASSIDCCBJJBBBBBBBBSBCCCCDDIINPPPPRRTTTTTTSS"
OPMN2:   .byte "OSSOOTBRDDDMNDTTNEPPIMSCCEMNPVVERLLLLEENNOHHLLTTAASXXYEE"
OPMN3:   .byte "LRLRRACAYXAPDCYXCCXYTPRCSQIELCSIKCDIVXYXYPAPAPISXYXASACD"
        
LC204:  .byte   $08,$84,$81,$22,$21,$26,$20,$80
LC20C:  .byte   $03,$20,$1C,$14,$14,$10,$04,$0C

; SMON START
SMON:   cld
        ldx     #$05
LC22E:  pla
        sta     PCHSAVE,x       ; save stack
        dex
        bpl     LC22E
        lda     PCLSAVE
        bne     LC23D
        dec     PCHSAVE         ; PC high
LC23D:  dec     PCLSAVE         ; PC low  
        tsx
        stx     SPSAVE
        lda     #'R'            ; execute 'R' command
        jmp     LC2FF           ; jump to main loop
        
LC249:  jsr     PEEKCH
        beq     LC259
LC24E:  jsr     GETWRD
        sta     PCLSAVE
        lda     $FC
        sta     PCHSAVE
LC259:  rts
     
        ;; get 3 words into $A4-$A9
LC25A:  ldx     #$A4
        jsr     GETWRDX
        jsr     GETWRDX
        bne     GETWRDX

        ;; get start (FB/FC) and end (FD/FE) address from command line
        ;; end address is optional, defaults to $FFFE
GETSE:  jsr     GETWRD           ; get word from command line
        lda     #$FE
        sta     $FD
        lda     #$FF
        sta     $FE
        jsr     PEEKCH          ; is there more command line input?
        bne     GETWRDX         ; yes, get another word
        sta     $0277           ; put NUL into keyboard buffer
        inc     $C6
        rts

        ;; get two words from command line, store in $FB/$FC and $FD/$FE
GETDW:  jsr     GETWRD
        .byte  $2C              ; skip next (2-byte) opcode

        ;; get word from command line, store in $FB/$FC
GETWRD: ldx     #$FB
        
        ;; get word from command line, store in (X)/(X+1)
GETWRDX:jsr     LC28D
        sta     $01,x
        jsr     GETBYT
        sta     $00,x
        inx
        inx
        rts

        ;; get byte from command line, ignore leading " " and ","
LC28D:  jsr     GETCHR
        cmp     #$20
        beq     LC28D
        cmp     #$2C
        beq     LC28D
        bne     LC29D

        ;; get byte from command line, return in A
GETBYT: jsr     GETCHR       ; get character
LC29D:  jsr     LC2AF        ; convert to 0-15
        asl
        asl
        asl
        asl
        sta     $B4
        jsr     GETCHR       ; get character
        jsr     LC2AF        ; convert to 0-15
        ora     $B4
        rts

        ;; convert character in A from ASCII HEX to 0-15
LC2AF:  cmp     #$3A
        bcc     LC2B5
        adc     #$08
LC2B5:  and     #$0F
        rts

        ;; skip spaces from command line
LC2B8:  jsr     GETCHR
        cmp     #$20
        beq     LC2B8
        dec     $D3
        rts

        ;; peek whether next character on command line is CR (Z set if so)
PEEKCH: jsr     CHRIN
        dec     $D3
        cmp     #$0D
LC2C9:  rts

        ;; convert character in A to uppercase
UCASE:  cmp     #'a'
        bcc     UCASE1
        cmp     #'z'+1
        bcs     UCASE1
        and     #$DF
UCASE1: rts
        
        ;; get next character from command line, error if CR (end of line)
GETCHR: jsr     CHRIN
        jsr     UCASE
GETCL1: cmp     #$0D
        bne     LC2C9

        ; invalid input
ERROR:  lda     #$3F                    ; print "?"
        jsr     CHROUT

        ;; main loop
LC2D6:  ldx     SPSAVE                         
        txs
        ldx     #$00                    ; clear keyboard buffer
        stx     $C6
        lda     $D3                     ; get cursor column 
        beq     SKIPCR                  ; jump if zero
        jsr     LC351                   ; print CR
SKIPCR: lda     ($D1,x)                 ; get first character of next line
        ldx     #$06                    ; compare to known line start characters: ':;,()
LC2E5:  cmp     LC061,x
        beq     LC2F2                   ; skip prompt if found
        dex
        bpl     LC2E5
        lda     #$2E                    ; print prompt (".")
        jsr     CHROUT
LC2F2:  jsr     GETCHR                  ; await next input
        cmp     #$2E 
        beq     LC2F2                   ; ignore leading "."
        jmp     LC2FF
LC2FC:  jmp     ERROR
        
        ;; find user command in A
LC2FF:  sta     $AC
        and     #$7F
        ldx     #ICMDE-ICMD
FNDCMD: cmp     ICMD-1,x                       ; compare command char
        beq     LC30F                          ; found valid command
        dex                                    ; next command char
        bne     FNDCMD                         ; loop until we checked all command chars
        beq     LC2FC                          ; no match => error
LC30F:  jsr     LC315                          ; execute command
        jmp     LC2D6                          ; back to main loop

        ;; execute command specified by index in X
LC315:  txa                                    ; X = X*2+1
        asl
        tax
        inx
        lda     IOFS-2,x                       ; low address 
        pha                                    ; on stack
        dex
        lda     IOFS-2,x                       ; high address
        pha                                    ; on stack 
        rts                                    ; execute command

        ;; output data word in FB/FC
LC323:  lda     $FC
        jsr     LC32A
        lda     $FB

        ;; output data byte in A as HEX
LC32A:  pha
        lsr
        lsr
        lsr
        lsr
        jsr     LC335
        pla
        and     #$0F
LC335:  cmp     #$0A
        bcc     LC33B
        adc     #$06
LC33B:  adc     #$30
        jmp     CHROUT

        ;; output CR, followed by character in X
LC340:  lda     #$0D
LC342:  jsr     CHROUT
        txa
        jmp     CHROUT

        ;; output two SPACE
LC349:  jsr     LC34C

        ;; output SPACE
LC34C:  lda     #$20
        jmp     CHROUT

        ;; output CR
LC351:  lda     #$0D
        jmp     CHROUT

        ;; print 0-terminated string pointed to by A/Y
STROUT: sta     $BB
        sty     $BC
        ldy     #$00
STROUT1:lda     ($BB),y
        beq     LC366
        jsr     CHROUT
        inc     $BB
        bne     STROUT1
        inc     $BC
        bne     STROUT1
LC366:  rts

        ;; increment address in $FB/$FC
LC367:  inc     $FB
        bne     LC36D
        inc     $FC
LC36D:  rts

        ;; HELP (H)
HELP:   lda     #<HLPMSG        ; get help message start addr
        sta     $BB             ; into $BB/$BC
        lda     #>HLPMSG
        sta     $BC
        ldy     #$00
HLPL1:  lda     #$0d            ; output CR
        jsr     CHROUT
        jsr     STROUT1         ; output string until 0
        iny                     ; next byte
        cpy     #20             ; are we at line 20?
        bne     HLPL2           ; jump if not
        lda     #' '            ; put SPACE in keyboard buffer
        sta     $0277           ; (to pause output)
        inc     $C6
HLPL2:  jsr     LC472           ; check for PAUSE,STOP
        lda     ($BB),y         ; get first byte of next string
        bne     HLPL1           ; loop if not 0
        rts
                
        ;; REGISTER (R)
REGISTER:
        ldy     #>REGHDR
        lda     #<REGHDR
        jsr     STROUT
        ldx     #$3B
        jsr     LC340
        lda     PCHSAVE
        sta     $FC
        lda     PCLSAVE
        sta     $FB
        jsr     LC323
        jsr     LC34C
        ldx     #$FB
LC3A4:  lda     $01AF,x
        jsr     LC32A
        jsr     LC34C
        inx
        bne     LC3A4
        lda     SRSAVE
        jmp     LC3D0
        
        ;; Semicolon (; - edit register)
SEMI:   jsr     LC24E
        ldx     #$FB
LC3BB:  jsr     GETCHR
        jsr     GETBYT
        sta     $01AF,x
        inx
        bne     LC3BB
        jsr     LC34C
        lda     SRSAVE,x
        jmp     LC3D0
LC3D0:  sta     $AA
        lda     #$20
        ldy     #$09
LC3D6:  jsr     CHROUT
        asl     $AA
        lda     #$30
        adc     #$00
        dey
        bne     LC3D6
        rts
        
        ;; GO (G)
GO:     jsr     LC249
        ldx     SPSAVE
        txs
        ldx     #$FA
LC3EC:  lda     $01AE,x
        pha
        inx
        bne     LC3EC
        pla
        tay
        pla
        tax
        pla
        rti

        ;; LOAD (L)
LOAD:   lda     #13
        jsr     CHROUT
LDNXT:  jsr     UAGETW          ; get character from UART
        cmp     #' '
        beq     LDNXT           ; ignore space at beginning of line
        cmp     #13
        beq     LDNXT           ; ignore CR at beginning of line
        cmp     #10
        beq     LDNXT           ; ignore LF at beginning of line
        cmp     #27
        beq     LDBRK           ; stop when receiving BREAK
        cmp     #3
        beq     LDBRK           ; stop when receiving CTRL-C
        cmp     #':'            ; expect ":" at beginning of line
        bne     LDEIC
        jsr     LDBYT           ; get record byte count
        tax
        jsr     LDBYT           ; get address high byte
        sta     $FC
        jsr     LDBYT           ; get address low byte
        sta     $FB
        jsr     LDBYT           ; get record type
        beq     LDDR            ; jump if data record (record type 0)
        cmp     #1              ; end-of-file record (record type 1)
        bne     LDERI           ; neither a data nor eof record => error

        ;; read Intel HEX end-of-file record
        jsr     LDBYT           ; get next byte (should be checksum)
        cmp     #$FF            ; checksum of EOF record is FF
        bne     LDECS           ; error if not
LDEOF:  rts

        ;; read Intel HEX data record
LDDR:   clc                     ; prepare checksum
        txa                     ; byte count
        adc     $FB             ; address low
        clc
        adc     $FC             ; address high
        sta     $FD             ; store checksum
        ldy     #0              ; offset
        inx
LDDR1:  dex                     ; decrement number of bytes
        beq     LDDR2           ; done if 0
        jsr     LDBYT           ; get next data byte
        sta     ($FB),y         ; store data byte
        cmp     ($FB),y         ; check data byte
        bne     LDEM            ; memory error if no match
        clc
        adc     $FD             ; add to checksum
        sta     $FD             ; store checksum
        iny
        bne     LDDR1
LDDR2:  jsr     LDBYT           ; get checksum byte
        clc
        adc     $FD             ; add to computed checkum
        bne     LDECS           ; if sum is 0 then checksum is ok
        lda     #'+'
        jsr     UAPUTW
        inc     $D3
        cpy     #0              ; did we have 0 bytes in this record?
        bne     LDNXT           ; if not then expect another record
        beq     LDEOF           ; end of file

        
LDBRK:  lda     #'B'            ; received BREAK (ESC)
        .byte   $2C
LDERI:  lda     #'R'            ; unknown record identifier error
        .byte   $2C
LDECS:  lda     #'C'            ; checksum error
        .byte   $2C
LDEIC:  lda     #'I'            ; input character error
        .byte   $2C
LDEM:   lda     #'M'            ; memory error
        jsr     CHROUT
LDERR:  jmp     ERROR
        
        ;; get HEX byte from UART
LDBYT:  jsr     LDNIB           ; get high nibble
        asl
        asl
        asl
        asl
        sta     $B4
        jsr     LDNIB           ; get low libble
        ora     $B4             ; combine
        rts
        ;; get HEX character from UART, convert to 0-15
LDNIB:  jsr     UAGETW          ; get character from UART
        jsr     UCASE           ; convert to uppercase
        cmp     #'0'
        bcc     LDEIC
        cmp     #'F'+1
        bcs     LDEIC
        cmp     #'9'+1
        bcc     LDBYT2
        cmp     #'A'
        bcc     LDEIC
        adc     #$08
LDBYT2: and     #$0F
        rts
                
        ;; MEMDUMP (M)
MEMDUMP:jsr     GETCHR
        beq     MDERR           ; error if CR
        cmp     #'T'            ; is it 'T'
        bne     MD1             ; go to memory dump
        jmp     MEMTST
MD1:    cmp     #'S'
        bne     MD2
        jmp     MEMSIZ
MD2:    cmp     #' '
        bne     MDERR
MD3:    jsr     GETSE           ; get start (FB/FC) and end address (FD/FE)
LC3FC:  ldx     #$3A            ; ':'
        jsr     LC340           ; print NEWLINE followed by ':'
        jsr     LC323           ; print address in FB/FC
        ldy     #80-17
        ldx     #0
LC408:  jsr     LC34C           ; output space
        cpy     #80-9
        bne     LC409
        jsr     LC34C           ; output space
        iny
LC409:  lda     ($FB,x)
        jsr     LC32A           ; output byte as HEX
        lda     ($FB,x)
        jsr     LC439           ; write ASCII char of byte directly to screen
        bne     LC408           ; repeat until end-of-line
        jsr     PREOL           ; print to end of line
        jsr     LC45D           ; check for PAUSE/STOP or end condition
        bcc     LC3FC           ; repeat until end
        rts

        ;; Colon (: - edit memory dump)
COLON:  jsr     GETWRD          ; get start addressz
        ldy     #80-17
        ldx     #$00
LC424:  cpy     #80-9
        bne     LC434
        iny
LC434:  jsr     CHRIN           ; get next character
        cmp     #$20            ; was it space?
        beq     LC424           ; skip space
        cmp     #$0d            ; was it CR?
        beq     COLOD           ; done if so
        dec     $D3             ; go back one input char
        jsr     GETBYT          ; get hex byte
        sta     ($FB,x)         ; store byte
        cmp     ($FB,x)         ; compare (make sure it's not ROM)
        beq     LC433           ; if match then skip
MDERR:  jmp     ERROR           ; print error
LC433:  jsr     LC439           ; write ASCII to screen
        bne     LC424           ; repeat until end
        lda     #80-17
        jsr     PRLINE
COLOD:  rts

        ;; put character into screen buffer at column Y
        ;; (make sure it is printable first)
LC439:  cmp     #$20            ; character code < 32 (space)
        bcc     LC449           ; if so, print "."
        cmp     #$7F            ; character code >= 127
        bcs     LC449           ; if so, print "."
        bcc     LC44F           ; print character
LC449:  lda     #$2E
LC44F:  sta     ($D1),y
        lda     $0286
        sta     ($F3),y
LC456:  jsr     LC367
        iny
        cpy     #80
        rts
     
        ;; check stop/pause condition, return with carry set
        ;; if end address reached
LC45D:  jsr     LC472           ; end-of-line wait handling
        jmp     LC466           ; check for end address and return

        ;; increment address in $FB/$FC and check whether end address
        ;; ($FD/$FE) has been reached, if not, C is clear on return
LC463:  jsr     LC367           ; increment address in $FB/$FC
        
        ;; check whether end address has been reached, C is clear if not
LC466:  lda     $FB
        cmp     $FD
        lda     $FC
        sbc     $FE
        rts

        ;; end-of-line wait handling:
        ;; - stop if STOP key pressed
        ;; - wait if any key pressed
        ;; - if SPACE pressed, immediately stop again after next line
LC472:  jsr     LC486           ; check for STOP or keypress
        beq     LC485           ; no key => done
LC477:  jsr     LC486           ; check for STOP or keypress
        beq     LC477           ; no key => wait
        cmp     #$20            ; is SPACE?
        bne     LC485           ; no => done
        sta     $0277           ; put SPACE in keyboard buffer
        inc     $C6             ; (i.e. advance just one line)
LC485:  rts

        ;; check for STOP or other keypress
LC486:  jsr     GETIN           ; get input character
        pha                     ; save char
        jsr     STOP            ; check stop key
        beq     LC491           ; jump if pressed
        pla                     ; restore char to A
LC490:  rts
LC491:  jmp     LC2D6           ; back to main loop (resets stack)

        ;; 
LC4CB:  ldy     #$00
        lda     ($FB),y         ; get opcode at $FB/FC
        bit     $AA
        bmi     LC4D5
        bvc     LC4E1
LC4D5:  ldx     #$1F
LC4D7:  cmp     LC13D-1,x
        beq     LC50B
        dex
        cpx     #$15
        bne     LC4D7
LC4E1:  ldx     #$04
LC4E3:  cmp     LC14A-1,x
        beq     LC509
        cmp     LC14E-1,x
        beq     LC50B
        dex
        bne     LC4E3
        ldx     #$38
LC4F2:  cmp     OPC-1,x
        beq     LC50B
        dex
        cpx     #$16
        bne     LC4F2
LC4FC:  lda     ($FB),y
        and     LC0FC-1,x
        eor     OPC-1,x
        beq     LC50B
        dex
        bne     LC4FC
LC509:  ldx     #$00
LC50B:  stx     $AD
        txa
        beq     LC51F
        ldx     #$11
LC512:  lda     ($FB),y
        and     LC0B6-1,x
        eor     LC0C7-1,x
        beq     LC51F
        dex
        bne     LC512
LC51F:  lda     LC0EB-1,x
        sta     $AB
        lda     LC0D9-1,x
        sta     $B6
        ldx     $AD
        rts
        
LC52C:  ldy     #$01
        lda     ($FB),y
        tax
        iny
        lda     ($FB),y
        ldy     #$10
        cpy     $AB
        bne     LC541
        jsr     LC54A
        ldy     #$03
        bne     LC543
LC541:  ldy     $B6
LC543:  stx     $AE
        nop
        sta     $AF
        nop
        rts
        
LC54A:  ldy     #$01
        lda     ($FB),y
        bpl     LC551
        dey
LC551:  sec
        adc     $FB
        tax
        inx
        beq     LC559
        dey
LC559:  tya
        adc     $FC
LC55C:  rts

        
; DISASS (D)
DISASS: ldx     #$00
        stx     $AA
        jsr     GETSE           ; get start (FB/FC) and end address (FD/FE)
LC564:  jsr     LC58C
        lda     $AD
        cmp     #$16
        beq     LC576
        cmp     #$30
        beq     LC576
        cmp     #$21
        bne     LC586
        nop
LC576:  jsr     LC351
        ldx     #$23
        lda     #$2D
LC580:  jsr     CHROUT
        dex
        bne     LC580
LC586:  jsr     LC45D
        bcc     LC564
        rts
        
LC58C:  ldx     #$2C            ; output NEWLINE followed by ","
        jsr     LC340
        jsr     LC323           ; output FB/FC (address)
        jsr     LC34C           ; output SPACE
LC597:  jsr     LC675           ; erase to end of line
        jsr     LC4CB
        jsr     LC34C           ; output SPACE
LC5A0:  lda     ($FB),y         ; get data byte
        jsr     LC32A           ; output byte in A
        jsr     LC34C           ; output SPACE
        iny
        cpy     $B6
        bne     LC5A0
        lda     #$03
        sec
        sbc     $B6
        tax
        beq     LC5BE
LC5B5:  jsr     LC349
        jsr     LC34C
        dex
        bne     LC5B5
LC5BE:  lda     #$20
        jsr     CHROUT
        ldy     #$00
        ldx     $AD
LC5C7:  bne     LC5DA
        ldx     #$03
LC5CB:  lda     #$2A
        jsr     CHROUT
        dex
        bne     LC5CB
        bit     $AA
        bmi     LC55C
        jmp     LC66A
LC5DA:  bit     $AA
        bvc     LC607
        lda     #$08
        bit     $AB
        beq     LC607
        lda     ($FB),y
        and     #$FC
        sta     $AD
        iny
        lda     ($FB),y
        asl
        tay
        lda     $033C,y
        sta     $AE
        nop
        iny
        lda     $033C,y
        sta     $AF
        nop
        jsr     LC6BE
        ldy     $B6
        jsr     LC693
        jsr     LC4CB
LC607:  lda     OPMN1-1,x
        jsr     CHROUT
        lda     OPMN2-1,x
        jsr     CHROUT
        lda     OPMN3-1,x
        jsr     CHROUT
        lda     #$20
        bit     $AB
        beq     LC622
        jsr     LC349
LC622:  ldx     #$20
        lda     #$04
        bit     $AB
        beq     LC62C
        ldx     #$28
LC62C:  txa
        jsr     CHROUT
        bit     $AB
        bvc     LC639
        lda     #$23
        jsr     CHROUT
LC639:  jsr     LC52C
        dey
        beq     LC655
        lda     #$08
        bit     $AB
        beq     LC64C
        lda     #$4D
        jsr     CHROUT
        ldy     #$01
LC64C:  lda     $AD,y
        jsr     LC32A
        dey
        bne     LC64C
LC655:  ldy     #$03
LC657:  lda     LC0AD-1,y
        bit     $AB
        beq     LC667
        lda     LC0B0-1,y
        ldx     LC0B3-1,y
        jsr     LC342
LC667:  dey
        bne     LC657
LC66A:  lda     $B6
LC66C:  jsr     LC367
        sec
        sbc     #$01
        bne     LC66C
        rts

        ;; erase screen buffer to end of line
LC675:  ldy     $D3
        lda     #' '
LC679:  sta     ($D1),y
        iny
        cpy     #40
        bcc     LC679
        rts
        
LC681:  cpx     $AB
        bne     LC689
        ora     $AD
        sta     $AD
LC689:  rts

        ;; copy $AD through $AD+y to ($FB)
LC68A:  lda     $AD,y
        sta     ($FB),y
        cmp     ($FB),y
        bne     LC697
LC693:  dey
        bpl     LC68A
        rts
        
LC697:  pla
        pla
        rts
        
LC69A:  bne     LC6B8
        txa
        ora     $AB
        sta     $AB

        ;; get first character that is not " $(," (max 4)
LC6A1:  lda     #$04
        sta     $B5
LC6A5:  jsr     CHRIN           ; get character
        cmp     #$20            ; is it space?
        beq     LC6B9           ; 
        cmp     #$24            ; is it "$"?
        beq     LC6B9
        cmp     #$28            ; is it "("?
        beq     LC6B9
        cmp     #$2C            ; is it ","?
        beq     LC6B9
        jsr     UCASE           ; convert to uppercase
LC6B8:  rts
        ;; character was either " ", "$", "(" or ","
LC6B9:  dec     $B5
        bne     LC6A5           ; get next character
        rts
        
LC6BE:  cpx     #$18
        bmi     LC6D0
        lda     $AE
        nop
        sec
        sbc     #$02
        sec
        sbc     $FB
        sta     $AE
        nop
        ldy     #$40
LC6D0:  rts

; Assembler (A)
ASSEMBLER:
        jsr     GETWRD          ; get start address
        sta     $FD
        lda     $FC
        sta     $FE
LC6DA:  jsr     LC351           ; print CR
LC6DD:  jsr     LC6E4           ; get and assemble line
        bmi     LC6DD
        bpl     LC6DA
        
LC6E4:  lda     #$00
        sta     $D3
        jsr     LC34C           ; output ' '
        jsr     LC323           ; output address
        jsr     LC34C           ; output ' '
        jsr     CHRIN           ; get character
        lda     #$01            ; set input start column within line
        sta     $D3
        ldx     #$80
        bne     LC701
        ;; entry point from "," command (assemble single line)
COMMA:  ldx     #$80            ; set "comma" flag
        stx     $02B1
LC701:  stx     $AA
        jsr     GETWRD          ; get word (address) from command line
        lda     #$25            ; set last input char (37)
        sta     LASTCOL
        bit     $02B1           ; skip the following if "comma" flag NOT set
        bpl     LC717
        ldx     #$0A            ; skip 10 characters (for "," command)
LC711:  jsr     CHRIN           
        dex
        bne     LC711
LC717:  lda     #$00
        sta     $02B1
        jsr     LC6A1           ; get a character (skip " $(,")
        cmp     #$46            ; is it "f"?
        bne     LC739           ; jump if not
        ;; disassemble the whole input and exit
        lsr     $AA
        pla
        pla
        ldx     #$02
LC729:  lda     $FA,x           ; swap $FB/$FC and $FD/$FE
        pha
        lda     $FC,x
        sta     $FA,x
        pla
        sta     $FC,x
        dex
        bne     LC729
        jmp     LC564           ; disassemble
LC739:  cmp     #$2E            ; was character "."?
        bne     LC74E           ; jump if not
        jsr     GETBYT
        ldy     #$00
        sta     ($FB),y         ; store opcode
        cmp     ($FB),y         ; compare (in case of ROM)
        bne     LC74C           ; if different then error
        jsr     LC367           ; increment FB/FC pointer
        iny
LC74C:  dey
        rts
        
LC74E:  ldx     #$FD
        cmp     #$4D            ; was character "M"?
        bne     LC76D           ; jump if not
        jsr     GETBYT
        ldy     #$00
        cmp     #$3F
        bcs     LC74C
        asl
        tay
        lda     $FB
        sta     $033C,y
        lda     $FC
        iny
        sta     $033C,y
        ;; read 3 opcode characters and store in $a6-$a8
LC76A:  jsr     LC6A1           ; get a character
LC76D:  sta     $A9,x           ; store character
        cpx     #$FD
        bne     LC777
        lda     #$07
        sta     $B7
LC777:  inx
        bne     LC76A           ; get more characters (total 3)
        ldx     #$38
        ;; find mnemonic in table
LC77C:  lda     $A6             ; get first opcode char
        cmp     OPMN1-1,x        ; find it in table
        beq     LC788           ; jump if found
LC783:  dex
        bne     LC77C
        dex
        rts                     ; not found => error exit
LC788:  lda     $A7             ; get second opcode char
        cmp     OPMN2-1,x       ; compare with expected
        bne     LC783           ; repeat if no match
        lda     $A8             ; get third opcode char
        cmp     OPMN3-1,x       ; compare with expected
        bne     LC783           ; repeat if no match
        ;; found mnemonic
        lda     OPC-1,x         ; get opcode
        sta     $AD             ; store opcode
        jsr     LC6A1           ; get another character
        ldy     #$00
        cpx     #$20
        bpl     LC7AD
        cmp     #$20
        bne     LC7B0
        lda     LC14E-1,x
        sta     $AD
LC7AD:  jmp     LC831
LC7B0:  ldy     #$08
        cmp     #$4D
        beq     LC7D6
        ldy     #$40
        cmp     #$23
        beq     LC7D6
        jsr     LC29D
        sta     $AE
        nop
        sta     $AF
        nop
        jsr     LC6A1
        ldy     #$20
        cmp     #$30
        bcc     LC7E9
        cmp     #$47
        bcs     LC7E9
        ldy     #$80
        dec     $D3
LC7D6:  jsr     LC6A1
        jsr     LC29D
        sta     $AE
        nop
        jsr     LC6A1
        cpy     #$08
        beq     LC7E9
        jsr     LC6BE
LC7E9:  sty     $AB
        ldx     #$01
        cmp     #$58
        jsr     LC69A
        ldx     #$04
        cmp     #$29
        jsr     LC69A
        ldx     #$02
        cmp     #$59
        jsr     LC69A
        lda     $AD
        and     #$0D
        beq     LC810
        ldx     #$40
        lda     #$08
        jsr     LC681
        lda     #$18
        .byte  $2C              ; skip next (2-byte) opcode
LC810:  lda     #$1C
        ldx     #$82
        jsr     LC681
        ldy     #$08
        lda     $AD
        cmp     #$20
        beq     LC828
LC81F:  ldx     LC204-1,y
        lda     LC20C-1,y
        jsr     LC681
LC828:  dey
        bne     LC81F
        lda     $AB
        bpl     LC830
        iny
LC830:  iny
LC831:  jsr     LC68A           ; copy opcode plus arguments
        dec     $B7
        lda     $B7
        sta     $D3
        jmp     LC597           ; disassemble
        
; ADDSUB
ADDSUB: jsr     GETWRD
        jsr     GETCHR
        eor     #$02
        lsr
        lsr
        php
        jsr     GETWRDX
        jsr     LC351
        plp
        bcs     LC8BA
        lda     $FD
        adc     $FB
        tax
        lda     $FE
        adc     $FC
LC8B7:  sec
        bcs     LC8C3
LC8BA:  lda     $FB
        sbc     $FD
        tax
        lda     $FC
        sbc     $FE
LC8C3:  tay
LC8C4:  txa

        ;; output 16-bit integer in A/Y as HEX, binary and decimal
LC8C5:  sty     $FC
        sta     $FB
        sty     $62
        sta     $63
        php
        lda     #$00
        sta     $D3
        jsr     LC675
        lda     $FC
        bne     LC8E8
        jsr     LC349
        lda     $FB
        jsr     LC32A
        lda     $FB
        jsr     LC3D0
        beq     LC8EB
LC8E8:  jsr     LC323
LC8EB:  jsr     LC34C
        plp
        jmp     PRTINT
        
; Convert Hexadecimal
BEFHEX: jsr     LC28D
        tax
        ldy     $D3
        lda     ($D1),y
        eor     #$20
        beq     LC8B7
        txa
        tay
        jsr     GETBYT
LC919:  sec
        bcs     LC8C5

        ; Convert Binary
BEFBIN: jsr     LC2B8
        ldy     #$08
LC921:  pha
        jsr     GETCHR
        cmp     #$31
        pla
        rol
        dey
        bne     LC921
        beq     LC919

;; Convert Decimal
BEFDEC: jsr     LC2B8
        ldx     #$00
        txa
LC934:  stx     $FB
        sta     $FC
        tay
        jsr     CHRIN
        cmp     #$3A
        bcs     LC8C4
        sbc     #$2F
        bcs     LC948
        sec
        jmp     LC8C4
LC948:  sta     $FD
        asl     $FB
        rol     $FC
        lda     $FC
        sta     $FE
        lda     $FB
        asl
        rol     $FE
        asl
        rol     $FE
        clc
        adc     $FB
        php
        clc
        adc     $FD
        tax
        lda     $FE
        adc     $FC
        plp
        adc     #$00
        jmp     LC934
        
; OCCUPY (O)
OCCUPY: jsr     GETDW           ; get address range
        jsr     LC28D           ; get data byte
        pha
        jsr     LC351           ; print CR
        pla
LC9C7:  ldx     #$00
LC9C9:  sta     ($FB,x)
        pha
        jsr     LC463
        pla
        bcc     LC9C9
        rts
        
; WRITE (W) - move memory
WRITE:  jsr     LC25A
        jsr     LC351           ; print CR
LC9D6:  lda     $A6
        bne     LC9DC
        dec     $A7
LC9DC:  dec     $A6
        jsr     LCA30
        stx     $B5
        ldy     #$02
        bcc     LC9EB
        ldx     #$02
        ldy     #$00
LC9EB:  clc
        lda     $A6
        adc     $AE
        sta     $AA
        lda     $A7
        adc     $AF
        sta     $AB
LC9F8:  lda     ($A4,x)
        sta     ($A8,x)
        eor     ($A8,x)
        ora     $B5
        sta     $B5
        lda     $A4
        cmp     $A6
        lda     $A5
        sbc     $A7
        bcs     LCA29
LCA0C:  clc
        lda     $A4,x
        adc     LC06B,y
        sta     $A4,x
        lda     $A5,x
        adc     LC06B+1,y
        sta     $A5,x
        txa
        clc
        adc     #$04
        tax
        cmp     #$07
        bcc     LCA0C
        sbc     #$08
        tax
        bcs     LC9F8
LCA29:  lda     $B5
        beq     LCA3C
        jmp     ERROR
LCA30:  sec
        ldx     #$FE
LCA33:  lda     $AA,x
        sbc     $A6,x
        sta     $B0,x
        inx
        bne     LCA33
LCA3C:  rts

        ;; Convert (C) - do V followed by W
CONVERT:jsr     LCA62           ; convert addresses
        jmp     LC9D6           ; move memory

        ;; Variation (V) - convert addresses referencing a memory region
MOVE:   jmp     LCA62

LCA46:  cmp     $A7
        bne     LCA4C
        cpx     $A6
LCA4C:  bcs     LCA61
        cmp     $A5
        bne     LCA54
        cpx     $A4
LCA54:  bcc     LCA61
        sta     $B4
        txa
        clc
        adc     $AE
        tax
        lda     $B4
        adc     $AF
LCA61:  rts
        
LCA62:  jsr     LC25A           ; get address range and destination
        jsr     GETDW           ; get range
        jsr     LC351           ; print CR
LCA68:  jsr     LCA30
LCA6B:  jsr     LC4CB
        iny
        lda     #$10
        bit     $AB
        beq     LCA9B
        ldx     $FB
        lda     $FC
        jsr     LCA46
        stx     $AA
        lda     ($FB),y
        sta     $B5
        jsr     LC54A
        ldy     #$01
        jsr     LCA46
        dex
        txa
        clc
        sbc     $AA
        sta     ($FB),y
        eor     $B5
        bpl     LCAAE
        jsr     LC351
        jsr     LC323
LCA9B:  bit     $AB
        bpl     LCAAE
        lda     ($FB),y
        tax
        iny
        lda     ($FB),y
        jsr     LCA46
        sta     ($FB),y
        txa
        dey
        sta     ($FB),y
LCAAE:  jsr     LC66A
        jsr     LC466
        bcc     LCA6B
        rts

        ;; KONTROLLE (K)
KONTROLLE:
        jsr     GETSE
LCABA:  ldx     #$27
        jsr     LC340
        jsr     LC323
        ldy     #$08
        ldx     #$00
        jsr     LC34C
LCAC9:  lda     ($FB,x)         ; get next byte
        jsr     LC439           ; write ASCII char of byte directly to screen
        bne     LCAC9           ; repeat until end of line
        jsr     PREOL           ; print to end of line
        ldx     #$00
        jsr     LC45D
        beq     LCADA
        jmp     LCABA
LCADA:  rts

        ;; TICK (' - read ASCII chars to memory)
TICK:   jsr     GETWRD          ; get starting address
        ldy     #$03            ; skip up to 3 spaces
LCAE0:  jsr     CHRIN
        cmp     #' '            ; is it a space?
        bne     TSTRT           ; jump if not
        dey
        bne     LCAE0
TLOOP:  jsr     CHRIN           ; get character
TLOOP1: cmp     #$0D            ; is it CR?
        beq     TEND            ; done if so
        sta     ($FB),y         ; store character
LCAEF:  iny
        cpy     #72             ; do we have 72 characters yet?
        bcc     TLOOP           ; loop if not
TEND:   rts
TSTRT:  ldy     #0
        jmp     TLOOP1

EQUALS: jsr     GETDW
        ldx     #$00
LCAFA:  lda     ($FB,x)
        cmp     ($FD,x)
        bne     LCB0B
        jsr     LC367
        inc     $FD
        bne     LCAFA
        inc     $FE
        bne     LCAFA
LCB0B:  jsr     LC34C
        jmp     LC323
        
; FIND (F)
FIND:   lda     #$FF            ; set start and end address to $FFFF
        ldx     #$04
LCB15:  sta     $FA,x
        dex
        bne     LCB15
        jsr     GETCHR          ; get next character
        ldx     #$05
LCB1F:  cmp     FSCMD-1,x       ; compare with sub-command char (AZIRT)
        beq     LCB69           ; jump if found
        dex
        bne     LCB1F           ; repeat until all checked

        ;; no sub-command found => plain "F" (find bytes)
        ;; (X=0 at this point)
LCB27:  stx     $A9             ; store number of bytes
        jsr     LCBB4           ; get search data for byte (two nibbles+bit masks)
        inx                     ; next byte
        jsr     CHRIN           ; get next character
        cmp     #' '            ; is it space?
        beq     LCB27           ; skip if so
        cmp     #$2C            ; is it ","
        bne     LCB3B           ; repeat if not
        jsr     GETDW           ; get start and end address of range
LCB3B:  jsr     LC351           ; print CR
LCB3E:  ldy     $A9             ; get number of bytes in sequence
LCB40:  lda     ($FB),y         ; get next byte in memory
        jsr     LCBD6           ; compare A with byte in expected sequence
        bne     LCB5F           ; jump if no match
        dey                     ; next byte
        bpl     LCB40           ; repeat until last byte in dequence
        jsr     LC323           ; found a match => print current address
        jsr     LC34C           ; print space
        ldy     $D3             ; get cursor coumn
        cpy     #76             ; compare to 76
        bcc     LCB5F           ; jump if less
        jsr     LC472           ; handle PAUSE/STOP
        jsr     LC351           ; print CR
LCB5F:  jsr     LC463           ; increment current location and check end
        bcc     LCB3E           ; repeat if end has not been reached
        ldy     #$27
        rts

        ;; execute "find" sub-command AZIRT with index in X
LCB69:  lda     LC074-1,x
        sta     $A8
        lda     LC079-1,x       ; get length of data item (2=word/1=byte/0=none)
        sta     $A9             ; store
        tax                     ; into x
        beq     LCB7C           ; skip getting argument if 0
LCB76:  jsr     LCBB4           ; get two nibbles
        dex                     ; do we need more (i.e. word)?
        bne     LCB76           ; jump if so
LCB7C:  jsr     GETDW           ; get start and end address
LCB7F:  jsr     LC4CB
        jsr     LC52C
        lda     $A8
        bit     $AB
        bne     LCB94
        tay
        bne     LCBAF
        lda     $AD
        bne     LCBAF
        beq     LCBA1
LCB94:  ldy     $A9
LCB96:  lda     $AD,y
        jsr     LCBD6
        bne     LCBAF
        dey
        bne     LCB96
LCBA1:  sty     $AA
        jsr     LC58C           ; disassemble one opcode at current addres
        jsr     LC472           ; handle PAUSE/STOP
LCBA9:  jsr     LC466           ; check whether end address has been reached
        bcc     LCB7F           ; repeat if not
        rts
        
LCBAF:  jsr     LC66A
        beq     LCBA9

        ;; get two nibbles with bit mask from command line
        ;; first  goes into $036C+x (bit mask in $03CC+x)
        ;; second goes into $033C+x (bit mask in $039C+x)
LCBB4:  jsr     LCBC0
        sta     $03CC,x
        lda     $033C,x
        sta     $036C,x
        
        ;; get nibble from command line, checking for wildcard ('*')
LCBC0:  jsr     GETCHR          ; get character
        ldy     #$0F            ; bit mask $0F
        cmp     #'*'            ; is it '*'?
        bne     LCBCB           ; jump if not
        ldy     #$00            ; bit mask $00
LCBCB:  jsr     LC2AF           ; convert char to nibble $0-$F
        sta     $033C,x         ; store nibble
        tya
        sta     $039C,x         ; store bit mask
        rts

        ;; compare byte in A with byte Y of expected sequence
        ;; return with Z set if matching
LCBD6:  sta     $B4             ; temp storage
        lsr                     ; get high nibble into low
        lsr
        lsr
        lsr
        eor     $036C,y         ; zero-out bits that match for high nibble
        and     $03CC,y         ; zero-out bits according to bit mask for high nibble
        and     #$0F            ; only bits 0-3
        bne     LCBF0           ; if not zero then we have a difference
        lda     $B4             ; get byte back
        eor     $033C,y         ; zero-out bits that match for low nibble
        and     $039C,y         ; zero-out bits according to bit mask for low nibble
        and     #$0F            ; only bits 0-3
LCBF0:  rts

        ;; memory size (MS)
MEMSIZ: ldx     #3
MSL1:   ldx     #$01            ; get 00,01,FF,FF
        stx     $FC             ; into FB-FE
        dex
        stx     $FB
        dex
        stx     $FD
        stx     $FE
        jsr     LC351           ; print CR
        ldx     #$00
MSL2:   lda     ($FB,x)         ; save current value
        tay
        lda     #$55
        sta     ($FB,x)
        cmp     ($FB,x)
        bne     MSL5
        lda     #$AA
        sta     ($FB,x)
        cmp     ($FB,x)
        bne     MSL5
MSL4:   tya
        sta     ($FB,x)         ; restore original value
        jsr     LC367           ; increment address
        jsr     LC466           ; check if we've tested the whole range
        bcc     MSL2            ; repeat if not
        .byte   $2C             ; skip following 2-byte opcode
MSL5:   sta     ($FB,x)
        jsr     LC323           ; print current address
        rts                     ; done
        
        ;; memory test (MT)
MEMTST: ldx     #$A4
        jsr     GETWRDX         ; get start address
        jsr     GETWRDX         ; get end address
        ldy     #1              ; default: 1 repetition
        jsr     PEEKCH          ; do we have more arguments?
        beq     MTL1            ; skip if not
        jsr     LC28D           ; get number of repetitions
        tay
MTL1:   sty     $FF             ; store number of repetitions
        lda     $FC             ; get high byte of start address
        bne     MTL2            ; is it greater than zero?
        jmp     ERROR           ; no => can't test zero-page memory
MTL2:   jsr     LC351           ; print CR
MTL3:   ldx     #3
MTL4:   lda     $A4,x           ; get start and end address back
        sta     $FB,x           ; from temp to FB-FE
        dex
        bpl     MTL4
        ldx     #0
MTL5:   lda     ($FB,x)         ; save current value
        tay
        lda     #$00
        sta     ($FB,x)
        cmp     ($FB,x)
        bne     MTL6
        lda     #$55
        sta     ($FB,x)
        cmp     ($FB,x)
        bne     MTL6
        lda     #$AA
        sta     ($FB,x)
        cmp     ($FB,x)
        bne     MTL6
        lda     #$FF
        sta     ($FB,x)
        cmp     ($FB,x)
        beq     MTL7
MTL6:   jsr     LC323           ; fail: output current address
        jsr     LC34C           ; output space
MTL7:   tya
        sta     ($FB,x)         ; restore original value
        jsr     LC367           ; increment address
        jsr     LC466           ; check if we've tested the whole range
        bcc     MTL5            ; repeat if not
        lda     #'+'            ; print pacifier
        jsr     $FFD2
        dec     $FF             ; decrement repetition count
        bne     MTL3            ; go again until 0
        rts
        
; TRACE (Tx)
TRACE:  .if     VIA == 0
        jmp     ERROR           ; can only do trace if we have a VIA
        .endif
        pla
        pla
        jsr     CHRIN
        jsr     UCASE
        cmp     #$57
        bne     LCBFD
        jmp     LCD56           ; TW command
LCBFD:  cmp     #$42
        bne     LCC04
        jmp     LCDD0           ; TB command
LCC04:  cmp     #$51
        bne     LCC0B
        jmp     LCD4F           ; TQ command
LCC0B:  cmp     #$53
        beq     LCC12           ; TS command
        jmp     ERROR

        ;; Trace Stop (TS)
LCC12:  jsr     LC28D
        pha
        jsr     LC28D
        pha
        jsr     LC249
        ldy     #$00
        lda     ($FB),y
        sta     $02BC
        tya
        sta     ($FB),y
        lda     #<TBINT         ; set BREAK vector
        sta     BRK_LO          ; to breakpoint entry
        lda     #>TBINT
        sta     BRK_HI
        ldx     #$FC
        jmp     LC3EC

        ;; entry point after breakpoint is hit
TBINT:  ldx     #$03
LCC38:  pla
        sta     SRSAVE,x
        dex
        bpl     LCC38
        pla
        pla
        tsx
        stx     SPSAVE
        lda     PCHSAVE
        sta     $FC
        lda     PCLSAVE
        sta     $FB
        lda     $02BC
        ldy     #$00
        sta     ($FB),y
        lda     #<SMON          ; restore BREAK vector
        sta     BRK_LO          ; to SMON main loop
        lda     #>SMON
        sta     BRK_HI
        lda     #$52
        jmp     LC2FF
LCC65:  jsr     LC351
RTSCMD: rts
        sta     AKSAVE
        php
        pla
        and     #$EF
        sta     SRSAVE
        stx     XRSAVE
        sty     YSAVE
        pla
        clc
        adc     #$01
        sta     PCLSAVE
        pla
        adc     #$00
        sta     PCHSAVE
        lda     #$80
        sta     $02BC
        bne     LCCA5

        ;; entry point from TW after an instruction has been executed
        ;; (via timer interrupt)
TWINT:  lda     #$40            ; clear VIA timer 1 interrupt flag
        sta     VIA_IFR
        jsr     LCDE5           ; restore IRQ vector
        cld                     ; make sure "decimal" flag is not set
        .if UART_TYPE==6522     ; if VIA is also used as UART
        lda     #$40            ; set T1 free run, T2 clock ?2
        sta     VIA_ACR         ; set VIA 1 ACR
        lda	#$40		; disable VIA timer 1 interrupt
	sta	VIA_IER		; set VIA 1 IER
        lda	#$90		; enable VIA CB1 interrupt
	sta	VIA_IER		; set VIA 1 IER
        .endif
        ldx     #$05            ; get registers from stack
LCC9E:  pla                     ; (were put there when IRQ happened)
        sta     PCHSAVE,x       ; store them in PCHSAVE area
        dex
        bpl     LCC9E
LCCA5:  lda     IRQ_LO          ; save IRQ pointer
        sta     $02BB
        lda     IRQ_HI
        sta     $02BA
        tsx
        stx     SPSAVE          ; save stack pointer
        cli                     ; allow interrupts
        
        lda     SRSAVE
        and     #$10
        beq     LCCC5
LCCBD:  jsr     LCC65
        lda     #$52
        jmp     LC2FF
LCCC5:  bit     $02BC
        bvc     LCCE9
        sec
        lda     PCLSAVE
        sbc     $02BD
        sta     $02B1
        lda     PCHSAVE
        sbc     $02BE
        ora     $02B1
        bne     LCD46
        lda     $02BF
        bne     LCD43
        lda     #$80
        sta     $02BC
LCCE9:  bmi     LCCFD
        lsr     $02BC
        bcc     LCCBD
        ldx     SPSAVE
        txs
        lda     #>RTSCMD
        pha
        lda     #<RTSCMD
        pha
        jmp     LCDBA
LCCFD:  jsr     LCC65
        lda     #$A8
        sta     $FB
        lda     #$02
        sta     $FC
        jsr     LC34C
        ldy     #$00
LCD0D:  lda     ($FB),y
        jsr     LC32A
        iny
        cpy     #$07
        beq     LCD20
        cpy     #$01
        beq     LCD0D
        jsr     LC34C
        bne     LCD0D
LCD20:  lda     PCLSAVE         ; get PC
        ldx     PCHSAVE
        sta     $FB             ; set it as current address
        stx     $FC
        jsr     LC349           ; output two spaces
        jsr     LC4CB           ; 
        jsr     LC5C7           ; disassemble next opcode
LCD33:  jsr     GETIN           ; get keyboard key
        beq     LCD33           ; wait until we have something
        cmp     #$4A            ; was it 'J'?
        bne     LCD46           ; jump if not
        lda     #$01
        sta     $02BC
        bne     LCD72           ; take next TW step
LCD43:  dec     $02BF
LCD46:  lda     $91             ; get "STOP" flag
        cmp     #$7F            ; is it set?
        bne     LCD72           ; if not, take next TW step
        jmp     LCCBD

        ;; Trace Quick (TQ)
LCD4F:  jsr     LCDF2
        lda     #$40
        bne     LCD60
     
        ;; Trace Walk (TW)
LCD56:  jsr     LCDF2
        php
        pla
        sta     SRSAVE
        lda     #$80
LCD60:  sta     $02BC
        tsx
        stx     SPSAVE
        jsr     LC249
        jsr     LCC65
        lda     $02BC
        beq     LCDA9
LCD72:  .if UART_TYPE==6522     ; if VIA is also used as UART
        lda     VIA_IER         ; get enabled VIA interrupts
        and     #$60            ; isolate T1 and T2 interrupts
        bne     LCD72           ; wait until both disabled (UART is idle)
        .endif
        sei
        lda     #$7F
        sta     VIA_IER         ; disable all VIA interrupts
        lda     #$C0
        sta     VIA_IER         ; enable VIA timer 1 interrupt
        lda     #$00
        sta     VIA_ACR         ; VIA timer 1 single-shot mode
        ldx     #0
        lda     #73             ; 73 cycles until timer expires
        sta     VIA_T1LL        ; set VIA timer 1 low-order latch 
        stx     VIA_T1CH        ; set VIA timer 1 high-order counter (start timer)
        lda     #<TWINT         ; (2)
        ldx     #>TWINT         ; (2)
        sta     $02BB           ; (4)
        stx     $02BA           ; (4)
LCDA9:  ldx     SPSAVE          ; (4)
        txs                     ; (2)
        cli                     ; (2)
        lda     $02BB           ; (4)
        ldx     $02BA           ; (4)
        sta     IRQ_LO          ; (4)
        stx     IRQ_HI          ; (4)
LCDBA:  lda     PCHSAVE         ; (4)
        pha                     ; (3)
        lda     PCLSAVE         ; (4)
        pha                     ; (3)
        lda     SRSAVE          ; (4)
        pha                     ; (3)
        lda     AKSAVE          ; (4)
        ldx     XRSAVE          ; (4)
        ldy     YSAVE           ; (4)
        rti                     ; (6) => total 75 cycles, timer expires during RTI?

        ;; Trace Break (TB)
LCDD0:  jsr     LC28D
        sta     $02BE
        jsr     LC28D
        sta     $02BD
        jsr     LC28D
        sta     $02BF
        jmp     LC2D6

        ;; restore IRQ vector
LCDE5:  lda     $02B8
        ldx     $02B9
        sta     IRQ_LO
        stx     IRQ_HI
        rts

        ;; save IRQ vector and set BRK vector to entry point
LCDF2:  lda     IRQ_LO
        ldx     IRQ_HI
        sta     $02B8
        stx     $02B9
        lda     #<TWINT
        sta     BRK_LO
        lda     #>TWINT
        sta     BRK_HI
        rts
        
;;; ----------------------------------------------------------------------------
;;; ---------------------------  C64 KERNAL routines   -------------------------
;;; ----------------------------------------------------------------------------

LINEBUF         = $0400         ; line ("screen") buffer memory start
NUMCOLS         = 80            ; number of columns per row
NUMROWS         = 24            ; number of rows
INPUT_UCASE     = 0             ; do not automatically convert input to uppercase
SUPPRESS_NP     = 0             ; do not suppress any characters on output

        ;; print 16-bit integer in $62/$63 as decimal value, adapted from:
        ;; https://beebwiki.mdfs.net/Number_output_in_6502_machine_code#16-bit_decimal
PRTINT: LDY #8                  ; offset to powers of ten
PRL1:   LDX #$FF
        SEC                     ; start with digit=-1
PRL2:   LDA $63
        SBC PRPOW+0,Y
        STA $63                 ; subtract current tens
        LDA $62
        SBC PRPOW+1,Y
        STA $62
        INX
        BCS PRL2                ; loop until <0
        LDA $63                 ; add current tens back in
        ADC PRPOW+0,Y
        STA $63
        LDA $62
        ADC PRPOW+1,Y
        STA $62
        TXA
        BEQ PRL3                ; leading zero => skip
        ORA #'0'                ; convert to 0-9 digit
        JSR CHROUT              ; output character
PRL3:   DEY
        DEY
        BPL PRL1                ; Loop for next digit
        RTS
PRPOW:  .word 1, 10, 100, 1000, 10000
        
        .include "kernal.asm"
