#!/bin/sh
# PixInsight Update Assistant: the one part that runs as administrator.
#
# PixInsight's installer refuses to run while the folder /Applications/PixInsight
# exists, and it removes nothing itself (TESTING.md, test 6). So this script:
#
#   1. moves the present folder aside, as "PixInsight (before update)";
#   2. runs PixInsight's own installer;
#   3. asks the new PixInsight for its list of options, to see that it starts
#      on this Mac at all (TESTING.md, "The real update": the first one
#      installed a PixInsight that could not start);
#   4. if it starts, moves the user's own top-level folders, such as star
#      catalogues, into the new folder;
#   5. only then, with the update a success, moves the old folder into the
#      user's Trash. Until this point the old folder has only had another
#      name, in the same place, and could be put back by renaming it;
#   6. if the installer fails or the new PixInsight does not start, moves what
#      the installer left aside, as "PixInsight (failed update)", and moves
#      the old folder back, so that PixInsight is as it was.
#
# It deletes nothing, and it changes no owner of anything.
#
#   $1  the PixInsight folder, /Applications/PixInsight
#   $2  the installer package
#   $3  a log file; the outcome is written to "$3.result"
#   $4  the user's home folder, whose Trash receives the old folder
#   $5  absent in real use. In a rehearsal: a stand-in for the installer,
#       called as  "$5" <folder> <package>

FOLDER="$1"
PKG="$2"
LOG="$3"
HOMEDIR="${4:-}"
STANDIN="${5:-}"
RESULT="$LOG.result"

say() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }
finish() { # $1 = result, $2 = where the old folder is now, $3 = why it was put back, $4 = the folder with what the installer left
   printf 'result=%s\nold=%s\nwhy=%s\nleft=%s\n' "$1" "$2" "${3:-}" "${4:-}" > "$RESULT"
   say "finished: $1${2:+ (old folder: $2)}${3:+ (why: $3)}"
}

# Does the new PixInsight start on this Mac? It is asked for its list of
# options, which it prints without opening a window and without writing any
# file. A PixInsight built for a chip that this Mac does not have fails here.
# When this runs as administrator, PixInsight gets a throwaway home folder.
starts() {
   BIN="$FOLDER/PixInsight.app/Contents/MacOS/PixInsight"
   ANSWER="$LOG.start"
   if [ ! -x "$BIN" ]; then
      say "the new folder has no PixInsight program"
      return 1
   fi
   if [ "$(id -u)" -eq 0 ]; then
      HOME="$(dirname "$LOG")" "$BIN" --help >"$ANSWER" 2>&1 &
   else
      "$BIN" --help >"$ANSWER" 2>&1 &
   fi
   P=$!
   T=0
   while kill -0 "$P" 2>/dev/null && [ "$T" -lt 120 ]; do
      sleep 1
      T=$((T+1))
   done
   if kill -0 "$P" 2>/dev/null; then
      kill "$P" 2>/dev/null
      say "the new PixInsight gave no answer within two minutes"
      return 1
   fi
   wait "$P"
   CODE=$?
   if [ "$CODE" -ne 0 ]; then
      say "the new PixInsight does not start on this Mac (it ended with code $CODE). What it said:"
      grep -v '^[[:space:]]*$' "$ANSWER" 2>/dev/null | head -5 | sed 's/^/   /' >> "$LOG"
      return 1
   fi
   say "the new PixInsight starts"
   return 0
}

: > "$RESULT"
say "started for $FOLDER"

if [ ! -d "$FOLDER" ] || [ ! -f "$PKG" ]; then
   say "the folder or the package is missing"
   finish untouched ""
   exit 10
fi

# 1. Move the present folder aside.
ASIDE="$FOLDER (before update)"
N=1
while [ -e "$ASIDE" ]; do
   N=$((N+1))
   ASIDE="$FOLDER (before update $N)"
done
if ! mv "$FOLDER" "$ASIDE" 2>>"$LOG"; then
   say "could not move the present folder aside"
   finish untouched ""
   exit 11
fi
say "present folder moved aside, as $(basename "$ASIDE")"

# 2. Run the installer.
if [ -n "$STANDIN" ]; then
   "$STANDIN" "$FOLDER" "$PKG" >>"$LOG" 2>&1
else
   /usr/sbin/installer -pkg "$PKG" -target / >>"$LOG" 2>&1
fi
RC=$?
say "installer ended with code $RC"

# 3. See that the new PixInsight starts, before anything of the user's moves.
WHY="installer"
if [ "$RC" -eq 0 ] && [ -d "$FOLDER/PixInsight.app" ]; then
   if starts; then
      # 4. Carry over what is the user's own: every top-level item of the old
      #    folder that the new one does not have. Add-ons are not carried
      #    over; PixInsight fetches them again for the new version.
      NOT_CARRIED=""
      for ITEM in "$ASIDE"/*; do
         [ -e "$ITEM" ] || continue
         NAME="$(basename "$ITEM")"
         if [ ! -e "$FOLDER/$NAME" ]; then
            if mv "$ITEM" "$FOLDER/$NAME" 2>>"$LOG"; then
               say "carried over: $NAME"
            else
               say "could not carry over: $NAME"
               NOT_CARRIED=yes
            fi
         fi
      done
      # If something of the user's own could not be carried over, the old
      # folder stays in Applications, and the user is told not to delete it.
      if [ -n "$NOT_CARRIED" ]; then
         finish installed "check:$(basename "$ASIDE")"
         exit 0
      fi
      # 5. The update has succeeded: the installer reported success, the new
      #    PixInsight starts, and everything of the user's is across. Only
      #    now does the old folder go to the user's Trash. No owner is
      #    changed, so the folder is whole if the user takes it out again.
      #    If it cannot be moved there, it stays in Applications.
      TRASH="$HOMEDIR/.Trash"
      if [ -n "$HOMEDIR" ] && [ -d "$TRASH" ]; then
         DEST="$TRASH/$(basename "$ASIDE")"
         N=1
         while [ -e "$DEST" ]; do
            N=$((N+1))
            DEST="$TRASH/$(basename "$ASIDE") $N"
         done
         if mv "$ASIDE" "$DEST" 2>>"$LOG"; then
            say "old folder moved to the Trash, as $(basename "$DEST")"
            finish installed "trash:$(basename "$DEST")"
            exit 0
         fi
      fi
      say "the old folder could not be moved to the Trash; it stays in Applications"
      finish installed "kept:$(basename "$ASIDE")"
      exit 0
   fi
   WHY="nostart"
fi

# 6. The installer failed, or the new PixInsight does not start: put
#    everything back.
LEFT=""
if [ -e "$FOLDER" ]; then
   FAILED="$FOLDER (failed update)"
   N=1
   while [ -e "$FAILED" ]; do
      N=$((N+1))
      FAILED="$FOLDER (failed update $N)"
   done
   if mv "$FOLDER" "$FAILED" 2>>"$LOG"; then
      LEFT="$(basename "$FAILED")"
      say "what the installer left was moved to $LEFT"
   fi
fi
# Only into an empty place: a move onto a folder that is still there would
# put the old folder inside it.
if [ ! -e "$FOLDER" ] && mv "$ASIDE" "$FOLDER" 2>>"$LOG"; then
   finish restored "" "$WHY" "$LEFT"
   exit 20
fi
say "the old folder could not be moved back; it is at $ASIDE"
finish failed "kept:$(basename "$ASIDE")" "$WHY" "$LEFT"
exit 21
