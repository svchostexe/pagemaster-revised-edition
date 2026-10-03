; The Pagemaster (SNES, US) - title screen "REVISED EDITION" banner, red and slanted, stamped onto the page by a rubber stamp
; (pale wood block with grain, black turned handle, black foam line and a red rubber pad). asar patch, LoROM.
;
; The title menu text (START GAME / PASSWORD / CHEATS) is not background: it is 16x16 OAM sprites using
; a 26-glyph font (A-Z) already in OBJ VRAM, palette 7. Glyph tile for letter n is
; (n/8)*$20 + (n%8)*2, e.g. A=$00 M=$28 S=$44. The title frame routine at A9:EEC4 clears the
; OAM shadow ($0957 + 4*slot: x, y, tile, attr; high table at $0B57) and then draws its text
; into the top slots (106..127). Slots 0..105 stay hidden on the title, so after the clear we
; stamp the banner letters into 0..15 and the stamp itself into 16..58 (a space is a slot parked at y=$F0).
;
; Hook: A9:EEDE `LDA #$1000 : STA $B8` (5 bytes) -> JSL + NOP; the stub redoes both instructions.
; The title frame routine and the OAM DMA routine (A9:FC68) both run every OTHER video frame (30 Hz) while the title is up,
; and the palette upload (BA:F38A) only once when the title loads.
;
; Animation: !STAMP_T counts title frames since the red ink is in the palette buffer (0 whenever it is not, so every visit to
; the title replays it; the value is protected by !STAMP_K = T eor $5A5A because that WRAM is never initialised).
;   T 1..11   VRAM jobs (below), nothing to see
;   T 12..19  the stamp drops in, accelerating (the handle first)
;   T 19      impact: the game's sound routine plays !THUD_SND, the thud sample injected into the title sound bank (thud.asm)
;   T 20..22  it sits on the page; the screen jolts for 7 title frames (BG vertical scroll, see stamp_bgv)
;   T 23..27  it lifts off
;   T >= 26   the letters appear, ink flashes white -> pink -> red (CGRAM written directly, see stamp_flash)
; Art (genstamp2.py -> stamp_art.inc / stamp_parts.inc): ten 16x16 graphics, each four OBJ tiles, borrowed from the VRAM tiles of
; the font glyphs B F J K L Q U X Y Z (none of them appears on the title screen; the password screen's text that uses U and Y
; is only reachable after the stamp has handed the tiles back). The stamp's colours live in OBJ palette 5 indices 1-12 (the
; banner ink uses 13 and 14). Per T, stamp_act lists up to two VRAM jobs for the OAM DMA hook (hp.asm calls stamp_vblank at
; BE:9800, inside vblank): save a glyph's tiles to WRAM, upload the stamp graphic, later restore the glyph, write the palette.

lorom

!BANNER_X = 36                  ; 15 used slots at a 12 px pitch, centred
!BANNER_Y = 152                 ; y of the first letter; each later letter sits 3/2 px higher (stamp slant)
!BANNER_ATTR = $3A              ; priority 3, OBJ palette 5 (a row that is empty on the title)
incsrc "stamp_defs.inc"          ; !PLATE_Y (the stamp's y when it is down; its pad bottom follows the banner's letters) and !STAMP_PARTS
!LETTERS_T = 26
!THUD_T = 19                    ; the T at which the stamp reaches the page
!THUD_SND = $0070               ; effect 0 of group 3 in the title bank: the synthesised thud (patches/thud.asm)
!T_END = 38                     ; the per-T tables cover T = 0..37
!MUSIC_FRAMES = 34              ; the title song starts this many title frames after the title is set up (see music_defer)
!MUS_T = $7E6030                ; word: title frames since music_defer armed it
!MUS_K = $7E6032                ; word: !MUS_T eor $A5A5 (0 = not armed; this WRAM is never initialised)

