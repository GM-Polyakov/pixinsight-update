# PixInsight Update Assistant, Windows test W5.
#
# Question: when PixInsight is started with the closing-message script,
# helper\macos\message.js, does it run it and say the right sentence? On
# Windows this reopening is also the only check that a new PixInsight starts.
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-w5.ps1 [quiet] [handover] [attended]
#
# Needs PixInsight closed. Without a word it runs the part "quiet" only.
#
#    handover  one start in the background that stays open. The runner then
#              hands it a second script with -x=, as the rehearsal does to
#              pick the add-on's menu item again, and asks it to close.
#    quiet     two starts in the background, as the rehearsal reopens
#              PixInsight. The script writes its sentence to a file where it
#              would show a window. The first working folder has a space in
#              its name, the second a comma, because PixInsight reads a comma
#              after -r=<file> as the start of the script's arguments.
#    attended  one start as the helper will reopen PixInsight after a real
#              update: an ordinary session that shows the message in a window.
#              A person clicks OK. Then the runner hands the open PixInsight a
#              second script with -x=, and at the end asks PixInsight to close.
#
# Output: tests\out\windows\w5\
# Exit code: 0 every check passed, 1 a check failed, 2 nothing was started.

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Part)

. "$PSScriptRoot\lib.ps1"

if (-not $Part) { $Part = @('quiet') }

$passed = 0
$failed = 0
function Add-Check {
   param([string]$What, [bool]$Good)
   if ($Good) { $script:passed++; "   pass  $What" } else { $script:failed++; "   FAIL  $What" }
}

$exe = Get-PixInsightExe
if (-not $exe) {
   'No PixInsight was found. Nothing was started.'
   exit 2
}
if (Test-PixInsightRunning) {
   'PixInsight is running. Close it first. Nothing was started.'
   exit 2
}
$dir = Join-Path $UA_Out 'w5'
New-Item -ItemType Directory -Force $dir | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
$have = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion

# A working folder with message.js and the file "outcome", as the helper
# leaves them when it reopens PixInsight.
function New-MessageFolder {
   param([string]$Name, [string]$Old, [bool]$Quiet)
   $work = Join-Path $env:TEMP $Name
   if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
   New-Item -ItemType Directory -Force $work | Out-Null
   Copy-Item -LiteralPath (Join-Path $UA_Root 'helper\macos\message.js') -Destination $work
   $lines = @(
      "old=$Old",
      'expected=9.9.9',
      'result=installed',
      'folder=',
      'why=',
      'left=',
      ('title=' + (Get-Wording 'product')),
      ('done=' + (Get-Wording 'done')),
      ('notUpdated=' + (Get-Wording 'notUpdated')),
      ('oldFolderTrash=' + (Get-Wording 'oldFolderTrash')),
      ('oldFolderLeft=' + (Get-Wording 'oldFolderLeft')),
      ('oldFolderCheck=' + (Get-Wording 'oldFolderCheck')),
      ('wontStart=' + (Get-Wording 'wontStart')),
      ('failedFolder=' + (Get-Wording 'failedFolder')),
      ('quiet=' + $(if ($Quiet) { '1' } else { '' }))
   )
   [IO.File]::WriteAllText((Join-Path $work 'outcome'), (($lines -join "`n") + "`n"), $utf8)
   return $work
}

