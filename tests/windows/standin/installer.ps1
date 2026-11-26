# PixInsight Update Assistant: a stand-in for PixInsight's installer, used by
# the Windows rehearsal, tests\windows\run-rehearsal.ps1.
#
# In a rehearsal the helper runs it in place of the real installer:
#
#    powershell.exe -NoProfile -ExecutionPolicy Bypass -File installer.ps1 -Folder <the PixInsight folder> -Installer <the downloaded file>
#
# Like the real installer it empties the PixInsight folder first, so that
# everything that lay there is gone, the module of an old add-on included.
# Then it leaves a small folder that looks like a newly installed PixInsight,
# and ends with code 0, which is what the real installer reports when it has
# installed.
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

   [void][IO.Directory]::CreateDirectory((Join-Path $Folder 'bin'))
   [IO.File]::WriteAllText((Join-Path $Folder 'bin\PixInsight.exe'), "a stand-in for the new PixInsight program`n")
   [IO.File]::WriteAllText($mark, "new version`n")
   "stand-in installer: installed into $Folder"
   exit 0
} catch {
   "stand-in installer: $($_.Exception.Message)"
   exit 1
}
