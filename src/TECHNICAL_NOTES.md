# Pagemaster (SNES US) - RE notes

ROM: LoROM, 2MB, sha1 02fa190bfbed8699ce8f741bac6675f3582ced68. File offset = (bank&0x7F)*0x8000 + (addr&0x7FFF).

## Harness (all in work/pagemaster/)
- Headless needs Port1 = SNES controller in ~/.config/Mesen2/settings.json (it was "None": no input ever reached the game, which caused the attract-demo mixup) and ScriptWindow.AllowIoOsAccess=true. The GUI rewrites settings.json on save: re-check both. Kill the live GUI (kill -9, it ignores SIGTERM) before headless runs or they exit instantly (single instance).
- mkstate.lua: boot to title, Start @1400, Right x90 @2100 on the map, Start @2300, savestate @3500 -> states/level1.mss (Torture Chamber, Richard idle on the floor).
- phases.lua + phases_cfg.lua: load state, run input phases, dump WRAM (dumps/<name>.bin) + screenshot each phase.
- pctrace3.lua: log PC of reads/writes to chosen addresses. Savestate calls must run inside an exec callback.
- bin/dis65816.py <rom> <bank> <start> <end> [m=16|8] [x=16|8]: linear disassembler (flag state is a guess, watch for misaligned output).
- Controls (Mesen default arrows layout): Arrows = d-pad, A key = SNES B (jump?), S = SNES A, Z = Y, X = X, D = Start, E = Select.

## RAM findings (WRAM = CPU 00:0000-1FFF mirror)
- Entities are per-slot 16-bit arrays indexed by X (slot*2): X pos at $0EBD,X; Y pos at $0E65,X; also $185D/$18B5/$190D/$1965,X and $1285,X (sign = facing/flag?).
- Update routine B2:F0D8 loads slot X into DP temps: $3C = X pos, $3A = Y pos, $1E05/$1E07 = hitbox offsets, $1E/$20 = size?.
- Richard (slot 0?) world X is read as $003C in the traces (48 -> 373 over 120 frames holding Right at ~2.7px/frame). Y during a jump: 615 (ground) -> 539 apex -> 615 ($1DE9 etc).
- $1D5F..$1D6D: 8 words that mirror X-7/Y-42/X+7/Y+2 style box edges, no CPU writes seen (block move/DMA?).
- B2:F227.. : tilemap (background) collision: tile type bytes 1,2,3,8,9 via LDA ($36),Y. NOT the enemy hit test.

## Open
- Locate the player-vs-enemy hit test and the stomp check (not in the tile routine). Next: write watchpoint on health/lives, or trace readers of enemy X/Y arrays $0EBD,X with Richards slot.

## Collision findings (2026-10-01, session 2)

Entity table (slot offset = slot*2, 0x00..0x56, 16-bit fields, many at odd addresses):
- X `$0EBD,X`, Y `$0E65,X`, prev-frame Y `$15F5,X`, Y velocity `$1285,X` (bounce sets 0xFFFE), flags `$0D5D,X`, next-in-list index `$1E6B,X` (low byte, 0xFF = end, high byte = prev link).
- Hitbox per entity: left offset `$185D,X`, top offset `$18B5,X`, width `$190D,X`, height `$1965,X`.
- Richard = slot 0x52: box (-6, -43, w13, h43). Slot 0x4E/0x50 (X=232, bat?) box (-8,-25,w17,h23). Slots 0x42-0x4A are 16x16-ish boxes (pickups?).
- Slots 0x00-0x34 in the Torture Chamber start state are uninitialised garbage, ignore.

Code (file bank = runtime bank - 0x80; B2 = file bank 0x32):
- `B2:FC2D` shared "probe vs list" test. Builds a rect for entity X into `$1D5F` L, `$1D61` T, `$1D63` R(=L+W), `$1D65` B(=T+H), checks `$1D6F` count of extra rects at `$1D71+8*n`, then walks the entity list starting at `$1E69` doing a strict AABB overlap (no tolerance). Hit: unlinks target via `B2:F084`, sets target flag 0x4000, returns Y=target, carry set. Callers: A8:D588, AC:BEAB, AC:C094, AC:C0B6, AC:C6E2, B2:EF6B, BA:F215 (per-enemy AI).
- `B2:FD22` same idea for entity `$0C33`, list at `$1D8B`, called from 97:FB03.
- `B2:FD0C` landing-from-above test: carry set if (prevY + top + height - 1) <= `$1D69` (top of box 2). ZERO tolerance. Called from 80:86DF, whose carry-set path bounces (sets `$1285,X`=-2, adds score 0x40, INC `$1805,X`): that is the stomp response.
- `B2:FD01`: prevY + top compared with `$1D6D`. Called from B2:FDF3.
- `B2:F084`: linked-list unlink (not damage).
- `B2:F227`: background tile collision (separate from entity collision).

