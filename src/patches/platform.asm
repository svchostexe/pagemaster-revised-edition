; The Pagemaster (SNES, US) - more forgiving platform edges: thin platforms (the flat open-book platforms) catch Richard
; when he only just reaches them. asar patch, LoROM.
;
; Every entity's tile collision runs through B2:F6C2 (standing) or B2:F7C7 (airborne; Richard's fall state B25C uses
; this one): JSL B2:F227 (vertical probe) -> on a hit B2:F1E3 (snap, zero vy)
; -> B2:F40A (horizontal probe). F227 counts the solid tiles in the columns under the entity's box (left edge x+$1E05,
; width $1E; Richard -6 and 13) at the feet row when falling/standing (vy >= 0), the head row when rising; carry set =
; ground if any column is solid. Measured on the flat book in the Torture Chamber: it catches a drop for x 803..917.
; For Richard only, in that falling/standing case, a probe that finds no ground is retried with the footprint widened by
; !FLOOR_EXT px on each side - but only if the same widened columns one tile higher are free of solid tile. That second
; check is what keeps him from "standing" in mid-air beside a wall. Registers/DP temps are restored before returning and
; the probe that decides the result is always the last one run, so the snap (B2:F1E3) sees consistent data.

lorom

!FLOOR_EXT = 8
!SV_05 = $7E6010               ; scratch words (7E:6000-63FF is never touched by the game; hp.asm uses 6000-6004)
!SV_07 = $7E6012
!SV_1E = $7E6014

org $B2F6C2                    ; standing/walking collision pass: was JSL $B2F227
    jsl floor_wide

org $B2F7C7                    ; airborne collision pass (state B25C etc.): was JSL $B2F227
    jsl floor_wide

org $BEB700                    ; (was BE:8800; hp.asm grew into it with the cheat checks)
floor_wide:
    cpx.w $0C33                ; Richard's slot
    bne .plain
    lda.w $1285,x              ; vy: negative = rising, leave the head probe alone
    bmi .plain
    jsl $B2F227                ; 1) the normal probe
    bcs .done
    lda.w $1E05                ; keep the originals
    sta.l !SV_05
    lda.w $1E07
    sta.l !SV_07
    lda.b $1E
    sta.l !SV_1E
    lda.w $1E05                ; widen the footprint
    sec
    sbc.w #!FLOOR_EXT
    sta.w $1E05
    lda.b $1E
    clc
    adc.w #!FLOOR_EXT*2
    sta.b $1E
    lda.w $1E07                ; 2) the same columns one tile higher: solid there = a wall beside us, not a platform
    sec
    sbc.w #8
    sta.w $1E07
    jsl $B2F227
    bcs .wall
    lda.l !SV_07               ; 3) feet row again with the widened footprint; its result stands (LDA/STA keep carry)
    sta.w $1E07
    jsl $B2F227
    lda.l !SV_05
    sta.w $1E05
    lda.l !SV_1E
    sta.b $1E
    rtl
.wall:
    lda.l !SV_05
    sta.w $1E05
    lda.l !SV_07
    sta.w $1E07
    lda.l !SV_1E
    sta.b $1E
    jsl $B2F227                ; normal probe again so its results are the last ones left behind
    clc
.done:
    rtl
.plain:
    jml $B2F227                ; tail call, its RTL returns to B2:F6C6

; --- Landing on entity platforms (flying books, type $00E0, flag $0001) -------------------------------------------------
; B2:FD22's list loop lands Richard on a flag-1 entity when (a) his box overlaps the entity's and (b) B2:FD01 says the entity's
; previous-frame top was at or below Richard's previous-frame bottom. Recording (bookrec2.lua) showed the overlap only starts once
; his bottom is ~2 px past the book top, while (b) already fails once his previous bottom was 1 px past it: a fall whose frame
; step puts the previous bottom in that 400/401 gap (top = 399) overlaps but never lands and falls straight through. Slow falls
; (a standing jump's descent, 2 px/frame) fall in the gap almost every time. Fix: while Richard is not rising (vy >= 0), accept a
; previous bottom up to !LAND_TOL px below the top. Rising keeps the original test, so jumping up through a book still works.

!LAND_TOL = 8

org $B2FDF3                    ; was JSL $B2FD01
    jsl book_land

org $BE9200
book_land:                     ; X = platform entity, returns carry set = may land (same contract as B2:FD01)
    lda.w $15F5,x
    clc
    adc.w $18B5,x
    cmp.w $1D6D                ; original: platform's previous top >= Richard's previous bottom
    bcs .ok
    pha
    phx
    ldx.w $0C33
    lda.w $1285,x              ; Richard's vy: negative = rising
    plx
    bmi .rising
    pla
    clc
    adc.w #!LAND_TOL
    cmp.w $1D6D
.ok:
    rtl
.rising:
    pla
    clc
    rtl

; --- Wider catch box for the flying books (type $00E0) ---------------------------------------------------------------------
; The books' box (left -22, width 43) is narrower than the sprite, so a jump from under the visible edge of a book overlaps
; nothing (recorded: standing jumps at x=2637 against a book at x=2668 had no overlap at all). 97:F350 copies the per-type
; box tables into the entity ($185D left / $190D width / $18B5 top / $1965 height); hook the top-field copy and, for type
; $00E0, grow the box by !BOOK_EXT px on each side. Vertical box is unchanged.

!BOOK_EXT = 8

org $97F36B                    ; was LDA.W $D48C,Y : STA.W $18B5,X (6 bytes), DBR = $97 here
    jsl book_box
    nop
    nop

org $BE9300
book_box:
    php
    rep #$30
    lda.w $D48C,y              ; displaced
    sta.w $18B5,x
    cpy.w #$00E0
    bne .done
    lda.w $185D,x
    sec
    sbc.w #!BOOK_EXT
    sta.w $185D,x
    lda.w $190D,x
    clc
    adc.w #!BOOK_EXT*2
    sta.w $190D,x
.done:
    plp
    rtl
