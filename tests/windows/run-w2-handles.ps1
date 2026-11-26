# PixInsight Update Assistant, Windows test W2, third part.
#
# Question: what does a helper inherit from PixInsight when it is started
# through a starter file, and does any of it lie inside the PixInsight folder?
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-w2-handles.ps1
#
# Needs PixInsight closed. It opens a second, separate PixInsight as an
# ordinary session for a few seconds; the helper closes it again the normal
# way.
#
# Output: tests\out\windows\w2\w2-handles-log.txt
# Exit code: 0 the helper holds nothing inside the PixInsight folder, 1 it
#            does or the test did not run, 2 nothing was started.

. "$PSScriptRoot\lib.ps1"

$exe = Get-PixInsightExe
if (-not $exe) {
   'No PixInsight was found. Nothing was started.'
   exit 2
}
if (Test-PixInsightRunning) {
   'PixInsight is running. Close it first. Nothing was started.'
   exit 2
}

$dir = Join-Path $UA_Out 'w2'
New-Item -ItemType Directory -Force $dir | Out-Null
$work = Join-Path $env:TEMP 'PixInsightUpdateAssistant-w2handles'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
$problem = Join-Path $env:TEMP 'pi-update-assistant-w2h-error.txt'
Remove-Item -LiteralPath $problem, (Join-Path $dir 'w2-handles-script.txt') -ErrorAction SilentlyContinue

$env:PI_UA_W_OUT = ConvertTo-SlashPath $dir
$p = Start-PixInsightScript -Exe $exe -Script (Join-Path $PSScriptRoot 'w2-handles-probe.js') -Normal
"started $exe as process $($p.Id), as an ordinary session"

$helperLog = Join-Path $work 'w2-handles-log.txt'
$finished = $false
for ($i = 0; $i -lt 480 -and -not $finished; $i++) {
   if (Test-Path -LiteralPath $helperLog) { $finished = (Get-ResultText $helperLog).Contains('helper finished') }
   if (-not $finished) { Start-Sleep -Milliseconds 250 }
}
Start-Sleep -Seconds 1
if (-not $p.HasExited) {
   'PixInsight is still open; asking it to close.'
   [void]$p.CloseMainWindow()
   if (-not $p.WaitForExit(20000)) {
      Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
      'It did not close; its process was stopped.'
   }
}

if (Test-Path -LiteralPath $problem) { '--- the script stopped with an error'; Get-ResultText $problem }
'--- the helper''s log'
$log = ''
if (Test-Path -LiteralPath $helperLog) {
   $log = Get-ResultText $helperLog
   # Paths inside the user's own folder are shortened in what is printed.
   ($log -split "`n") | Where-Object { $_ } | ForEach-Object { "   $($_.Replace($env:USERPROFILE, '~'))" }
   Copy-Item -LiteralPath $helperLog -Destination $dir -Force
} else {
   '   (no log: the helper did not start)'
}
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

''
"a PixInsight is running now: $(Test-PixInsightRunning)"
if ($log -match 'inside the PixInsight folder: 0') {
   'RESULT: the helper holds nothing open inside the PixInsight folder.'
   exit 0
}
'RESULT: see the log.'
exit 1
