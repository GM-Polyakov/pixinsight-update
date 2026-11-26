# PixInsight Update Assistant, Windows test W1.
#
# Question: does a script written for PixInsight's old script engine load on
# Windows, and what does PixInsight report about itself there?
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-w1.ps1
#
# Needs PixInsight closed. It opens a second, separate PixInsight in the
# background once, which leaves by itself. Nothing is installed or changed.
#
# Output: tests\out\windows\w1-result.txt
# Exit code: 0 the probe reported, 1 it did not, 2 nothing was started.

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

New-Item -ItemType Directory -Force $UA_Out | Out-Null
$result = Join-Path $UA_Out 'w1-result.txt'
$problem = Join-Path $env:TEMP 'pi-update-assistant-w1-error.txt'
Remove-Item -LiteralPath $result, $problem -ErrorAction SilentlyContinue

$env:PI_UA_W_OUT = ConvertTo-SlashPath $UA_Out
$began = Get-Date
$p = Start-PixInsightScript -Exe $exe -Script (Join-Path $PSScriptRoot 'w1-probe.js')
"started $exe as process $($p.Id)"

$came = Wait-ForFile -Path $result, $problem -Seconds 240
$reported = [int]((Get-Date) - $began).TotalSeconds
$exited = $p.WaitForExit(120000)
$closed = [int]((Get-Date) - $began).TotalSeconds
Start-Sleep -Seconds 2

''
if ($came -eq $result) {
   "--- what PixInsight reported, $reported s after the start"
   Get-ResultText $result
} elseif ($came) {
   '--- the probe stopped with an error'
   Get-ResultText $problem
} else {
   '--- the probe wrote nothing within 240 s'
}

'--- the PixInsight that was started'
if ($exited) {
   "process $($p.Id) ended $closed s after the start, with exit code $($p.ExitCode)"
} else {
   "process $($p.Id) was still running 120 s after the probe"
}
"a PixInsight is running now: $(Test-PixInsightRunning)"
if ($came -eq $result) {
   $pidSeen = Get-ResultValue $result 'pid'
   "process number as PixInsight reports it: $pidSeen; as Windows gave it at the start: $($p.Id)"
}

if ($came -eq $result) { exit 0 }
exit 1
