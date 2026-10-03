; The Pagemaster (SNES, US) - movement feel patch. asar patch, LoROM. Apply AFTER hitfix.asm (different free space).
;
; Richard's horizontal speed is 16.16 fixed point ($1335,X integer : $12DD,X fraction).
; Originally:
;   accelerate  +/-$2C71 per frame   (0.17 px/frame^2, ~19 frames to the +/-3.33 cap)
;   friction A  $0B1C per frame      (0.043)  applied every frame after accelerating (routine B0:C9D7)
;   friction B  $1638 per frame      (0.087)  same, other state (routine B0:CA54)
; so he ramps up slowly and slides 40-70 px after you let go.
; The accelerate routines read the joypad, so they are Richard-only and are patched in place.
; The friction routines are shared with enemies, so they get a slot check ($0C33 = player slot)
; and only Richard uses the new values.

lorom

!ACCEL  = $8000        ; was $2C71
!FRIC_A = $3000        ; was $0B1C  (Richard only)
!FRIC_B = $4000        ; was $1638  (Richard only)

; ---- accelerate constants (Richard-only code) ----
org $B0C9F6
    dw !ACCEL                  ; routine 1, right
org $B0CA07
    dw (-!ACCEL)&$FFFF         ; routine 1, left
org $B0CA73
    dw !ACCEL                  ; routine 2, right
org $B0CA84
    dw (-!ACCEL)&$FFFF         ; routine 2, left

; ---- friction hooks (6 bytes each: LDA $12DD,X / LDY $1335,X) ----
org $B0CAD1
    jml fric_a
    nop
    nop

org $B0CB0C
    jml fric_b
    nop
    nop

; ---- new code in the free padding at the end of the ROM ----
org $BE8100

fric_a:
    cpx.w $0C33
    beq .player
    lda.w $12DD,x              ; not Richard: the two instructions we displaced, then back
    ldy.w $1335,x
    jml $B0CAD7
.player:
    lda.w $12DD,x
    ldy.w $1335,x
    bpl .pos
    clc
    adc.w #!FRIC_A
    sta.w $12DD,x
    tya
    adc.w #$0000
    sta.w $1335,x
    bpl .zero
    rtl
.pos:
    clc
    adc.w #(-!FRIC_A)&$FFFF
    sta.w $12DD,x
    tya
    adc.w #$FFFF
    sta.w $1335,x
    bpl .chk
.zero:
    stz.w $12DD,x
    stz.w $1335,x
.chk:
    lda.w $12DD,x
    ora.w $12DD,x              ; (original ORAs the same word twice; kept as is)
    bne .nz
    sec
    rtl
.nz:
    clc
    rtl

fric_b:
    cpx.w $0C33
    beq .player
    lda.w $12DD,x
    ldy.w $1335,x
    jml $B0CB12
.player:
    lda.w $12DD,x
    ldy.w $1335,x
    bpl .pos
    clc
    adc.w #!FRIC_B
    sta.w $12DD,x
    tya
    adc.w #$0000
    sta.w $1335,x
    bpl .zero
    rtl
.pos:
    clc
    adc.w #(-!FRIC_B)&$FFFF
    sta.w $12DD,x
    tya
    adc.w #$FFFF
    sta.w $1335,x
    bpl .chk
.zero:
    stz.w $12DD,x
    stz.w $1335,x
.chk:
    lda.w $12DD,x
    ora.w $12DD,x
    bne .nz
    sec
    rtl
.nz:
    clc
    rtl