; Palette 5 is empty on the title, so the banner gets its own red ink. The OBJ palette upload
; (BA:F38A, DMA of the WRAM buffer at $0595 to CGRAM $80) is hooked; its stub fills row 5
; ($0635) with ink/shadow in the font's two used indices (13 shadow, 14 face), only when the
; buffer looks like the title (row 5 empty, row 6 = the title fairy palette). The stamp stub then
; only draws while that red is in the buffer, so the password screen (same frame routine) stays clean.
!PAL5_IDX13 = $7E064F
!PAL5_IDX14 = $7E0651

!STAMP_T = $7E6020              ; word (7E:6000-63FF is never touched by the game except hitfix's scratch at 6040-605F)
!STAMP_K = $7E6022              ; word, T eor $5A5A
!S_OFF = $7E6024                ; word scratch: stamp vertical offset this frame
!S_TMP = $7E6026                ; word scratch
!S_G = $7E6028                  ; word scratch: graphic number of the current VRAM job
!S_KIND = $7E602A               ; word scratch: kind of the current VRAM job
!S_JOBS = $7E602C               ; word scratch: this frame's two job codes
!STAMP_SAVE = $7E6500           ; 1280 bytes (6500-69FF): the original glyph tiles, 10 graphics x 128 bytes

org $A9EEDE
    jsl stamp_frame
    nop

org $B0851A                     ; title setup: was LDA #$00C0 : JSL $9F8008 (start the title song) - deferred, see music_defer
    jsl music_defer
    nop
    nop
    nop

org $BAF38A
    jsl banner_pal
    nop
    nop
    nop

org $BE8200
banner_pal:
    php
    rep #$20
    lda.l !PAL5_IDX13
    ora.l !PAL5_IDX14
    bne +
    lda.l $7E0595+(6*32)+(1*2)  ; row 6 idx 1: the fairy's pink, loaded on the title only
    cmp.w #$52D9
    bne +
    lda.w #$0008                ; shadow: dark red
    sta.l !PAL5_IDX13
    lda.w #$0C1F                ; face: stamp-ink red (r31 g0 b3)
    sta.l !PAL5_IDX14
+   plp
    sep #$20                    ; displaced: SEP #$20 : LDA #$80 : STA $2121
    lda.b #$80
    sta.w $2121
    rtl

!n = 0
macro glyph(tile)
    db !BANNER_X+(12*!n), !BANNER_Y-((!n*3)/2), <tile>, !BANNER_ATTR
    !n #= !n+1
endmacro
macro gap()
    db 0, $F0, 0, 0
    !n #= !n+1
endmacro

; R E V I S E D _ E D I T I O N (16th slot unused)
banner_oam:
    %glyph($42)
    %glyph($08)
    %glyph($4A)
    %glyph($20)
    %glyph($44)
    %glyph($08)
    %glyph($06)
    %gap()
    %glyph($08)
    %glyph($06)
    %glyph($20)
    %glyph($46)
    %glyph($20)
    %glyph($2C)
    %glyph($2A)
    %gap()

; Every sound effect is silent while the title song plays: the song reserves all eight SPC voices at priority $80 and effects
; (priority $40) can only take a voice with a lower priority. So the song's start command ($C0, sent by the title setup right after
; $E1 "release music voices") is held back: music_defer arms !MUS_T, stamp_frame counts title frames and sends $C0 after the stamp has
; landed and the thud has played (!MUSIC_FRAMES). If the player leaves the title earlier, the next screen sends its own music.
music_defer:
    php
    rep #$30
    pha
    lda.w #0
    sta.l !MUS_T
    lda.w #$A5A5
    sta.l !MUS_K
    pla
    plp
    rtl

macro set_t()                   ; A = T
    sta.l !STAMP_T
    eor.w #$5A5A
    sta.l !STAMP_K
endmacro

