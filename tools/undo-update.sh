#!/bin/sh
# Puts the previous PixInsight back after an update by Update Assistant.
#
#   sh tools/undo-update.sh --check     look only, and say what would be done
#   sudo sh tools/undo-update.sh        do it
#
# What it does, in this order:
#   1. moves the PixInsight folder that the update installed aside, as
#      "PixInsight (undone update)" in Applications;
#   2. moves the previous folder back to /Applications/PixInsight, from the
#      Trash or from Applications, wherever the update left it;
#   3. moves the folders that the update carried over, such as star
#      catalogues, back into it;
#   4. gives the folder back to the system account, as PixInsight's installer
#      had it, and lets PixInsight's own updater run as administrator again.
#
# It deletes nothing. If a step fails, the steps before it are reversed.
# Nothing of PixInsight may be running.
#
# For rehearsals the three places can be given as arguments:
#   undo-update.sh [--check] [<PixInsight folder> [<previous folder> [<owner of the user's folders>]]]

set -u

CHECK=""
if [ "${1:-}" = "--check" ]; then
   CHECK=yes
   shift
fi

OWNER="${3:-${SUDO_USER:-$(id -un)}}"
HOMEDIR="$(eval echo "~$OWNER")"
NEW="${1:-/Applications/PixInsight}"
PARENT="$(dirname "$NEW")"
OLD="${2:-}"

say() { echo "undo-update: $*"; }
fail() { say "$*"; exit 1; }

# Where did the update leave the previous folder?
if [ -z "$OLD" ]; then
   for CANDIDATE in "$HOMEDIR/.Trash/PixInsight (before update)" "$PARENT/PixInsight (before update)"; do
      if [ -d "$CANDIDATE/PixInsight.app" ]; then
         OLD="$CANDIDATE"
         break
      fi
   done
fi

[ -n "$OLD" ] && [ -d "$OLD/PixInsight.app" ] || fail "the previous PixInsight folder was not found, neither in the Trash nor in Applications. Nothing was changed."
[ -d "$NEW" ] || fail "there is no folder at $NEW. Nothing was changed."
if ps -axo comm= | grep -q -F "$NEW/PixInsight.app/Contents/"; then
   fail "PixInsight is running. Quit it and run this again. Nothing was changed."
fi

version_of() { /usr/bin/plutil -extract CFBundleShortVersionString raw "$1/PixInsight.app/Contents/Info.plist" 2>/dev/null || cat "$1/PixInsight.app/Contents/version.txt" 2>/dev/null || echo "unknown"; }

ASIDE="$PARENT/PixInsight (undone update)"
N=1
while [ -e "$ASIDE" ]; do
   N=$((N+1))
   ASIDE="$PARENT/PixInsight (undone update $N)"
done

# The folders the update carried over: every folder at the top of the new
# PixInsight folder that the previous one does not have.
CARRIED=""
for ITEM in "$NEW"/*; do
   [ -d "$ITEM" ] || continue
   NAME="$(basename "$ITEM")"
   [ -e "$OLD/$NAME" ] || CARRIED="$CARRIED|$NAME"
done

say "installed now:        PixInsight $(version_of "$NEW"), at $NEW"
say "previous:             PixInsight $(version_of "$OLD"), at $OLD"
say "to be moved back in:  $(echo "${CARRIED#|}" | sed 's/|/, /g')"
say "the installed folder will be kept as: $ASIDE"

if [ -n "$CHECK" ]; then
   say "this was only a look. Nothing was changed."
   exit 0
fi

# 1. The installed folder goes aside.
mv "$NEW" "$ASIDE" || fail "could not move $NEW aside. Nothing was changed."

# 2. The previous folder comes back.
if ! mv "$OLD" "$NEW"; then
   mv "$ASIDE" "$NEW"
   fail "could not move the previous folder back from $OLD. The installed folder was put back; nothing was changed. If the previous folder is in the Trash, drag it into Applications with the Finder and run this again."
fi

# 3. The carried-over folders come back.
OLDIFS="$IFS"
IFS="|"
for NAME in ${CARRIED#|}; do
   [ -n "$NAME" ] || continue
   if mv "$ASIDE/$NAME" "$NEW/$NAME"; then
      say "moved back: $NAME"
   else
      say "COULD NOT move back: $NAME. It is still in $ASIDE"
   fi
done
IFS="$OLDIFS"

# 4. Ownership as PixInsight's installer had it. The folders that were
#    carried over belong to the user and keep their owner.
if [ "$(id -u)" -eq 0 ]; then
   for ITEM in "$NEW" "$NEW"/* "$NEW"/.[!.]*; do
      [ -e "$ITEM" ] || continue
      NAME="$(basename "$ITEM")"
      case "|${CARRIED#|}|" in
         *"|$NAME|"*) continue ;;
      esac
      if [ "$ITEM" = "$NEW" ]; then
         chown root:admin "$ITEM"
      else
         chown -R root:admin "$ITEM"
      fi
   done
   UPDATER="$NEW/PixInsight.app/Contents/MacOS/PixInsightUpdater"
   [ -f "$UPDATER" ] && chmod +s "$UPDATER"
fi

say "done. PixInsight $(version_of "$NEW") is back at $NEW."
say "the folder the update had installed is kept at: $ASIDE"
