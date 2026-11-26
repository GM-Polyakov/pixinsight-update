#!/bin/sh
# Runs test 1 (what PixInsight reports about itself) and test 2 (a helper that
# outlives PixInsight), then prints the results.
#
# It starts PixInsight in automation mode, where PixInsight saves no settings,
# runs tests/t2-detached-helper.js, and lets PixInsight exit by itself.
# Nothing is installed and nothing in the PixInsight folder is changed.
#
# Usage:  sh tests/run-t2.sh

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
APP="/Applications/PixInsight/PixInsight.app"
BIN="$APP/Contents/MacOS/PixInsight"
ERR="${TMPDIR:-/tmp}/pi-update-assistant-t2-error.txt"

mkdir -p "$OUT"
rm -f "$OUT"/t1-runtime.txt "$OUT"/t2-helper*.sh "$OUT"/t2-log-*.txt "$OUT"/t2-helper-log.txt "$ERR"

if pgrep -f "$BIN" >/dev/null; then
   echo "PixInsight is already running. Quit it, then run this again."
   exit 2
fi

echo "PixInsight started at $(date '+%H:%M:%S')"
open -n -a "$APP" --args -n --automation-mode -r="$HERE/t2-detached-helper.js" --force-exit

# 1. Wait until the script inside PixInsight has written its report.
i=0
while [ $i -lt 240 ] && [ ! -f "$OUT/t1-runtime.txt" ] && [ ! -f "$ERR" ]; do sleep 1; i=$((i+1)); done
echo "script finished after ${i} s"

# 2. Wait until PixInsight has exited.
j=0
while [ $j -lt 120 ] && pgrep -f "$BIN" >/dev/null; do sleep 1; j=$((j+1)); done
echo "PixInsight exited at $(date '+%H:%M:%S')"

# 3. Give the helpers their ten seconds, plus a margin.
sleep 14

echo
echo "=== Test 1: what PixInsight reports ==="
grep -v '^way ' "$OUT/t1-runtime.txt" 2>/dev/null || echo "(no report was written)"
[ -f "$ERR" ] && { echo "script error:"; cat "$ERR"; }

echo
echo "=== Test 2: what each start call returned ==="
grep '^way ' "$OUT/t1-runtime.txt" 2>/dev/null

echo
echo "=== Test 2: what each helper logged ==="
pass=""
for way in A B C D E F; do
   echo "--- way $way ---"
   cat "$OUT/t2-log-$way.txt" 2>/dev/null || echo "(this helper wrote nothing)"
   grep -q '^3 ' "$OUT/t2-log-$way.txt" 2>/dev/null && pass="$pass $way"
done

echo
if pgrep -f "$BIN" >/dev/null; then echo "PixInsight is still running."; else echo "PixInsight is not running."; fi
if [ -n "$pass" ]; then
   echo "RESULT: pass - helpers started by way(s)$pass kept running after PixInsight exited."
else
   echo "RESULT: fail - no helper logged anything after PixInsight exited."
fi
