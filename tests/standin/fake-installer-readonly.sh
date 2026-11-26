#!/bin/sh
# A stand-in for PixInsight's installer that succeeds but leaves a folder into
# which nothing more can be written. The rehearsal uses it to check what
# happens when the user's own folders cannot be carried over.
# Called by install.sh as:   fake-installer-readonly.sh <folder> <package>

FOLDER="$1"

mkdir -p "$FOLDER/PixInsight.app/Contents/MacOS" "$FOLDER/bin"
echo "new version (stand-in)" > "$FOLDER/PixInsight.app/Contents/version.txt"
printf '#!/bin/sh\necho "PixInsight Core, new version (stand-in)"\nexit 0\n' > "$FOLDER/PixInsight.app/Contents/MacOS/PixInsight"
chmod 755 "$FOLDER/PixInsight.app/Contents/MacOS/PixInsight"
chmod 555 "$FOLDER"
echo "stand-in installer: installed into $FOLDER and made it read-only"
exit 0
