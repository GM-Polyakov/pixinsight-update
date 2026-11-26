# PixInsight Update Assistant: a stand-in for an installer that never ran,
# because the user answered No when Windows asked for administrator rights.
# The Windows rehearsal uses it to check that the helper then reports the
# PixInsight folder as untouched and reopens the PixInsight that is still
# there.
#
# In a rehearsal the helper runs it in place of the real installer:
#
#    powershell.exe -NoProfile -ExecutionPolicy Bypass -File installer-declined.ps1 -Folder <the PixInsight folder> -Installer <the downloaded file>
#
# It changes nothing and ends with code 1223. That is the number Windows gives
# for "the operation was cancelled by the user", and the helper takes it as
# its result when the administrator prompt was answered No.
#
# Both parameters are taken so that the helper can call every stand-in in the
# same way. Neither is used.
#
# Windows PowerShell 5.1, plain ASCII.

param([string]$Folder, [string]$Installer)

'stand-in installer: ending as if the administrator prompt had been answered No; nothing was changed'
exit 1223
