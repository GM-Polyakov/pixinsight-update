# PixInsight Update Assistant, Windows test W2.
#
# Question: which way of starting a helper works from the old script engine
# on Windows, does the helper outlive PixInsight, does any window show, and
# how can the script tell that the helper is alive?
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-w2.ps1
#
# Needs PixInsight closed. It opens a second, separate PixInsight in the
# background once, which leaves by itself. The helpers it starts are a few
# lines of PowerShell each and end by themselves. Nothing is installed.
#
# Output: tests\out\windows\w2\
# Exit code: 0 at least one helper outlived PixInsight, 1 none did,
#            2 nothing was started.

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
if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
New-Item -ItemType Directory -Force $dir | Out-Null
$work = Join-Path $env:TEMP 'PixInsightUpdateAssistant-w2'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
# The ways H and I use a working folder with a space in its name.
$spaced = Join-Path $env:TEMP 'PixInsightUpdateAssistant w2 space'
if (Test-Path -LiteralPath $spaced) { Remove-Item -LiteralPath $spaced -Recurse -Force }
$result = Join-Path $dir 'w2-result.txt'
$problem = Join-Path $env:TEMP 'pi-update-assistant-w2-error.txt'
Remove-Item -LiteralPath $problem -ErrorAction SilentlyContinue

# The window watcher, itself without a window.
$seen = Join-Path $dir 'w2-windows.txt'
$ready = Join-Path $dir 'w2-watch-ready'
$stop = Join-Path $dir 'w2-watch-stop'
$watchLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Out "{1}" -Ready "{2}" -Stop "{3}"' -f `
   (Join-Path $PSScriptRoot 'w2-watch.ps1'), $seen, $ready, $stop
$watch = Start-Process -FilePath 'powershell.exe' -ArgumentList $watchLine -WindowStyle Hidden -PassThru
if (-not (Wait-ForFile -Path $ready -Seconds 60)) {
   'The window watcher did not start. Nothing else was started.'
   exit 2
}

$env:PI_UA_W_OUT = ConvertTo-SlashPath $dir
$began = Get-Date
$p = Start-PixInsightScript -Exe $exe -Script (Join-Path $PSScriptRoot 'w2-probe.js')
"started $exe as process $($p.Id)"

$came = Wait-ForFile -Path $result, $problem -Seconds 300
$reported = [int]((Get-Date) - $began).TotalSeconds
$exited = $p.WaitForExit(120000)
$closed = [int]((Get-Date) - $began).TotalSeconds
# The helpers log once more ten seconds after PixInsight has gone.
Start-Sleep -Seconds 16
[IO.File]::WriteAllText($stop, "stop`n")
[void]$watch.WaitForExit(15000)

''
if ($came -eq $result) {
   "--- what the probe reported, $reported s after the start"
   Get-ResultText $result
} elseif ($came) {
   '--- the probe stopped with an error'
   Get-ResultText $problem
} else {
   '--- the probe wrote nothing within 300 s'
}

'--- the PixInsight that was started'
if ($exited) {
   "process $($p.Id) ended $closed s after the start, with exit code $($p.ExitCode)"
} else {
   "process $($p.Id) was still running 120 s after the probe"
}
"a PixInsight is running now: $(Test-PixInsightRunning)"

''
'--- the helpers'' logs'
$outlived = @()
foreach ($way in 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I') {
   $log = Join-Path $work "w2-log-$way.txt"
   if ($way -eq 'H' -or $way -eq 'I') { $log = Join-Path $spaced "w2-log-$way.txt" }
   if (Test-Path -LiteralPath $log) {
      $text = Get-ResultText $log
      "way ${way}:"
      ($text -split "`n") | Where-Object { $_ } | ForEach-Object { "   $_" }
      if ($text -match '(?m)^\S+ 3 helper still running') { $outlived += $way }
      Copy-Item -LiteralPath $log -Destination $dir
   } else {
      "way ${way}: no log"
   }
}

''
'--- way J: a helper that shows a window of its own, started by PixInsight as the add-on starts its helper'
$formLog = Join-Path $work 'w2-form-from-pixinsight.txt'
$windowSeen = $false
if (Test-Path -LiteralPath $formLog) {
   ((Get-ResultText $formLog) -split "`n") | Where-Object { $_ } | ForEach-Object { "   $_" }
   Copy-Item -LiteralPath $formLog -Destination $dir
} else {
   '   no log: it did not start'
}
if (Test-Path -LiteralPath $seen) {
   $windowSeen = [bool](@(Get-Content -LiteralPath $seen) | Where-Object { $_.Contains('appeared:') -and $_.Contains('Update Assistant window test (from-pixinsight)') })
}
"   the watcher saw that window on the screen: $windowSeen"

''
'--- windows that appeared while the test ran'
if (Test-Path -LiteralPath $seen) {
   $all = @(Get-Content -LiteralPath $seen)
   $ofInterest = @($all | Where-Object { $_ -match 'title=' })
   "$($all.Count) new windows in all; $($ofInterest.Count) of them console windows or windows of programs the test starts:"
   $ofInterest | ForEach-Object { "   $_" }
   'the others, by program:'
   $all | Where-Object { $_ -notmatch 'title=' } |
      ForEach-Object { if ($_ -match 'program=(\S*)') { $Matches[1] } } |
      Group-Object | ForEach-Object { "   $($_.Count) x $($_.Name)" }
} else {
   'the watcher left no record'
}

''
$left = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
   Where-Object { $_.CommandLine -match 'w2-helper\.ps1' })
"helpers still running now: $($left.Count)"
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $spaced -Recurse -Force -ErrorAction SilentlyContinue

if ($outlived.Count -gt 0) {
   "RESULT: helpers started by way(s) $($outlived -join ', ') outlived PixInsight."
   exit 0
}
'RESULT: no helper logged anything after PixInsight exited.'
exit 1
