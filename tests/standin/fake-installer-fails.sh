#!/bin/sh
# A stand-in for PixInsight's installer that fails half-way, used by the
# rehearsal to check that the old folder is put back.
# Called by install.sh as:   fake-installer-fails.sh <folder> <package>

FOLDER="$1"

mkdir -p "$FOLDER/bin"
echo "half of a module" > "$FOLDER/bin/Core-pxm.dylib"
echo "stand-in installer: failing on purpose after writing part of $FOLDER"
exit 1
