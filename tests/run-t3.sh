#!/bin/sh
# Test 3: can a script inside PixInsight sign in to PixInsight's download
# service, find the newest installer and fetch it?
#
# Run this yourself in a terminal:   sh tests/run-t3.sh
#
# What it does:
#   1. Asks for your PixInsight user name and password. Typing is hidden.
#      If PI_USER and PI_PASS are already set, it uses those and does not ask.
#   2. Starts PixInsight in automation mode, where PixInsight saves no
#      settings, and runs tests/t3-signin-probe.js. That script sends your
#      details only to https://pixinsight.com/dist/ and reads the list of
#      installers. To learn the size of the newest macOS installer it starts
#      that download and stops it at once; nothing is kept.
#   3. Prints the report, tests/out/t3-report.txt. The report holds response
#      codes, sizes, installer file names and host names. It holds no user
#      name, password, session value or text from your account page.
#   4. Names the installer and its size, and asks whether to download it into
#      tests/out/download/. The file is only unpacked and read later. It is
#      never run by these tests.
#
# Your details are passed to PixInsight as environment variables of that one
# process. They are not written to any file.
#
#   sh tests/run-t3.sh --anonymous    runs only the steps that need no sign-in.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
APP="/Applications/PixInsight/PixInsight.app"
BIN="$APP/Contents/MacOS/PixInsight"
PROBE="$HERE/t3-signin-probe.js"

mkdir -p "$OUT"

if pgrep -f "$BIN" >/dev/null; then
   echo "PixInsight is already running. Quit it, then run this again."
   exit 2
fi

# ---------------------------------------------------------------------------
if [ "${1:-}" = "--anonymous" ]; then
   rm -f "$OUT/t3-report.txt" "$OUT/t3-choice.txt"
   : > "$OUT/t3-anonymous-only"
   env -u PI_USER -u PI_PASS -u PI_T3_BASE -u PI_T3_MODE "$BIN" -n --automation-mode -r="$PROBE" --force-exit >/dev/null 2>&1
   rm -f "$OUT/t3-anonymous-only"
   cat "$OUT/t3-report.txt" 2>/dev/null || echo "(no report was written)"
   exit 0
fi

# ---------------------------------------------------------------------------
trap 'stty echo 2>/dev/null' EXIT INT TERM
rm -f "$OUT/t3-anonymous-only"
# Make sure this run talks to pixinsight.com and nothing else.
unset PI_T3_BASE PI_T3_FILE PI_T3_HOW PI_T3_SIZE

if [ -z "${PI_USER:-}" ]; then
   printf 'PixInsight user name (typing is hidden): '
   stty -echo; IFS= read -r PI_USER; stty echo; printf '\n'
fi
if [ -z "${PI_PASS:-}" ]; then
   printf 'PixInsight password (typing is hidden): '
   stty -echo; IFS= read -r PI_PASS; stty echo; printf '\n'
fi
if [ -z "$PI_USER" ] || [ -z "$PI_PASS" ]; then
   echo "No user name or no password was given. Nothing was sent."
   exit 1
fi
export PI_USER PI_PASS

rm -f "$OUT/t3-report.txt" "$OUT/t3-choice.txt" "$OUT/t3-download.txt" "$OUT/t3-progress.txt"
rm -rf "$OUT/private"
echo "Signing in and reading the list of installers. PixInsight opens and closes by itself."
PI_T3_MODE=probe "$BIN" -n --automation-mode -r="$PROBE" --force-exit >/dev/null 2>&1
echo
echo "================ report (tests/out/t3-report.txt) ================"
cat "$OUT/t3-report.txt" 2>/dev/null || echo "(no report was written)"
echo "=================================================================="

if [ ! -f "$OUT/t3-choice.txt" ]; then
   echo
   echo "No installer could be fetched, so nothing is offered for download."
   unset PI_USER PI_PASS
   exit 0
fi

NAME="$(sed -n 's/^name=//p' "$OUT/t3-choice.txt")"
SIZE="$(sed -n 's/^size=//p' "$OUT/t3-choice.txt")"
HOW="$(sed -n 's/^how=//p' "$OUT/t3-choice.txt")"
SHA1="$(sed -n 's/^sha1=//p' "$OUT/t3-choice.txt")"
MB=$(( SIZE / 1048576 ))
echo
printf 'Download %s (%s MB) from the PixInsight download service into tests/out/download/?\nIt will be unpacked and read. It will not be run. [y/N] ' "$NAME" "$MB"
IFS= read -r ANSWER
case "$ANSWER" in
   y|Y|yes|Yes|YES) ;;
   *) echo "Not downloaded."; unset PI_USER PI_PASS; exit 0 ;;
esac

rm -rf "$OUT/download"
mkdir -p "$OUT/download"
PI_T3_MODE=download PI_T3_FILE="$NAME" PI_T3_HOW="$HOW" PI_T3_SIZE="$SIZE" "$BIN" -n --automation-mode -r="$PROBE" --force-exit >/dev/null 2>&1 &
PIPID=$!
while kill -0 "$PIPID" 2>/dev/null; do
   if [ -f "$OUT/t3-progress.txt" ]; then
      GOT=0; TOTAL=0
      read -r GOT TOTAL < "$OUT/t3-progress.txt" 2>/dev/null || true
      if [ "${TOTAL:-0}" -gt 0 ] 2>/dev/null; then
         printf '\r   %s of %s MB (%s%%)   ' $(( GOT / 1048576 )) $(( TOTAL / 1048576 )) $(( GOT * 100 / TOTAL ))
      fi
   fi
   sleep 2
done
wait "$PIPID" 2>/dev/null
unset PI_USER PI_PASS
printf '\n\n'
echo "================ download (tests/out/t3-download.txt) ================"
cat "$OUT/t3-download.txt" 2>/dev/null || echo "(no result was written)"
if [ -f "$OUT/download/$NAME" ]; then
   echo "Computing the file's SHA-1 checksum..."
   GOT_SHA1="$(shasum -a 1 "$OUT/download/$NAME" | cut -d' ' -f1)"
   echo "checksum of the downloaded file = $GOT_SHA1"
   echo "checksum shown on the page      = ${SHA1:-none found}"
   if [ -n "$SHA1" ] && [ "$GOT_SHA1" = "$SHA1" ]; then
      echo "checksum = match"
   else
      echo "checksum = NO MATCH"
   fi
   echo "checksum = $GOT_SHA1" >> "$OUT/t3-download.txt"
   echo "checksum matches the page = $([ -n "$SHA1" ] && [ "$GOT_SHA1" = "$SHA1" ] && echo yes || echo no)" >> "$OUT/t3-download.txt"
fi
echo "======================================================================"
ls -l "$OUT/download" 2>/dev/null