foreach ($part in $Part) {
   if ($part -eq 'quiet') {
      $cases = @(
         @{ Name = 'PixInsightUpdateAssistant w5'; Old = '1.9.5'; Expect = ((Get-Wording 'done') -replace '%1', $have); What = 'a working folder with a space in its name, after an update'; Counts = $true },
         @{ Name = 'PixInsightUpdateAssistant w5 no update'; Old = $have; Expect = ((Get-Wording 'notUpdated') -replace '%1', $have); What = 'the same, after no update'; Counts = $true },
         @{ Name = 'PixInsightUpdateAssistant,w5'; Old = '1.9.5'; Expect = ((Get-Wording 'done') -replace '%1', $have); What = 'a working folder with a comma in its name. This one only shows what happens; it is not counted'; Counts = $false }
      )
      foreach ($case in $cases) {
         ''
         "=== quiet: $($case.What)"
         if (Test-PixInsightRunning) { 'PixInsight is running. Nothing was started.'; exit 2 }
         $work = New-MessageFolder $case.Name $case.Old $true
         # Exactly what the helper passes in a rehearsal.
         $line = '-n --automation-mode --no-focus-stealing -r="{0}" --force-exit' -f (ConvertTo-SlashPath (Join-Path $work 'message.js'))
         $p = Start-Process -FilePath $exe -ArgumentList $line -WorkingDirectory (Split-Path -Parent $exe) -PassThru
         $null = $p.Handle
         $shown = Join-Path $work 'message-shown.txt'
         [void](Wait-ForFile -Path $shown -Seconds $(if ($case.Counts) { 120 } else { 45 }))
         $exited = $p.WaitForExit($(if ($case.Counts) { 120000 } else { 30000 }))
         Start-Sleep -Seconds 1
         $text = ''
         if (Test-Path -LiteralPath $shown) {
            $text = Get-ResultText $shown
            ($text -split "`n") | Where-Object { $_ } | ForEach-Object { "   $_" }
         }
         $facts = @(
            @('PixInsight ran the script and it wrote its sentence', ($text.Length -gt 0)),
            @("the sentence is: $($case.Expect)", $text.Contains($case.Expect)),
            @("it names the version that is running, $have", $text.Contains("running=$have`n")),
            @('the script removed the file "outcome"', (-not (Test-Path -LiteralPath (Join-Path $work 'outcome')))),
            @('the script removed itself', (-not (Test-Path -LiteralPath (Join-Path $work 'message.js')))),
            @('PixInsight left by itself', $exited)
         )
         foreach ($fact in $facts) {
            if ($case.Counts) { Add-Check $fact[0] $fact[1] }
            else { "   seen  $($fact[0]): $($fact[1])" }
         }
         if (-not $exited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
         Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
      }
   }

   if ($part -eq 'handover') {
      ''
      '=== handover: an open PixInsight is handed a second script with -x='
      if (Test-PixInsightRunning) { 'PixInsight is running. Nothing was started.'; exit 2 }
      $work = New-MessageFolder 'PixInsightUpdateAssistant-w5' '1.9.5' $true
      Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'w5-x.js') -Destination $work
      # A PixInsight in the background that stays open after its script, as
      # the rehearsal keeps one open.
      $p = Start-PixInsightScript -Exe $exe -Script (Join-Path $work 'message.js') -Stay
      [void](Wait-ForFile -Path (Join-Path $work 'message-shown.txt') -Seconds 120)
      Start-Sleep -Seconds 2
      Add-Check 'PixInsight is open and has run its first script' ((-not $p.HasExited) -and (Test-Path -LiteralPath (Join-Path $work 'message-shown.txt')))
      if (-not $p.HasExited) {
         $x = Start-Process -FilePath $exe -ArgumentList ('-x="{0}"' -f (ConvertTo-SlashPath (Join-Path $work 'w5-x.js'))) -PassThru
         $ran = Join-Path $work 'w5-x-ran.txt'
         [void](Wait-ForFile -Path $ran -Seconds 30)
         $xEnded = $x.WaitForExit(15000)
         $ranText = ''
         if (Test-Path -LiteralPath $ran) { $ranText = Get-ResultText $ran }
         Add-Check 'the open PixInsight ran the script handed over with -x=' ($ranText.Contains("pid=$($p.Id)`n"))
         Add-Check 'the second start of the program ended by itself' ($xEnded)
         if (-not $xEnded) {
            "   the second start, process $($x.Id), is still running with a window titled '$((Get-Process -Id $x.Id -ErrorAction SilentlyContinue).MainWindowTitle)'; stopping it"
            Stop-Process -Id $x.Id -Force -ErrorAction SilentlyContinue
         }
         $p.Refresh()
         [void]$p.CloseMainWindow()
         $closed = $p.WaitForExit(30000)
         Add-Check 'PixInsight closed on request' ($closed)
         if (-not $closed) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
      }
      Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
   }

   if ($part -eq 'attended') {
      ''
      '=== attended: PixInsight opens as an ordinary session and shows the message'
      if (Test-PixInsightRunning) { 'PixInsight is running. Nothing was started.'; exit 2 }
      $work = New-MessageFolder 'PixInsightUpdateAssistant-w5' '1.9.5' $false
      Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'w5-x.js') -Destination $work

      $seen = Join-Path $dir 'w5-windows.txt'
      $ready = Join-Path $dir 'w5-watch-ready'
      $stop = Join-Path $dir 'w5-watch-stop'
      Remove-Item -LiteralPath $seen, $ready, $stop -ErrorAction SilentlyContinue
      $watchLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Out "{1}" -Ready "{2}" -Stop "{3}" -Also PixInsight' -f `
         (Join-Path $PSScriptRoot 'w2-watch.ps1'), $seen, $ready, $stop
      $watch = Start-Process -FilePath 'powershell.exe' -ArgumentList $watchLine -WindowStyle Hidden -PassThru
      if (-not (Wait-ForFile -Path $ready -Seconds 60)) { 'The window watcher did not start. Nothing else was started.'; exit 2 }

      # As the helper will reopen PixInsight after a real update, except that
      # PixInsight's own check for updates is left out of this test.
      $line = '--no-startup-check-updates -r="{0}"' -f (ConvertTo-SlashPath (Join-Path $work 'message.js'))
      $p = Start-Process -FilePath $exe -ArgumentList $line -WorkingDirectory (Split-Path -Parent $exe) -PassThru
      $null = $p.Handle
      "started $exe as process $($p.Id). Waiting for the message to be answered, five minutes at most."
      # The script removes "outcome" just before it shows the window, and
      # removes itself after the window has been answered.
      $answered = $false
      for ($i = 0; $i -lt 1200 -and -not $answered -and -not $p.HasExited; $i++) {
         $answered = -not (Test-Path -LiteralPath (Join-Path $work 'message.js'))
         if (-not $answered) { Start-Sleep -Milliseconds 250 }
      }
      Add-Check 'the script took the file "outcome"' (-not (Test-Path -LiteralPath (Join-Path $work 'outcome')))
      Add-Check 'the message was answered, and the script removed itself' ($answered)
      Add-Check 'PixInsight is still open after the message' (-not $p.HasExited)

      # A second script, handed to the open PixInsight.
      if (-not $p.HasExited) {
         $x = Start-Process -FilePath $exe -ArgumentList ('-x="{0}"' -f (ConvertTo-SlashPath (Join-Path $work 'w5-x.js'))) -PassThru
         $ran = Join-Path $work 'w5-x-ran.txt'
         [void](Wait-ForFile -Path $ran -Seconds 30)
         $xEnded = $x.WaitForExit(15000)
         $ranText = ''
         if (Test-Path -LiteralPath $ran) { $ranText = Get-ResultText $ran }
         Add-Check 'the open PixInsight ran the script handed over with -x=' ($ranText.Contains("pid=$($p.Id)`n"))
         Add-Check 'the second start of the program ended by itself' ($xEnded)
         if (-not $xEnded) { Stop-Process -Id $x.Id -Force -ErrorAction SilentlyContinue }

         'Asking PixInsight to close.'
         $p.Refresh()
         [void]$p.CloseMainWindow()
         Add-Check 'PixInsight closed on request' ($p.WaitForExit(30000))
      }
      [IO.File]::WriteAllText($stop, "stop`n")
      [void]$watch.WaitForExit(15000)
      '--- windows of PixInsight that came and went, in order'
      if (Test-Path -LiteralPath $seen) {
         Get-Content -LiteralPath $seen | Where-Object { $_ -match 'program=PixInsight' } | ForEach-Object { "   $_" }
      }
      Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $ready, $stop -ErrorAction SilentlyContinue
   }
}

''
"a PixInsight is running now: $(Test-PixInsightRunning)"
"RESULT: $passed checks passed, $failed failed."
if ($failed -gt 0) { exit 1 }
exit 0
