#!/bin/sh
# A stand-in for macOS's pkgutil, used by the rehearsal.
# Called by the helper as:   fake-pkgutil.sh --check-signature <package>
#
# The rehearsal's installer package is four bytes and zeros and carries no
# signature. This says about it what the real pkgutil says about a genuine
# PixInsight installer, so that the helper's reading of that report is
# rehearsed. The cases "unsigned" and "genuine" use the real pkgutil.

echo "Package \"$(basename "$2")\":"
echo "   Status: signed by a developer certificate issued by Apple for distribution"
echo "   Notarization: trusted by the Apple notary service"
echo "   Signed with a trusted timestamp on: 2026-11-19 19:45:19 +0000"
echo "   Certificate Chain:"
echo "    1. Developer ID Installer: PLEIADES ASTROPHOTO SOCIEDAD LIMITADA (DVX5WE77BM)"
echo "    2. Developer ID Certification Authority"
echo "    3. Apple Root CA"
