# PixInsight Update Assistant, Windows test W2, second part.
#
# Question: can a helper that was started hidden still put a window of its
# own on the screen? Windows may hide the first window of a program that was
# itself started hidden.
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-w2-form.ps1
#
# PixInsight is not involved. Two small windows appear for three seconds each,
# one per way of starting:
#
#    hidden-start           started hidden by another PowerShell (Start-Process
#                           -WindowStyle Hidden), as the second stage of a
#                           two-stage start would be; the window is shown
#                           with ShowDialog()
#    hidden-start-modeless  the same start; the window is shown with Show()
#    starter-file           started through a .cmd starter file by a program
#                           that allows it no console window, as PixInsight
#                           starts a helper (test W2, ways A and B)
#
# Output: tests\out\windows\w2\w2-form-*.txt
# Exit code: 0 the window of the helper started through a starter file was on
#            the screen, 1 it was not.
#
# The same question with PixInsight as the starter is way J of run-w2.ps1.

. "$PSScriptRoot\lib.ps1"

$dir = Join-Path $UA_Out 'w2'
New-Item -ItemType Directory -Force $dir | Out-Null
$work = Join-Path $env:TEMP 'PixInsightUpdateAssistant-w2form'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force $work | Out-Null
$form = Join-Path $work 'w2-form.ps1'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'w2-form.ps1') -Destination $form
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$seen = Join-Path $dir 'w2-form-windows.txt'
$ready = Join-Path $dir 'w2-watch-ready'
$stop = Join-Path $dir 'w2-watch-stop'
Remove-Item -LiteralPath $seen, $ready, $stop -ErrorAction SilentlyContinue
$watchLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Out "{1}" -Ready "{2}" -Stop "{3}"' -f `
   (Join-Path $PSScriptRoot 'w2-watch.ps1'), $seen, $ready, $stop
$watch = Start-Process -FilePath 'powershell.exe' -ArgumentList $watchLine -WindowStyle Hidden -PassThru
if (-not (Wait-ForFile -Path $ready -Seconds 60)) {
   'The window watcher did not start. Nothing else was started.'
   exit 2
}

function Wait-ForClosed {
   param([string]$Tag)
   $log = Join-Path $work "w2-form-$Tag.txt"
   for ($i = 0; $i -lt 120; $i++) {
      if ((Test-Path -LiteralPath $log) -and ((Get-ResultText $log) -match '(?m) (closed|E .*)$')) { return }
      Start-Sleep -Milliseconds 250
   }
}

# 1. Started hidden by another PowerShell.
Start-Process -FilePath $powershell -WindowStyle Hidden -WorkingDirectory $work -ArgumentList (
   '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Tag hidden-start -Dir "{1}"' -f $form, $work)
Wait-ForClosed 'hidden-start'

# 1b. The same, with the window shown by Show() and kept alive by the script.
Start-Process -FilePath $powershell -WindowStyle Hidden -WorkingDirectory $work -ArgumentList (
   '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Tag hidden-start-modeless -Dir "{1}" -Modeless' -f $form, $work)
Wait-ForClosed 'hidden-start-modeless'

# 2. Through a starter file, started without any console window.
$starter = Join-Path $work 'w2-form-start.cmd'
$starterLine = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -Tag starter-file -Dir "{2}"' -f $powershell, $form, $work
[IO.File]::WriteAllText($starter, "@echo off`r`n$starterLine`r`n")
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $starter
$psi.WorkingDirectory = $work
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
[void][System.Diagnostics.Process]::Start($psi)
Wait-ForClosed 'starter-file'

Start-Sleep -Seconds 1
[IO.File]::WriteAllText($stop, "stop`n")
[void]$watch.WaitForExit(15000)

$onScreen = @{}
foreach ($tag in 'hidden-start', 'hidden-start-modeless', 'starter-file') {
   ''
   "--- $tag"
   $onScreen[$tag] = $false
   $log = Join-Path $work "w2-form-$tag.txt"
   if (Test-Path -LiteralPath $log) {
      $text = Get-ResultText $log
      ($text -split "`n") | Where-Object { $_ } | ForEach-Object { "   $_" }
      Copy-Item -LiteralPath $log -Destination $dir -Force
      $onScreen[$tag] = $text.Contains('Windows says the window is visible: True')
   } else {
      '   (no log: it did not start)'
   }
}
''
'--- what the watcher saw of these windows'
if (Test-Path -LiteralPath $seen) {
   Get-Content -LiteralPath $seen | Where-Object { $_ -match 'title=' } | ForEach-Object { "   $_" }
}
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ready, $stop -ErrorAction SilentlyContinue

''
# What was found on 2026-11-25, and what the build rests on: the window of a
# helper started through a starter file comes onto the screen, and the window
# of a helper that another PowerShell started hidden does not, in either way
# of showing it.
"RESULT: started through a starter file, the window was on the screen: $($onScreen['starter-file'])."
"        started hidden, with ShowDialog(): $($onScreen['hidden-start']); with Show(): $($onScreen['hidden-start-modeless']). Both were False when this was first run."
if ($onScreen['starter-file']) { exit 0 }
exit 1
