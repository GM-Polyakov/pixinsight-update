#!/bin/sh
# An attended rehearsal: you see and use every window, and nothing real changes.
#
# What is real:      PixInsight, the add-on's windows, the helper's windows,
#                    the quit request and the reopening.
# What is stand-in:  the download service (a made-up account on this computer),
#                    the installer, the PixInsight folder and the Trash, all
#                    under tests/out/attended/.
# Nothing goes to pixinsight.com, /Applications/PixInsight is not touched, and
# no administrator password is asked for.
#
#   sh tests/run-attended.sh          start the rehearsal
#   sh tests/run-attended.sh again    like picking "Update PixInsight" again
#                                     while the first run is under way: shows
#                                     progress and offers to cancel
#
# Close PixInsight before you start.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="$HERE/out/attended"
FOLDER="$OUT/Applications/PixInsight"
TRASH="$OUT/home/.Trash"
APP="/Applications/PixInsight/PixInsight.app"
BIN="$APP/Contents/MacOS/PixInsight"
SCRIPT="$ROOT/dist/stage/src/scripts/UpdateAssistant/UpdateAssistant.js"
WORK="${TMPDIR%/}/PixInsightUpdateAssistant"
PORT=8719

if [ "${1:-}" = "again" ]; then
   "$BIN" -x="$SCRIPT" >/dev/null 2>&1
   echo "Asked the running PixInsight to open Update PixInsight again."
   exit 0
fi

if pgrep -f "$BIN" >/dev/null; then
   echo "PixInsight is running. Quit it, then start the rehearsal again."
   exit 2
fi
sh "$ROOT/build/build.sh" >/dev/null || { echo "The build failed; run sh build/build.sh to see why."; exit 1; }

rm -rf "$OUT" "$WORK"
mkdir -p "$OUT/control" "$FOLDER/PixInsight.app/Contents" "$FOLDER/bin" "$FOLDER/gaia" "$TRASH"
echo "old version (stand-in)" > "$FOLDER/PixInsight.app/Contents/version.txt"
echo "a module of an add-on, built for the old version" > "$FOLDER/bin/OldAddon-pxm.dylib"
echo "the user's star catalogue" > "$FOLDER/gaia/catalogue.xpsd"

# A stand-in installer of 24 MB, sent slowly, so that the download takes
# about a minute and there is time to look at the progress window.
/usr/bin/python3 "$HERE/standin/dist-server.py" --port "$PORT" --layout real --cdn other --refuse-curl \
   --newest 9.9.9 --size-mb 24 --slow-ms 150 --log "$OUT/standin-server.log" >/dev/null 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null' EXIT INT TERM
sleep 1

cat <<EOF

PixInsight opens now with the Update PixInsight window.

  1. Sign in with the stand-in's made-up account:
        user name:  standin-user
        password:   standin-pass!1
     (Try a wrong password first if you like.)
  2. The download takes about a minute. To see the progress window, run this
     in a second terminal:   sh "$HERE/run-attended.sh" again
     You can leave that window open: it closes by itself when you choose
     Restart Now.
  3. Answer "Restart now, or later?" in the small window.
  4. PixInsight closes, the stand-in installer runs, and PixInsight reopens.
     The stand-in page offers a made-up version, 9.9.9. The closing message
     names the version you really have, because the rehearsal installs
     nothing real.

This terminal waits until the rehearsal is over, at most 30 minutes.

EOF

open -n -a "$APP" \
   --env "PI_UA_TEST_DIR=$OUT/control" --env "PI_UA_BASE=http://127.0.0.1:$PORT/dist/" --env "PI_UA_TEST_WINDOWS=1" \
   --env "PI_UA_TEST_INSTALL_DIR=$FOLDER" --env "PI_UA_TEST_INSTALLER=$HERE/standin/fake-installer.sh" \
   --env "PI_UA_TEST_HOME=$OUT/home" --env "PI_UA_TEST_OLD=1.9.2" \
   --env "PI_UA_TEST_PKGUTIL=$HERE/standin/fake-pkgutil.sh" \
   --args -n --no-startup-check-updates -r="$SCRIPT"

# Wait for the helper to start, then for it to finish.
I=0
while [ $I -lt 1800 ]; do
   if [ -f "$WORK/log.txt" ]; then
      grep -q "helper finished" "$WORK/log.txt" && break
      if ! pgrep -f "$WORK/helper.sh" >/dev/null && ! [ -f "$WORK/status" ]; then break; fi
   elif ! pgrep -f "$BIN" >/dev/null && [ $I -gt 30 ]; then
      break
   fi
   sleep 1; I=$((I+1))
done

echo "=== what happened ==="
if [ -f "$WORK/log.txt" ]; then
   sed 's/^/   helper: /' "$WORK/log.txt"
else
   echo "   The helper was never started (no update was begun)."
fi
echo "=== the stand-in PixInsight folder ==="
echo "   version in place:        $(cat "$FOLDER/PixInsight.app/Contents/version.txt" 2>/dev/null || echo none)"
echo "   star catalogue present:  $([ -f "$FOLDER/gaia/catalogue.xpsd" ] && echo yes || echo no)"
echo "   old add-on carried over: $([ -f "$FOLDER/bin/OldAddon-pxm.dylib" ] && echo yes || echo no)"
echo "   in the stand-in Trash:   $(ls "$TRASH" 2>/dev/null | tr '\n' ' ')"
echo "   left in Applications:    $(ls "$OUT/Applications" 2>/dev/null | grep -v '^PixInsight$' | tr '\n' ' ')"
echo
echo "The stand-in service is stopped now. The real PixInsight folder was not touched."
