; The Pagemaster (SNES, US) - OAM builder speed-up. asar patch, LoROM. Needs no free space (in-place rewrite, same length).
;
; A9:F793 turns a metasprite into OAM shadow entries; its inner loop (A9:F800..F872) runs once per drawn tile (~45 per frame,
; the second-hottest routine in the game). For the OAM high table ($0B57: x-high and size bits, 2 bits per sprite) it did
;     PHB / PHY / PHK / PLB   ... table reads with DB = A9 ...   PLY / PLB
; i.e. switched the data bank just to read three 8-entry ROM tables (A9:FBC9 clear masks, FBD9 x-high bits, FBE9 size bits)
; with `abs,Y`. Here the tables are read with long addressing (`and.l/ora.l $A9xxxx,X`) so the bank switch goes away, and the
; slot arithmetic is done straight from $BC (slot*4) instead of via two TXA/LSR/LSR round trips.
; The WRAM accesses ($0B57) keep using the caller's data bank exactly like the original's other WRAM accesses ($0957/$0959 just
; above): the bank is always in $80-$BF there (seen: 94, B2, B4, B8, BB, BD), which mirrors low WRAM.
; Same result bit for bit; about 12 cycles saved per drawn tile. Replaces A9:F823..F856 (52 bytes), next instruction is F857.

lorom

org $A9F823
oam_block:
    phy
    lda.b $BC                  ; slot*4
    lsr a
    and.w #$000E               ; (slot & 7) * 2  = table index (orig: Y)
    tax
    lda.b $BC
    lsr a
    lsr a
    lsr a
    lsr a
    and.w #$FFFE               ; (slot >> 2) & ~1 = high-table byte offset (orig: X)
    tay
    lda.w $0B57,y
    and.l $A9FBC9,x            ; clear this slot's two bits
    sta.b $32
    lda.b $38
    and.w #$FF00               ; x >= 256?
    beq oam_nox
    lda.b $32
    ora.l $A9FBD9,x            ; set x-high bit
    sta.b $32
oam_nox:
    lda.b $32
    ora.l $A9FBE9,x            ; size bit
    sta.w $0B57,y
    ply
assert pc() == $A9F857
