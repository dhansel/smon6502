;;; ----------------------------------------------------------------------------
;;; ---------------------- UART communication functions  -----------------------
;;; ----------------------------------------------------------------------------

UART    = $8200
UARTS   = UART+0
UARTD   = UART+1

        ;; initialize UART
UAINIT: lda #$03                ; reset UART
        sta UARTS
        lda #$15                ; set 8N1 serial parameter
        sta UARTS
        rts
                
        ;; write character to UART, wait until UART is ready to transmit
        ;; A, X and Y registers must remain unchanged
UAPUTW: PHA                     ; save character
UAPUTL: LDA     UARTS           ; check UART status
        AND     #$02            ; can write?
        BEQ     UAPUTL          ; wait if not
        PLA                     ; restore character
        STA     UARTD           ; write character
        RTS

        ;; get character from UART, return result in A,
        ;; return A=0 if no character available for reading
        ;; X and Y registers must remain unchanged
UAGET:  LDA     UARTS           ; check UART status
        AND     #$01            ; can read?
        BEQ     UAGRET          ; if not, return with Z flag set
        LDA     UARTD           ; read UART data
UAGRET: RTS
        
        ;; get character from UART, wait if none, return result in A
        ;; X and Y registers must remain unchanged
UAGETW: JSR     UAGET
        BEQ     UAGETW
        RTS
