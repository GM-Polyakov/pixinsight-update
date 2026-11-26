# PixInsight Update Assistant: a stand-in for PixInsight's installer that
# fails before it has changed anything. The Windows rehearsal uses it to check
# that the helper then reports the PixInsight folder as untouched and reopens
# the PixInsight that is still there.
#
# In a rehearsal the helper runs it in place of the real installer:
#
#    powershell.exe -NoProfile -ExecutionPolicy Bypass -File installer-fails.ps1 -Folder <the PixInsight folder> -Installer <the downloaded file>
#
# It changes nothing and ends with code 1603, which is what Windows' own
# installing service reports when an installation has failed.
#
# Both parameters are taken so that the helper can call every stand-in in the
# same way. Neither is used.
#
# Windows PowerShell 5.1, plain ASCII.

param([string]$Folder, [string]$Installer)

'stand-in installer: failing on purpose; nothing was changed'
exit 1603