org $BE9500
stamp_frame:
    php
    rep #$30
    pha
    phx
    phy
    phb
    pea.w $BEBE                 ; DBR = $BE so the tables can be indexed with Y
    plb
    plb
    lda.l !MUS_T                ; the deferred title song
    tax
    eor.w #$A5A5
    cmp.l !MUS_K
    bne .musdone                ; not armed
    cpx.w #!MUSIC_FRAMES
    bcs .musdone                ; already started
    inx
    txa
    sta.l !MUS_T
    eor.w #$A5A5
    sta.l !MUS_K
    cpx.w #!MUSIC_FRAMES
    bne .musdone
    lda.w #$00C0
    jsl $9DEDB3
.musdone:
    lda.l !PAL5_IDX14
    cmp.w #$0C1F
    beq .active
    lda.w #0                    ; not the title (or its red is not loaded yet): replay next time
    %set_t()
    brl .done
.active:
    lda.l !STAMP_T
    tax
    eor.w #$5A5A
    cmp.l !STAMP_K
    beq .valid
    ldx.w #0
.valid:
    cpx.w #100
    bcs .noinc
    inx
.noinc:
    txa
    %set_t()                    ; X = T from here on
    cpx.w #!THUD_T
    bne .nothud
    phx                         ; the stamp lands: a sound through the game's own sound routine
    lda.w #!THUD_SND
    jsl $9DEDB3
    plx
.nothud:
    cpx.w #!T_END
    bcs .letters                ; the stamp is over
    txa
    asl a
    tay
    lda.w stamp_plate,y
    cmp.w #$7FFF
    beq .letters                ; stamp not in view yet
    sta.l !S_OFF
    ldy.w #0                    ; Y = index into stamp_parts (6 bytes each), X := OAM offset of slot 16
    phx                         ; keep T
    ldx.w #16*4
.spr:
    lda.w stamp_parts,y          ; x
    sta.l !S_TMP
    lda.w stamp_parts+2,y        ; ry (signed)
    clc
    adc.w #!PLATE_Y
    clc
    adc.l !S_OFF
    cmp.w #$FFF1                ; above y=-15: nothing of it is on screen, park it
    bmi .park
    and.w #$00FF
    xba
    ora.l !S_TMP
    bra .put
.park:
    lda.l !S_TMP
    ora.w #$F000
.put:
    sta.l $7E0957,x
    lda.w stamp_parts+4,y       ; (attr << 8) | tile
    sta.l $7E0959,x
    inx
    inx
    inx
    inx
    tya
    clc
    adc.w #6
    tay
    cpy.w #!STAMP_PARTS*6
    bne .spr
    lda.w #$AAAA                ; slots 16..63: size = large, x bit 8 = 0
    sta.l $7E0B5B
    sta.l $7E0B5D
    sta.l $7E0B5F
    sta.l $7E0B61
    sta.l $7E0B63
    sta.l $7E0B65
    plx                         ; T
.letters:
    cpx.w #!LETTERS_T
    bcc .done
    ldx.w #0
-   lda.l banner_oam,x
    sta.l $7E0957,x
    inx
    inx
    cpx.w #64
    bne -
    lda.w #$AAAA                ; slots 0..15: size = large, x bit 8 = 0
    sta.l $7E0B57
    sta.l $7E0B59
.done:
    plb
    ply
    plx
    pla
    plp
    rep #$30                    ; original: LDA #$1000 (16-bit) : STA $B8
    lda.w #$1000
    sta.b $B8
    rtl

; Called from the OAM DMA routine (hp.asm: oam_hud), i.e. in vblank, once per title frame. Everything here uses long addressing.
; Job code = (kind << 4) | graphic: kind 1 save the glyph tiles, 2 upload the stamp graphic, 3 restore the glyph, 4 palette.
org $BE9800
stamp_vblank:
    php
    rep #$30
    pha
    phx
    phy
    phb
    pea.w $BEBE
    plb
    plb
    lda.l !STAMP_T
    tax
    eor.w #$5A5A
    cmp.l !STAMP_K
    beq .valid
    brl .out
