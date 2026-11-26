#!/bin/sh
# A stand-in for PixInsight's installer for the worst case: it fails half-way,
# and nothing can be moved afterwards, because it leaves the folder around the
# PixInsight folder read-only. The rehearsal uses it to check that the old
# folder is then left whole under its other name, and that the user is told.
# Called by install.sh as:   fake-installer-lost.sh <folder> <package>

FOLDER="$1"

mkdir -p "$FOLDER/bin"
echo "half of a module" > "$FOLDER/bin/Core-pxm.dylib"
chmod 555 "$(dirname "$FOLDER")"
echo "stand-in installer: failing on purpose, and nothing can be moved any more"
exit 1
