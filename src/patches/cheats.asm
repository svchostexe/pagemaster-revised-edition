; The Pagemaster (SNES, US) - CHEATS menu on the title screen. asar patch, LoROM.
;
; Title menu (B0:8505 sets it up, the loop is B0:8617): three items now. The menu index is WRAM $0300 (0 START GAME,
; 1 PASSWORD, 2 CHEATS). Hooks below: the two text positions move up (START GAME y=$B0, PASSWORD y=$C0, CHEATS $D0, pitch 16 so
; all three fit above y=224), the third text entity is created, Up/Down cycle through three items, the fairy cursor follows
; (B0:85EA x, B0:85FE y), and B0:865C (item chosen) branches on the index.
;
; CHEATS runs its own little loop (cheat_screen): vsync wait (9D:FE2B), OAM DMA (A9:FC68), pad (BD:93B6, $70 = new presses),
; and redraws the whole OAM shadow every frame with the menu font (glyph tile for letter n = (n/8)*$20+(n%8)*2, 16x16
; sprites). The selected row is drawn in red (OBJ palette 5, the banner ink), the others in menu yellow (palette 7). The BG
; is hidden (TM = OBJ only) while it runs. Digits have no font glyphs, so the level number borrows the VRAM tiles of the glyphs
; Q and Z (never used by the labels), saved on entry and put back on exit (VRAM reads: first pair is a throwaway).
;
; State (WRAM 7E:6400-6425, never touched by the game; NOT 7E:6040+, hitfix.asm keeps per-frame scratch there): !CH_K = $C3A5
; marks it valid (else every cheat is off); flags:
;   $01 invincible   $02 infinite lives   $04 more hit blocks (5)   $08 full library cards   $10 moon jump   $20 super speed
; so a reset or power cycle clears them, as agreed. World/level: !CH_WORLD 0..4 (25/14/19/4/3 levels), !CH_LEVEL.
; PLAY: sets !CH_AUTO and returns START GAME; when the game reaches the world map (80:811D, after the normal new game init) map_skip
; pokes $028A/$028C, sets mode 2 (enter level, what a death restart sets) and jumps to the level loader at 80:8183.
;
; Gameplay hooks (the other flag readers, hp.asm for invincible / blocks / cards):
;   infinite lives: B0:C2B8 (DEC $01E8 : BNE) -> cheat_life      moon jump: 97:F9F4 gravity -> moon_grav (Richard only)
;   super speed: 97:FBFF position integration -> super_x (Richard gets a second step of his horizontal velocity)

lorom

!CH_K      = $7E6400
!CH_FLAGS  = $7E6402
!CH_WORLD  = $7E6404
!CH_LEVEL  = $7E6406
!CH_SEL    = $7E6408
!CH_DONE   = $7E640A
!CH_X      = $7E640C
!CH_Y      = $7E640E
!CH_ATTR   = $7E6410
!CH_SLOT   = $7E6412
!CH_TMP    = $7E6414
!CH_IN     = $7E6416
!CH_SHOWN0 = $7E6418
!CH_SHOWN1 = $7E641A
!CH_T      = $7E641C
!CH_O      = $7E641E
!CH_TMP2   = $7E6420
!CH_BD     = $7E6422           ; word: the saved backdrop colour
!CH_AUTO   = $7E6424           ; word: set by PLAY, consumed by map_skip
!CH_SAVE   = $7E6280           ; 8 tiles x 32 bytes (6280-637F)

!ATTR_SEL  = $3A               ; priority 3, palette 5 (red ink)
!ATTR_NORM = $3E               ; priority 3, palette 7 (menu yellow)

; ---- title menu hooks ----
org $B08542                     ; LDA #$00B4 (START GAME y) -> $B0
    db $B0
org $B08559                     ; LDA #$00C8 (PASSWORD y) -> $C0
    db $C0
org $B0856F                     ; was LDA #$01AA : JSL $97F844 (the fairy cursor)
    jsl menu_extra
    nop
    nop
    nop
org $B0863E                     ; was LDA $0300 : EOR #1 : STA $0300
    jsl menu_step
    nop
    nop
    nop
    nop
    nop
