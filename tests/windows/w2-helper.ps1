# PixInsight Update Assistant, Windows test W2: the helper that the probe starts.
#
# It is started by PixInsight in several ways (see w2-probe.js). Each copy:
#   1. writes its process number, and holds a file open so that nobody else
#      can open or delete it for as long as this helper lives;
#   2. logs who started it and whether it has a console window;
#   3. rewrites a small status file ten times a second while PixInsight runs;
#   4. logs when PixInsight has exited, and again ten seconds later.
#
# Line "3" in its log is the proof that it outlived PixInsight.
#
# Windows PowerShell 5.1, plain ASCII.

param([string]$Way = '?', [int]$PixInsightPid = 0, [string]$Dir = '.')

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding $false
$log = Join-Path $Dir "w2-log-$Way.txt"

function Add-Note {
   param([string]$Text)
   [IO.File]::AppendAllText($log, ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $Text + "`n"), $utf8)
}

function Test-PixInsight {
   return [bool](Get-Process -Id $PixInsightPid -ErrorAction SilentlyContinue |
      Where-Object { $_.ProcessName -eq 'PixInsight' })
}

try {
   [IO.File]::WriteAllText((Join-Path $Dir "w2-pid-$Way.txt"), "$PID`n", $utf8)
   $lock = [IO.File]::Open((Join-Path $Dir "w2-lock-$Way"), [IO.FileMode]::OpenOrCreate,
      [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

   $me = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
   $parentName = (Get-Process -Id $me.ParentProcessId -ErrorAction SilentlyContinue).ProcessName
   Add-Note ("1 helper started; process $PID; parent $($me.ParentProcessId) ($parentName); current folder " +
      [Environment]::CurrentDirectory + '; sees PI_UA_W_OUT: ' + [bool]$env:PI_UA_W_OUT)

   $native = Add-Type -Name W2Native -Namespace UA -PassThru -MemberDefinition (
      '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); ' +
      '[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);')
   $h = $native::GetConsoleWindow()
   if ($h -eq [IntPtr]::Zero) {
      Add-Note '  console window: none'
   } else {
      Add-Note ('  console window: exists; visible now: ' + $native::IsWindowVisible($h))
   }

   # The status file, replaced in one step each time, as the real helper will.
   $status = Join-Path $Dir "w2-status-$Way"
   $tmp = $status + '.tmp'
   $failed = 0
   $n = 0
   while ($n -lt 300 -and (Test-PixInsight)) {
      try {
         [IO.File]::WriteAllText($tmp, "phase=testing`ncount=$n`nhelper=$PID`nend=1`n", $utf8)
         if ([IO.File]::Exists($status)) {
            [IO.File]::Replace($tmp, $status, [NullString]::Value)
         } else {
            [IO.File]::Move($tmp, $status)
         }
      } catch {
         $failed++
      }
      $n++
      Start-Sleep -Milliseconds 100
   }
   Add-Note "  status written $n times; $failed of them failed"

   $waited = 0
   while ((Test-PixInsight) -and $waited -lt 480) {
      Start-Sleep -Milliseconds 500
      $waited++
   }
   if (Test-PixInsight) {
      Add-Note 'X gave up: PixInsight is still running'
   } else {
      $me = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
      Add-Note "2 PixInsight exited; my parent's number is still $($me.ParentProcessId)"
      Start-Sleep -Seconds 10
      Add-Note '3 helper still running ten seconds later'
   }
   $lock.Close()
} catch {
   try { Add-Note ('E ' + $_.Exception.Message) } catch { }
}
