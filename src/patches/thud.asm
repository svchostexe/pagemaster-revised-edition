; The Pagemaster (SNES, US) - a real thud for the title stamp: a synthesised sample + effect added to the title sound bank. asar patch, LoROM.
;
; Why: the title/world-map SPC bank (bank 1) ships dummy effect tables (the same 42-byte block four times), so every sound id is silent
; there. Sound ids $40-$7F are four groups of 16 effects ((id-$40)>>4 picks the group, loaded in order from the bank's `fe` blocks); the
; driver code is in RAM at $0381.., the effect bytecode interpreter at $0E5D, the `fd` sample loader at $0807, the `fe` group loader at
; $08BC/$139C (a literal-run / back-reference stream). genthud.py builds the two blocks from a synthesised pitch-dropping sine + noise
; click (BRR encoded, ~5.4 KB), and this patch:
;   * relocates bank 1's block list (the original has no room to grow: the next bank's list follows it directly) with
;     entry 4 (the 4th dummy group = ids $70-$7F) replaced by the thud group and the thud sample appended last (-> sample index 13),
;   * points the bank table entry (9F:FD71 + 3*1) at the new list.
; Effect id $70 plays the thud (see !THUD_SND in banner.asm).

lorom

org $9FFD74                     ; bank table entry for bank 1 (3 bytes per bank at 9F:FD71)
    dl bank1_list

org $BECC00
bank1_list:
!i = 0
while !i < 19
    if !i == 4
        dl thud_group_block
    else
        dl read3($9F988E+(3*!i))
    endif
    !i #= !i+1
endwhile
    dl thud_sample_block
    dl $000000

org $BECD00
incsrc "thud.inc"
