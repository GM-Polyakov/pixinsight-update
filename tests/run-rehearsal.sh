#!/bin/sh
# Rehearses the whole update without touching the real PixInsight folder and
# without contacting pixinsight.com.
#
# What is real:      PixInsight itself, the add-on as built in dist/stage/,
#                    the helper, curl, the quit request, the reopening.
# What is stand-in:  the download service (tests/standin/dist-server.py, with a
#                    made-up account), the installer (tests/standin/fake-installer*.sh),
#                    the PixInsight folder and the Trash (all under tests/out/rehearsal/).
#                    No administrator password is asked for.
# No windows are shown, except the progress window in the case "window": the
# add-on and the helper take their answers from the rehearsal's settings, and
# write down what they would have shown.
#
# PixInsight opens and closes once or twice in most cases, about twenty times
# in all. It is opened in the background, so it should not take the keyboard.
# Do not run this while you are using PixInsight: the runner refuses to start
# then, because its tidying-up closes PixInsight.
#
# Usage:  sh tests/run-rehearsal.sh            every case
#         sh tests/run-rehearsal.sh now later  only these cases
#
# Cases: now, later, window, cancel, interrupted, broken, installfail, nostart,
#        carryfail, refused, uptodate, offline, windows,
#        and five that run the helper alone, without PixInsight:
#        noreopen, notrash, lost, unsigned, genuine
#
# The stand-in download page offers a made-up version, 9.9.9, so that there is
# something to update to whatever PixInsight this computer has.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="$HERE/out/rehearsal"
CONTROL="$OUT/control"
FOLDER="$OUT/Applications/PixInsight"
BEFORE="$OUT/Applications/PixInsight (before update)"
TRASH="$OUT/home/.Trash"
TRASHED="$TRASH/PixInsight (before update)"
APP="/Applications/PixInsight/PixInsight.app"
BIN="$APP/Contents/MacOS/PixInsight"
SCRIPT="$ROOT/dist/stage/src/scripts/UpdateAssistant/UpdateAssistant.js"
WORK="${TMPDIR%/}/PixInsightUpdateAssistant"
PORT=8719
LOG="$OUT/standin-server.log"
SIZE_MB=8
PASSED=0
FAILED=0
SERVER=""