.valid:
    cpx.w #!T_END
    bcc .inrange
    brl .out
.inrange:
    txa
    asl a
    tay
    lda.w stamp_act,y           ; two job codes per T: low byte first
    sta.l !S_JOBS
    and.w #$00FF
    beq .nojob1
    jsr do_job
.nojob1:
    lda.l !S_JOBS
    xba
    and.w #$00FF
    beq .nojob2
    jsr do_job
.nojob2:
    lda.l !STAMP_T
    asl a
    tay
    lda.w stamp_flash,y
    beq .noflash
    sta.l !S_TMP
    sep #$20
    lda.b #$DE                  ; CGRAM word 128+5*16+14: OBJ palette 5, index 14 (the ink face)
    sta.l $002121
    lda.l !S_TMP
    sta.l $002122
    lda.l !S_TMP+1
    sta.l $002122
    rep #$20
.noflash:
    lda.w stamp_bgv,y
    cmp.w #$7FFF
    beq .out
    sta.l !S_TMP
    sep #$20                    ; BG1/2/3 vertical scroll: each register needs its own consecutive low/high pair (the
    lda.l !S_TMP                ; write latch is shared by all of them); 10 bit, so negatives are $3xx
    sta.l $00210E
    lda.l !S_TMP+1
    and.b #$03
    sta.l $00210E
    lda.l !S_TMP
    sta.l $002110
    lda.l !S_TMP+1
    and.b #$03
    sta.l $002110
    lda.l !S_TMP
    sta.l $002112
    lda.l !S_TMP+1
    and.b #$03
    sta.l $002112
    rep #$20
.out:
    plb
    ply
    plx
    pla
    plp
    rtl

; A = job code. Kinds 1-3 work on one graphic = four tiles (TL, TR, +16 tiles, +17 tiles) at the borrowed glyph's VRAM address.
do_job:
    sta.l !S_TMP
    and.w #$000F
    sta.l !S_G
    lda.l !S_TMP
    lsr a
    lsr a
    lsr a
    lsr a
    and.w #$000F
    sta.l !S_KIND
    cmp.w #4
    bne .gfx
    sep #$20                    ; kind 4: the stamp's palette, OBJ palette 5 indices 1-12 (CGRAM word 128+5*16+1)
    lda.b #$D1
    sta.l $002121
    ldx.w #0
-   lda.w stamp_pal,x
    sta.l $002122
    inx
    cpx.w #24
    bne -
    rep #$20
    rts
.gfx:
    lda.l !S_G
    asl a
    tay
    lda.w glyph_vram,y
    sta.l !S_TMP                ; VRAM word address of the top-left tile
    lda.l !S_G
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    tax                         ; X = graphic number * 128: offset into stamp_gfx and !STAMP_SAVE
    sep #$20
    lda.b #$80
    sta.l $002115
    rep #$20
    lda.l !S_KIND
    cmp.w #1
    beq .save
    cmp.w #3
    beq .rest
    lda.l !S_TMP                ; kind 2: upload the stamp graphic
    jsr up16
    lda.l !S_TMP
    clc
    adc.w #16
    jsr up16
    lda.l !S_TMP
    clc
    adc.w #$100
    jsr up16
    lda.l !S_TMP
    clc
    adc.w #$110
    jsr up16
    rts
.save:
    lda.l !S_TMP
    jsr rd16
    lda.l !S_TMP
    clc
    adc.w #16
    jsr rd16
    lda.l !S_TMP
    clc
    adc.w #$100
    jsr rd16
    lda.l !S_TMP
    clc
    adc.w #$110
    jsr rd16
    rts
.rest:
    lda.l !S_TMP
    jsr wr16
    lda.l !S_TMP
    clc
    adc.w #16
    jsr wr16
    lda.l !S_TMP
    clc
    adc.w #$100
    jsr wr16
    lda.l !S_TMP
    clc
    adc.w #$110
    jsr wr16
    rts

