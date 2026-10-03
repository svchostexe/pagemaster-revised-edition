; The Pagemaster (SNES, US) - hit detection fixes. asar patch, LoROM.
; Apply to the clean US ROM (sha1 02fa190b...):  asar hitfix.asm out.sfc
;
; 1) Stomp tolerance (B2:FD0C): the "landed from above" test only passed when the
;    stomper's previous-frame bottom was at or above the target's top, with zero slack.
;    Now allows !STOMP_TOL extra pixels of overlap.
; 2) Contact inset (B2:FC2D): the shared "probe vs entity list" test used the full
;    probe rectangle. The probe is now inset by !HURT_INSET pixels on every side, so
;    brushing past something no longer counts as a hit.

; 3) Player pass (B2:FD22, player vs the entity list): this is where stone fists, thrown objects, rising hazards and the static
;    hazard rects hurt Richard (B0:C2EC), and also where pickups are collected and stomps/triggers are detected. It builds
;    Richard's rect into $1D5F..$1D65 and tests every entity strictly against it. Everything is tested against an inset rect
;    (!PIN_X/!PIN_T/!PIN_B) except pickups, which get a grown rect (!GROW_X/!GROW_Y). See the block at BE:9000 below.

lorom

!STOMP_TOL  = 6
!HURT_INSET = 2
!PIN_X      = 3      ; Richard hurtbox inset, left and right
!PIN_T      = 3      ; top
!PIN_B      = 2      ; bottom

; ---- free space: 0xFF padding at the end of the ROM (file 0x1E941A..end) ----
org $BE8000

; Replaces `DEC A : CMP $1D69` at B2:FD16 (same 4 bytes: JSL).
; In: A = previous-frame bottom (16-bit). Out: flags from CMP, as the caller expects.
stomp_tol:
    sec
    sbc.w #!STOMP_TOL+1        ; original subtracted 1 (DEC A)
    cmp.w $1D69
    rtl

; Replaces the probe-rectangle build at B2:FC42..FC61 (jumped over, rejoin at FC62).
; Same math as the original, with the rectangle inset by !HURT_INSET.
hurt_probe:
    ; original rectangle build, byte for byte the same math (incl. its +1 carry quirk)
    lda.w $0EBD,x
    clc
    adc.w $185D,x
    sta.w $1D5F
    adc.w $190D,x
    sta.w $1D63
    lda.w $0E65,x
    clc
    adc.w $18B5,x
    sta.w $1D61
    adc.w $1965,x
    sta.w $1D65
    ; inset on every side
    lda.w $1D5F
    clc
    adc.w #!HURT_INSET
    sta.w $1D5F
    lda.w $1D63
    sec
    sbc.w #!HURT_INSET
    sta.w $1D63
    lda.w $1D61
    clc
    adc.w #!HURT_INSET
    sta.w $1D61
    lda.w $1D65
    sec
    sbc.w #!HURT_INSET
    sta.w $1D65
    jml $B2FC62

; ---- hooks ----
org $B2FD16
    jsl stomp_tol              ; 22 xx xx BE, replaces 3A CD 69 1D

org $B2FC42
    jml hurt_probe             ; replaces the 32-byte probe build, rejoin at FC62