Candidate hit-detection fixes (untested, need Dave's call on which interaction feels broken):
1. Stomp tolerance: make FD0C accept prevBottom-1-TOL <= top2 (JSL to freespace for the SBC).
2. Shrink Richard's damage hurtbox: change his per-entity box fields (`$185D/$18B5/$190D/$1965` for slot 0x52) where they are loaded.
3. Strictness of FC2D: add a few px of slack.

## Patch v1: work/pagemaster/patches/hitfix.asm (build with work/pagemaster/build.sh -> build/pagemaster_hitfix.sfc)
- Stomp tolerance: B2:FD16 (DEC A / CMP $1D69) -> JSL to BE:8000, allows !STOMP_TOL (6) px of overlap. Verified by disassembly only; no stompable enemy in the Torture Chamber start calls B2:FD0C (callers 80:86DF), so needs a play test where one exists.
- Contact inset: B2:FC42 probe build -> JML to BE:8008, same math then inset !HURT_INSET (2) px on every side. Verified dynamically (probecmp.lua): every edge moves exactly 2 px inward vs original, incl. the original +1 carry quirk.
- Free space used: BE:8000.. (file 0x1F0000, inside the 0xFF padding 0x1E941A..end).
- Overlay: overlay.lua draws all entity boxes (camera = PPU layer0 hscroll, vscroll+256) onto screenshots; Richard green, others red.
- Not done: stomp verification; attacks and ledges. (SNES checksum: asar already writes a valid one; bin/romtools.py fixsum is a safety net.)

## Recording analysis (Dave play session, 11193 frames, 2026-10-01)
- Tools: rec.lua (log inputs in the live GUI via Script Window), replay.lua / deathtrace.lua / hurttrace.lua (headless replay of recordings/rec_inputs.txt from rec_start.mss), ab.sh (same inputs on original vs patched ROM). Lives counter is WRAM $01E8.
- A/B: original and patched ROM give IDENTICAL life-loss frames (6623, 7569, 10273 -> game over, 10621 reset). Patch v1 changed nothing in this run. FC2D probed only bats (10 probes, 0 hits); FD0C stomp never called; FD01 3x (static objects).
- All 3 deaths are tiny box overlaps (1-3 px) from hazards that do NOT use FC2D: stone fist (slot 34, box -16,-48,w36,h48), thrown projectile (slot 32, -4,-9,w10,h11), rising object (slot 20, w11 h23). Sprites visibly overlap Richard in the first two, so these boxes are tight, not generous.
- Dave never pressed an attack button (inputs were only b/left/right/start/up).
- Open: locate the real player-hurt routine (not FC2D). VY52 / flags writes were not seen via write callbacks (likely different bank mirror or block copy), so next approach is a read-watch on the hazard slots or tracing writes to $01E8 via polling + PC sampling.

## Movement feel (Dave: controls mushy, jumps slippery) - patches/feel.asm
- Richard horizontal speed = 16.16 fixed ($1335,X int : $12DD,X frac), slot 0x52 = $0C33 (player slot). Velocity is written by routines in B0, not by plain stores to bank 0: absolute stores use the data bank register (often the $80-$BF WRAM mirrors), so write callbacks must be registered on every mirror bank (b and b+0x80, for b = 0..0x3F).
- B0:C9D7 (accelerate + friction A via B0:CAD1) and B0:CA54 (accelerate + friction B via B0:CB0C). Accelerate immediates: C9F6/CA07/CA73/CA84 (orig +/-$2C71 = 0.17 px/f^2, about 19 frames to the 3.33 cap). Friction A $0B1C (0.043), B $1638 (0.087); both are applied every frame ON TOP of the acceleration, so net accel was about 0.13 and stopping took 31 frames / 60 px.
- Friction routines are shared with enemies: hooked with a CPX $0C33 check so only Richard gets the new values.
- Measured with feeltest.lua (scripted inputs from states/level1.mss), original vs ACCEL=$8000, FRIC_A=$3000, FRIC_B=$4000: full speed +25 -> +11 frames; ground stop 31 f / 60 px -> 12 f / 21 px; air coast 91 -> 28 px; air reverse 20 -> 8 frames.
- Not changed: jump arc (vy starts at -5 instantly, symmetric, variable height by B hold), landing, max speed 3.33.
- From the recording (feel.py on recordings/fl_frames.txt): run-start latency median 3 frames, ramp about 7 frames per 1 px/frame, ground slide 12-54 px, landing slide 40-70 px.
- Build: build.sh makes build/pagemaster_hitfix.sfc (v1 only) and build/pagemaster_feel.sfc (v1 + feel).

## Attacks / jump forgiveness (session 2, after Dave said the feel patch "feels much better")
- Attacks: none in the Torture Chamber. btnprobe.lua pressed X, Y, A, L, R from the level start: no animation change, no new entity slot, nothing. Only B (jump) and the d-pad do anything. Item "attacks" dropped for this level (other levels untested).
- Jump trigger: the ground state routine (B0:BC10..) starts a jump on a fresh B press ($031E & $8000) by setting the state pointer ($138D,X) to $B23C; B0:BC55 then sets vy to -5 (or -6 with $2AAB fraction), so takeoff is 2 frames after the press. Entities run a state machine via $138D,X (Richard states seen: B002 ground, B25C fall, B5EA rise, AD18/AD83 ground variants, B9B3 landing, B712 jump variant).
- Recording evidence (jumpforgive.py on recordings/f2_frames.txt, 47 B presses): 41 started a ground jump, 1 press landed 8 frames early and was ignored, 0 presses within 8 frames of walking off an edge (74 walk-offs). So jump buffer / coyote time are not demonstrated pain points; not built.
- Possible remaining items: shave the 2-frame takeoff delay, landing behaviour (state B9B3), hurt routine (hazards use a different, tight test), stomp (no stompable enemy seen yet), other levels.

## Jump takeoff latency - patches/jumpfast.asm (build/pagemaster_all.sfc, dist/pagemaster_all.ips)
- Original timeline: B pressed in frame N, the game sees the fresh press ($031E bit 15) in frame N+1 (hardware joypad latency, unavoidable) and the ground state only SETS the next state ($138D,X = $B5D3, one-shot jump-start state) and returns; the jump impulse (B0:BC55) and the first rise happen in N+2.
- Fix: the five ground-state sites (B0:B01E run B002, A867 idle A84B, B15B B13B, ADAF AD83, AD30 AD18; identical 7 bytes LDA #$B5D3 / STA $138D,X / RTL) become JML $B0B5D3, so the jump runs the same frame the press is seen. Verified by jumptest.lua (orig vs patched, standing / running right / left): takeoff exactly 1 frame earlier in every case, arc identical afterwards. Cost: that one frame applies horizontal physics twice (6 px step instead of 3).
- 41 of 47 recorded jumps came from these five states (B002 27, A84B 5, B13B 5, AD83 4, AD18 1). Other air-to-jump sites (17 more LDA #$B5D3 sites) untouched.
- The remaining delay (press -> game sees it) is the SNES auto-joypad read, one frame, not patchable.

## Level starts, passwords, level list (session 2, last part)
See work/pagemaster/LEVELS.md. Password format and checker at B0:92E2 (6 x 4-bit symbols, XOR with the 6th, XOR checksum), fields: world, lives, library cards. States: states/start_{horror,adventure,fantasy}_1_*.mss load in the live GUI via File > Load State > Load from file (Ctrl+L). Name table at file 0x1C8524 is name-then-ID. Each world map has ONE node and the level only advances when a level is completed; password does not select a level.
Dead ends: rumoured cheat code B A L Down Y x2 does nothing; poking WRAM 0x268/0x28C does nothing to the node level; teleporting Richard (WRAM F0F/EB7) did not reveal an exit. Scripts: pw*.lua (password UI/validator tracing), passcycle.lua (many codes, fast), mapstate.lua, levelstart.lua, nodeprobe.lua, progpoke.lua, sweep.lua, cheat.lua.

## Title banner - patches/banner.asm (build/pagemaster_full.sfc, dist/pagemaster_full.ips)
- Title menu text (START GAME / PASSWORD) is 16x16 OAM sprites (large size, palette 7, attr $3E), NOT background. Font is A-Z in OBJ VRAM: tile = (n/8)*$20 + (n%8)*2 (A=$00, M=$28, S=$44). No digits/punctuation. OAM shadow in WRAM at $0957 (x, y, tile, attr per slot), high table $0B57; the menu text lives in slots 111..127, slots 0..15 are free on the title.
- Frame routine A9:EEC4 clears the shadow ($F000 words) then draws; the hook at A9:EEDE (`LDA #$1000 : STA $B8`) JSLs to BE:8200, which stamps 16 sprites into slots 0..15 ("REVISED EDITION", x=36 pitch 12, y=152 minus 3/2 px per letter = slanted stamp across the book) and redoes the displaced instructions.
- Colour: OBJ palette 5 is empty on the title, so a second hook at BA:F38A (the OBJ palette DMA from WRAM $0595, row n at +32n) fills row 5 idx 13/14 (the only indices the font uses) with dark red / $0C1F when row 6 idx 1 = $52D9 (title fairy palette). The stamp stub draws only while that red is in the buffer, which keeps it off the password screen.
- The same frame routine runs the password screen; the palette guard keeps the banner off it (first version leaked onto the password dots). Start -> Horror World and gameplay are clean. Verified by headless screenshots (shots/tb_1300.png, shots/lk_*).
- asar gotcha: `db 30+12*n` evaluates left to right ((30+12)*n); parenthesise. Copying files to the CT from Windows via scp can bring CRLF into build.sh; run `sed -i 's/\r$//'`.
- Sprite budget: 15 visible letters = 30 of 34 slivers on that scanline, so a longer line will drop sprites.

## Player hurt path + v2 hurtbox inset (deep dive, 2026-10-01)
- Life loss chain (found by write-tracing $01E8 with callbacks on every WRAM mirror, hurt2.lua): B2:FD22 player-vs-hazard pass (builds Richard's rect $1D5F L/$1D61 T/$1D63 R/$1D65 B, tests the static rect list at $1D8B and the hazard entity list from $1E0F, entity flag $0D5D bit 0x02 = touch hurts) -> JSL B0:C2EC (hurt dispatcher; many enemy AIs call it directly: A8, AC, B5, BA banks) -> B0:C2AE -> `DEC $01E8` at C2B8. B0:C338/C37A gate on $01EC bits $20/$10 (i-frames), B6:86AA skips damage when $0294 & $60 (debug/cheat bits). There is NO hit-point system: every hurt is a life.
- B0:C2EC runs every frame of an overlap (i-frames stop repeats); only the first reaches C2AE.
- hitfix.asm v2 insets Richard's hurtbox in that pass (!PIN_X 3, !PIN_T 3, !PIN_B 2; hooks B2:FD48 and B2:FE3D, code BE:8400) and restores the box-2 copy ($1D67..$1D6D) to full size.
- Verification (deathsave.lua, DS_MODE=save|test): savestates 25 frames before each recorded death (recordings/pre_{6598,7544,10250}.mss), same inputs on orig / 0-inset / v2. The 0-inset build is identical to the original (stubs are clean). v2 delays each of the three hits by exactly 1 frame and does not avoid any: those deaths are real overlaps by moving hazards, not edge brushes. v2 is harmless but nearly inert on this recording.
- Do NOT use whole-run replay A/B across ROMs: the stubs cost cycles, frame timing shifts and runs diverge (even with 0 insets).
- Open: a hit-point buffer (e.g. 2 hits per life) is the real "one-hit-lethal" fix but needs Dave's call and a HUD indicator.

## Hit-point buffer + HUD (patches/hp.asm, in build/pagemaster_full.sfc / dist/pagemaster_full.ips)
- Dave's spec: 3 hits per life, 3 basic blocks matching the colour scheme in the top left, pits cost a block, every level refills.
- State (WRAM 7E:6000-6004; that 1 KB block was never touched in boot or the 11000-frame recording; $01EC has no free bits): HP word (lo = hits taken 0..2, hi = lo EOR $A5, anything else reads as 0), HUD_ACTIVE, HUD_TICK, RESPAWN. Uninitialised WRAM is safe by design.
- Hooks: hp_hurt replaces JSL B0:C2AE at B0:C32E and A8:CFD3 (hits 1-2: B0:BD2B + B0:C2C5 flinch, no life lost; hit 3: reset, original C2AE). hp_hurt_pit at B0:A667 (fall = a hit, then the game's own respawn; sets RESPAWN). hp_spawn at B0:A787 (player spawn = level start AND respawn): refills unless RESPAWN. hp_init at B0:C179 (new game). hud_tick at B2:FD22 sets HUD_ACTIVE=3 each gameplay frame.
- Gameplay is IRQ driven: the NMI vector never fires in a level (IRQ at 00:FFA5 -> JML [$D3]), the whole frame runs from the IRQ handler, OAM shadow $0957 is DMA'd by A9:FC68 around scanline 226 (inside vblank). oam_hud hooks that routine's first 6 bytes, (re)uploads two 8x8 OBJ tiles ($FC full, $FD empty; no sprite ever referenced them) every 64 frames and stamps OAM slots 0-2 (x 12/21/30, y 20, palette 7, small size). Mesen screenshots crop the top ~8 scanlines, so y=8 looked half hidden.
- Verified (hptest.lua, bootlevel.lua; absolute paths only, relative io.open paths silently fail in the headless harness): pre-death states with HP_POKE=0/1/2 (d=0,1 keep the life, d=2 takes it and refills), pit with d=0 (hp 1, lives 3, respawn at start with the damage kept) and d=2 (lethal), level spawn refills a poked d=2, HUD visible in all three worlds, absent on the map and title.
- Not done: damage carries through death-less respawns only by design; other hurt paths that call C2AE directly are only these three sites (A8:CFD3, B0:A667, B0:C32E), verified by ROM scan.

## HUD tile fix (2026-10-02, from Dave's own-PC recording)
- Symptom: blocks showed green/blue/red garbage. Cause: the game streams enemy/animation graphics into OBJ tiles during play and overwrote $FC/$FD (my first choice). Found with a Lua recorder (kit hudrec.lua: screenshots every 10 frames + log of OAM 0-2, tile bytes, palette 7, OBSEL) running in Dave's Windows Mesen (needs AllowIoOsAccess=true in the kit settings.json; left on, backup settings.json.bak-before-hudrec).
- Fix: blocks now use OBJ tiles $21 (full) / $27 (empty), the blank right halves of font glyphs I and L (never written in an 11000-frame recording), re-uploaded every 16 frames, cleared when gameplay ends (title banner draws an I). HUD_ACTIVE is only valid as 1..3 (uninitialised WRAM made blocks + a garbled banner appear on the title).
- tilestress.lua (replay the recording, count frames where $21 != block art while the HUD is active): 9000 frames, 5478 active, 3 bad frames, longest run 2.

## Non-fatal hit reaction (2026-10-02, Dave: "health doesn't reflect in the bars")
- Cause: state B969/B9B3, which the first hp.asm used as the "flinch", is the game's death sequence (hop, fall through the floor, then B6875B restarts the level ~200 frames later). Every hit therefore restarted the level, the spawn hook refilled the blocks, and the bars never showed damage. Found from Dave's hudrec.log (HP=01 followed by active=00, then a spawn and HP=00).
- Now: hits 1-2 call hp_flinch: hurt sound ($00C2 via 9D:EDB3), the game's own invulnerability B0:C344 (flag $01EC&$20, timer $0330=$D5, entity flag $2000), and state B5D3 (jump-start = knock-up). Richard keeps playing in place. The third hit still goes to the original C2AE (life lost, death sequence). Pits keep the death sequence/respawn (B0:C2C5) with RESPAWN set so the damage survives the respawn.
- Verified (hptest.lua): d=0/1 hits keep the life, no respawn, invulnerability ends ~270 frames later, a later hit counts; d=2 and pit paths unchanged; level start still refills; HUD shows 3 full -> 2 full + 1 empty after a hit.

## Platform edge forgiveness (platform.asm, 2026-10-02, Dave: "thin book platforms ... not very forgiving")
- Tile collision for every entity: B2:F227 (counts solid tiles in the columns under the box at the feet row; carry = ANY column solid; slope types 2/3/8 depend on sub-tile height $38; "hit tile" types 1 solid, 9 special). Call sites: B2:F6C2 (standing/walking pass) and B2:F7C7 (airborne pass: Richard's fall state B25C). Hooking only F6C2 changes nothing for landings.
- Patch: for Richard (slot $0C33) with vy >= 0, if the normal probe finds no ground, retry with the footprint widened by !FLOOR_EXT = 8 px each side, but only when the same widened columns one tile higher are free of solid tile (wall guard so he cannot stand in mid-air beside a wall). Scratch words 7E:6010-6014.
- Verified with dropscan.lua (drop Richard from y=330 at each x, savestate reloaded per x): the flat book (world x 803..917, top y 424) now catches from x 795 to ~925; 313 drops over x 40-1600: only 9 differ, all edge catches (book edges, a y=480 platform at x 620/625/745, ramp edge 570/575), no odd landing heights. The start-area ramp at x~574 is a slope, not a ledge. Hit-point tests still pass. calltrace2.lua shows which F227 caller a state uses.
- Lessons: dropscan without a per-x reload is invalid (Richard grabs something and hangs in AD18); Windows python cannot open Git Bash /tmp paths, use the real Temp path.

## Flying books (platform.asm, 2026-10-02, Dave: "you have to hit them straight in the middle")
- Flying book = entity type $00E0, flag $0001 at $0D5D (landing sets $0010); box was left -22, top -17, w43, h11 (top y 399 at rest). Landing is decided in B2:FD22's list loop: overlap (strict AABB) -> B2:FD01 (book prev top >= Richard prev bottom) -> B0:BD32 -> B0:C579 snaps him to the top.
- Recorded with bookrec.lua / bookrec2.lua (Games\Pagemaster\Record Books.bat; SELECT drops a mark; needs Mesen AllowIoOsAccess=true). Findings: (1) Richard's rect bottom is y+1 and overlap only starts at curB >= 402, but FD01 already failed once prevB was 400/401: a 2 px dead zone that dropped slow falls (standing jumps) through. Fix: book_land at BE:9200 (hook B2:FDF3), accepts prevB up to !LAND_TOL=8 px below the top when Richard vy >= 0. (2) The remaining misses had no overlap at all: the box is narrower than the ~50 px sprite. Fix: book_box at BE:9300 (hook 97:F36B, the type box copy in 97:F350) widens type $00E0 by !BOOK_EXT=8 px each side.
- Verified: entity boxes identical to the previous build in all three world starts (boxdump.lua, 900 frames); headless cannot spawn the books by teleport, so the books were verified by Dave's play-test ("books feel good now"). Scripts: platscan.lua/run_platscan.sh (all-level scan for landable entities; ~5 min per level, found nothing in 5 levels, not worth it), booktest.lua, boxdump.lua.

## Title stamp animation (banner.asm + hp.asm hook, 2026-10-02, Dave: "animate the REVISED like a library stamp")
- Title facts (titleprobe.lua, hookprobe.lua, vramprobe.lua, scrollprobe.lua): the title frame routine A9:EEC4 and the OAM DMA routine A9:FC68 run every OTHER video frame (30 Hz); the OBJ palette upload BA:F38A runs once at title load, so colour changes mid-title must write CGRAM directly; slots 0..105 are free on the title (menu text is 106..127); all of OBJ VRAM is occupied except a few blank tiles, so the stamp borrows the font glyphs Z/Y/X (never on the title or password screens) and restores them from a WRAM copy afterwards (VRAM reads: the first pair returns the prefetch, the second returns it again - throw one pair away); the game rewrites BG scroll every video frame, so a scroll write from the 30 Hz hook lasts exactly one frame (jitter reads as a shake).
- stamp_frame (BE:9500, hook A9:EEDE) counts T per title frame (WRAM 7E:6020, check word 7E:6022 = T eor $5A5A; reset whenever the red ink is not in the palette buffer, so the password screen and returning to the title replay it). stamp_vblank (BE:9800, called from oam_hud in hp.asm) does the VRAM jobs, CGRAM ink flash and BG jolt per T. Schedule: T6-13 drop, 14-16 down + jolt, 17-21 lift, 20+ letters with white->pink->red flash. Tables stamp_plate / stamp_bgv / stamp_flash / stamp_act at the end of banner.asm; genstamp.py regenerates the three 16x16 block graphics.
- Verified headless (contact sheets in shots/stamp3_*.png): drop/hold/lift/reveal frames, Start pressed mid-stamp and after it both reach the Horror World map and level, password screen unchanged, glyph Z/Y/X tiles byte-identical to the original after T=24. Not verified: how it feels at real speed, sound (none added).
- Thud (2026-10-02): at T=13 (the frame the stamp reaches the page) stamp_frame calls the game's sound routine 9D:EDB3 with !THUD_SND = $0052. Chosen from sndscan.lua (histogram of sound id and caller over four levels): $4D (B0:B090, jump state) and $52 (A9:F39C, an animation-script event) fire 1:1 per jump, so $52 is the landing sound. Verified headless that exactly one sound call fires at the impact frame; audibility not verified (no audio capture in Mesen's Lua). Change !THUD_SND if Dave wants a different sound.

## CHEATS menu (cheats.asm + hp.asm + build.sh, 2026-10-02, Dave: title menu item A, all six cheats, reset each boot)
- Title menu (loop B0:8617, setup B0:8505): WRAM $0300 = index; three items now (START GAME y=$B0, PASSWORD y=$C0, CHEATS y=$D0, pitch 16 so they fit above y=224). Hooks: B0:8542/8559 text y, B0:856F third text entity (string in bank BE) + the displaced fairy, B0:863E Up/Down cycle through 3, B0:85FE/85ED cursor y/x, B0:865C chosen item. START GAME / PASSWORD return modes $11 / $12 through B0:8669 (B6:875B stores the mode in $0292).
- CHEATS is a modal screen: its own loop (9D:FE2B vsync, A9:FC68 OAM DMA, BD:93B6 pad, $70 = new presses), the OAM shadow redrawn each frame from the menu font, BG hidden (TM=OBJ) and the backdrop colour forced black; the digit glyphs borrow the VRAM tiles of the font letters Q and Z (saved on entry, restored on exit). Selected row red (palette 5), others yellow (palette 7).
- State at 7E:6400.. (valid when K=$C3A5). Flags $01 invincible (hp_hurt/hp_hurt_pit ignore the hit, a pit respawns with no cost), $02 infinite lives (B0:C2B8 dec skipped), $04 more blocks (5; HP_MAX byte 7E:6005, HUD draws 5), $08 full cards ($01F8=8 at every spawn), $10 moon jump (gravity $42AA -> $1AAA for Richard, 97:F9F4), $20 super speed (a second step of Richard's horizontal velocity, 97:FBFF).
- PLAY: sets !CH_AUTO and returns START GAME; hook 80:811D (the world map, reached after the normal new-game init at 80:8106) pokes $028A/$028C, sets mode 2 and jumps to the level loader 80:8183. World/level are the game's own indices (25/14/19/4/3 levels); LEVEL_SELECT.md lists the names.
- Gotchas found: WRAM 7E:6040-605F is hitfix's pickup/hurtbox scratch (my first cheat state there was clobbered every frame, found by hptest.lua with HP_WATCHK=1); hp.asm grew past BE:8800 and overwrote platform.asm's floor_wide (moved to BE:B700, crash at boot: oam_hud's tail was clobbered); Python on Windows writes CRLF (break build.sh), always open(...,newline='\n').
- Verified headless: three-item navigation, screen draw/toggles/world+level changes, PLAY into a level (GET READY card + gameplay), cheat effects with hptest.lua (invincible: 33 hits ignored, no HP/life change; infinite lives: lives stay 1 after a fatal hit; blocks: hits 2 of 5 survive; cards: $01F8=8 after PLAY; speed/moon: motion differs from baseline), five-block HUD. Not verified: how it feels, sound blips on the menu (none added).

## Sound on the title (investigated 2026-10-02; Dave: "i dont hear the thud")
- The thud call works mechanically (9D:EDB3 -> 9F:8008 -> 9F:81F8, exactly one call at T=19) but is silent: the title/world-map SPC sound bank (bank 1, table at 9F:FD71, blocks listed per bank) contains no usable sound-effect table. Evidence: DSP voices (spcDspRegisters) show no voice for any id $20-$67 on the title; the "menu blips" seen on voice 6 (sample 03) are the title MUSIC, not effects; the title menu issues no sound commands at all; the only commands on the title/map are the music commands $E4/$E1/$C0.
- Bank 1 lists the same 42-byte dummy block (1F:FA20) four times where the in-level banks have real effect tables (bank 2: 1F:F7DE, F890, F979, FA4C). Pointing bank 1's entries 1-4 (1F:988E+3..) at those makes ids $66/$67 produce a short high tick (sample $0B, vol $17) - but only after ~f2550 of title time (the music holds the voice earlier), so it is useless for the stamp (title T=19 is ~f1270). Not shipped. A real thud needs a new sample + effect definition injected into the title bank (driver reverse engineering).
- SFX ids are bank-relative (landing is $52 in bank 2 but the equivalent effect is $66 when the bank-2 tables sit in bank 1). Sound commands from Lua: hook exec at 1F:81F8 (the jml target is the 1F mirror, not 9F). Useful scripts: dspwatch.lua, sndscan2.lua/sndtest.asm (id sweep), spcdump.lua (SPC RAM + DSP dump; BRR decode in the transcript).

## Stamp v4 (wood-grain stamp modelled on a rubber stamp photo, 2026-10-02)
- genstamp2.py draws ten 16x16 graphics (4 wood variants incl. a dark end-grain cap used flipped on the right, 2 red rubber pads on a black foam line, black lathe-turned handle in 4 pieces) and writes patches/stamp_art.inc + stamp_parts.inc + shots/stamp_preview.png. Block is 2 wood rows (32 px) + a pad row (foam 2 px + red rubber 7 px) = covers the banner band; handle 64 px tall.
- Colours: OBJ palette 5 indices 1-12 (written once at T=1; the banner ink keeps 13/14). Graphics borrow the VRAM tiles of the glyphs B F J K L Q U X Y Z (saved to WRAM 7E:6500, restored T=28-37). Two VRAM jobs per vblank are fine (all 40 tiles verified byte-identical to the art after upload; glyph tiles verified identical to the originals after restore).

## Stamp thud - SOLVED (thud.asm + banner.asm music_defer, 2026-10-02: "try the sound driver injection")
- SPC driver (RAM dump via spcdump.lua, disassembled with spcdis.py; interpreter at $0E5D, command dispatch $0381/$03A9, effect start $08F5/$0A32): sound ids $40-$7F = 4 groups of 16 effects ((id-$40)>>4 selects the group pointer from $153D), each effect a small bytecode program (preamble `f4 fa f6 ef 60 ee 0c f0 00 ec 60 eb 0c ed 00 e9 00`, `fe SS` = play sample SS (bit 6 = slide), `note dur`, `ff` end; notes index the pitch table at $143D, $1000 = note 76). Commands $E0-$FF go through a RET-table at $0649: `fc` init, `fd` sample load, `fe` group load, `ff` end, $E1 = release music voices, $E2 = release effect voices.
- Bank data in the ROM: bank table at 9F:FD71 (3-byte pointers) -> a list of 24-bit block pointers (ends 000000) -> blocks `[len16][payload]`. `fd` payload = size16, loop offset16, H (header size), H header bytes [volL, volR, ADSR1, ADSR2, tune, ...], BRR data; the sample directory entry (start = write ptr + H) is made by the loader in load order. `fe` payload = a literal-run / back-reference stream: byte n<$80 = copy n+1 literals, byte >= $80 = copy `len` bytes from (256-byte) back, a 0 length ends (`ff 00`). A group = word 16, 16 effect offsets, programs.
- Why every effect was silent on the title: bank 1's four effect groups are dummies, AND the title song reserves all 8 SPC voices at priority $80 while effects have priority $40 and can only take a voice with a lower number. The song's start command $C0 (sent right after $E1 by the title setup, B0:8516/851A) is therefore deferred: music_defer arms a counter, stamp_frame sends $C0 after !MUSIC_FRAMES (34) title frames, i.e. after the thud. The title now starts silent, the stamp lands with the thud, then the song starts.
- thud.asm relocates bank 1's block list (the next bank's list follows it directly, no room to grow), swaps its 4th dummy group for the thud group and appends the thud sample as sample 13: a 0.3 s synthesised sound (sine falling 166->46 Hz with a noise click, BRR encoded, ~5.4 KB; genthud.py, preview shots/thud_preview.wav), played at native pitch (note 76), header volume $50.
- Verified (dspwatch.lua): $70 sent at title T=19, voice 0 plays sample $0D for 18 frames (0.30 s) at pitch $1000 vol $4E/$4E, silence, then the song starts at T=34 with its voices intact; the E1/C0 pair at the world map is unchanged. Not verified: how it sounds (no audio capture).

## Stamp v5: rotated to the banner's slope (genstamp3.py)
- The whole stamp is sheared to the REVISED text slope (1 px per 8 px): each 16 px column sits 2 px higher than its left neighbour, the top edge of the upper wood row and the bottom edge of the pad row carry the matching 1 px per 8 px slope inside the art, the neck graphic is pre-sheared and the handle rows step left. Geometry constants come from patches/stamp_defs.inc (!PLATE_Y = 117 puts the pad's lower edge ~3 px under the banner letters). 42 sprites, same 10 borrowed glyph slots.