up16:                           ; A = VRAM word address, X = offset into stamp_gfx: write 16 words
    sta.l $002116
    ldy.w #16
-   lda.l stamp_gfx,x
    sta.l $002118
    inx
    inx
    dey
    bne -
    rts

rd16:                           ; A = VRAM word address, X = offset into !STAMP_SAVE: save 16 words
    sta.l $002116
    sep #$20
    lda.l $002139               ; the first pair returns the prefetch and the second returns it again (the latch reloads
    lda.l $00213A               ; before VMADD increments): read one pair and throw it away
    ldy.w #16
-   lda.l $002139
    sta.l !STAMP_SAVE,x
    inx
    lda.l $00213A
    sta.l !STAMP_SAVE,x
    inx
    dey
    bne -
    rep #$20
    rts

wr16:                           ; A = VRAM word address, X = offset into !STAMP_SAVE: put 16 words back
    sta.l $002116
    sep #$20
    ldy.w #16
-   lda.l !STAMP_SAVE,x
    sta.l $002118
    inx
    lda.l !STAMP_SAVE,x
    sta.l $002119
    inx
    dey
    bne -
    rep #$20
    rts

glyph_vram:                     ; VRAM word address of the top-left tile of the glyphs B F J K L Q U X Y Z, one per graphic
    dw $02*16, $0A*16, $22*16, $24*16, $26*16, $40*16, $48*16, $4E*16, $60*16, $62*16

; per-T tables, T = 0..37
stamp_act:                      ; two VRAM jobs per T, low byte first: $1g save, $2g upload, $3g restore, $40 palette
    db $00,$00
    db $40,$10                  ; T 1: palette, save graphic 0
    db $11,$20                  ; T 2..10: save graphic g, upload graphic g-1
    db $12,$21
    db $13,$22
    db $14,$23
    db $15,$24
    db $16,$25
    db $17,$26
    db $18,$27
    db $19,$28
    db $29,$00                  ; T 11: upload graphic 9
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00   ; T 12..19
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00   ; T 20..27
    db $30,$00                  ; T 28..37: put the glyph tiles back
    db $31,$00
    db $32,$00
    db $33,$00
    db $34,$00
    db $35,$00
    db $36,$00
    db $37,$00
    db $38,$00
    db $39,$00
stamp_plate:                    ; vertical offset of the whole stamp, $7FFF = not drawn
    dw $7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF   ; T 0..11
    dw $FF6A,$FF80,$FF9C,$FFBC,$FFDA,$FFF0,$FFFC,$0000                           ; T 12..19 drop: -150 -128 -100 -68 -38 -16 -4 0
    dw $0000,$0000,$0000                                                         ; T 20..22 down
    dw $FFFA,$FFF0,$FFE0,$FFC8,$FFA6                                             ; T 23..27 lift: -6 -16 -32 -56 -90
    dw $7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF               ; T 28..37
stamp_bgv:                      ; BG vertical scroll, $7FFF = leave alone
    dw $7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF   ; T 0..19
    dw $7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF
    dw $FFF9,$0005,$FFFC,$0003,$FFFE,$0001,$0000                                 ; T 20..26: -7 +5 -4 +3 -2 +1 0
    dw $7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF,$7FFF        ; T 27..37
stamp_flash:                    ; ink face colour (BGR555) written to CGRAM, 0 = leave alone
    dw 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0                       ; T 0..25
    dw $7FFF,$529F,$295F,$189F,$0C1F                                             ; T 26..30
    dw 0,0,0,0,0,0,0                                                             ; T 31..37

;
; the art (1.6 KB) goes further up so it cannot run into cheats.asm at BE:A000
org $BEC000
incsrc "stamp_parts.inc"
incsrc "stamp_art.inc"
