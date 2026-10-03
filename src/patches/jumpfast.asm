; The Pagemaster (SNES, US) - jump takeoff latency patch. asar patch, LoROM. Needs no free space.
;
; Originally each ground state (idle, run, ...) does its physics, sees the fresh B press
; ($031E & $8000), only SETS the next state pointer ($138D,X = $B5D3) and returns. The jump
; state then runs on the NEXT frame, so takeoff comes one frame after the game already knew
; about the press (on top of the hardware's one-frame joypad latency).
;
; B5D3 is a one-shot state: it plays the jump animation, sets the jump impulse (B0:BC55),
; switches the state to the rising state ($B5EA) and runs the rising physics in the same call,
; ending in an RTL. So the ground states can simply jump into it: `JML $B0B5D3` replaces
; `LDA #$B5D3 : STA $138D,X : RTL` (7 bytes -> JML + 3 NOPs) and the jump starts one frame earlier.
; Cost: that single frame applies horizontal physics twice (once by the ground state, once by the
; rising state), a one-off extra step of at most one frame's travel.
;
; Sites (all identical 7-byte `A9 D3 B5 9D 8D 13 6B`), the five ground states Dave's jumps started from:
;   B0:B01E run (B002), B0:A867 idle (A84B), B0:B15B (B13B), B0:ADAF (AD83), B0:AD30 (AD18)

lorom

macro fast_jump(addr)
    org <addr>
    jml $B0B5D3
    nop
    nop
    nop
endmacro

%fast_jump($B0B01E)
%fast_jump($B0A867)
%fast_jump($B0B15B)
%fast_jump($B0ADAF)
%fast_jump($B0AD30)
