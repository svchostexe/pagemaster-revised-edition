; The Pagemaster (SNES, US) - hit-point buffer: three hits per life, three blocks in the top left. asar patch, LoROM.
;
; Originally every hurt costs a life: B0:C2EC (hurt dispatcher) -> B0:C2AE -> `DEC $01E8` at B0:C2B8, then the
; "hurt" state B969, which is really the death sequence (Richard hops, falls through the floor, the level restarts). Now the two contact-hurt call sites (B0:C32E, the shared dispatcher, and
; A8:CFD3, one enemy type) call hp_hurt instead of C2AE: the first two hits only play the flinch (B0:C2C5), the
; third takes the life and resets the buffer (jumps to the original C2AE). The pit check (B0:A667) goes through
; the same path (a fall costs a block, then the game's own respawn runs; hp_hurt_pit flags that respawn so the
; spawn hook does not refill). Every level start (the spawn hook, B0:A787) and a new game (B0:C179) refill.
;
; State: !HP_STATE word, low byte = hits taken (0..2), high byte = low EOR $A5. Anything that does not match
; (uninitialised WRAM) reads as 0 hits. !HUD_ACTIVE is set to 3 each gameplay frame by the hook at B2:FD22
; (the player-vs-hazard pass, which only runs in a level); oam_hud draws the HUD only while it is non-zero.
;
; HUD: three 8x8 sprites at the top left (x 12/21/30, y 20), OBJ tiles $21 (full) and $27 (empty) in palette 7, the
; menu-font yellow. Those are the blank right halves of the font glyphs I and L. The game streams enemy and animation
; graphics into many other OBJ tiles during play (the first version used $FC/$FD and showed garbage whenever that
; happened), but never wrote $21/$27/$31 in an 11000-frame recording. The stub re-uploads the two tiles every 16 frames,
; clears them again when gameplay ends (the title banner draws an I) and stamps OAM shadow entries 0..2 itself.
; Gameplay is IRQ driven (the NMI vector never fires there): the whole frame runs from the IRQ handler and the OAM
; shadow ($0957) is pushed by the DMA routine at A9:FC68 around scanline 226, inside vblank. That routine's first
; instructions become a JSL to oam_hud, which uploads/stamps and then runs the displaced code.

lorom

!HP_STATE   = $7E6000          ; word (7E:6000-63FF was never touched by the game in boot or the 11000-frame recording)
!HUD_ACTIVE = $7E6002          ; byte
!HUD_TICK   = $7E6003          ; byte
!RESPAWN    = $7E6004          ; byte, set by the pit path: the spawn that follows is a respawn, not a level start
!HP_MAX     = $7E6005          ; byte, 3 hit blocks or 5 with the MORE BLOCKS cheat (refreshed by hp_max_store)
!CH_K       = $7E6400          ; cheats.asm state: !CH_K = $C3A5 when valid, !CH_FLAGS bit 0 invincible, 2 more blocks, 3 full cards
!CH_FLAGS   = $7E6402
!BLK_FULL   = $21
!BLK_EMPTY  = $27
!BLK_X      = 12
!BLK_Y      = 20
!BLK_PITCH  = 9
!BLK_ATTR   = $3E              ; priority 3, palette 7

; ---- hooks ----
org $B0C32E
    jsl hp_hurt                ; was JSL $B0C2AE

org $B0A667
    jsl hp_hurt_pit            ; fell out of the world: was JSL $B0C2AE, now costs a hit like any other and respawns

org $B0A787                    ; player spawn (level start AND respawn): was STX $0C33 : JSL $97F454
    jsl hp_spawn
    nop
    nop
    nop

org $A8CFD3
    jsl hp_hurt                ; was JSL $B0C2AE

org $B0C179                    ; was LDA #$0003 : STA $01E8 : STZ $01EC
    jsl hp_init
    nop
    nop
    nop
    nop
    nop

org $B2FD22                    ; was LDX $0C33 : BPL +1 : RTL
    jml hud_tick
    nop

org $A9FC68                    ; OAM DMA routine, was SEP #$10 : TDC : STA $2102
    jsl oam_hud
    nop
    nop

; ---- code and data in free space ----
org $BE8500

; A = hits taken + 1 (8-bit A, from the stored state; uninitialised/invalid state counts as 0 hits)
macro next_hit()
    jsl hp_max_store
    lda.l !HP_STATE
    eor.b #$A5
    cmp.l !HP_STATE+1
    bne +
    lda.l !HP_STATE
    cmp.l !HP_MAX
    bcc ++