# The installer that must be chosen is the one for this Mac's chip.
if [ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then CHIP=arm64; else CHIP=x64; fi
# The PixInsight on this computer, and the made-up newer version that the
# stand-in download page offers.
HAVE="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null)"
NEW="9.9.9"
PKGNAME="PI-macosx-$CHIP-$NEW-20991231-c.pkg"

# One sentence from the add-on's table of wording, as the user would read it.
wording() { sed -n "s/^ *$1: *\"\(.*\)\",\{0,1\}\$/\1/p" "$ROOT/src/UpdateAssistant-wording.jsh" | head -1; }

check() { # $1 = what is checked, $2... = a command that must succeed
   WHAT="$1"; shift
   if "$@" >/dev/null 2>&1; then
      echo "   pass  $WHAT"; PASSED=$((PASSED+1))
   else
      echo "   FAIL  $WHAT"; FAILED=$((FAILED+1))
   fi
}
has() { grep -q -F -- "$2" "$1"; }                 # file contains text
hasnot() { ! grep -q -F -- "$2" "$1" 2>/dev/null; }
absent() { [ ! -e "$1" ]; }
running() { pgrep -f "$BIN" >/dev/null; }
not_running() { ! running; }

wait_for() { # $1 = seconds, $2... = a command that must come true
   LIMIT="$1"; shift
   I=0
   while [ $I -lt "$LIMIT" ]; do
      "$@" >/dev/null 2>&1 && return 0
      sleep 1; I=$((I+1))
   done
   return 1
}

# Set for the cases that run the helper alone. They never open PixInsight, so
# they may run while it is open, and they must never close it.
ALONE_CASE=""

# Wait until the reopened PixInsight has shown its closing message, and then
# until the helper has written its last line. PixInsight 1.9.6 starts and
# leaves faster than the helper takes to see that it has stayed up.
wait_for_end() {
   wait_for 150 test -f "$WORK/message-shown.txt"
   wait_for 30 has "$WORK/log.txt" "helper finished"
}

prepare() { # the rest = options for the stand-in service; "none" starts no service
   if [ -z "$ALONE_CASE" ] && running; then echo "PixInsight is running. Quit it, then run the rehearsal again."; exit 2; fi
   chmod -R u+w "$OUT" 2>/dev/null
   rm -rf "$OUT" "$WORK"
   mkdir -p "$CONTROL" "$FOLDER/PixInsight.app/Contents" "$FOLDER/bin" "$FOLDER/gaia" "$TRASH"
   echo "old version (stand-in)" > "$FOLDER/PixInsight.app/Contents/version.txt"
   echo "a module of an add-on, built for the old version" > "$FOLDER/bin/OldAddon-pxm.dylib"
   echo "the user's star catalogue" > "$FOLDER/gaia/catalogue.xpsd"
   SERVER=""
   if [ "${1:-}" != "none" ]; then
      /usr/bin/python3 "$HERE/standin/dist-server.py" --port "$PORT" --layout real --cdn other --refuse-curl --newest "$NEW" --size-mb "$SIZE_MB" --log "$LOG" "$@" >/dev/null 2>&1 &
      SERVER=$!
      sleep 1
   fi
}

start_update() { # $1 = password, $2 = answer to "restart now or later", $3 = installer, the rest = more settings
   PASS="$1"; ANSWER="$2"; INSTALLER="$3"; shift 3
   set -- --env "PI_UA_TEST_DIR=$CONTROL" --env "PI_UA_BASE=http://127.0.0.1:$PORT/dist/" \
          --env "PI_USER=standin-user" --env "PI_PASS=$PASS" \
          --env "PI_UA_TEST_INSTALL_DIR=$FOLDER" --env "PI_UA_TEST_INSTALLER=$HERE/standin/$INSTALLER" \
          --env "PI_UA_TEST_HOME=$OUT/home" --env "PI_UA_TEST_PKGUTIL=$HERE/standin/fake-pkgutil.sh" \
          --env "PI_UA_TEST_QUIET=1" --env "PI_UA_TEST_ANSWER=$ANSWER" "$@"
   # -g: in the background, so that PixInsight does not take the keyboard from
   # whoever is using the Mac while the rehearsal runs.
   open -n -g -a "$APP" "$@" --args -n --automation-mode -r="$SCRIPT"
   wait_for 90 test -f "$CONTROL/script-result.txt"
}

again() { # $1 = status | cancel: pick the menu item again in the PixInsight that is running
   echo "$1" > "$CONTROL/action.txt"
   "$BIN" -x="$SCRIPT" >/dev/null 2>&1
   wait_for 30 test -f "$CONTROL/script-result-$1.txt"
}

finish() {
   if [ -z "$ALONE_CASE" ] && running; then "$BIN" --terminate=1 >/dev/null 2>&1; wait_for 20 not_running || pkill -f "$BIN"; fi
   [ -n "$SERVER" ] && { kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null; }
   pkill -f "$WORK/helper.sh" 2>/dev/null
   # Keep what the helper wrote, so that a failed case can be understood later.
   KEEP="$HERE/out/rehearsal-logs/${CASE:-case}"
   rm -rf "$KEEP"; mkdir -p "$KEEP"
   cp "$WORK"/*.txt "$WORK"/status "$CONTROL"/*.txt "$LOG" "$KEEP"/ 2>/dev/null
   rm -rf "$WORK"
}

show() { [ "${VERBOSE:-0}" = "1" ] && { echo "   --- $1"; sed 's/^/   | /' "$1" 2>/dev/null | cut -c1-200; }; return 0; }

common_checks() {
   check "the helper deleted the file with the installer's address and cookie" absent "$WORK/job.conf"
   check "the downloaded installer was removed afterwards" absent "$WORK/$PKGNAME"
   check "neither the made-up user name nor the password is in any file the add-on left" sh -c "! grep -R -q -e standin-user -e standin-pass '$WORK' '$CONTROL' 2>/dev/null"
   check "no session value or cookie is in any file the add-on left" sh -c "! grep -R -q -e session_id= -e PHPSESSID '$WORK' '$CONTROL' 2>/dev/null"
   check "the sign-out link was not followed" hasnot "$LOG" "LOGOUT LINK FOLLOWED"
}

# -----------------------------------------------------------------------------

case_now() {
   echo; echo "== now: sign in, download, restart now, install, reopen =="
   prepare
   start_update 'standin-pass!1' now fake-installer.sh --env "PI_UA_TEST_OLD=1.9.2"
   show "$CONTROL/script-result.txt"
   check "sign-in accepted" has "$CONTROL/script-result.txt" "signin=ok"
   check "newest version read from the page: $NEW" has "$CONTROL/script-result.txt" "newest=$NEW"
   check "the Mac's chip was recognised from inside PixInsight ($CHIP)" has "$CONTROL/script-result.txt" "chip=$CHIP"
   check "the installer for this Mac's chip was chosen" has "$CONTROL/script-result.txt" "file=$PKGNAME"
   check "the user is told that the download runs in the background, and nothing more" has "$CONTROL/script-result.txt" "shown=PixInsight $NEW is downloading in the background (8 MB). You'll be asked when it's ready to install. To see progress or to cancel, pick Update PixInsight again."
   check "that sentence is the last thing shown" sh -c "[ \"\$(tail -1 '$CONTROL/script-result.txt' | cut -c1-6)\" = 'shown=' ]"
   wait_for_end
   show "$WORK/log.txt"; show "$WORK/install-log.txt"; show "$WORK/message-shown.txt"
   check "PixInsight was reopened and said which version is running" has "$WORK/message-shown.txt" "You're now on PixInsight $HAVE."
   check "it also said where the previous PixInsight is" has "$WORK/message-shown.txt" "Your previous PixInsight is in the Trash, as PixInsight (before update). It is safe to delete once the new version works for you."
   check "the helper noticed that PixInsight had closed" has "$WORK/log.txt" "PixInsight has closed"
   check "the new PixInsight was asked whether it starts" has "$WORK/install-log.txt" "the new PixInsight starts"
   check "the old folder went to the Trash only after that, and after the catalogue was across" sh -c "awk '/the new PixInsight starts/{a=NR} /carried over: gaia/{b=NR} /old folder moved to the Trash/{c=NR} END{exit !(a>0 && b>a && c>b)}' '$WORK/install-log.txt'"
   check "the helper made sure that PixInsight had reopened" has "$WORK/log.txt" "PixInsight has reopened"
   check "the new version is in place" has "$FOLDER/PixInsight.app/Contents/version.txt" "new version"
   check "the user's star catalogue was carried over" test -f "$FOLDER/gaia/catalogue.xpsd"
   check "the old add-on module was not carried over" absent "$FOLDER/bin/OldAddon-pxm.dylib"
   check "the previous PixInsight is in the Trash, complete" test -f "$TRASHED/bin/OldAddon-pxm.dylib"
   check "nothing was deleted: the folder in the Trash holds everything but the catalogue" sh -c "[ -f '$TRASHED/PixInsight.app/Contents/version.txt' ] && [ ! -e '$TRASHED/gaia' ]"
   check "no folder of the old version is left in Applications" absent "$BEFORE"
   check "the download was fetched by the helper under the add-on's own name" has "$LOG" "agent=PixInsightUpdateAssistant/"
   check "the download went through the file host" has "$LOG" "download redirected"
   common_checks
   wait_for 40 not_running
   check "the reopened PixInsight is the only thing left to close (it closed itself in the rehearsal)" not_running
   finish
}

case_later() {
   echo; echo "== later: install only when the user quits PixInsight =="
   prepare
   start_update 'standin-pass!1' later fake-installer.sh
   wait_for 60 has "$WORK/status" "phase=waiting"
   check "after the download the helper waits" has "$WORK/status" "phase=waiting"
   check "nothing is installed while PixInsight is open" has "$FOLDER/PixInsight.app/Contents/version.txt" "old version"
   again status
   show "$CONTROL/script-result-status.txt"
   check "picking the menu item again shows that the update is waiting" has "$CONTROL/script-result-status.txt" "status_text=PixInsight $NEW is ready. It will be installed when you quit PixInsight."
   check "PixInsight is still open" running
   "$BIN" --terminate=1 >/dev/null 2>&1
   wait_for_end
   show "$WORK/message-shown.txt"
   check "once PixInsight was closed, the new version was installed" has "$FOLDER/PixInsight.app/Contents/version.txt" "new version"
   check "the reopened PixInsight said truthfully that it is still the old one" has "$WORK/message-shown.txt" "PixInsight was not updated. You're still on PixInsight $HAVE."
   common_checks
   wait_for 40 not_running
   finish
}

case_cancel() {
   echo; echo "== cancel: stop the update during the download =="
   prepare --slow-ms 200
   start_update 'standin-pass!1' now fake-installer.sh
   wait_for 20 has "$WORK/status" "phase=downloading"
   sleep 3
   again cancel
   show "$CONTROL/script-result-cancel.txt"
   check "picking the menu item again shows the progress of the download" has "$CONTROL/script-result-cancel.txt" "status_text=Downloading PixInsight $NEW:"
   check "after cancelling the user is told that nothing was changed" has "$CONTROL/script-result-cancel.txt" "shown=The update was stopped. Nothing was changed."
   wait_for 20 absent "$WORK/status"
   check "the helper stopped" sh -c "! pgrep -f '$WORK/helper.sh'"
   check "the partial download was removed" absent "$WORK/$PKGNAME"
   check "the PixInsight folder is untouched" test -f "$FOLDER/bin/OldAddon-pxm.dylib"
   check "PixInsight is still open" running
   common_checks
   finish
}

case_interrupted() {
   echo; echo "== interrupted: the download breaks off once, and Try Again resumes it =="
   prepare --drop-first-mb 3
   start_update 'standin-pass!1' now fake-installer.sh --env "PI_UA_TEST_RETRY=again"
   wait_for_end
   show "$WORK/log.txt"
   check "the stand-in broke the first download off" has "$LOG" "broken off on purpose"
   check "the helper noticed" has "$WORK/log.txt" "curl ended with code"
   check "the second attempt asked only for the missing part" has "$LOG" "(bytes "
   check "the update then went through" has "$FOLDER/PixInsight.app/Contents/version.txt" "new version"
   common_checks
   wait_for 40 not_running
   finish
}

case_broken() {
   echo; echo "== broken: the download does not match the checksum on the page =="
   prepare --bad-sha1
   start_update 'standin-pass!1' now fake-installer.sh
   wait_for 60 has "$WORK/log.txt" "would show:"
   show "$WORK/log.txt"
   check "the helper refused the download" has "$WORK/log.txt" "not the installer that the page listed"
   check "the user is told to start again" has "$WORK/log.txt" "would show: The download stopped. To start again, pick Update PixInsight in PixInsight."
   check "nothing was installed" has "$FOLDER/PixInsight.app/Contents/version.txt" "old version"
   check "PixInsight was not asked to close" running
   common_checks
   finish
}

case_installfail() {
   echo; echo "== installfail: the installer fails, and the old folder is put back =="
   prepare
   start_update 'standin-pass!1' now fake-installer-fails.sh
   wait_for_end
   show "$WORK/install-log.txt"; show "$WORK/message-shown.txt"
   check "the old version is back in place" has "$FOLDER/PixInsight.app/Contents/version.txt" "old version"
   check "with the add-on module" test -f "$FOLDER/bin/OldAddon-pxm.dylib"
   check "and with the user's star catalogue" test -f "$FOLDER/gaia/catalogue.xpsd"
   check "what the failed installer left was set aside, not deleted" test -d "$OUT/Applications/PixInsight (failed update)"
   check "no folder of the old version is left over under another name" absent "$BEFORE"
   check "nothing went to the Trash" sh -c "[ -z \"\$(ls -A '$TRASH')\" ]"
   check "the reopened PixInsight said that it was not updated" has "$WORK/message-shown.txt" "PixInsight was not updated. You're still on PixInsight $HAVE."
   check "and where to find what the installer left" has "$WORK/message-shown.txt" "What the installer left is in Applications as PixInsight (failed update). You can delete that folder."
   common_checks
   wait_for 40 not_running
   finish
}

case_carryfail() {
   echo; echo "== carryfail: the user's own folder cannot be moved into the new folder =="
   prepare
   start_update 'standin-pass!1' now fake-installer-readonly.sh
   wait_for_end
   show "$WORK/install-log.txt"; show "$WORK/message-shown.txt"
   check "the new version is in place" has "$FOLDER/PixInsight.app/Contents/version.txt" "new version"
   check "the star catalogue is still in the old folder, which stayed in Applications" test -f "$BEFORE/gaia/catalogue.xpsd"
   check "the old folder did not go to the Trash" sh -c "[ -z \"\$(ls -A '$TRASH')\" ]"
   check "the user is told where the folders are and not to delete them" has "$WORK/message-shown.txt" "They are still in PixInsight (before update), in Applications. Do not delete that folder."
   common_checks
   wait_for 40 not_running
   finish
}

case_window() {
   echo; echo "== window: Restart Now is chosen while the progress window is open in PixInsight =="
   prepare --slow-ms 150
   start_update 'standin-pass!1' now fake-installer.sh
   wait_for 20 has "$WORK/status" "phase=downloading"
   # Pick the menu item again. The progress window opens, and nobody closes it.
   echo progress > "$CONTROL/action.txt"
   "$BIN" -x="$SCRIPT" >/dev/null 2>&1 &
   wait_for 20 test -f "$WORK/window-open"
   check "the progress window is open in PixInsight while the download runs" test -f "$WORK/window-open"
   wait_for 90 has "$WORK/log.txt" "answer: now"
   sleep 2
   check "Restart Now was chosen while the window was open" has "$WORK/log.txt" "a window of the add-on is open in PixInsight"
   if wait_for 40 has "$WORK/log.txt" "PixInsight has closed"; then
      check "PixInsight closed at the helper's request" has "$WORK/log.txt" "PixInsight has closed"
   else
      check "PixInsight closed at the helper's request" false
      show "$WORK/log.txt"; show "$WORK/status"
      echo "   (PixInsight stayed open with the window. Leaving the case here.)"
      finish
      return
   fi
   show "$CONTROL/script-result-progress.txt"; show "$WORK/log.txt"
   check "the window had closed by itself, because PixInsight was about to be asked to quit" has "$CONTROL/script-result-progress.txt" "closed_by=restart"
   wait_for_end
   check "the update then went through" has "$FOLDER/PixInsight.app/Contents/version.txt" "new version"
   check "PixInsight was reopened and said which version is running" has "$WORK/message-shown.txt" "PixInsight $HAVE."
   common_checks
   wait_for 40 not_running
   finish
}

case_nostart() {
   echo; echo "== nostart: the installer succeeds, but the new PixInsight does not start on this Mac =="
   prepare
   start_update 'standin-pass!1' now fake-installer-nostart.sh
   wait_for_end
   show "$WORK/install-log.txt"; show "$WORK/message-shown.txt"
   check "the installer reported success" has "$WORK/install-log.txt" "installer ended with code 0"
   check "the new PixInsight was asked whether it starts, and it does not" has "$WORK/install-log.txt" "the new PixInsight does not start"
   check "the reason it gave is in the log" has "$WORK/install-log.txt" "AVX2"
   check "the old version is back in place" has "$FOLDER/PixInsight.app/Contents/version.txt" "old version"
   check "with the add-on module" test -f "$FOLDER/bin/OldAddon-pxm.dylib"
   check "and with the user's star catalogue, which never left it" test -f "$FOLDER/gaia/catalogue.xpsd"
   check "the PixInsight that does not start was set aside, not deleted" has "$OUT/Applications/PixInsight (failed update)/PixInsight.app/Contents/version.txt" "new version"
   check "no folder of the old version is left over under another name" absent "$BEFORE"
   check "nothing went to the Trash" sh -c "[ -z \"\$(ls -A '$TRASH')\" ]"
   check "the reopened PixInsight said that it was not updated" has "$WORK/message-shown.txt" "PixInsight was not updated. You're still on PixInsight $HAVE."
   check "and why" has "$WORK/message-shown.txt" "The new version does not start on this Mac, so your previous PixInsight was put back."
   check "and where to find what the installer left" has "$WORK/message-shown.txt" "What the installer left is in Applications as PixInsight (failed update). You can delete that folder."
   common_checks
   wait_for 40 not_running
   finish
}

# The five cases below run the helper alone. PixInsight is not opened: what
# the helper is told to reopen is a stand-in that cannot be opened, or is missing.
# Two settings change what it is given:
#   ALONE_PKG=<file>     the package to "download", in place of a stand-in file
#   ALONE_PKGUTIL=real   macOS's own signature tool, in place of the stand-in
ALONE_PKG=""
ALONE_PKGUTIL=""
start_helper_alone() { # $1 = stand-in installer, $2 = the application the helper is to reopen, $3 = the stand-in home folder
   mkdir -p "$WORK"; chmod 700 "$WORK"
   cp "$ROOT/helper/macos/helper.sh" "$ROOT/helper/macos/install.sh" "$ROOT/helper/macos/message.js" "$WORK/"
   chmod 700 "$WORK/helper.sh" "$WORK/install.sh"
   for KEY in product ok cancel downloadStopped tryAgain startAgain notGenuine ready restartNow later installing hide adminPrompt \
              done notUpdated oldFolderTrash oldFolderLeft oldFolderCheck wontStart failedFolder notReopened folderLost; do
      printf '%s' "$(wording "$KEY")" > "$WORK/text-$KEY"
   done
   PACKAGE="$ALONE_PKG"
   ALONE_NAME="$PKGNAME"
   if [ -z "$PACKAGE" ]; then
      PACKAGE="$OUT/standin.pkg"
      { printf 'xar!'; head -c 200000 /dev/urandom; } > "$PACKAGE"
   else
      ALONE_NAME="$(basename "$PACKAGE")"
   fi
   {
      echo "url=file://$PACKAGE"
      echo "cookie=none=none"
      echo "client=rehearsal"
      echo "file=$ALONE_NAME"
      echo "sha1=$(/usr/bin/shasum -a 1 "$PACKAGE" | cut -d' ' -f1)"
      echo "size=$(stat -f %z "$PACKAGE")"
      echo "new=$NEW"
      echo "old=$HAVE"
      echo "pid=$$"
      echo "install_dir=$FOLDER"
      echo "app=$2"
      echo "test_answer=now"
      echo "test_installer=$HERE/standin/$1"
      echo "test_home=${3:-$OUT/home}"
      [ "$ALONE_PKGUTIL" = real ] || echo "test_pkgutil=$HERE/standin/fake-pkgutil.sh"
      echo "test_quiet=1"
   } > "$WORK/job.conf"
   "$WORK/helper.sh" >/dev/null 2>&1 &
}

case_noreopen() {
   echo; echo "== noreopen: the update is installed, but PixInsight cannot be reopened (helper alone) =="
   prepare none
   mkdir -p "$OUT/Unopenable/PixInsight.app"
   start_helper_alone fake-installer.sh "$OUT/Unopenable/PixInsight.app"
   wait_for 150 has "$WORK/log.txt" "helper finished"
   show "$WORK/log.txt"
   check "the new version was installed" has "$FOLDER/PixInsight.app/Contents/version.txt" "new version"
   check "the old folder is in the Trash" test -f "$TRASHED/bin/OldAddon-pxm.dylib"
   check "the helper tried to reopen PixInsight three times, and looked each time" has "$WORK/log.txt" "attempt 3 to reopen PixInsight"
   check "it did not claim that PixInsight had reopened" hasnot "$WORK/log.txt" "PixInsight has reopened"
   check "the user is told to open PixInsight by hand" has "$WORK/log.txt" "would show: PixInsight could not be reopened. Open it from the Applications folder."
   check "the helper deleted the file with the installer's address and cookie" absent "$WORK/job.conf"
   finish
}

case_notrash() {
   echo; echo "== notrash: the update succeeds, but the old folder cannot be moved to the Trash (helper alone) =="
   prepare none
   mkdir -p "$OUT/Unopenable/PixInsight.app" "$OUT/home-without-trash"
   start_helper_alone fake-installer.sh "$OUT/Unopenable/PixInsight.app" "$OUT/home-without-trash"
   wait_for 150 has "$WORK/log.txt" "helper finished"
   show "$WORK/log.txt"; show "$WORK/install-log.txt"
   check "the new version was installed" has "$FOLDER/PixInsight.app/Contents/version.txt" "new version"
   check "the old folder stayed in Applications, complete" test -f "$BEFORE/bin/OldAddon-pxm.dylib"
   check "the helper knows where it is, so that the user can be told" has "$WORK/log.txt" "old folder: kept:PixInsight (before update)"
   check "nothing went to the Trash" sh -c "[ -z \"\$(ls -A '$TRASH')\" ]"
   finish
}

case_lost() {
   echo; echo "== lost: the installer fails and the old folder cannot be put back (helper alone) =="
   prepare none
   start_helper_alone fake-installer-lost.sh "$FOLDER/PixInsight.app"
   wait_for 60 has "$WORK/log.txt" "helper finished"
   show "$WORK/log.txt"; show "$WORK/install-log.txt"
   check "the old version is complete under its other name" sh -c "[ -f '$BEFORE/bin/OldAddon-pxm.dylib' ] && [ -f '$BEFORE/gaia/catalogue.xpsd' ]"
   check "the old folder was not moved into the half-made new one" absent "$FOLDER/PixInsight (before update)"
   check "the user is told where the previous PixInsight is and what to do" has "$WORK/log.txt" "would show: The update failed, and your previous PixInsight could not be put back. It is in Applications as PixInsight (before update)."
   check "the helper did not try to reopen a PixInsight that is not there" hasnot "$WORK/log.txt" "to reopen PixInsight"
   finish
}

case_unsigned() {
   echo; echo "== unsigned: the download is not signed by PixInsight's maker (helper alone, macOS's own signature tool) =="
   prepare none
   mkdir -p "$OUT/Unopenable/PixInsight.app"
   ALONE_PKGUTIL=real
   start_helper_alone fake-installer.sh "$OUT/Unopenable/PixInsight.app"
   ALONE_PKGUTIL=""
   wait_for 60 has "$WORK/log.txt" "would show:"
   sleep 1
   show "$WORK/log.txt"
   check "the checksum was right, so only the signature can have stopped it" hasnot "$WORK/log.txt" "not the installer that the page listed"
   check "the helper refused the package" has "$WORK/log.txt" "the installer is not signed by PixInsight's maker"
   check "the user is told so" has "$WORK/log.txt" "would show: The downloaded installer is not signed by PixInsight's maker, so it was not installed. Nothing was changed."
   check "nothing was installed" has "$FOLDER/PixInsight.app/Contents/version.txt" "old version"
   check "the old folder was never renamed" absent "$BEFORE"
   check "the downloaded package was removed" absent "$WORK/$PKGNAME"
   check "the helper ended there" sh -c "! pgrep -f '$WORK/helper.sh'"
   finish
}

case_genuine() {
   echo; echo "== genuine: a real PixInsight installer passes the signature check (helper alone, macOS's own signature tool) =="
   GENUINE="$(ls "$HERE"/out/download/PI-macosx-*.pkg 2>/dev/null | head -1)"
   if [ -z "$GENUINE" ]; then
      echo "   skipped: this case needs a genuine PixInsight installer package in tests/out/download/"
      return
   fi
   prepare none
   mkdir -p "$OUT/Unopenable/PixInsight.app"
   ALONE_PKGUTIL=real
   ALONE_PKG="$GENUINE"
   start_helper_alone fake-installer.sh "$OUT/Unopenable/PixInsight.app"
   ALONE_PKGUTIL=""
   ALONE_PKG=""
   wait_for 300 has "$WORK/log.txt" "helper finished"
   show "$WORK/log.txt"
   check "the package is $(basename "$GENUINE"), as downloaded from PixInsight" test -f "$GENUINE"
   check "the helper accepted it: signed by PixInsight's maker and notarised by Apple" has "$WORK/log.txt" "the installer is signed by PixInsight's maker (DVX5WE77BM) and notarised by Apple"
   check "and went on to the install step" has "$FOLDER/PixInsight.app/Contents/version.txt" "new version"
   check "its copy of the package was removed afterwards" absent "$WORK/$(basename "$GENUINE")"
   finish
}

case_refused() {
   echo; echo "== refused: a wrong password =="
   prepare
   start_update 'not-the-password' now fake-installer.sh
   show "$CONTROL/script-result.txt"
   check "the user is told that the details were not accepted" has "$CONTROL/script-result.txt" "shown=That user name or password wasn't accepted."
   check "no helper was started" absent "$WORK/status"
   finish
}

case_uptodate() {
   echo; echo "== uptodate: nothing newer than the installed version =="
   prepare --only-old
   start_update 'standin-pass!1' now fake-installer.sh
   show "$CONTROL/script-result.txt"
   check "the user is told that this is the newest version" has "$CONTROL/script-result.txt" "shown=You already have the newest version, PixInsight $HAVE."
   check "no helper was started" absent "$WORK/status"
   check "nothing was downloaded" hasnot "$LOG" "download started"
   finish
}

case_offline() {
   echo; echo "== offline: the download service cannot be reached =="
   prepare none
   start_update 'standin-pass!1' now fake-installer.sh
   show "$CONTROL/script-result.txt"
   check "the user is told that PixInsight cannot be reached" has "$CONTROL/script-result.txt" "shown=Can't reach PixInsight right now. PixInsight is working normally."
   check "no helper was started" absent "$WORK/status"
   finish
}

case_windows() {
   echo; echo "== windows: both windows open for a second and close, with no mistake in their code =="
   prepare none
   echo windows > "$CONTROL/action.txt"
   open -n -g -a "$APP" --env "PI_UA_TEST_DIR=$CONTROL" --env "PI_UA_BASE=http://127.0.0.1:$PORT/dist/" \
        --env "PI_UA_TEST_INSTALL_DIR=$FOLDER" --args -n --automation-mode -r="$SCRIPT"
   wait_for 90 test -f "$CONTROL/script-result-windows.txt"
   show "$CONTROL/script-result-windows.txt"
   check "the sign-in window was built, opened and closed" has "$CONTROL/script-result-windows.txt" "signin_window=ok"
   check "the progress window was built, opened and closed" has "$CONTROL/script-result-windows.txt" "status_window=ok"
   check "the progress sentence gives size, progress and time left" has "$CONTROL/script-result-windows.txt" "status_text=Downloading PixInsight 1.9.6: 300 MB of 1.1 GB (27%). About 4 minutes left."
   check "no error was reported" hasnot "$CONTROL/script-result-windows.txt" "error="
   finish
}

# -----------------------------------------------------------------------------

sh "$ROOT/build/build.sh" >/dev/null || { echo "The build failed; run sh build/build.sh to see why."; exit 1; }
[ $# -eq 0 ] && set -- now later window cancel interrupted broken installfail nostart carryfail refused uptodate offline windows noreopen notrash lost unsigned genuine
[ -n "$HAVE" ] || { echo "No PixInsight was found at $APP."; exit 2; }
echo "PixInsight on this computer: $HAVE. The stand-in download page offers: $NEW."
for CASE in "$@"; do
   case "$CASE" in
      noreopen|notrash|lost|unsigned|genuine) ALONE_CASE=yes ;;
      *) ALONE_CASE="" ;;
   esac
   case "$CASE" in
      now|later|window|cancel|interrupted|broken|installfail|nostart|carryfail|refused|uptodate|offline|windows|noreopen|notrash|lost|unsigned|genuine) "case_$CASE" ;;
      *) echo "unknown case: $CASE" ;;
   esac
done
echo
echo "RESULT: $PASSED checks passed, $FAILED failed."
[ "$FAILED" -eq 0 ]
