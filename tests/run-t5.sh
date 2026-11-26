#!/bin/sh
# Test 5: ask PixInsight to quit the normal way, from a helper that PixInsight
# itself started, and see what the helper learns.
#
#   sh tests/run-t5.sh clean      nothing unsaved: PixInsight should just quit
#   sh tests/run-t5.sh unsaved    one unsaved test image: PixInsight shows its
#                                 own warning, and a person answers it
#   sh tests/run-t5.sh log        show the helper's log again
#
# In "unsaved" mode PixInsight asks whether to exit although an image is
# unsaved. Click No the first time. About twenty seconds later it asks again:
# click Yes. The test image is a grey square that this test created.
#
# PixInsight runs as a normal session, so it saves its window layout on exit
# as usual. The update check at startup is switched off for this session, so
# PixInsight downloads nothing and schedules nothing to install.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
APP="/Applications/PixInsight/PixInsight.app"
BIN="$APP/Contents/MacOS/PixInsight"
ERR="${TMPDIR:-/tmp}/pi-update-assistant-t5-error.txt"
mkdir -p "$OUT"

show() {
   echo "--- what the helper logged ---"
   cat "$OUT/t5-helper-log.txt" 2>/dev/null || echo "(no helper log)"
   if pgrep -f "$BIN" >/dev/null; then echo "PixInsight is running."; else echo "PixInsight is not running."; fi
}

case "${1:-}" in
clean|unsaved)
   if pgrep -f "$BIN" >/dev/null; then
      echo "PixInsight is already running. Quit it, then run this again."
      exit 2
   fi
   rm -f "$OUT/t5-helper-log.txt" "$OUT/t5-helper.sh" "$OUT/t5-script.txt" "$ERR"
   echo "$1" > "$OUT/t5-mode.txt"
   if [ "$1" = "unsaved" ]; then
      echo "PixInsight will ask whether to exit although an image is unsaved."
      echo "Click No the first time. When it asks again, click Yes."
   fi
   open -n -a "$APP" --args -n --no-startup-check-updates -r="$HERE/t5-quit-with-prompts.js"
   LIMIT=90; [ "$1" = "unsaved" ] && LIMIT=600
   i=0
   while [ $i -lt $LIMIT ]; do
      grep -q 'helper finished' "$OUT/t5-helper-log.txt" 2>/dev/null && break
      [ -f "$ERR" ] && break
      sleep 1; i=$((i+1))
   done
   echo "waited ${i} s"
   cat "$OUT/t5-script.txt" 2>/dev/null || echo "(the script inside PixInsight wrote nothing)"
   [ -f "$ERR" ] && { echo "script error:"; cat "$ERR"; }
   show
   ;;
log)
   show
   ;;
*)
   echo "usage: sh tests/run-t5.sh clean | unsaved | log"
   exit 1
   ;;
esac