+   lda.b #0
++  inc
endmacro

macro store_hits()
    sta.l !HP_STATE
    eor.b #$A5
    sta.l !HP_STATE+1
endmacro

; Contact hit (B0:C32E, A8:CFD3). Hits 1-2: hurt sound + the game's own invulnerability + a knock-up, Richard keeps
; playing where he is. The game's "hurt" state (B969/B9B3) is its death sequence (fall through the floor, level
; restart), so it is only used for the hit that really takes a life.
hp_hurt:
    php
    rep #$30
    pha
    lda.w #$0001                ; invincible cheat: ignore the hit
    jsl cheat_test
    bne .invinc
    sep #$20
    %next_hit()
    cmp.l !HP_MAX
    bcs .fatal
    %store_hits()
    rep #$30
    pla
    plp
    jml hp_flinch              ; tail call: its RTL returns to the caller of hp_hurt
.fatal:
    lda.b #0
    %store_hits()
    lda.b #$A5
    sta.l !HP_STATE+1
    rep #$30
    pla
    plp
    jml $B0C2AE                ; original: BD2B, DEC lives, game over or the death sequence
.invinc:
    pla
    plp
    rtl

; Fell out of the world (B0:A667): a hit like any other, but the respawn has to happen, so the non-fatal case runs the
; game's own death sequence (B0:C2C5, no life lost) and flags the spawn that follows so it does not refill.
hp_hurt_pit:
    php
    rep #$30
    pha
    sep #$20
    lda.b #1
    sta.l !RESPAWN
    rep #$30
    lda.w #$0001                ; invincible cheat: the fall costs nothing, but the respawn still has to happen
    jsl cheat_test
    bne .invinc
    sep #$20
    %next_hit()
    cmp.l !HP_MAX
    bcs .fatal
    %store_hits()
    rep #$30
    pla
    plp
    jsl $B0BD2B                ; as C2AE would
    jsl $B0C2C5                ; death sequence without losing a life
    rtl
.invinc:
    pla
    plp
    jsl $B0BD2B
    jsl $B0C2C5
    rtl
.fatal:
    lda.b #0
    %store_hits()
    lda.b #$A5
    sta.l !HP_STATE+1
    rep #$30
    pla
    plp
    jml $B0C2AE

; Non-fatal contact hit: 213 frames of invulnerability (B0:C344, the same routine the game uses after a respawn),
; and the jump-start state (B5D3: jump animation + impulse) as the knock-up.
hp_flinch:
    php
    rep #$30
    pha
    phx
    phy
    jsl $B0C344
    lda.l $7E0C33              ; player slot
    bmi .out
    tax
    lda.w #$B5D3
    sta.l $7E138D,x
.out:
    rep #$30
    ply
    plx
    pla
    plp
    rtl

hp_spawn:
    stx.w $0C33
    php
    rep #$20
    pha
    sep #$20
    lda.l !RESPAWN
    bne .respawn
    rep #$20
    lda.w #$A500               ; fresh level: full blocks
    sta.l !HP_STATE
    sep #$20
.respawn:
    lda.b #0
    sta.l !RESPAWN
    rep #$30
    lda.w #$0008                ; full cards cheat: library cards = 8 (the most the game counts)
    jsl cheat_test
    beq .nocards
    lda.w #8
    sta.w $01F8
.nocards:
    rep #$20
    pla
    plp
    jsl $97F454
    rtl

hp_init:
    lda.w #$0000
    sta.l !RESPAWN
    lda.w #$0003
    sta.l $7E01E8
    lda.w #$0000
    sta.l $7E01EC
    lda.w #$A500
    sta.l !HP_STATE
    lda.w #$0003               ; A was 3 when the displaced code ran into JSL $8083AF
    rtl

hud_tick:
    ldx.w $0C33
    bmi .out
    sep #$20
    lda.b #3
    sta.l !HUD_ACTIVE
    rep #$20
    jml $B2FD28
.out:
    rtl

macro stamp_block(i)
    lda.b #!BLK_X+(!BLK_PITCH*<i>)
    sta.l $7E0957+(4*<i>)
    lda.b #!BLK_Y
    sta.l $7E0958+(4*<i>)
    lda.b #!BLK_EMPTY
    cpy.w #<i>+1               ; carry = blocks left > i
    bcc +
    lda.b #!BLK_FULL
+   sta.l $7E0959+(4*<i>)
    lda.b #!BLK_ATTR
    sta.l $7E095A+(4*<i>)
endmacro

