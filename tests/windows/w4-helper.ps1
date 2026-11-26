# PixInsight Update Assistant, Windows test W4: the helper that asks PixInsight
# to close.
#
# The probe, w4-probe.js, starts it the way test W2 found to work: through a
# starter file. It waits six seconds, then sends PixInsight's main window the
# request that Windows sends when the X button of a window is clicked, and
# watches whether PixInsight exits. If PixInsight is still there ten seconds
# later, it asks a second time. In the mode "window" it first waits until the
# script's own window has closed.
#
#    -Mode           clean | window | unsaved
#    -PixInsightPid  the process number of the PixInsight to close
#    -Dir            the working folder; the log is w4-helper-log.txt there
#
# Windows PowerShell 5.1, plain ASCII.

param([string]$Mode = 'clean', [int]$PixInsightPid = 0, [string]$Dir = '.')

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding $false
$log = Join-Path $Dir 'w4-helper-log.txt'
$windowOpen = Join-Path $Dir 'w4-window-open'

function Add-Note {
   param([string]$Text)
   [IO.File]::AppendAllText($log, ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $Text + "`n"), $utf8)
}

function Get-PixInsight {
   return Get-Process -Id $PixInsightPid -ErrorAction SilentlyContinue |
      Where-Object { $_.ProcessName -eq 'PixInsight' }
}

# Ask PixInsight to close, the way the X button of its window does.
function Send-CloseRequest {
   param([string]$Label)
   $p = Get-PixInsight
   if (-not $p) {
      Add-Note "${Label}: PixInsight is not running"
      return
   }
   $p.Refresh()
   $handle = $p.MainWindowHandle
   $sent = $false
   if ($handle -ne [IntPtr]::Zero) { $sent = $p.CloseMainWindow() }
   Add-Note "${Label}: main window $handle, titled '$($p.MainWindowTitle)'; Windows took the request: $sent"
}

# Watch PixInsight for some seconds. Returns after how many seconds it had
# gone, or -1 if it is still running.
function Wait-PixInsightExit {
   param([int]$Seconds)
   for ($t = 0; $t -lt $Seconds * 4; $t++) {
      if (-not (Get-PixInsight)) { return [math]::Round($t / 4.0, 1) }
      Start-Sleep -Milliseconds 250
   }
   return -1
}

try {
   [Environment]::CurrentDirectory = $Dir
   Add-Note "helper started in mode $Mode; process $PID; PixInsight is process $PixInsightPid"
   Start-Sleep -Seconds 6
   if ($Mode -eq 'window') {
      Add-Note ('the script''s window is open: ' + [IO.File]::Exists($windowOpen))
   }
   Send-CloseRequest 'request 1'
   # With an unsaved image a person may be answering PixInsight's question.
   $first = 10
   if ($Mode -eq 'unsaved') { $first = 15 }
   $gone = Wait-PixInsightExit $first
   if ($gone -ge 0) {
      Add-Note "PixInsight exited $gone s after request 1"
   } else {
      Add-Note "PixInsight is still running $first s after request 1"
      if ($Mode -eq 'window') {
         for ($w = 0; $w -lt 160 -and [IO.File]::Exists($windowOpen); $w++) { Start-Sleep -Milliseconds 250 }
         Add-Note ('the script''s window has closed: ' + (-not [IO.File]::Exists($windowOpen)))
         Start-Sleep -Seconds 2
         Add-Note ('PixInsight is running before request 2: ' + [bool](Get-PixInsight))
      }
      Send-CloseRequest 'request 2'
      # With an unsaved image PixInsight waits for an answer. Watch it longer,
      # to see whether it stays open when nobody answers.
      $watch = 10
      if ($Mode -eq 'unsaved') { $watch = 40 }
      $gone = Wait-PixInsightExit $watch
      if ($gone -ge 0) {
         Add-Note "PixInsight exited $gone s after request 2"
      } else {
         Add-Note "PixInsight is still running $watch s after request 2"
      }
   }
} catch {
   try { Add-Note ('E ' + $_.Exception.Message) } catch { }
}
try { Add-Note 'helper finished' } catch { }
