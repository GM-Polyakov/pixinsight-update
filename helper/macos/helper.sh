#!/bin/sh
# PixInsight Update Assistant: the helper for macOS.
#
# The script inside PixInsight writes this file into a private folder and
# starts it detached. From then on the helper works on its own:
#
#   1. downloads the installer with curl, in the background;
#   2. checks the download against the checksum from the download page, and
#      checks that the package is signed by PixInsight's maker;
#   3. asks "Restart now, or later?";
#   4. asks PixInsight to quit the normal way, or waits until the user quits;
#   5. asks for the administrator password once and runs install.sh, which
#      moves the old PixInsight folder aside, runs PixInsight's own installer,
#      makes sure that the new PixInsight starts on this Mac, carries the
#      user's own folders over, and only then puts the old folder in the
#      Trash. If the installer fails or the new PixInsight does not start,
#      the old folder goes back;
#   6. reopens PixInsight and makes sure that it has opened. PixInsight then
#      says which version is running.
#
# It never receives the PixInsight user name or password. What it receives is
# the address of one installer and the session cookie that goes with it, in
# the file job.conf, which it deletes as soon as it has read it.
#
# Everything it shows the user comes from the text-* files next to it, which
# the script writes from its one table of wording.

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/log.txt"
# However the helper ends, it removes its own file.
trap 'rm -f "$DIR/helper.sh"' EXIT

conf() { sed -n "s/^$1=//p" "$DIR/job.conf" 2>/dev/null | head -1; }
text() { cat "$DIR/text-$1" 2>/dev/null; }
note() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }
# A sentence with its %1 filled in.
fill() { # $1 = the name of the sentence, $2 = what goes in the place of %1
   SENTENCE="$(text "$1")"
   MARK='%1'
   case "$SENTENCE" in
      *"$MARK"*) printf '%s%s%s' "${SENTENCE%%"$MARK"*}" "$2" "${SENTENCE#*"$MARK"}" ;;
      *) printf '%s' "$SENTENCE" ;;
   esac
}

URL="$(conf url)"
COOKIE="$(conf cookie)"
CLIENT="$(conf client)"
FILE="$(conf file)"
SHA1="$(conf sha1)"
SIZE="$(conf size)"
NEW="$(conf new)"
OLD="$(conf old)"
PI="$(conf pid)"
INSTALL_DIR="$(conf install_dir)"
APP="$(conf app)"
# Rehearsal only. Empty in real use.
T_ANSWER="$(conf test_answer)"
T_RETRY="$(conf test_retry)"
T_INSTALLER="$(conf test_installer)"
T_HOME="$(conf test_home)"
T_PKGUTIL="$(conf test_pkgutil)"
T_QUIET="$(conf test_quiet)"
rm -f "$DIR/job.conf"

TITLE="$(text product)"
PKG="$DIR/$FILE"
BEGAN="$(date +%s)"
# The Apple team of PixInsight's maker, Pleiades Astrophoto. Apple puts it into
# every certificate it issues to them, and it stays the same when a
# certificate is renewed. An installer package must be signed by this team.
MAKER="DVX5WE77BM"

