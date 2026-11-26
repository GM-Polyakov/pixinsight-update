#!/bin/sh
# A stand-in for PixInsight's installer that succeeds, but installs a
# PixInsight that does not start on this Mac. Its PixInsight ends the way the
# Intel build of PixInsight 1.9.6 ended on an Apple chip in the real update of
# 2026-11-24: with a message about the chip, and with code 1.
# The rehearsal uses it to check that the old folder is then put back.
# Called by install.sh as:   fake-installer-nostart.sh <folder> <package>

FOLDER="$1"

if [ -e "$FOLDER" ]; then
   echo "stand-in installer: a previous installation was found at $FOLDER"
   exit 1
fi

mkdir -p "$FOLDER/PixInsight.app/Contents/MacOS" "$FOLDER/bin"
echo "new version (stand-in)" > "$FOLDER/PixInsight.app/Contents/version.txt"
echo "a module of the new version" > "$FOLDER/bin/Core-pxm.dylib"
printf '#!/bin/sh\necho "*** Error: PixInsight requires a processor supporting the AVX2 and FMA3 instruction sets (stand-in)" >&2\nexit 1\n' > "$FOLDER/PixInsight.app/Contents/MacOS/PixInsight"
chmod 755 "$FOLDER/PixInsight.app/Contents/MacOS/PixInsight"
echo "stand-in installer: installed into $FOLDER a PixInsight that does not start"
exit 0
