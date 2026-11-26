#!/bin/sh
# A stand-in for PixInsight's installer, used by the rehearsal.
# Called by install.sh as:   fake-installer.sh <folder> <package>
#
# Like the real installer it refuses to run while the folder exists. Then it
# creates a small folder that looks like a newly installed PixInsight, with a
# stand-in for the PixInsight program that "starts": asked for its list of
# options, it answers and ends well.

FOLDER="$1"
PKG="$2"

if [ -e "$FOLDER" ]; then
   echo "stand-in installer: a previous installation was found at $FOLDER"
   exit 1
fi
if [ "$(head -c 4 "$PKG" 2>/dev/null)" != "xar!" ]; then
   echo "stand-in installer: $PKG is not an installer package"
   exit 1
fi

mkdir -p "$FOLDER/PixInsight.app/Contents/MacOS" "$FOLDER/bin" "$FOLDER/src/scripts"
echo "new version (stand-in)" > "$FOLDER/PixInsight.app/Contents/version.txt"
echo "a module of the new version" > "$FOLDER/bin/Core-pxm.dylib"
printf '#!/bin/sh\necho "PixInsight Core, new version (stand-in)"\nexit 0\n' > "$FOLDER/PixInsight.app/Contents/MacOS/PixInsight"
chmod 755 "$FOLDER/PixInsight.app/Contents/MacOS/PixInsight"
echo "stand-in installer: installed into $FOLDER"
exit 0
