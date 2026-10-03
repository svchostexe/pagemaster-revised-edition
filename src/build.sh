#!/bin/sh
# build.sh: clean US ROM + patches ->
#   build/pagemaster_hitfix.sfc  hit detection only          (dist/pagemaster_hitfix.ips)
#   build/pagemaster_feel.sfc    + movement feel             (dist/pagemaster_hitfix_feel.ips)
#   build/pagemaster_all.sfc     + 1-frame-faster jump start (dist/pagemaster_all.ips)
# asar writes a valid SNES checksum itself; romtools fixsum is a safety net. dist/*.ips contain no ROM data.
set -e
cd /opt/romhack/work/pagemaster
cp ../../roms/pagemaster.smc build/pagemaster_hitfix.sfc
asar patches/hitfix.asm build/pagemaster_hitfix.sfc
cp build/pagemaster_hitfix.sfc build/pagemaster_feel.sfc
asar patches/feel.asm build/pagemaster_feel.sfc
cp build/pagemaster_feel.sfc build/pagemaster_all.sfc
asar patches/jumpfast.asm build/pagemaster_all.sfc
for r in hitfix feel all; do python3 ../../bin/romtools.py fixsum build/pagemaster_$r.sfc; done
python3 ../../bin/romtools.py ips ../../roms/pagemaster.smc build/pagemaster_hitfix.sfc dist/pagemaster_hitfix.ips
python3 ../../bin/romtools.py ips ../../roms/pagemaster.smc build/pagemaster_feel.sfc dist/pagemaster_hitfix_feel.ips
python3 ../../bin/romtools.py ips ../../roms/pagemaster.smc build/pagemaster_all.sfc dist/pagemaster_all.ips
sha1sum build/*.sfc
# + title-screen banner/stamp + three-hit hit-point buffer with top-left HUD + wider platform footing + CHEATS menu (all of the above)
cp build/pagemaster_all.sfc build/pagemaster_full.sfc
asar patches/banner.asm build/pagemaster_full.sfc
asar patches/hp.asm build/pagemaster_full.sfc
asar patches/platform.asm build/pagemaster_full.sfc
asar patches/cheats.asm build/pagemaster_full.sfc
asar patches/thud.asm build/pagemaster_full.sfc
python3 ../../bin/romtools.py fixsum build/pagemaster_full.sfc
python3 ../../bin/romtools.py ips ../../roms/pagemaster.smc build/pagemaster_full.sfc dist/pagemaster_full.ips
sha1sum build/pagemaster_full.sfc
# + perf: in-place OAM builder speed-up (patches/perf_oam.asm), all of the above
cp build/pagemaster_full.sfc build/pagemaster_perf.sfc
asar patches/perf_oam.asm build/pagemaster_perf.sfc
python3 ../../bin/romtools.py fixsum build/pagemaster_perf.sfc
python3 ../../bin/romtools.py ips ../../roms/pagemaster.smc build/pagemaster_perf.sfc dist/pagemaster_perf.ips
sha1sum build/pagemaster_perf.sfc
