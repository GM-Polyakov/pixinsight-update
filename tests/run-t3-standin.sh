#!/bin/sh
# Runs the sign-in probe against the stand-in download service on this
# computer, with the stand-in's made-up account. Nothing goes to pixinsight.com.
#
# For each variant of the stand-in, it runs the probe once to list the
# installers and find a route that reaches one, then once more to download the
# stand-in "installer" by that route, and checks the result.
#
# Usage:  sh tests/run-t3-standin.sh                              every variant
#         sh tests/run-t3-standin.sh --cdn other --strict-agent     one variant
#         VERBOSE=1 sh tests/run-t3-standin.sh ...                  whole reports

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
BIN="/Applications/PixInsight/PixInsight.app/Contents/MacOS/PixInsight"
PROBE="$HERE/t3-signin-probe.js"
PORT=8719
SIZE_MB=8
LOG="$OUT/standin-server.log"

mkdir -p "$OUT"
if pgrep -f "$BIN" >/dev/null; then
   echo "PixInsight is already running. Quit it, then run this again."
   exit 2
fi

run_pi() { # $1 = mode, $2 = file, $3 = how, $4 = size
   PI_USER="standin-user" PI_PASS='standin-pass!1' PI_T3_BASE="http://127.0.0.1:$PORT/dist/" \
   PI_T3_MODE="$1" PI_T3_FILE="$2" PI_T3_HOW="$3" PI_T3_SIZE="$4" \
      perl -e 'alarm 180; exec @ARGV' "$BIN" -n --automation-mode -r="$PROBE" --force-exit >/dev/null 2>&1
}

one() { # $1 = the route expected to work, the rest = options for the stand-in
   EXPECT="$1"; shift
   echo
   echo "################ stand-in options: $* ################"
   rm -f "$OUT/t3-report.txt" "$OUT/t3-choice.txt" "$OUT/t3-download.txt" "$OUT/t3-progress.txt" "$OUT/t3-anonymous-only" "$LOG"
   rm -rf "$OUT/download"
   /usr/bin/python3 "$HERE/standin/dist-server.py" --port "$PORT" --layout real --refuse-curl --size-mb "$SIZE_MB" --log "$LOG" "$@" >/dev/null 2>&1 &
   SERVER=$!
   sleep 1

   run_pi probe "" "" ""
   if [ "${VERBOSE:-0}" = "1" ]; then
      cat "$OUT/t3-report.txt" 2>/dev/null
   else
      grep -E '^(RESULT|STOPPED|The )|route [0-9]|SHA-1|withheld|stopped on an error' "$OUT/t3-report.txt" 2>/dev/null | cut -c1-330
   fi

   if [ -f "$OUT/t3-choice.txt" ]; then
      NAME="$(sed -n 's/^name=//p' "$OUT/t3-choice.txt")"
      HOW="$(sed -n 's/^how=//p' "$OUT/t3-choice.txt")"
      SIZE="$(sed -n 's/^size=//p' "$OUT/t3-choice.txt")"
      SHA1="$(sed -n 's/^sha1=//p' "$OUT/t3-choice.txt")"
      if [ "$HOW" = "$EXPECT" ]; then echo "CHECK route: pass ($HOW)"; else echo "CHECK route: FAIL - expected $EXPECT, got $HOW"; fi
      run_pi download "$NAME" "$HOW" "$SIZE"
      grep -E '^(fetched|bytes written|result)' "$OUT/t3-download.txt" 2>/dev/null | cut -c1-260
      FILE="$OUT/download/$NAME"
      if [ -f "$FILE" ] && [ "$(stat -f %z "$FILE")" = "$((SIZE_MB * 1048576))" ] && [ "$(shasum -a 1 "$FILE" | cut -d' ' -f1)" = "$SHA1" ]; then
         echo "CHECK download: pass (the size is right and the checksum matches the one on the page)"
      else
         echo "CHECK download: FAIL"
      fi
   else
      echo "CHECK: FAIL - the probe found no route to an installer"
   fi

   if grep -q 'LOGOUT LINK FOLLOWED' "$LOG" 2>/dev/null; then echo "CHECK sign-out link: FAIL - the probe followed it"; else echo "CHECK sign-out link: pass (not followed)"; fi
   if grep -R -q -e 'standin-user' -e 'standin-pass' "$OUT/t3-report.txt" "$OUT/t3-download.txt" "$OUT/t3-choice.txt" 2>/dev/null; then
      echo "CHECK secrets in the reports: FAIL - the made-up user name or password appears"
   else
      echo "CHECK secrets in the reports: pass (neither appears)"
   fi
   if grep -q -e 'Standin' -e 'example.org' -e '12345678' -e '203.0.113' -e 'session_id=' -e 'PHPSESSID=' "$OUT/t3-report.txt" "$OUT/t3-download.txt" 2>/dev/null; then
      echo "CHECK account details in the reports: FAIL"
   else
      echo "CHECK account details in the reports: pass (no name, e-mail, customer number, internet address, session or cookie value)"
   fi
   if [ -n "$(find "$OUT" -newer "$LOG" -type f ! -name 't3-*' ! -name 'standin-server.log' ! -path '*/download/*' 2>/dev/null)" ]; then
      echo "CHECK files left behind: FAIL - $(find "$OUT" -newer "$LOG" -type f ! -name 't3-*' ! -name 'standin-server.log' ! -path '*/download/*' | tr '\n' ' ')"
   else
      echo "CHECK files left behind: pass (only the reports and the download)"
   fi
   echo "--- requests the stand-in saw, by client name: $(sed -n 's/.*agent=\([^ ]*\).*/\1/p' "$LOG" | sort | uniq -c | tr '\n' ' ')"
   kill "$SERVER" 2>/dev/null
   wait "$SERVER" 2>/dev/null
   rm -rf "$OUT/download"
}

if [ $# -ge 1 ]; then
   EXPECTED="${EXPECT:-?}"
   one "$EXPECTED" "$@"
else
   one pixinsight-cookie --cdn none
   one curl-cookie --cdn same
   one curl-cookie --cdn other
   one curl-all --cdn other --strict-agent
fi