org $B085FE                     ; cursor y (JSR'd)
    jsl menu_cy
    rts
org $B085ED                     ; cursor x (the JSR $85FE before it stays)
    jsl menu_cx
    rtl
org $B0865C                     ; item chosen
    jml menu_select

; ---- gameplay hooks ----
org $B0C2B8                     ; was DEC $01E8 : BNE $C2C5
    jml cheat_life
    nop
org $97F9F4                     ; was LDA $122D,X : CLC : ADC #$42AA
    jml moon_grav
    nop
    nop
    nop
org $97FBFF                     ; was LDA $12DD,X : CLC
    jml super_x

org $80811D                     ; the world map (first instruction pair of L_80811D: LDA #$00B0 : LDX #$94A4)
    jml map_skip
    nop
    nop

org $BEA000
; A = mask (16-bit): A = mask & flags, Z set when the cheat is off or the state is not valid
ct:
    pha
    lda.l !CH_K
    cmp.w #$C3A5
    bne .off
    pla
    and.l !CH_FLAGS
    rtl
.off:
    pla
    lda.w #0
    rtl

cheat_life:
    lda.w #$0002
    jsl ct
    bne .keep
    dec.w $01E8
    bne .cont
    jml $B0C2BD
.cont:
    jml $B0C2C5
.keep:
    jml $B0C2C5

moon_grav:
    cpx.w $0C33
    bne .norm
    lda.w #$0010
    jsl ct
    beq .norm
    lda.w $122D,x
    clc
    adc.w #$1AAA                ; 0.10 px/frame^2 instead of 0.26: about 2.5x the jump height, floaty
    jml $97F9FB
.norm:
    lda.w $122D,x
    clc
    adc.w #$42AA
    jml $97F9FB

super_x:
    cpx.w $0C33
    bne .norm
    lda.w #$0020
    jsl ct
    beq .norm
    lda.w $12DD,x               ; one extra step of his horizontal velocity (2x speed)
    clc
    adc.w $11D5,x
    sta.w $11D5,x
    lda.w $1335,x
    adc.w $0EBD,x
    sta.w $0EBD,x
.norm:
    lda.w $12DD,x
    clc
    jml $97FC03

; PLAY from the CHEATS screen: when the game gets to the world map (new game init has just run), poke the chosen world/level,
; set mode 2 (enter level, what a death restart sets) and go straight to the level loader at 80:8183
map_skip:
    lda.l !CH_AUTO
    cmp.w #$A55A
    bne .norm
    lda.w #0
    sta.l !CH_AUTO
    lda.l !CH_WORLD
    sta.l $00028A
    lda.l !CH_LEVEL
    sta.l $00028C
    lda.w #2
    sta.l $000292
    jml $808183
.norm:
    lda.w #$00B0                ; displaced
    ldx.w #$94A4
    jml $808123

; ---- title menu ----
menu_extra:                     ; third text entity, then the displaced fairy creation
    lda.w #$00D0
    sta.w $0C3B
    lda.w #$00BE
    sta.b $C0
    lda.w #str_cheats
    sta.b $BE
    lda.w #$01AE
    jsl $97F844
    lda.w #$01AA
    jsl $97F844
    rtl

menu_step:                      ; A = pad edges & $0C00: Down $0400, Up $0800
    and.w #$0400
    beq .up
    lda.w $0300
    inc a
    cmp.w #3
    bcc .st
    lda.w #0
    bra .st
.up:
    lda.w $0300
    dec a
    bpl .st
    lda.w #2
.st:
    sta.w $0300
    rtl

menu_cy:                        ; cursor y = 206 + 16 * index
    lda.w $0300
    asl a
    asl a
    asl a
    asl a
    clc
    adc.w #$00CE
    sta.w $0E65,x
    rtl

menu_cx:                        ; cursor x: right edge of the item's text + 23
    lda.w $0300
    beq .a
    cmp.w #1
    beq .b
    lda.w #$00BB
    bra .s
.a:
    lda.w #$00D2
    bra .s
.b:
    lda.w #$00C8
.s:
    sta.w $0EBD,x
    rtl

menu_select:
    lda.w $0300
    beq .start
    cmp.w #1
    beq .pw
    jsl cheat_screen
    bcs .play
    stz.w $055B                 ; back in the menu: clear the "chosen" latch, restart the idle timeout and the Start mask
    lda.w #$0355
    jsl $8FF3E8
    lda.w #$1000
    jsl $8FF3CB
    jml $B08617
.play:
    lda.w #$0011
    jml $B08669
.start:
    lda.w #$0011
    jml $B08669
.pw:
    lda.w #$0012
    jml $B08669

; ---- the CHEATS screen ----
; returns carry set = PLAY (world/level already poked), clear = back to the menu
cheat_screen:
    php
    rep #$30
    pha
    phx
    phy
    phb
    pea.w $BEBE
    plb
    plb
    lda.l !CH_K
    cmp.w #$C3A5
    beq .valid
    lda.w #0
    sta.l !CH_FLAGS
    sta.l !CH_WORLD
    sta.l !CH_LEVEL
    lda.w #$C3A5
    sta.l !CH_K
.valid:
    lda.w #0
    sta.l !CH_SEL
    sta.l !CH_DONE
    lda.w #$FFFF
    sta.l !CH_SHOWN0
    sta.l !CH_SHOWN1
    ldx.w #0                    ; save the VRAM tiles of the glyphs Q and Z, one tile per frame
.save:
    phx
    jsl $9DFE2B
    plx
    lda.w tile_list,x
    and.w #$00FF
    asl a
    asl a
    asl a
    asl a
    pha
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    tay
    pla
    phx
    tyx
    jsr rd_tile
    plx
    inx
    cpx.w #8
    bne .save
    jsl $9DFE2B
    sep #$20
    lda.b #$10                  ; main screen: OBJ only
    sta.l $00212C
    lda.b #0                    ; save CGRAM colour 0 (the backdrop) and make it black
    sta.l $002121
    lda.l $00213B
    sta.l !CH_BD
    lda.l $00213B
    sta.l !CH_BD+1
    lda.b #0
    sta.l $002121
    sta.l $002122
    sta.l $002122
    rep #$20
.loop:
    jsl $9DFE2B
    jsl $A9FC68
    jsr upload_digits
    jsl $BD93B6
    jsr do_input
    jsr draw
    lda.l !CH_DONE
    beq .loop
    ldx.w #0                    ; put the glyph tiles back
.rest:
    phx
    jsl $9DFE2B
    plx
    lda.w tile_list,x
    and.w #$00FF
    asl a
    asl a
    asl a
    asl a
    pha
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    tay
    pla
    phx
    tyx
    jsr wr_tile
    plx
    inx
    cpx.w #8
    bne .rest
    jsl $9DFE2B
    sep #$20
    lda.b #$11                  ; main screen: BG1 + OBJ, as on the title
    sta.l $00212C
    lda.b #0
    sta.l $002121               ; backdrop colour back
    lda.l !CH_BD
    sta.l $002122
    lda.l !CH_BD+1
    sta.l $002122
    rep #$20
    lda.l !CH_DONE
    cmp.w #2
    bne .back
    lda.w #$A55A                ; PLAY: the title returns "start game"; map_skip then jumps over the world map
    sta.l !CH_AUTO              ; (a magic value: this WRAM is not initialised, so "non-zero" would fire on a cold boot)
    plb
    ply
    plx
    pla
    plp
    sec
    rtl
.back:
    plb
    ply
    plx
    pla
    plp
    clc
    rtl

; A = VRAM word address, X = offset into !CH_SAVE: save 16 words
rd_tile:
    sta.l !CH_TMP
    sep #$20
    lda.b #$80
    sta.l $002115
    rep #$20
    lda.l !CH_TMP
    sta.l $002116
    sep #$20
    lda.l $002139               ; first pair returns the prefetch and the second returns it again: discard one
    lda.l $00213A
    ldy.w #16
-   lda.l $002139
    sta.l !CH_SAVE,x
    inx
    lda.l $00213A
    sta.l !CH_SAVE,x
    inx
    dey
    bne -
    rep #$20
    rts

; A = VRAM word address, X = offset into !CH_SAVE: put 16 words back
wr_tile:
    sta.l !CH_TMP
    sep #$20
    lda.b #$80
    sta.l $002115
    rep #$20
    lda.l !CH_TMP
    sta.l $002116
    sep #$20
    ldy.w #16
-   lda.l !CH_SAVE,x
    sta.l $002118
    inx
    lda.l !CH_SAVE,x
    sta.l $002119
    inx
    dey
    bne -
    rep #$20
    rts

; A = VRAM word address of the top-left tile, X = offset into digit_gfx: write the four tiles of one digit
up_digit:
    sta.l !CH_TMP
    sep #$20
    lda.b #$80
    sta.l $002115
    rep #$20
    lda.l !CH_TMP
    jsr .tile
    lda.l !CH_TMP
    clc
    adc.w #16
    jsr .tile
    lda.l !CH_TMP
    clc
    adc.w #$100
    jsr .tile
    lda.l !CH_TMP
    clc
    adc.w #$110
.tile:
    sta.l $002116
    ldy.w #16
-   lda.l digit_gfx,x
    sta.l $002118
    inx
    inx
    dey
    bne -
    rts

; one VRAM job per frame: bring the two digit glyphs in line with the level number
upload_digits:
    lda.l !CH_LEVEL
    inc a
    ldx.w #0
-   cmp.w #10
    bcc +
    sbc.w #10
    inx
    bra -
+   sta.l !CH_O
    txa
    sta.l !CH_T
    cmp.l !CH_SHOWN0
    beq .ones
    sta.l !CH_SHOWN0
    cmp.w #0
    beq .ones                   ; blank tens: nothing to upload, nothing drawn
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    tax
    lda.w #$0400                ; glyph Q, tile $40
    jsr up_digit
    rts
.ones:
    lda.l !CH_O
    cmp.l !CH_SHOWN1
    beq .ret
    sta.l !CH_SHOWN1
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    tax
    lda.w #$0620                ; glyph Z, tile $62
    jsr up_digit
.ret:
    rts

; ---- input ----
do_input:
    lda.l $000070
    sta.l !CH_IN
    and.w #$0800                ; Up
    beq .nu
    lda.l !CH_SEL
    dec a
    bpl +
    lda.w #9
+   sta.l !CH_SEL
    rts
.nu:
    lda.l !CH_IN
    and.w #$0400                ; Down
    beq .nd
    lda.l !CH_SEL
    inc a
    cmp.w #10
    bcc +
    lda.w #0
+   sta.l !CH_SEL
    rts
.nd:
    lda.l !CH_IN
    and.w #$8000                ; B: back
    beq .nb
    lda.w #1
    sta.l !CH_DONE
    rts
.nb:
    lda.l !CH_SEL
    cmp.w #6
    bcs .special
    lda.l !CH_IN                ; flag rows: Left / Right / A / Start toggle
    and.w #$1380
    beq .none
    lda.l !CH_SEL
    tax
    lda.w #1
    cpx.w #0
    beq .m
-   asl a
    dex
    bne -
.m: eor.l !CH_FLAGS
    sta.l !CH_FLAGS
.none:
    rts
.special:
    cmp.w #6
    beq .world
    cmp.w #7
    beq .level
    cmp.w #8
    beq .play
    lda.l !CH_IN                ; BACK
    and.w #$1080
    beq .none
    lda.w #1
    sta.l !CH_DONE
    rts
.play:
    lda.l !CH_IN
    and.w #$1080
    beq .none
    lda.w #2
    sta.l !CH_DONE
    rts
.world:
    lda.l !CH_IN
    and.w #$0200                ; Left
    beq .wr
    lda.l !CH_WORLD
    dec a
    bpl .wset
    lda.w #4
    bra .wset
.wr:
    lda.l !CH_IN
    and.w #$1180                ; Right / A / Start
    beq .none
    lda.l !CH_WORLD
    inc a
    cmp.w #5
    bcc .wset
    lda.w #0
.wset:
    sta.l !CH_WORLD
    lda.w #0
    sta.l !CH_LEVEL
    rts
.level:
    lda.l !CH_WORLD
    tax
    lda.w level_counts,x
    and.w #$00FF
    sta.l !CH_TMP
    lda.l !CH_IN
    and.w #$0200                ; Left
    beq .lr
    lda.l !CH_LEVEL
    dec a
    bpl .lset
    lda.l !CH_TMP
    dec a
    bra .lset
.lr:
    lda.l !CH_IN
    and.w #$1180
    beq .none2
    lda.l !CH_LEVEL
    inc a
    cmp.l !CH_TMP
    bcc .lset
    lda.w #0
.lset:
    sta.l !CH_LEVEL
.none2:
    rts

; ---- drawing ----
; A = glyph tile: puts one 16x16 sprite at (!CH_X, !CH_Y) with !CH_ATTR, then advances !CH_X by 12
put_glyph:
    and.w #$00FF
    sta.l !CH_TMP
    ldx.w #0
    lda.l !CH_SLOT
    tax
    lda.l !CH_Y
    and.w #$00FF
    xba
    sta.l !CH_TMP2
    lda.l !CH_X
    and.w #$00FF
    ora.l !CH_TMP2
    sta.l $7E0957,x
    lda.l !CH_ATTR
    and.w #$00FF
    xba
    ora.l !CH_TMP
    sta.l $7E0959,x
    txa
    clc
    adc.w #4
    sta.l !CH_SLOT
    lda.l !CH_X
    clc
    adc.w #12
    sta.l !CH_X
    rts

; Y = address of a zero-terminated string in this bank (letters and spaces only)
put_str:
-   lda.w 0,y
    and.w #$00FF
    beq .done
    iny
    cmp.w #$0020
    beq .space
    sec
    sbc.w #$0041
    pha
    and.w #$0018
    asl a
    asl a
    sta.l !CH_TMP
    pla
    and.w #$0007
    asl a
    ora.l !CH_TMP
    phy
    jsr put_glyph
    ply
    bra -
.space:
    lda.l !CH_X
    clc
    adc.w #12
    sta.l !CH_X
    bra -
.done:
    rts

row_attr:                       ; A = row number: red when it is the selected one
    cmp.l !CH_SEL
    beq .sel
    lda.w #!ATTR_NORM
    sta.l !CH_ATTR
    rts
.sel:
    lda.w #!ATTR_SEL
    sta.l !CH_ATTR
    rts

macro label_row(i, str)
    lda.w #<i>
    jsr row_attr
    lda.w #24
    sta.l !CH_X
    lda.w #40+(16*<i>)
    sta.l !CH_Y
    ldy.w #<str>
    jsr put_str
endmacro

flag_value:                     ; A = flag mask: draws ON/OFF at x=168 in the current row colour
    pha
    lda.w #168
    sta.l !CH_X
    pla
    and.l !CH_FLAGS
    beq .off
    ldy.w #str_on
    bra .put
.off:
    ldy.w #str_off
.put:
    jsr put_str
    rts

macro flag_value(i)
    lda.w #1<<<i>
    jsr flag_value
endmacro

draw:
    ldx.w #0                    ; clear the OAM shadow: every slot parked at y=$F0, all large
    lda.w #$F000
-   sta.l $7E0957,x
    inx
    inx
    inx
    inx
    cpx.w #512
    bne -
    ldx.w #0
    lda.w #$AAAA
-   sta.l $7E0B57,x
    inx
    inx
    cpx.w #32
    bne -
    lda.w #0
    sta.l !CH_SLOT
    lda.w #!ATTR_SEL            ; header
    sta.l !CH_ATTR
    lda.w #92
    sta.l !CH_X
    lda.w #12
    sta.l !CH_Y
    ldy.w #str_title
    jsr put_str
    %label_row(0, str_invincible)
    %flag_value(0)
    %label_row(1, str_lives)
    %flag_value(1)
    %label_row(2, str_blocks)
    %flag_value(2)
    %label_row(3, str_cards)
    %flag_value(3)
    %label_row(4, str_moon)
    %flag_value(4)
    %label_row(5, str_speed)
    %flag_value(5)
    %label_row(6, str_world)
    lda.w #100
    sta.l !CH_X
    lda.l !CH_WORLD
    asl a
    tax
    lda.w world_ptrs,x
    tay
    jsr put_str
    %label_row(7, str_level)
    lda.w #7
    jsr row_attr
    lda.l !CH_T                 ; tens digit (glyph Q's tiles), only once uploaded
    beq .noten
    cmp.l !CH_SHOWN0
    bne .noten
    lda.w #100
    sta.l !CH_X
    lda.w #$0040
    jsr put_glyph
.noten:
    lda.l !CH_O                 ; ones digit (glyph Z's tiles)
    cmp.l !CH_SHOWN1
    bne .noone
    lda.w #112
    sta.l !CH_X
    lda.w #$0062
    jsr put_glyph
.noone:
    %label_row(8, str_play)
    %label_row(9, str_back)
    lda.w #!ATTR_NORM           ; the selected level's name, centred on the last line (same text as its GET READY card)
    sta.l !CH_ATTR
    lda.w #204
    sta.l !CH_Y
    lda.l !CH_WORLD
    asl a
    tax
    lda.w world_base,x
    clc
    adc.l !CH_LEVEL
    asl a
    tax
    lda.w name_ptrs,x
    tay
    lda.w 0,y
    and.w #$00FF
    sta.l !CH_X
    iny
    jsr put_str
    rts

tile_list:
    db $40,$41,$50,$51,$62,$63,$72,$73
level_counts:
    db 25,14,19,4,3
world_base:
    dw 0,25,39,58,62
world_ptrs:
    dw str_horror, str_adventure, str_fantasy, str_timed, str_ending

str_cheats:    db "CHEATS",0
str_title:     db "CHEATS",0
str_invincible: db "INVINCIBLE",0
str_lives:     db "INF LIVES",0
str_blocks:    db "MORE BLOCKS",0
str_cards:     db "FULL CARDS",0
str_moon:      db "MOON JUMP",0
str_speed:     db "SUPER SPEED",0
str_world:     db "WORLD",0
str_level:     db "LEVEL",0
str_play:      db "PLAY",0
str_back:      db "BACK",0
str_on:        db "ON",0
str_off:       db "OFF",0
str_horror:    db "HORROR",0
str_adventure: db "ADVENTURE",0
str_fantasy:   db "FANTASY",0
str_timed:     db "TIMED",0
str_ending:    db "ENDING",0

org $BEB000
incsrc "digits.inc"

org $BEB800
incsrc "levelnames.inc"