# The file name comes from a web page: accept a plain installer name only.
case "$FILE" in
   ""|*/*|.*) note "refused the file name"; exit 1 ;;
esac
case "$FILE" in
   *.pkg) ;;
   *) note "not a macOS installer package: $FILE"; exit 1 ;;
esac

status() { # $1 = phase, $2 = bytes received
   printf 'phase=%s\ngot=%s\ntotal=%s\nversion=%s\nhelper=%s\nbegan=%s\nnow=%s\n' \
      "$1" "${2:-0}" "${SIZE:-0}" "$NEW" "$$" "$BEGAN" "$(date +%s)" > "$DIR/status.tmp" && mv -f "$DIR/status.tmp" "$DIR/status"
}

# True while the PixInsight that started the update is running, or anything
# else from inside the same application: a second PixInsight, or PixInsight's
# own updater, which runs after PixInsight closes if add-on updates are pending
# and then starts PixInsight again.
pixinsight_running() {
   if [ -n "$PI" ] && ps -p "$PI" -o comm= 2>/dev/null | grep -q "PixInsight"; then
      return 0
   fi
   ps -axo comm= 2>/dev/null | grep -q -F "$APP/Contents/"
}

# A question with two buttons. Prints the text of the button that was chosen.
ask() { # $1 = question, $2 = the default button, $3 = the other button
   /usr/bin/osascript -e 'on run argv' -e 'tell me to activate' \
      -e 'set r to display dialog (item 1 of argv) with title (item 2 of argv) buttons {item 4 of argv, item 3 of argv} default button 2' \
      -e 'return button returned of r' -e 'end run' "$1" "$TITLE" "$2" "$3" 2>>"$LOG"
}

# A message with one button.
tell_user() { # $1 = message
   [ -n "$T_QUIET" ] && { note "would show: $1"; return; }
   /usr/bin/osascript -e 'on run argv' -e 'tell me to activate' \
      -e 'display dialog (item 1 of argv) with title (item 2 of argv) buttons {item 3 of argv} default button 1' \
      -e 'end run' "$1" "$TITLE" "$(text ok)" >/dev/null 2>>"$LOG"
}

# Remove what is no longer needed. The logs stay for one more run.
tidy() {
   rm -f "$PKG" "$DIR/cancel" "$DIR/status" "$DIR/status.tmp" "$DIR/window-open" \
         "$DIR/install.sh" "$DIR/install-log.txt.result" "$DIR/install-log.txt.start"
}

stop_if_cancelled() {
   if [ -f "$DIR/cancel" ]; then
      note "cancelled by the user"
      [ -n "${CURL:-}" ] && kill "$CURL" 2>/dev/null
      tidy
      rm -f "$DIR"/text-* "$DIR/message.js"
      exit 0
   fi
}

note "helper started for PixInsight $NEW (from $OLD); PixInsight is process $PI"

# --- 1. Download -------------------------------------------------------------
while :; do
   status downloading "$(stat -f %z "$PKG" 2>/dev/null || echo 0)"
   # curl reads the address and the cookie from its input, so that neither
   # appears in the list of running programs. It resumes a partial file.
   printf 'url = "%s"\nuser-agent = "%s"\ncookie = "%s"\nlocation\nfail\nsilent\nshow-error\ncontinue-at = "-"\noutput = "%s"\n' \
      "$URL" "$CLIENT" "$COOKIE" "$PKG" | /usr/bin/curl -K - 2>>"$LOG" &
   CURL=$!
   while kill -0 "$CURL" 2>/dev/null; do
      status downloading "$(stat -f %z "$PKG" 2>/dev/null || echo 0)"
      stop_if_cancelled
      sleep 1
   done
   wait "$CURL"
   RC=$?
   CURL=""
   stop_if_cancelled
   [ "$RC" -eq 0 ] && break

   note "curl ended with code $RC"
   status stopped "$(stat -f %z "$PKG" 2>/dev/null || echo 0)"
   if [ -n "$T_RETRY" ]; then
      CHOICE="$T_RETRY"
      T_RETRY="cancel"
   elif [ "$(ask "$(text downloadStopped)" "$(text tryAgain)" "$(text cancel)")" = "$(text tryAgain)" ]; then
      CHOICE="again"
   else
      CHOICE="cancel"
   fi
   if [ "$CHOICE" != "again" ]; then
      note "the user gave up after the download stopped"
      tidy
      rm -f "$DIR"/text-* "$DIR/message.js"
      exit 0
   fi
done

# --- 2. Check the download ---------------------------------------------------
status checking "$(stat -f %z "$PKG" 2>/dev/null || echo 0)"
GOOD=yes
[ "$(head -c 4 "$PKG" 2>/dev/null)" = "xar!" ] || GOOD=no
if [ "$GOOD" = yes ] && [ -n "$SHA1" ]; then
   [ "$(/usr/bin/shasum -a 1 "$PKG" | cut -d' ' -f1)" = "$SHA1" ] || GOOD=no
fi
if [ "$GOOD" != yes ]; then
   note "the download is not the installer that the page listed"
   tidy
   tell_user "$(text startAgain)"
   rm -f "$DIR"/text-* "$DIR/message.js"
   exit 1
fi
# The checksum shows that the file is the one the download page listed. The
# signature shows who made it. Apple's installer, run from a script, installs
# an unsigned package without a word, so the helper looks first: the package
# must carry a certificate that Apple issued to PixInsight's maker.
PKGUTIL="${T_PKGUTIL:-/usr/sbin/pkgutil}"
SIGNATURE="$("$PKGUTIL" --check-signature "$PKG" 2>&1)"
if echo "$SIGNATURE" | grep -q "Status: signed by a developer certificate issued by Apple" &&
   echo "$SIGNATURE" | grep -q "Developer ID Installer: .*($MAKER)"; then
   if echo "$SIGNATURE" | grep -q "Notarization: trusted by the Apple notary service"; then
      note "the installer is signed by PixInsight's maker ($MAKER) and notarised by Apple"
   else
      note "the installer is signed by PixInsight's maker ($MAKER); macOS did not confirm that Apple has notarised it"
   fi
else
   note "the installer is not signed by PixInsight's maker. What macOS says about it:"
   echo "$SIGNATURE" | head -4 | sed 's/^/   /' >> "$LOG"
   tidy
   tell_user "$(text notGenuine)"
   rm -f "$DIR"/text-* "$DIR/message.js"
   exit 1
fi
note "download complete and checked"
stop_if_cancelled

# --- 3. Restart now, or later? -----------------------------------------------
status asking "$(stat -f %z "$PKG")"
if [ -n "$T_ANSWER" ]; then
   ANSWER="$T_ANSWER"
elif [ "$(ask "$(text ready)" "$(text restartNow)" "$(text later)")" = "$(text restartNow)" ]; then
   ANSWER="now"
else
   ANSWER="later"
fi
note "answer: $ANSWER"
stop_if_cancelled

# --- 4. PixInsight closes ----------------------------------------------------
if [ "$ANSWER" = "now" ] && pixinsight_running; then
   # PixInsight ignores a request to quit while a window of a script is open
   # in it (TESTING.md, "The real update"). The phase "restart" makes the
   # add-on's progress window close itself, and keeps it from opening. The
   # file window-open is there for as long as any window of the add-on is
   # open: wait for it to go, for a minute at most.
   status restart "$(stat -f %z "$PKG")"
   [ -f "$DIR/window-open" ] && note "a window of the add-on is open in PixInsight; it has to close first"
   sleep 1
   WAITED=0
   while [ -f "$DIR/window-open" ] && [ "$WAITED" -lt 60 ] && pixinsight_running; do
      sleep 1
      WAITED=$((WAITED+1))
   done
   [ "$WAITED" -gt 0 ] && note "waited $WAITED s for a window of the add-on to close"
   # One more second, so that the script behind the window has ended too.
   sleep 1
   # The ordinary quit request, the one that Cmd-Q sends. PixInsight shows its
   # own warning if images are unsaved. If the user answers No, PixInsight
   # stays open and the update simply waits, as with "Later".
   /usr/bin/osascript -e 'on run argv' -e 'tell application (item 1 of argv) to quit' -e 'end run' "$APP" >/dev/null 2>&1
   note "asked PixInsight to quit"
fi
status waiting "$(stat -f %z "$PKG")"
while :; do
   while pixinsight_running; do
      stop_if_cancelled
      sleep 1
   done
   # Look once more after a moment: PixInsight's own updater may be about to
   # start, or to start PixInsight again.
   sleep 3
   pixinsight_running || break
done
note "PixInsight has closed"

# --- 5. Install --------------------------------------------------------------
status installing "$(stat -f %z "$PKG")"
INFO=""
if [ -n "$T_INSTALLER" ]; then
   # Rehearsal: a stand-in installer, a stand-in folder and a stand-in home
   # folder with its own Trash; no administrator rights.
   /bin/sh "$DIR/install.sh" "$INSTALL_DIR" "$PKG" "$DIR/install-log.txt" "$T_HOME" "$T_INSTALLER" >>"$LOG" 2>&1
   RC=$?
else
   /usr/bin/osascript -e 'on run argv' -e 'tell me to activate' \
      -e 'display dialog (item 1 of argv) with title (item 2 of argv) buttons {item 3 of argv} default button 1 giving up after 7200' \
      -e 'end run' "$(text installing)" "$TITLE" "$(text hide)" >/dev/null 2>&1 &
   INFO=$!
   # One administrator approval covers the whole of install.sh. Items 1 to 5
   # are install.sh and its four arguments; item 6 is the sentence macOS shows.
   /usr/bin/osascript -e 'on run argv' \
      -e 'set c to "/bin/sh"' \
      -e 'repeat with i from 1 to 5' -e 'set c to c & " " & quoted form of (item i of argv)' -e 'end repeat' \
      -e 'do shell script c with prompt (item 6 of argv) with administrator privileges' \
      -e 'end run' "$DIR/install.sh" "$INSTALL_DIR" "$PKG" "$DIR/install-log.txt" "$HOME" "$(text adminPrompt)" >/dev/null 2>>"$LOG"
   RC=$?
fi
note "install step ended with code $RC"
[ -n "$INFO" ] && kill "$INFO" 2>/dev/null

result() { sed -n "s/^$1=//p" "$DIR/install-log.txt.result" 2>/dev/null | head -1; }
RESULT="$(result result)"     # installed, restored, untouched or failed
FOLDER="$(result old)"        # trash:<name>, kept:<name> or check:<name>: where the old folder is now
WHY="$(result why)"           # installer or nostart: why the old folder was put back
LEFT="$(result left)"         # the folder that holds what a failed install left
[ -z "$RESULT" ] && RESULT="untouched"
note "result: $RESULT; old folder: ${FOLDER:-as it was}${WHY:+; why: $WHY}"

# --- 6. Reopen ---------------------------------------------------------------
if [ "$RESULT" = "failed" ]; then
   # The installer failed and the old folder could not be moved back, so
   # there is no PixInsight to reopen. Say where the old one is.
   tidy
   tell_user "$(fill folderLost "${FOLDER#*:}")"
   rm -f "$DIR"/text-* "$DIR/message.js"
   note "the previous PixInsight could not be put back; helper finished"
   exit 1
fi

{
   echo "old=$OLD"
   echo "expected=$NEW"
   echo "result=$RESULT"
   echo "folder=$FOLDER"
   echo "why=$WHY"
   echo "left=$LEFT"
   echo "title=$TITLE"
   echo "done=$(text done)"
   echo "notUpdated=$(text notUpdated)"
   echo "oldFolderTrash=$(text oldFolderTrash)"
   echo "oldFolderLeft=$(text oldFolderLeft)"
   echo "oldFolderCheck=$(text oldFolderCheck)"
   echo "wontStart=$(text wontStart)"
   echo "failedFolder=$(text failedFolder)"
   echo "quiet=$T_QUIET"
} > "$DIR/outcome"

tidy
NOT_REOPENED="$(text notReopened)"
rm -f "$DIR"/text-*

# True once PixInsight has opened: its process is there and stays, or it has
# already read the file "outcome" in order to show its message.
came_up() {
   I=0
   while [ "$I" -lt 30 ]; do
      [ -f "$DIR/outcome" ] || return 0
      if pixinsight_running; then
         sleep 5
         pixinsight_running && return 0
         [ -f "$DIR/outcome" ] || return 0
         return 1
      fi
      sleep 1
      I=$((I+1))
   done
   return 1
}

# In the real update of 2026-11-24 PixInsight was asked to open once, and
# nobody looked whether it had. Now: up to three attempts, each one checked.
TRY=1
REOPENED=no
while [ "$TRY" -le 3 ]; do
   if [ -n "$T_QUIET" ]; then
      # Rehearsal: PixInsight opens in the background, shows no message box
      # and leaves by itself.
      /usr/bin/open -n -g -a "$APP" --args -n --automation-mode -r="$DIR/message.js" --force-exit >>"$LOG" 2>&1
   else
      /usr/bin/open -a "$APP" --args -r="$DIR/message.js" >>"$LOG" 2>&1
   fi
   RC=$?
   if [ "$RC" -eq 0 ] && came_up; then
      REOPENED=yes
      break
   fi
   note "attempt $TRY to reopen PixInsight did not work (the request to open it ended with code $RC)"
   TRY=$((TRY+1))
   sleep 3
done

if [ "$REOPENED" = yes ]; then
   note "PixInsight has reopened (attempt $TRY); helper finished"
   exit 0
fi
tell_user "$NOT_REOPENED"
rm -f "$DIR/outcome" "$DIR/message.js"
note "PixInsight did not reopen; helper finished"
exit 1
