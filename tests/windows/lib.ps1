# PixInsight Update Assistant: shared pieces of the Windows test runners.
#
# Windows PowerShell 5.1. This file is plain ASCII on purpose: PowerShell 5.1
# reads a file without a byte-order mark in the system's own encoding.
#
# Use it from a runner with:   . "$PSScriptRoot\lib.ps1"

$ErrorActionPreference = 'Stop'

# The project folder, and where the Windows tests write their results.
# tests\out\ is not committed.
$UA_Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$UA_Out  = Join-Path $UA_Root 'tests\out\windows'

# The installed PixInsight program, or nothing. The environment variable
# PI_UA_EXE overrides the search.
function Get-PixInsightExe {
   if ($env:PI_UA_EXE) { return $env:PI_UA_EXE }
   $candidates = @()
   foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
      Get-ItemProperty $key -ErrorAction SilentlyContinue |
         Where-Object { $_.DisplayName -eq 'PixInsight' -and $_.InstallLocation } |
         ForEach-Object { $candidates += (Join-Path $_.InstallLocation 'bin\PixInsight.exe') }
   }
   $candidates += 'C:\Program Files\PixInsight\bin\PixInsight.exe'
   foreach ($c in $candidates) {
      if (Test-Path -LiteralPath $c) { return $c }
   }
   return $null
}

function Test-PixInsightRunning {
   return [bool](Get-Process -Name 'PixInsight' -ErrorAction SilentlyContinue)
}

# A path in the form PixInsight itself uses: forward slashes.
function ConvertTo-SlashPath {
   param([string]$Path)
   return ($Path -replace '\\', '/')
}

# The option that keeps a background PixInsight from taking the keyboard,
# --no-focus-stealing, exists from PixInsight 1.9.5 on. PixInsight 1.9.4 shows
# an error and does not start when it is given an option it does not know, so
# for an earlier PixInsight the option is left out, and that PixInsight comes
# to the front each time it opens.
function Get-FocusOption {
   param([string]$Exe)
   try {
      $known = "$((Get-Item -LiteralPath $Exe).VersionInfo.FileVersion)"
      if ([version]$known -ge [version]'1.9.5') { return ' --no-focus-stealing' }
   } catch { }
   return ''
}

# Start a second, separate PixInsight that runs one script. It opens in
# automation mode (fewer messages, no settings saved) and, where PixInsight
# knows the option, is asked not to take the keyboard. Unless -Stay is given
# it leaves by itself after the script.
# With -Normal it opens as an ordinary session, which shows PixInsight's own
# questions and stays open; only its splash picture and its check for updates
# are left out.
# Returns the process that was started.
function Start-PixInsightScript {
   param([string]$Exe, [string]$Script, [switch]$Stay, [switch]$Normal)
   # Start-Process joins arguments with spaces and adds no quotes, so the
   # quotes around the path are written here.
   $focus = Get-FocusOption $Exe
   if ($Normal) {
      $line = ('-n --no-splash --no-startup-check-updates' + $focus + ' -r="{0}"') -f (ConvertTo-SlashPath $Script)
   } else {
      $line = ('-n --automation-mode' + $focus + ' -r="{0}"') -f (ConvertTo-SlashPath $Script)
      if (-not $Stay) { $line += ' --force-exit' }
   }
   # A PowerShell that was started with -ExecutionPolicy Bypass, as the test
   # runners are, hands that switch on to every program it starts, in an
   # environment variable. A PixInsight that a person opens from the Start
   # menu has no such variable. So it is taken out for this start: a helper
   # that PixInsight starts then has to get by on the switch in its own
   # starter file, as it must in real use.
   $handedOn = $env:PSExecutionPolicyPreference
   Remove-Item Env:PSExecutionPolicyPreference -ErrorAction SilentlyContinue
   try {
      $p = Start-Process -FilePath $Exe -ArgumentList $line -PassThru
   } finally {
      if ($handedOn) { $env:PSExecutionPolicyPreference = $handedOn }
   }
   # Without this, PowerShell 5.1 cannot tell the exit code later.
   $null = $p.Handle
   return $p
}

# Wait until one of the files exists. Returns the one that came, or nothing.
function Wait-ForFile {
   param([string[]]$Path, [int]$Seconds)
   $until = (Get-Date).AddSeconds($Seconds)
   while ((Get-Date) -lt $until) {
      foreach ($f in $Path) {
         if (Test-Path -LiteralPath $f) { return $f }
      }
      Start-Sleep -Milliseconds 500
   }
   return $null
}

# The text of a small file that PixInsight wrote: UTF-8, any line ends.
function Get-ResultText {
   param([string]$Path)
   return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

# One sentence from the add-on's table of wording,
# src\UpdateAssistant-wording.jsh, by its name there.
function Get-Wording {
   param([string]$Name)
   $table = [IO.File]::ReadAllText((Join-Path $UA_Root 'src\UpdateAssistant-wording.jsh'), [Text.Encoding]::UTF8)
   $m = [regex]::Match($table, '(?m)^\s*' + [regex]::Escape($Name) + ':\s*"(.*)",?\s*$')
   if ($m.Success) { return $m.Groups[1].Value.Replace('\"', '"') }
   return ''
}

# One value from a file of lines "key=value". Empty if the key is missing.
function Get-ResultValue {
   param([string]$Path, [string]$Key)
   foreach ($line in ((Get-ResultText $Path) -split "`r?`n")) {
      if ($line.StartsWith($Key + '=')) { return $line.Substring($Key.Length + 1) }
   }
   return ''
}
