#!/bin/sh
# Builds the files that users point PixInsight at.
#
#   sh build/build.sh
#
# It is written for the /bin/sh of macOS and for the sh that comes with Git
# for Windows.
#
# Output, in dist/:
#   repository/updates.xri          the list that PixInsight reads
#   repository/<date>-UpdateAssistant-<version>.tar.gz   the add-on itself
#   stage/                          the add-on unpacked, as PixInsight will
#                                   have it; the rehearsal runs this copy
#
# With UA_DIST=<folder> the output goes into that folder in place of dist/.
# The Windows rehearsal uses this, because many programs on Windows cannot
# use a file whose full path is longer than 260 characters, and the output
# lies several folders deep. On Windows, write the folder with forward
# slashes, as in C:/Temp/UpdateAssistant: the tool that works out the
# package's checksum marks its answer when a file's name holds a backslash,
# and the build then stops rather than write a marked checksum into the list.
#
# Publish the contents of dist/repository/ at an https address that does not
# redirect. That address, ending in a slash, is the repository link.
#
# Publish only what a build on a Mac has written. Windows keeps no Unix
# permissions, so a package built there records every file as writable by
# everyone. A build on Windows serves the rehearsal and trials on that PC,
# and says at its end that it is not to be published.
#
# The helper files in helper/macos/ and helper/windows/ are stored inside the
# script as rows of hexadecimal digits, so that the add-on is plain script
# text and no character in a helper can upset PixInsight's script loader.

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
HELPER="$ROOT/helper/macos"
DIST="${UA_DIST:-$ROOT/dist}"
STAGE="$DIST/stage"
REPO="$DIST/repository"
DEST="$STAGE/src/scripts/UpdateAssistant"
# The helper files that are stored inside the script, by their place under
# helper/. message.js is used on both systems.
HELPERS="macos/helper.sh macos/install.sh macos/message.js windows/helper.ps1"

# On Windows this script runs in a shell of the Unix kind, such as the sh of
# Git for Windows. There uname gives a name that starts with one of these
# three words.
case "$(uname -s)" in
   MINGW*|MSYS*|CYGWIN*) WINDOWS=yes ;;
   *) WINDOWS=no ;;
esac

VERSION="$(sed -n 's/^#define UA_VERSION "\(.*\)"$/\1/p' "$SRC/UpdateAssistant.js")"
# The list's format asks for the release date in UTC.
DATE="${UA_RELEASE_DATE:-$(date -u +%Y%m%d)}"
[ -n "$VERSION" ] || { echo "build: no version found in src/UpdateAssistant.js"; exit 1; }

# --- Checks ------------------------------------------------------------------
FAILED=0