oam_hud:
    php
    rep #$30
    pha
    phx
    phy
    jsl $BE9800                ; banner.asm: stamp_vblank (title stamp tiles, ink flash, screen jolt; no-op in a level)
    sep #$20
    lda.l !HUD_ACTIVE
    cmp.b #1
    bcc .goidle                ; 0: not in a level
    cmp.b #4
    bcc .run                   ; 1..3: hud_tick set it recently
.goidle:
    lda.b #0                   ; (>= 4 is uninitialised WRAM)
    sta.l !HUD_ACTIVE
    brl .idle
.run:
    dec
    sta.l !HUD_ACTIVE
    lda.l !HUD_TICK
    inc
    sta.l !HUD_TICK
    and.b #$0F
    cmp.b #1
    bne .stamp
    ; (re)upload the two block tiles into the blank right halves of font glyphs I and L (OBJ tiles $21 / $27)
    lda.b #$80
    sta.l $002115
    rep #$20
    lda.w #!BLK_FULL*16
    sta.l $002116
    ldx.w #0
.up1:
    lda.l block_gfx,x
    sta.l $002118
    inx
    inx
    cpx.w #32
    bne .up1
    lda.w #!BLK_EMPTY*16
    sta.l $002116
.up2:
    lda.l block_gfx,x
    sta.l $002118
    inx
    inx
    cpx.w #64
    bne .up2
.stamp:
    jsl hp_max_store
    sep #$20
    lda.l !HP_STATE
    eor.b #$A5
    cmp.l !HP_STATE+1
    bne .zero
    lda.l !HP_STATE
    cmp.b #3
    bcc .got
.zero:
    lda.b #0
.got:
    eor.b #$FF                 ; blocks left = max - hits taken
    sec
    adc.l !HP_MAX
    rep #$20
    and.w #$00FF
    tay
    sep #$20
    %stamp_block(0)
    %stamp_block(1)
    %stamp_block(2)
    lda.l $7E0B57              ; OAM high table: slots 0..2 small, x < 256
    and.b #$C0
    sta.l $7E0B57
    lda.l !HP_MAX              ; MORE BLOCKS cheat: two more blocks, slots 3 and 4
    cmp.b #5
    bcc .nomore
    %stamp_block(3)
    %stamp_block(4)
    lda.l $7E0B57
    and.b #$3F
    sta.l $7E0B57
    lda.l $7E0B58
    and.b #$FC
    sta.l $7E0B58
.nomore:
    bra .out
.idle:
    lda.l !HUD_TICK
    beq .out                   ; already clean
    lda.b #0
    sta.l !HUD_TICK            ; next time gameplay starts, upload again
    lda.b #$80                 ; and give the two glyph halves back as blanks (the title banner draws an I)
    sta.l $002115
    rep #$20
    lda.w #!BLK_FULL*16
    sta.l $002116
    ldx.w #16
.clr1:
    lda.w #0
    sta.l $002118
    dex
    bne .clr1
    lda.w #!BLK_EMPTY*16
    sta.l $002116
    ldx.w #16
.clr2:
    lda.w #0
    sta.l $002118
    dex
    bne .clr2
    sep #$20
.out:
    rep #$30
    ply
    plx
    pla
    plp
    sep #$10                   ; displaced: SEP #$10 : TDC : STA $2102
    tdc
    sta.w $2102
    rtl

block_gfx:
    ; full block: black outline, yellow face, white top highlight, brown underside
    db $FF,$00,$FF,$7E,$81,$7E,$81,$7E
    db $81,$7E,$81,$7E,$81,$00,$FF,$00
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    ; empty block: black outline, dark brown face
    db $FF,$00,$FF,$7E,$FF,$7E,$FF,$7E
    db $FF,$7E,$FF,$7E,$FF,$7E,$FF,$00
    db $FF,$FF,$81,$FF,$81,$FF,$81,$FF
    db $81,$FF,$81,$FF,$81,$FF,$FF,$FF

; ---- cheat helpers (cheats.asm owns the state; these are the readers hp.asm needs) ----
org $BEB600
; A = mask (16-bit): A = mask & flags, Z set when the cheat is off or the cheat state is not valid
cheat_test:
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

; !HP_MAX = 3, or 5 with the MORE BLOCKS cheat. Preserves A, X, Y and the processor status.
hp_max_store:
    php
    rep #$30
    pha
    lda.w #$0004
    jsl cheat_test
    sep #$20
    beq .three
    lda.b #5
    bra .st
.three:
    lda.b #3
.st:
    sta.l !HP_MAX
    rep #$20
    pla
    plp
    rtl
