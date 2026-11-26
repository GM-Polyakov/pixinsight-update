# PixInsight Update Assistant: a stand-in for PixInsight's installer for the
# worst case on Windows. The real installer removes the old version before it
# installs the new one, so an installation that fails after that step leaves
# no PixInsight at all. The Windows rehearsal uses this stand-in to check that
# the helper then keeps the downloaded installer and tells the user where it
# is.
#
# In a rehearsal the helper runs it in place of the real installer:
#
#    powershell.exe -NoProfile -ExecutionPolicy Bypass -File installer-gone.ps1 -Folder <the PixInsight folder> -Installer <the downloaded file>
#
# It empties the PixInsight folder and ends with code 1603, which is what
# Windows' own installing service reports when an installation has failed.
#
# It only ever touches a folder that the rehearsal made, which it knows by the
# rehearsal's own file bin\version.txt. Should the real PixInsight folder be
# passed to it by mistake, it changes nothing and ends with code 2.
#
# The downloaded file is taken as a parameter so that the helper can call
# every stand-in in the same way. It is not read.
#
# Windows PowerShell 5.1, plain ASCII.

param([string]$Folder, [string]$Installer)

$ErrorActionPreference = 'Stop'

try {
   $mark = ''
   if ($Folder) { $mark = Join-Path $Folder 'bin\version.txt' }
   if (-not $mark -or -not (Test-Path -LiteralPath $mark) -or
       -not [IO.File]::ReadAllText($mark).Contains('(stand-in)')) {
      "stand-in installer: '$Folder' is not a folder that the rehearsal made; nothing was changed"
      exit 2
   }

   Get-ChildItem -LiteralPath $Folder -Force | Remove-Item -Recurse -Force
   "stand-in installer: failing on purpose after emptying $Folder"
   exit 1603
} catch {
   "stand-in installer: $($_.Exception.Message)"
   exit 1
}