; ---- player pass B2:FD22: per-entity-type rectangle (BE:9000, clear of hp.asm at BE:8500) ----
;
; The first version of this patch shrank Richard's rectangle for the whole pass. That pass does not only test hazards: every
; entity in the list is tested against that one rectangle, and the flags word $0D5D,x says what a hit means
; ($0001 stompable, $0002 hurts, $0004 trigger, $0008 / $0080 collectible: B2:FE56 runs the pickup handler). So the shrink made
; pickups need 3-4 px of overlap instead of the original 1 (measured with work/pagemaster/pickmeasure.lua), and stomp/trigger
; contact needed more as well. Now the pass uses three rectangles, chosen per entity:
;   hurts ($0002 set)                      -> inset rectangle (full - !PIN_X/!PIN_T/!PIN_B), as before; also used for the static hazard rects
;   collectible (flags & 7 == 0, & $88)    -> grown rectangle (full + !GROW_X/!GROW_Y on every side): a pickup counts when it is close
;   anything else (stomps, triggers)       -> the full original rectangle (the game's own behaviour)
; The inset and grown rectangles live in scratch WRAM (7E:6040.. / 7E:6050..: [left, top, right, bottom] words) and are rebuilt once
; per pass. $1D5F..$1D65 is the full rectangle again before the entity loop starts, so the box-2 copy at B2:FE3D is the original code.

!GROW_X     = 4      ; pickup grab margin, left and right
!GROW_Y     = 4      ; pickup grab margin, top and bottom
!R_INSET    = $7E6040
!R_GROW     = $7E6050

org $BE9000

; Replaces `LDA $1D89 : BNE $FD50 : JMP $FD89` at B2:FD48 (JML; the rest of the old bytes are never reached).
; $1D5F..$1D65 = full rectangle on entry.
pin_inset:
    lda.w $1D5F
    sec
    sbc.w #!GROW_X
    sta.l !R_GROW+0
    lda.w $1D61
    sec
    sbc.w #!GROW_Y
    sta.l !R_GROW+2
    lda.w $1D63
    clc
    adc.w #!GROW_X
    sta.l !R_GROW+4
    lda.w $1D65
    clc
    adc.w #!GROW_Y
    sta.l !R_GROW+6
    ; inset in place: the static hazard rects (first loop) are tested against $1D5F.. as before
    lda.w $1D5F
    clc
    adc.w #!PIN_X
    sta.w $1D5F
    lda.w $1D63
    sec
    sbc.w #!PIN_X
    sta.w $1D63
    lda.w $1D61
    clc
    adc.w #!PIN_T
    sta.w $1D61
    lda.w $1D65
    sec
    sbc.w #!PIN_B
    sta.w $1D65
    lda.w $1D89
    bne .rects
    jml $B2FD89
.rects:
    jml $B2FD50

; Replaces `LDA $1E0F : BPL $FD8F : RTL` at B2:FD89 (JML). Both ways out of the static-rect loop arrive here.
; Keep the inset rectangle for hurting entities, then give the entity loop the full rectangle back.
pass_restore:
    lda.w $1D5F
    sta.l !R_INSET+0
    sec
    sbc.w #!PIN_X
    sta.w $1D5F
    lda.w $1D61
    sta.l !R_INSET+2
    sec
    sbc.w #!PIN_T
    sta.w $1D61
    lda.w $1D63
    sta.l !R_INSET+4
    clc
    adc.w #!PIN_X
    sta.w $1D63
    lda.w $1D65
    sta.l !R_INSET+6
    clc
    adc.w #!PIN_B
    sta.w $1D65
    lda.w $1E0F
    bpl .go
    rtl
.go:
    jml $B2FD8F

; Replaces the entity/rectangle overlap test at B2:FD9C..FDCA (JML). X = entity. Original semantics, strict on all four sides, same
; instruction sequence (carry behaviour included); only the rectangle differs. Overlap -> B2:FDCB (the flag handlers), else B2:FE2D.
; Pickups are the entities whose collect handler (97:EFCC table, indexed by $0CAD,x) is AD:B4A2: types $4E, $50, $52, $16C.
; Their 11x11 boxes share the flag $0008 with enemies such as the bats (which must NOT get extra reach), so the type decides.
ent_test:
    lda.w $0D5D,x
    bit.w #$0008
    beq ent_inset
    lda.w $0CAD,x
    cmp.w #$004E
    beq ent_grow
    cmp.w #$0050
    beq ent_grow
    cmp.w #$0052
    beq ent_grow
    cmp.w #$016C
    bne ent_inset
ent_grow:
    lda.w $0EBD,x
    clc
    adc.w $185D,x
    cmp.l !R_GROW+4
    bmi .a
    jml $B2FE2D
.a: adc.w $190D,x
    cmp.l !R_GROW+0
    beq .no
    bmi .no
    lda.w $0E65,x
    clc
    adc.w $18B5,x
    cmp.l !R_GROW+6
    bpl .no
    adc.w $1965,x
    cmp.l !R_GROW+2
    beq .no
    bmi .no
    jml $B2FDCB
.no:
    jml $B2FE2D

ent_inset:
    lda.w $0EBD,x
    clc
    adc.w $185D,x
    cmp.l !R_INSET+4
    bmi .a
    jml $B2FE2D
.a: adc.w $190D,x
    cmp.l !R_INSET+0
    beq .no
    bmi .no
    lda.w $0E65,x
    clc
    adc.w $18B5,x
    cmp.l !R_INSET+6
    bpl .no
    adc.w $1965,x
    cmp.l !R_INSET+2
    beq .no
    bmi .no
    jml $B2FDCB
.no:
    jml $B2FE2D

org $B2FD48
    jml pin_inset

org $B2FD89
    jml pass_restore

org $B2FD9C
    jml ent_test
