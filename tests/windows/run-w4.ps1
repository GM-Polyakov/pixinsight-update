# PixInsight Update Assistant, Windows test W4.
#
# Question: can a helper ask PixInsight on Windows to close the normal way,
# and what happens when a window of a script is open, or an image is unsaved?
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-w4.ps1 [clean] [window] [unsaved]
#
# Without a mode it runs all three, one after the other. Needs PixInsight
# closed. Each mode opens a second, separate PixInsight as an ordinary session,
# because automation mode would answer PixInsight's own questions by itself.
# So PixInsight's window is on the screen for about half a minute per mode.
#
#    clean    nothing open: one request should close PixInsight
#    window   a window of a script is open: the request should have no effect
#             until that window has closed
#    unsaved  an unsaved image: PixInsight should stay open and ask. If nobody
#             answers, the runner then stops the process of this PixInsight,
#             which saves nothing. The image is a grey square made for the
#             test.
#
# Output: tests\out\windows\w4\
# Exit code: 0 clean and window behaved as expected, 1 not, 2 nothing started.

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Mode)

. "$PSScriptRoot\lib.ps1"

if (-not $Mode) { $Mode = 'clean', 'window', 'unsaved' }

$exe = Get-PixInsightExe
if (-not $exe) {
   'No PixInsight was found. Nothing was started.'
   exit 2
}

$dir = Join-Path $UA_Out 'w4'
New-Item -ItemType Directory -Force $dir | Out-Null
$work = Join-Path $env:TEMP 'PixInsightUpdateAssistant-w4'
$problem = Join-Path $env:TEMP 'pi-update-assistant-w4-error.txt'
$unexpected = 0

foreach ($m in $Mode) {
   ''
   "=== mode: $m"
   if (Test-PixInsightRunning) {
      'PixInsight is running. Close it first. Nothing was started.'
      exit 2
   }
   if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
   $scriptResult = Join-Path $dir "w4-script-$m.txt"
   $seen = Join-Path $dir "w4-windows-$m.txt"
   $ready = Join-Path $dir 'w4-watch-ready'
   $stop = Join-Path $dir 'w4-watch-stop'
   Remove-Item -LiteralPath $scriptResult, $seen, $ready, $stop, $problem -ErrorAction SilentlyContinue

   $watchLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Out "{1}" -Ready "{2}" -Stop "{3}" -Also PixInsight' -f `
      (Join-Path $PSScriptRoot 'w2-watch.ps1'), $seen, $ready, $stop
   $watch = Start-Process -FilePath 'powershell.exe' -ArgumentList $watchLine -WindowStyle Hidden -PassThru
   if (-not (Wait-ForFile -Path $ready -Seconds 60)) {
      'The window watcher did not start. Nothing else was started.'
      exit 2
   }

   $env:PI_UA_W_OUT = ConvertTo-SlashPath $dir
   $env:PI_UA_W_MODE = $m
   $p = Start-PixInsightScript -Exe $exe -Script (Join-Path $PSScriptRoot 'w4-probe.js') -Normal
   "started $exe as process $($p.Id), as an ordinary session"

   # The helper ends its log with "helper finished".
   $helperLog = Join-Path $work 'w4-helper-log.txt'
   $finished = $false
   for ($i = 0; $i -lt 600 -and -not $finished; $i++) {
      if (Test-Path -LiteralPath $helperLog) { $finished = (Get-ResultText $helperLog).Contains('helper finished') }
      if (-not $finished) { Start-Sleep -Milliseconds 250 }
   }
   Start-Sleep -Seconds 1

   $stillOpen = -not $p.HasExited
   if ($stillOpen) {
      # With its question open, PixInsight takes no further close request, and
      # --terminate is of no use on Windows: the second PixInsight that carries
      # it opens a window of its own and waits there (seen on 2026-11-25). So
      # the process of this test's own PixInsight is stopped. It holds nothing
      # but the grey test image.
      'PixInsight is still open, with its question unanswered. Stopping the process of this test''s own PixInsight; nothing is saved.'
      Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
      [void]$p.WaitForExit(10000)
   }
   [IO.File]::WriteAllText($stop, "stop`n")
   [void]$watch.WaitForExit(15000)

   '--- what the script reported'
   if (Test-Path -LiteralPath $scriptResult) { Get-ResultText $scriptResult } else { '(nothing: PixInsight did not run the script)' }
   if (Test-Path -LiteralPath $problem) { '--- the script stopped with an error'; Get-ResultText $problem }
   '--- the helper''s log'
   $log = ''
   if (Test-Path -LiteralPath $helperLog) {
      $log = Get-ResultText $helperLog
      ($log -split "`n") | Where-Object { $_ } | ForEach-Object { "   $_" }
      Copy-Item -LiteralPath $helperLog -Destination (Join-Path $dir "w4-helper-log-$m.txt") -Force
   } else {
      '   (no log: the helper did not start)'
   }
   '--- windows of PixInsight that came and went, in order'
   if (Test-Path -LiteralPath $seen) {
      Get-Content -LiteralPath $seen | Where-Object { $_ -match 'program=PixInsight' } | ForEach-Object { "   $_" }
      $others = @(Get-Content -LiteralPath $seen | Where-Object { $_ -notmatch 'program=PixInsight' })
      "   and $($others.Count) window(s) of other programs, of which console windows or windows of the test's programs: $(@($others | Where-Object { $_ -match 'title=' }).Count)"
   }

   $closed1 = $log -match 'PixInsight exited [\d.]+ s after request 1'
   $closed2 = $log -match 'PixInsight exited [\d.]+ s after request 2'
   $scriptFailed = Test-Path -LiteralPath $problem
   switch ($m) {
      'clean' {
         if ($closed1) { 'RESULT clean: as expected. One request closed PixInsight.' }
         else { $unexpected++; 'RESULT clean: NOT as expected. One request did not close PixInsight.' }
      }
      'window' {
         if ($scriptFailed) { $unexpected++; 'RESULT window: the script failed, so this case was not tested.' }
         elseif (-not $closed1 -and $closed2) { 'RESULT window: as expected. No quit while the script''s window was open; the second request closed PixInsight.' }
         else { $unexpected++; 'RESULT window: NOT as expected. See the log.' }
      }
      'unsaved' {
         # What happens here depends on what the person at the screen answers,
         # so the runner only says what it saw.
         if ($closed1) { 'RESULT unsaved: PixInsight closed after the first request.' }
         elseif ($closed2) { 'RESULT unsaved: PixInsight stayed open after the first request and closed after the second.' }
         else { 'RESULT unsaved: PixInsight stayed open after both requests.' }
      }
   }
   Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
   Remove-Item -LiteralPath $ready, $stop -ErrorAction SilentlyContinue
}

''
"a PixInsight is running now: $(Test-PixInsightRunning)"
if ($unexpected -gt 0) { exit 1 }
exit 0