# PixInsight 1.9.3 removes comments without understanding regular-expression
# literals. An escaped slash followed by a slash looks like a comment to it,
# and it then refuses the whole file without a message.
for f in "$SRC"/*.js "$SRC"/*.jsh "$HELPER"/*.js; do
   if grep -n -F '\//' "$f" >/dev/null; then
      echo "build: two slashes side by side inside a pattern, which PixInsight 1.9.3 refuses:"
      grep -n -F '\//' "$f" | sed "s#^#   $(basename "$f"):#"
      FAILED=1
   fi
   # Features of newer JavaScript that the old engine does not have.
   if grep -n -E '(^|[^A-Za-z0-9_])(class [A-Za-z_]+ *(extends|\{)|async function|await )|`' "$f" >/dev/null; then
      echo "build: newer JavaScript that PixInsight 1.9.3 cannot run:"
      grep -n -E '(^|[^A-Za-z0-9_])(class [A-Za-z_]+ *(extends|\{)|async function|await )|`' "$f" | sed "s#^#   $(basename "$f"):#"
      FAILED=1
   fi
done
for f in "$HELPER"/*.sh; do
   sh -n "$f" || { echo "build: $(basename "$f") is not valid shell"; FAILED=1; }
done
# The helper files go into the script byte for byte, and the script writes
# them out again byte for byte. A checkout with Windows line ends puts a
# carriage return at the end of every line, and a helper.sh with carriage
# returns does not run. So no helper file may hold one. The carriage return
# to look for is made with printf, because plain sh has no way of writing one
# inside a text.
CR="$(printf '\r')"
for h in $HELPERS; do
   f="$ROOT/helper/$h"
   if [ ! -f "$f" ]; then
      echo "build: helper/$h is missing"
      FAILED=1
   elif [ "$(LC_ALL=C tr -cd "$CR" < "$f" | wc -c | tr -d ' ')" != 0 ]; then
      echo "build: helper/$h holds carriage returns (Windows line ends), and it is stored exactly as it is"
      FAILED=1
   fi
done
# Windows PowerShell 5.1 reads a script file that has no byte-order mark in
# the system's own text encoding, which differs from PC to PC. Only plain
# ASCII means the same in all of them, so helper.ps1 may hold printable ASCII,
# tabs and line feeds, and nothing else.
f="$ROOT/helper/windows/helper.ps1"
if [ -f "$f" ]; then
   ODD="$(LC_ALL=C tr -d '\011\012\040-\176' < "$f" | wc -c | tr -d ' ')"
   if [ "$ODD" != 0 ]; then
      echo "build: helper/windows/helper.ps1 holds $ODD bytes that are not printable ASCII, a tab or a line feed"
      FAILED=1
   fi
fi
[ "$FAILED" -eq 0 ] || exit 1

# --- Stage -------------------------------------------------------------------
# Only the two folders that the build makes are removed. UA_DIST may name a
# folder that holds other things too.
rm -rf "$STAGE" "$REPO"
mkdir -p "$DEST" "$REPO"
cp "$SRC/UpdateAssistant.js" "$SRC/UpdateAssistant-wording.jsh" "$SRC/UpdateAssistant-page.jsh" "$DEST/"

{
   echo "// Generated by build/build.sh from helper/macos/ and helper/windows/. Do not edit."
   echo "// Each helper file is stored as hexadecimal digits and written out again"
   echo "// by UA.writeHelperFile() when an update starts."
   echo
   echo "var UA_HELPER = {};"
   for h in $HELPERS; do
      echo
      echo "UA_HELPER[\"$(basename "$h")\"] ="
      xxd -p "$ROOT/helper/$h" | tr -d '\n' | fold -w 96 | sed -e 's/^/   "/' -e 's/$/" +/' | sed -e '$ s/ +$/;/'
   done
} > "$DEST/UpdateAssistant-helper.jsh"

# --- Package -----------------------------------------------------------------
PACKAGE="$DATE-UpdateAssistant-$VERSION.tar.gz"
if [ "$WINDOWS" = yes ]; then
   # The tar that comes with Git for Windows is another program, which does
   # not know these options. Windows' own tar is the program that macOS has,
   # and takes the same ones. It is not one of Git's programs, so it gets its
   # paths written the Windows way.
   WINTAR="$(cygpath -u "$SYSTEMROOT/System32/tar.exe")"
   "$WINTAR" --no-mac-metadata --uid 0 --gid 0 --uname root --gname wheel \
      -czf "$(cygpath -w "$REPO/$PACKAGE")" -C "$(cygpath -w "$STAGE")" src
else
   # No macOS extras in the archive, and no trace of who built it.
   COPYFILE_DISABLE=1 tar --no-mac-metadata --uid 0 --gid 0 --uname root --gname wheel \
      -czf "$REPO/$PACKAGE" -C "$STAGE" src
fi
# macOS has shasum. Where it is missing, as it can be in the sh of Git for
# Windows, sha1sum gives the same checksum in the same form.
if command -v shasum >/dev/null 2>&1; then
   SHA1="$(shasum -a 1 "$REPO/$PACKAGE" | cut -d' ' -f1)"
else
   SHA1="$(sha1sum "$REPO/$PACKAGE" | cut -d' ' -f1)"
fi
# Two mishaps do not stop the build by themselves. Both tools put a backslash
# in front of their answer when the file's name holds one, as it does when
# UA_DIST is written the Windows way. And when the tool fails, the answer is
# empty. PixInsight refuses a package whose checksum is not the one in the
# list, so the build stops here unless it has the forty digits of a checksum.
case "$SHA1" in *[!0123456789abcdef]*) SHA1="" ;; esac
[ "${#SHA1}" -eq 40 ] || { echo "build: could not work out the package's checksum. On Windows, write UA_DIST with forward slashes, as in C:/Temp/UpdateAssistant."; exit 1; }

# --- The list that PixInsight reads ------------------------------------------
# The script is the same for both kinds of Mac, so the list names one platform,
# "macOS, any chip". (PixInsight 1.9.3 and earlier exist for Intel only, and
# whether they accept a list that names "arm64" is not known; see PUBLISHING.md.)
# Windows is a second platform with the same package, because the one script
# carries the helpers of both systems. The list does not say "every system":
# that would offer the add-on on Linux too, where it can do nothing.
# On both systems the range of PixInsight versions starts at 1.9.3, the oldest
# version the add-on has run on and the oldest it is required to serve. It ends at
# 1.9.99 on purpose: after the add-on has updated PixInsight, the new
# PixInsight fetches the add-on again only if the range includes it.
package_entry() {
   cat <<EOF
      <package fileName="$PACKAGE"
               sha1="$SHA1"
               type="script"
               releaseDate="$DATE">
         <title>
            PixInsight Update Assistant $VERSION
         </title>
         <remove>
            src/scripts/UpdateAssistant
         </remove>
         <description>
            <p>
               Updates PixInsight to the newest version from inside PixInsight:
               Script &gt; Utilities &gt; Update PixInsight.
            </p>
            <p>
               PixInsight Update Assistant is a free, independent add-on.
               It is not made or endorsed by Pleiades Astrophoto.
            </p>
         </description>
      </package>
EOF
}

{
   cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<xri version="1.0">

   <description>
      <p>
         PixInsight Update Assistant: updates PixInsight from inside PixInsight.
         A free, independent add-on. It is not made or endorsed by Pleiades Astrophoto.
      </p>
   </description>

   <platform os="macosx" arch="noarch" version="1.9.3:1.9.99">
EOF
   package_entry
   cat <<EOF
   </platform>

   <platform os="windows" arch="noarch" version="1.9.3:1.9.99">
EOF
   package_entry
   cat <<EOF
   </platform>

</xri>
EOF
} > "$REPO/updates.xri"

echo "built PixInsight Update Assistant $VERSION"
echo "   $REPO/updates.xri"
echo "   $REPO/$PACKAGE  (sha1 $SHA1)"
if [ "$WINDOWS" = yes ]; then
   # Git's tar would read the colon of a path like C:/folder as the end of
   # another computer's name, so the tar that made the archive lists it too.
   "$WINTAR" -tzf "$(cygpath -w "$REPO/$PACKAGE")" | sed 's/^/      /'
   # Windows keeps no Unix permissions, so its tar makes them up, and records
   # every folder and file as writable by everyone. The Mac's tar records what
   # the Mac's file system holds. On a Mac, PixInsight's updater installs a
   # package's files as files of the system, and whether it keeps the
   # permissions that the archive records is not known. If it does, every
   # program on that Mac could rewrite the stored install.sh, the one part
   # that later runs as administrator. So the build says that this package is
   # not the one to publish. The list goes with it, because it holds this
   # package's checksum.
   # The script text in the package differs from a Mac's as well, in a way
   # that is harmless as JavaScript: the sed of Git for Windows leaves the
   # last row of each helper without a line end, where the Mac's sed adds one.
   echo "   Built on Windows, this package records every file as writable by everyone."
   echo "   Do not publish it: the list and the package to publish come from a build on a Mac."
else
   tar -tzf "$REPO/$PACKAGE" | sed 's/^/      /'
fi
