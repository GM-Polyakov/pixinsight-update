# PixInsight Update Assistant: the rehearsal on Windows.
#
# Rehearses the whole update without touching the real PixInsight folder and
# without contacting pixinsight.com. It is the Windows counterpart of
# tests\run-rehearsal.sh.
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-rehearsal.ps1             every case
#    powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-rehearsal.ps1 now later   only these cases
#
# What is real:      PixInsight itself, the add-on as built, the helper,
#                    curl.exe, the close request, the reopening.
# What is stand-in:  the download service (tests\standin\dist-server.py, with
#                    a made-up account), the installer (tests\windows\standin\),
#                    the PixInsight folder and the Downloads folder (both made
#                    in the temporary folder). Nothing asks for administrator
#                    rights.
# No windows are shown, except in two cases: "windows" opens both windows of
# the add-on for a second, and "window" keeps the progress window open.
# Everywhere else the add-on and the helper take their answers from the
# rehearsal's settings, and write down what they would have shown.
#
# PixInsight opens and closes once or twice in most cases, about twenty times
# in all. It is opened in the background and asked not to take the keyboard.
# Do not run this while you are using PixInsight: the runner refuses to start
# while a PixInsight is running, and it never closes a PixInsight that it did
# not start.
#
# Needs: PixInsight closed, Python for the stand-in service, and Git Bash,
# because the build is a shell script.
#
# Cases: now, later, window, cancel, interrupted, broken, installfail, gone,
#        declined, ownfiles, refused, uptodate, offline, windows,
#        and three that run the helper alone, without PixInsight:
#        noreopen, unsigned, genuine
#
# The stand-in download page offers a made-up version, 9.9.9, so that there is
# something to update to whatever PixInsight this computer has.
#
# With the environment variable VERBOSE set to 1, the runner also prints the
# files that each case looks at.
#
# Output: the logs of each case are kept in tests\out\windows\rehearsal-logs\<case>\
# Exit code: 0 every check passed, 1 a check failed, 2 nothing could be started.
#
# Windows PowerShell 5.1, plain ASCII.

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Case)

. "$PSScriptRoot\lib.ps1"

$allCases = 'now', 'later', 'window', 'cancel', 'interrupted', 'broken', 'installfail', 'gone', 'declined',
            'ownfiles', 'refused', 'uptodate', 'offline', 'windows', 'noreopen', 'unsigned', 'genuine'
# The cases that need the stand-in download service, and with it Python.
$serviceCases = 'now', 'later', 'window', 'cancel', 'interrupted', 'broken', 'installfail', 'gone', 'declined',
                'ownfiles', 'refused', 'uptodate'
if (-not $Case) { $Case = $allCases }

# Everything the rehearsal makes lies in the temporary folder. The project
# folder's path can be too long for the build's output, which lies several
# folders deep (TESTING.md, the Windows trap 16).
$out = Join-Path $env:TEMP 'PixInsightUpdateAssistant-rehearsal'
$control = Join-Path $out 'control'
# The stand-in PixInsight folder. The space in its path is on purpose, because
# the real folder has one.
$folder = Join-Path $out 'Program Files\PixInsight'
$downloads = Join-Path $out 'Downloads'
$serverLog = Join-Path $out 'standin-server.log'
# The working folder of the add-on, the same one as in real use.
$work = Join-Path $env:TEMP 'PixInsightUpdateAssistant'
$dist = Join-Path $env:TEMP 'PixInsightUpdateAssistant-dist'
$scriptUnderTest = Join-Path $dist 'stage\src\scripts\UpdateAssistant\UpdateAssistant.js'
$keepRoot = Join-Path $UA_Out 'rehearsal-logs'

$port = 8719
$sizeMb = 8
# The made-up newer version that the stand-in download page offers, and the
# installer that the add-on must choose for it.
$new = '9.9.9'
$installerName = "PI-windows-x64-gpu-$new-20991231-c.exe"
$utf8 = New-Object Text.UTF8Encoding $false
$began = Get-Date
$showFiles = ($env:VERBOSE -eq '1')

$passed = 0
$failed = 0
# Set when a case could not be started. The run ends there.
$refusal = ''
$caseName = ''
# The PixInsight and the stand-in service that the case under way has started.
$pix = $null
$server = $null

# -----------------------------------------------------------------------------
# Small things
# -----------------------------------------------------------------------------

function Add-Check {
   param([string]$What, [bool]$Good)
   if ($Good) { $script:passed++; "   pass  $What" } else { $script:failed++; "   FAIL  $What" }
}

# The text of a file, or nothing if it cannot be read.
#
# The helper and the stand-in service are still writing their logs while the
# runner reads them, and the helper keeps replacing its status. On Windows the
# plain way of reading a file locks every writer out for the moment of the
# read. A helper that cannot add a line to its log at that moment would stop,
# and so would a request to the stand-in service. So the file is opened in the
# way that lets everybody else go on writing, replacing and deleting it, and a
# read that fails is tried again.
function Get-FileText {
   param([string]$Path)
   for ($try = 0; $try -lt 5; $try++) {
      try {
         $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
            ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
         try {
            return (New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)).ReadToEnd()
         } finally {
            $stream.Close()
         }
      } catch {
         Start-Sleep -Milliseconds 40
      }
   }
   return ''
}

# True if the file holds the text. The text is looked for as it stands, with
# regard to case, and never as a pattern.
function Test-FileText {
   param([string]$Path, [string]$Text)
   return (Get-FileText $Path).Contains($Text)
}

# Wait until the condition comes true. Returns whether it did.
function Wait-Until {
   param([int]$Seconds, [scriptblock]$Condition)
   $deadline = (Get-Date).AddSeconds($Seconds)
   while ((Get-Date) -lt $deadline) {
      if (& $Condition) { return $true }
      Start-Sleep -Milliseconds 250
   }
   return [bool](& $Condition)
}

# With VERBOSE set to 1: print a file that a case looks at, so that a failed
# check can be understood. The path of the user's own folder is shortened.
function Show-File {
   param([string]$Path)
   if (-not $showFiles) { return }
   "   --- $(Split-Path -Leaf $Path)"
   foreach ($line in ((Get-FileText $Path) -split "`r?`n")) {
      if (-not $line) { continue }
      $line = $line.Replace($env:USERPROFILE, '~').Replace((ConvertTo-SlashPath $env:USERPROFILE), '~')
      if ($line.Length -gt 200) { $line = $line.Substring(0, 200) }
      "   | $line"
   }
}

# Remove a folder with everything in it. A program that has just ended can
# keep a file busy for a moment, so the removal is tried for five seconds.
# Returns whether the folder is gone.
function Remove-Folder {
   param([string]$Path)
   for ($try = 0; $try -lt 20 -and (Test-Path -LiteralPath $Path); $try++) {
      try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 250 }
   }
   return (-not (Test-Path -LiteralPath $Path))
}

# Many parts of Windows refuse a path of 260 characters or more unless it is
# written in this longer form. The logs are kept inside the project folder,
# whose own path can be long, so the form is used for a folder whose path
# leaves too little room for the names of the files in it.
function ConvertTo-LongPath {
   param([string]$Path)
   if ($Path.Length -ge 200 -and $Path -match '^[A-Za-z]:\\') { return '\\?\' + $Path }
   return $Path
}

# The installed version as the add-on writes it: major.minor.release, and the
# revision after a hyphen only when it is above 0. PixInsight.exe carries the
# numbers as its product version.
function Get-InstalledVersion {
   param([string]$Exe)
   $text = [string](Get-Item -LiteralPath $Exe).VersionInfo.ProductVersion
   $m = [regex]::Match($text, '^\s*(\d+)\.(\d+)\.(\d+)(?:[-.](\d+))?')
   if (-not $m.Success) { return $text.Trim() }
   $version = '{0}.{1}.{2}' -f [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value
   if ($m.Groups[4].Success -and [int]$m.Groups[4].Value -gt 0) { $version += '-' + [int]$m.Groups[4].Value }
   return $version
}

# True if a program on this computer answers on the stand-in service's port.
function Test-ServicePort {
   $tcp = New-Object Net.Sockets.TcpClient
   try {
      $tcp.Connect('127.0.0.1', $port)
      return $true
   } catch {
      return $false
   } finally {
      $tcp.Close()
   }
}

# The helpers of the rehearsal that are running now: PowerShell processes
# whose command line names helper.ps1 in the working folder. The folder is
# recognised by its last part, because the temporary folder in front of it
# can be written in more than one way.
function Get-HelperProcess {
   $needle = '\PixInsightUpdateAssistant\helper.ps1'
   $found = @()
   try {
      $found = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
         $_.CommandLine -and $_.CommandLine.Replace('/', '\').IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
   } catch {
   }
   return $found
}

# Stop the helpers that an earlier case left running, each with the download
# it has under way. The download tool's command line names no folder, so it is
# found as a child of its helper.
function Stop-LeftoverHelper {
   foreach ($helper in @(Get-HelperProcess)) {
      try {
         Get-CimInstance Win32_Process -Filter "Name='curl.exe' AND ParentProcessId=$($helper.ProcessId)" |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
      } catch {
      }
      Stop-Process -Id $helper.ProcessId -Force -ErrorAction SilentlyContinue
   }
}

# One sentence from the add-on's table of wording, with its %1 and %2 filled
# in. If the table has no sentence of that name, what comes back can match
# nothing, so that the check that uses it fails instead of passing on an
# empty text.
function Get-Sentence {
   param([string]$Name, [string]$First = '', [string]$Second = '')
   $sentence = Get-Wording $Name
   if (-not $sentence) { return "(the table of wording has no sentence named $Name)" }
   return $sentence.Replace('%1', $First).Replace('%2', $Second)
}

# The last line of a file that holds anything.
function Get-LastLine {
   param([string]$Path)
   $lines = @((Get-FileText $Path) -split "`r?`n" | Where-Object { $_ })
   if ($lines.Count -eq 0) { return '' }
   return $lines[-1]
}

# -----------------------------------------------------------------------------
# What every case needs
# -----------------------------------------------------------------------------

# The files that the cases look at.
$result = Join-Path $control 'script-result.txt'
$log = Join-Path $work 'log.txt'
$statusFile = Join-Path $work 'status'
$shownFile = Join-Path $work 'message-shown.txt'
$versionFile = Join-Path $folder 'bin\version.txt'
$oldAddon = Join-Path $folder 'bin\OldAddon-pxm.dll'
$noResult = 'PixInsight ran the add-on''s script, which wrote its result'
# Set once a case has begun to change things, so that its end has work to do.
$prepared = $false

# The stand-in PixInsight folder as it is before an update: a program file
# that is never run, the module of an add-on, and a note of the version.
# The note lies in bin and not at the top of the folder, because the add-on
# refuses to update a PixInsight folder that has anything at its top that is
# not PixInsight's own. The stand-in installers know the folder by this note.
function New-StandinFolder {
   [void][IO.Directory]::CreateDirectory((Join-Path $folder 'bin'))
   [IO.File]::WriteAllText((Join-Path $folder 'bin\PixInsight.exe'), "a stand-in for the PixInsight program`n")
   [IO.File]::WriteAllText($oldAddon, "a module of an add-on, built for the old version`n")
   [IO.File]::WriteAllText($versionFile, "old version (stand-in)`n")
}

function Stop-StandinService {
   if ($script:server) {
      if (-not $script:server.HasExited) { Stop-Process -Id $script:server.Id -Force -ErrorAction SilentlyContinue }
      $script:server = $null
   }
   # Where Python is started through a launcher, the service runs as a child
   # of the program that was started here. So it is also looked for by its
   # command line, among the programs that started after this runner.
   try {
      $left = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'python%'" | Where-Object {
         $_.CommandLine -and $_.CommandLine.Contains('dist-server.py') -and
         $_.CommandLine.Contains("--port $port ") -and $_.CreationDate -ge $began })
      foreach ($process in $left) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue }
   } catch {
   }
}

# Start the stand-in download service with the case's own options and wait
# until it answers. With -NothingNewer its page does not offer the made-up
# newer version. Returns whether the service answers.
function Start-StandinService {
   param([string[]]$Options, [switch]$NothingNewer)
   # An answer from another program, or from a service that an earlier case
   # left running, would make the case test the wrong thing.
   if (-not (Wait-Until 6 { -not (Test-ServicePort) })) {
      $script:refusal = "Something already answers on port $port of this computer."
      return $false
   }
   $line = '-I "{0}" --port {1} --layout real --cdn other --refuse-curl' -f (Join-Path $UA_Root 'tests\standin\dist-server.py'), $port
   if ($NothingNewer) { $line += " --only-version $have" } else { $line += " --newest $new" }
   $line += ' --size-mb {0} --log "{1}"' -f $sizeMb, $serverLog
   if ($Options) { $line += ' ' + ($Options -join ' ') }
   $script:server = Start-Process -FilePath $python -ArgumentList $line -WindowStyle Hidden -PassThru

   # Wait until it answers, and make sure that the answer is the stand-in's.
   $answers = $false
   $deadline = (Get-Date).AddSeconds(30)
   while (-not $answers -and (Get-Date) -lt $deadline -and -not $script:server.HasExited) {
      try {
         $request = [Net.WebRequest]::Create("http://127.0.0.1:$port/dist/")
         $request.UserAgent = 'rehearsal-runner'
         $request.Timeout = 2000
         # No proxy: the request must go to this computer and nowhere else.
         $request.Proxy = New-Object Net.WebProxy
         $response = $request.GetResponse()
         $page = (New-Object IO.StreamReader $response.GetResponseStream()).ReadToEnd()
         $response.Close()
         $answers = $page.Contains('user_password')
      } catch {
         Start-Sleep -Milliseconds 250
      }
   }
   if (-not $answers) {
      $script:refusal = 'The stand-in download service did not start.'
      return $false
   }
   return $true
}

# Make everything ready for one case: no helper left over, the folders of the
# rehearsal made anew, and the stand-in service running unless -NoService is
# given. Returns whether the case can start. If it cannot, the reason is in
# $refusal and the run ends.
function Initialize-Case {
   param([string[]]$Service, [switch]$NoService, [switch]$NothingNewer)
   $script:pix = $null
   # A PixInsight that is open now was not opened by the rehearsal. The cases
   # would mistake it for their own, so nothing is started beside it.
   if (Test-PixInsightRunning) {
      $script:refusal = 'PixInsight is running. Close it, then run the rehearsal again.'
      return $false
   }
   $script:prepared = $true
   Stop-LeftoverHelper
   if (-not (Remove-Folder $out) -or -not (Remove-Folder $work)) {
      $script:refusal = 'A folder that an earlier run left in the temporary folder could not be removed.'
      return $false
   }
   [void][IO.Directory]::CreateDirectory($control)
   [void][IO.Directory]::CreateDirectory($downloads)
   New-StandinFolder
   if ($NoService) { return $true }
   return (Start-StandinService -Options $Service -NothingNewer:$NothingNewer)
}

# Open PixInsight in the background with the add-on's script and the given
# settings, and wait for the file that the script writes at its end. A
# variable in the runner's environment is inherited by PixInsight and, through
# it, by the helper. The settings are taken out of the runner's environment
# again as soon as PixInsight has started. Returns whether the file came.
function Start-RehearsalPixInsight {
   param([hashtable]$Settings, [string]$Written)
   foreach ($name in $Settings.Keys) { [Environment]::SetEnvironmentVariable($name, [string]$Settings[$name], 'Process') }
   try {
      $script:pix = Start-PixInsightScript -Exe $exe -Script $scriptUnderTest -Stay
   } finally {
      foreach ($name in $Settings.Keys) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
   }
   $came = [bool](Wait-ForFile -Path (Join-Path $control $Written) -Seconds 180)
   # A moment more, so that the file is not read while it is being written.
   Start-Sleep -Milliseconds 300
   return $came
}

# Start an update as a rehearsal: the script signs in to the stand-in service
# with the made-up account and, if the page offers something newer, starts the
# helper. Paths are written with forward slashes, as PixInsight writes them.
# "More" holds further settings of a case. Returns whether the script wrote
# its result.
function Start-Update {
   param([string]$Password, [string]$Answer, [string]$Installer, [hashtable]$More = @{})
   $settings = @{
      PI_UA_TEST_DIR         = ConvertTo-SlashPath $control
      PI_UA_BASE             = "http://127.0.0.1:$port/dist/"
      PI_USER                = 'standin-user'
      PI_PASS                = $Password
      PI_UA_TEST_INSTALL_DIR = ConvertTo-SlashPath $folder
      PI_UA_TEST_INSTALLER   = ConvertTo-SlashPath (Join-Path $PSScriptRoot "standin\$Installer")
      PI_UA_TEST_SIGNATURE   = 'accept'
      PI_UA_TEST_DOWNLOADS   = ConvertTo-SlashPath $downloads
      PI_UA_TEST_QUIET       = '1'
      PI_UA_TEST_ANSWER      = $Answer
   }
   foreach ($name in $More.Keys) { $settings[$name] = $More[$name] }
   return (Start-RehearsalPixInsight $settings 'script-result.txt')
}

# Pick the add-on's menu item again in the PixInsight that is open. A second
# start of the program with -x= hands the script to the open PixInsight and
# ends by itself. What the script is to do this time is in action.txt.
# With -NoWait the runner goes on at once, because the script opens a window
# that stays open.
function Invoke-Again {
   param([string]$Action, [switch]$NoWait)
   [IO.File]::WriteAllText((Join-Path $control 'action.txt'), "$Action`n")
   $second = Start-Process -FilePath $exe -ArgumentList ('-x="{0}"' -f (ConvertTo-SlashPath $scriptUnderTest)) -PassThru
   if ($NoWait) { return }
   [void](Wait-ForFile -Path (Join-Path $control "script-result-$Action.txt") -Seconds 60)
   [void]$second.WaitForExit(15000)
   # A moment more, so that the file is not read while it is being written.
   Start-Sleep -Milliseconds 300
}

# Ask a PixInsight to close the way its user does: with the request that the X
# button of its window sends. PixInsight ignores the request while a script is
# busy in it and does not remember it, so it is sent again every five seconds
# until PixInsight has gone or the time is up. --terminate cannot stand for
# the user here, because it opens a window on Windows. Returns whether
# PixInsight has gone.
function Send-CloseRequest {
   param([System.Diagnostics.Process]$Process, [int]$Seconds)
   $deadline = (Get-Date).AddSeconds($Seconds)
   while (-not $Process.HasExited -and (Get-Date) -lt $deadline) {
      try {
         $Process.Refresh()
         [void]$Process.CloseMainWindow()
      } catch {
      }
      if ($Process.WaitForExit(5000)) { break }
   }
   return $Process.HasExited
}

# Wait until the reopened PixInsight has shown its closing message, and then
# until the helper has written its last line. PixInsight starts more slowly
# than the helper takes to see that it has stayed up. The wait ends early
# when nothing more can come: the helper has finished and no PixInsight has
# been running for ten seconds.
function Wait-ForEnd {
   $deadline = (Get-Date).AddSeconds(150)
   $idleSince = $null
   while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $shownFile)) {
      if ((Test-FileText $log 'helper finished') -and -not (Test-PixInsightRunning)) {
         if (-not $idleSince) { $idleSince = Get-Date }
         if (((Get-Date) - $idleSince).TotalSeconds -ge 10) { break }
      } else {
         $idleSince = $null
      }
      Start-Sleep -Milliseconds 500
   }
   [void](Wait-Until 30 { Test-FileText $log 'helper finished' })
}

# The names of the files under the working folder and the control folder that
# hold one of the texts. A file that cannot be read, as the one the helper
# holds open for itself, counts as holding nothing.
function Find-Text {
   param([string[]]$Text)
   $found = @()
   foreach ($dir in $work, $control) {
      if (-not (Test-Path -LiteralPath $dir)) { continue }
      foreach ($file in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force)) {
         # A download that is still there is no note, and far too large to read.
         if ($file.Length -gt 64MB) { continue }
         $content = Get-FileText $file.FullName
         foreach ($t in $Text) {
            if ($content.Contains($t)) { $found += $file.Name; break }
         }
      }
   }
   return $found
}

# What is checked after every case that started the helper from PixInsight.
function Add-CommonCheck {
   Add-Check 'the helper deleted the file with the installer''s address and cookie' (-not (Test-Path -LiteralPath (Join-Path $work 'job.conf')))
   Add-Check 'the downloaded installer is no longer in the working folder' (-not (Test-Path -LiteralPath (Join-Path $work $installerName)))
   Add-Check 'the download tool''s instructions, which held the address and the cookie, are gone' (-not (Test-Path -LiteralPath (Join-Path $work 'curl-instructions')))
   $found = @(Find-Text 'standin-user', 'standin-pass')
   Add-Check 'neither the made-up user name nor the password is in any file the add-on left' ($found.Count -eq 0)
   if ($found.Count) { "      found in: $($found -join ', ')" }
   $found = @(Find-Text 'session_id=', 'PHPSESSID')
   Add-Check 'no session value or cookie is in any file the add-on left' ($found.Count -eq 0)
   if ($found.Count) { "      found in: $($found -join ', ')" }
   Add-Check 'the sign-out link was not followed' (-not (Test-FileText $serverLog 'LOGOUT LINK FOLLOWED'))
}

# Close every PixInsight that this run opened and that is still open: the one
# the case started, one that the helper reopened, and a second start that has
# not ended. They are known by their command line, which names a script in one
# of the rehearsal's folders, and by having started after this runner. Any
# other PixInsight is left alone.
function Stop-RehearsalPixInsight {
   $ids = @()
   if ($script:pix -and -not $script:pix.HasExited) { $ids += $script:pix.Id }
   $marked = @()
   try {
      $marked = @(Get-CimInstance Win32_Process -Filter "Name='PixInsight.exe'" | Where-Object {
         $_.CommandLine -and $_.CommandLine.Contains('PixInsightUpdateAssistant') -and $_.CreationDate -ge $began })
   } catch {
   }
   foreach ($one in $marked) {
      if ($ids -notcontains [int]$one.ProcessId) { $ids += [int]$one.ProcessId }
   }
   foreach ($id in $ids) {
      $process = Get-Process -Id $id -ErrorAction SilentlyContinue
      if (-not $process) { continue }
      $closed = $false
      try { $closed = Send-CloseRequest $process 20 } catch { }
      if (-not $closed) {
         Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
         # Stopping a process only asks Windows to end it. The process stays
         # on the list of processes until it has been taken apart, and the
         # next case refuses to start while a PixInsight is on that list. So
         # the runner waits here, for ten seconds at most, until this one has
         # gone.
         try { [void]$process.WaitForExit(10000) } catch { }
         '   (a PixInsight that the rehearsal had opened did not close on request; its process was stopped)'
      }
   }
   $script:pix = $null
}

# Keep what the add-on, the helper and the stand-in service wrote, so that a
# failed case can be understood later.
function Save-CaseLog {
   $keep = ConvertTo-LongPath (Join-Path $keepRoot $script:caseName)
   try {
      if ([IO.Directory]::Exists($keep)) { [IO.Directory]::Delete($keep, $true) }
      [void][IO.Directory]::CreateDirectory($keep)
      $files = @()
      if (Test-Path -LiteralPath $work) {
         $files += @(Get-ChildItem -LiteralPath $work -File | Where-Object { $_.Extension -eq '.txt' -or $_.Name -eq 'status' })
      }
      if (Test-Path -LiteralPath $control) { $files += @(Get-ChildItem -LiteralPath $control -File -Filter '*.txt') }
      if (Test-Path -LiteralPath $serverLog) { $files += @(Get-Item -LiteralPath $serverLog) }
      foreach ($file in $files) { [IO.File]::Copy($file.FullName, ($keep + '\' + $file.Name), $true) }
   } catch {
      "   (the logs of this case could not be kept: $($_.Exception.Message))"
   }
}

# The end of every case, whether it went well or not: stop what the case
# started, keep what was written, and remove the working folder.
function Complete-Case {
   if (-not $script:prepared) { return }
   $script:prepared = $false
   # The helpers go first. One that is still waiting for PixInsight to close
   # would start to install at the moment PixInsight is closed below. A step
   # that fails must not keep the others from being done.
   foreach ($step in 'Stop-LeftoverHelper', 'Stop-RehearsalPixInsight', 'Stop-StandinService', 'Save-CaseLog') {
      try { & $step } catch { "   (while tidying up after the case: $($_.Exception.Message))" }
   }
   [void](Remove-Folder $work)
}

# -----------------------------------------------------------------------------
# The cases that start the helper from PixInsight
# -----------------------------------------------------------------------------

function Test-CaseNow {
   ''
   '== now: sign in, download, restart now, install, reopen =='
   if (-not (Initialize-Case)) { return }
   # The version before the update is given as 1.9.2, so that the reopened
   # PixInsight, which is the real one and unchanged, counts as updated.
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer.ps1' @{ PI_UA_TEST_OLD = '1.9.2' })) { Add-Check $noResult $false; return }
   Show-File $result
   Add-Check 'sign-in accepted' (Test-FileText $result 'signin=ok')
   Add-Check "newest version read from the page: $new" (Test-FileText $result "newest=$new")
   Add-Check 'the add-on took this computer for an x64 one' (Test-FileText $result 'chip=x64')
   Add-Check 'the installer for Windows was chosen' (Test-FileText $result "file=$installerName")
   $started = Get-Sentence 'started' $new "$sizeMb MB"
   Add-Check 'the last thing shown is that the download runs in the background, and nothing more' ((Get-LastLine $result) -ceq "shown=$started")
   Wait-ForEnd
   Show-File $log
   Show-File $shownFile
   Add-Check 'PixInsight was reopened and said which version is running' (Test-FileText $shownFile (Get-Sentence 'done' $have))
   Add-Check 'the helper noticed that PixInsight had closed' (Test-FileText $log 'PixInsight has closed')
   Add-Check 'the installer ran and reported success' (Test-FileText $log 'installer ended with code 0')
   Add-Check 'the helper found the new PixInsight in place' (Test-FileText $log 'result: installed')
   Add-Check 'the helper made sure that PixInsight had reopened' (Test-FileText $log 'PixInsight has reopened')
   Add-Check 'the new version is in place' (Test-FileText $versionFile 'new version')
   Add-Check 'the old add-on module is gone, as after a real installation' (-not (Test-Path -LiteralPath $oldAddon))
   Add-Check 'the download was fetched by the helper under the add-on''s own name' (Test-FileText $serverLog 'agent=PixInsightUpdateAssistant/')
   Add-Check 'the download went through the file host' (Test-FileText $serverLog 'download redirected')
   Add-CommonCheck
   $none = Wait-Until 40 { -not (Test-PixInsightRunning) }
   Add-Check 'no PixInsight is left running: the reopened one closed itself, as it does in a rehearsal' $none
}

function Test-CaseLater {
   ''
   '== later: install only when the user quits PixInsight =='
   if (-not (Initialize-Case)) { return }
   if (-not (Start-Update 'standin-pass!1' 'later' 'installer.ps1')) { Add-Check $noResult $false; return }
   $waits = Wait-Until 60 { Test-FileText $statusFile 'phase=waiting' }
   Add-Check 'after the download the helper waits' $waits
   Add-Check 'nothing is installed while PixInsight is open' (Test-FileText $versionFile 'old version')
   Invoke-Again 'status'
   $again = Join-Path $control 'script-result-status.txt'
   Show-File $again
   Add-Check 'picking the menu item again shows that the update is waiting' (Test-FileText $again ('status_text=' + (Get-Sentence 'waiting' $new)))
   Add-Check 'PixInsight is still open' (-not $script:pix.HasExited)
   # The user quits PixInsight.
   [void](Send-CloseRequest $script:pix 30)
   Wait-ForEnd
   Show-File $log
   Show-File $shownFile
   Add-Check 'once PixInsight was closed, the new version was installed' (Test-FileText $versionFile 'new version')
   # True: the PixInsight that reopens is the real one, which no stand-in replaced.
   Add-Check 'the reopened PixInsight said truthfully that it is still the old one' (Test-FileText $shownFile (Get-Sentence 'notUpdated' $have))
   Add-CommonCheck
   [void](Wait-Until 40 { -not (Test-PixInsightRunning) })
}

function Test-CaseWindow {
   ''
   '== window: Restart Now is chosen while the progress window is open in PixInsight =='
   if (-not (Initialize-Case -Service '--slow-ms', '150')) { return }
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer.ps1')) { Add-Check $noResult $false; return }
   [void](Wait-Until 20 { Test-FileText $statusFile 'phase=downloading' })
   # Pick the menu item again. The progress window opens, and nobody closes it.
   Invoke-Again 'progress' -NoWait
   $open = Wait-Until 20 { Test-Path -LiteralPath (Join-Path $work 'window-open') }
   Add-Check 'the progress window is open in PixInsight while the download runs' $open
   $answered = Wait-Until 90 { Test-FileText $log 'answer: now' }
   Start-Sleep -Seconds 2
   Add-Check 'Restart Now was chosen' $answered
   Add-Check 'the window was open then, and the helper saw it' (Test-FileText $log 'a window of the add-on is open in PixInsight')
   $closed = Wait-Until 60 { Test-FileText $log 'PixInsight has closed' }
   Add-Check 'PixInsight closed at the helper''s request' $closed
   $again = Join-Path $control 'script-result-progress.txt'
   if (-not $closed) {
      Show-File $log
      Show-File $statusFile
      '   (PixInsight stayed open with the window. Leaving the case here.)'
      return
   }
   Show-File $again
   Show-File $log
   Add-Check 'the window had closed by itself, because PixInsight was about to be asked to quit' (Test-FileText $again 'closed_by=restart')
   Wait-ForEnd
   Add-Check 'the update then went through' (Test-FileText $versionFile 'new version')
   Add-CommonCheck
   [void](Wait-Until 40 { -not (Test-PixInsightRunning) })
}

function Test-CaseCancel {
   ''
   '== cancel: stop the update during the download =='
   if (-not (Initialize-Case -Service '--slow-ms', '200')) { return }
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer.ps1')) { Add-Check $noResult $false; return }
   [void](Wait-Until 20 { Test-FileText $statusFile 'phase=downloading' })
   Start-Sleep -Seconds 3
   Invoke-Again 'cancel'
   $again = Join-Path $control 'script-result-cancel.txt'
   Show-File $again
   Add-Check 'picking the menu item again shows the progress of the download' (Test-FileText $again "status_text=Downloading PixInsight ${new}:")
   Add-Check 'after cancelling the user is told that nothing was changed' (Test-FileText $again ('shown=' + (Get-Sentence 'stopped')))
   $gone = Wait-Until 20 { -not (Test-Path -LiteralPath $statusFile) }
   Add-Check 'the helper took its status away' $gone
   $ended = Wait-Until 15 { @(Get-HelperProcess).Count -eq 0 }
   Show-File $log
   Add-Check 'the helper stopped' $ended
   Add-Check 'the partial download was removed' (-not (Test-Path -LiteralPath (Join-Path $work $installerName)))
   Add-Check 'the PixInsight folder is untouched' (Test-Path -LiteralPath $oldAddon)
   Add-Check 'PixInsight is still open' (-not $script:pix.HasExited)
   Add-CommonCheck
}

function Test-CaseInterrupted {
   ''
   '== interrupted: the download breaks off once, and Try Again continues it =='
   if (-not (Initialize-Case -Service '--drop-first-mb', '3')) { return }
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer.ps1' @{ PI_UA_TEST_RETRY = 'again' })) { Add-Check $noResult $false; return }
   Wait-ForEnd
   Show-File $log
   Add-Check 'the stand-in broke the first download off' (Test-FileText $serverLog 'broken off on purpose')
   Add-Check 'the helper noticed' (Test-FileText $log 'curl ended with code')
   Add-Check 'the second attempt asked only for the missing part' (Test-FileText $serverLog '(bytes ')
   Add-Check 'the update then went through' (Test-FileText $versionFile 'new version')
   Add-CommonCheck
   [void](Wait-Until 40 { -not (Test-PixInsightRunning) })
}

function Test-CaseBroken {
   ''
   '== broken: the download does not match the checksum on the page =='
   if (-not (Initialize-Case -Service '--bad-sha1')) { return }
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer.ps1')) { Add-Check $noResult $false; return }
   [void](Wait-Until 60 { Test-FileText $log 'would show:' })
   # The helper ends there. Its last line says when it has tidied up.
   [void](Wait-Until 15 { Test-FileText $log 'helper finished' })
   Show-File $log
   Add-Check 'the helper refused the download' (Test-FileText $log 'not the installer that the page listed')
   Add-Check 'the user is told to start again' (Test-FileText $log ('would show: ' + (Get-Sentence 'startAgain')))
   Add-Check 'nothing was installed' (Test-FileText $versionFile 'old version')
   Add-Check 'PixInsight was not asked to close' (-not $script:pix.HasExited)
   Add-CommonCheck
}

function Test-CaseInstallFail {
   ''
   '== installfail: the installer fails before it has changed anything =='
   if (-not (Initialize-Case)) { return }
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer-fails.ps1')) { Add-Check $noResult $false; return }
   Wait-ForEnd
   Show-File $log
   Show-File $shownFile
   Add-Check 'the installer reported that it had failed' (Test-FileText $log 'installer ended with code 1603')
   Add-Check 'the helper found the PixInsight folder as it was' (Test-FileText $log 'result: untouched')
   Add-Check 'the old version is still in place' (Test-FileText $versionFile 'old version')
   Add-Check 'with the add-on module' (Test-Path -LiteralPath $oldAddon)
   Add-Check 'the reopened PixInsight said that it was not updated' (Test-FileText $shownFile (Get-Sentence 'notUpdated' $have))
   Add-CommonCheck
   [void](Wait-Until 40 { -not (Test-PixInsightRunning) })
}

function Test-CaseGone {
   ''
   '== gone: the installer fails after it has removed the old version =='
   if (-not (Initialize-Case)) { return }
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer-gone.ps1')) { Add-Check $noResult $false; return }
   [void](Wait-Until 120 { Test-FileText $log 'helper finished' })
   Show-File $log
   Add-Check 'the helper found that no PixInsight is left' (Test-FileText $log 'result: failed')
   Add-Check 'the user is told that PixInsight is no longer installed, and where its installer is' (Test-FileText $log ('would show: ' + (Get-Sentence 'notInstalled' $installerName)))
   Add-Check 'the installer was kept, in the Downloads folder' (Test-Path -LiteralPath (Join-Path $downloads $installerName))
   # The helper notes an attempt that failed and a reopening that worked in
   # different words, so both are looked for: what the helper would reopen in
   # this case is the real PixInsight, which does open. The helper has closed
   # the PixInsight of this case by now, so none may be running either.
   Add-Check 'the helper did not try to reopen a PixInsight that is not there' (-not (Test-FileText $log 'to reopen PixInsight') -and -not (Test-FileText $log 'PixInsight has reopened') -and -not (Test-PixInsightRunning))
   Add-Check 'the PixInsight program is gone from the stand-in folder' (-not (Test-Path -LiteralPath (Join-Path $folder 'bin\PixInsight.exe')))
   Add-CommonCheck
}

function Test-CaseDeclined {
   ''
   '== declined: the administrator prompt is answered No =='
   if (-not (Initialize-Case)) { return }
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer-declined.ps1')) { Add-Check $noResult $false; return }
   Wait-ForEnd
   Show-File $log
   Show-File $shownFile
   Add-Check 'the helper took the installer''s code for a No at the administrator prompt' (Test-FileText $log 'the administrator prompt was answered No')
   Add-Check 'the helper found the PixInsight folder as it was' (Test-FileText $log 'result: untouched')
   Add-Check 'the old version is still in place' (Test-FileText $versionFile 'old version')
   Add-Check 'the reopened PixInsight said that it was not updated' (Test-FileText $shownFile (Get-Sentence 'notUpdated' $have))
   Add-CommonCheck
   [void](Wait-Until 40 { -not (Test-PixInsightRunning) })
}

function Test-CaseOwnFiles {
   ''
   '== ownfiles: the PixInsight folder holds something of the user''s own, which the installer would delete =='
   if (-not (Initialize-Case)) { return }
   [void][IO.Directory]::CreateDirectory((Join-Path $folder 'gaia'))
   [IO.File]::WriteAllText((Join-Path $folder 'gaia\catalogue.xpsd'), "the user's star catalogue`n")
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer.ps1')) { Add-Check $noResult $false; return }
   Show-File $result
   Add-Check 'the user is told what the installer would delete, by name' (Test-FileText $result ('shown=' + (Get-Sentence 'ownFiles' 'gaia')))
   Add-Check 'no helper was started' (-not (Test-Path -LiteralPath $statusFile))
   Add-Check 'the add-on did not sign in' (-not (Test-FileText $serverLog 'signed in with details'))
}

function Test-CaseRefused {
   ''
   '== refused: a wrong password =='
   if (-not (Initialize-Case)) { return }
   if (-not (Start-Update 'not-the-password' 'now' 'installer.ps1')) { Add-Check $noResult $false; return }
   Show-File $result
   Add-Check 'the user is told that the details were not accepted' (Test-FileText $result ('shown=' + (Get-Sentence 'refused')))
   Add-Check 'no helper was started' (-not (Test-Path -LiteralPath $statusFile))
}

function Test-CaseUpToDate {
   ''
   '== uptodate: nothing newer than the installed version =='
   # The stand-in's page offers the installed version and nothing else, so the
   # case does not depend on which PixInsight is installed.
   if (-not (Initialize-Case -NothingNewer)) { return }
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer.ps1')) { Add-Check $noResult $false; return }
   Show-File $result
   Add-Check 'the user is told that this is the newest version' (Test-FileText $result ('shown=' + (Get-Sentence 'upToDate' $have)))
   Add-Check 'no helper was started' (-not (Test-Path -LiteralPath $statusFile))
   Add-Check 'nothing was downloaded' (-not (Test-FileText $serverLog 'download started'))
}

function Test-CaseOffline {
   ''
   '== offline: the download service cannot be reached =='
   if (-not (Initialize-Case -NoService)) { return }
   if (-not (Start-Update 'standin-pass!1' 'now' 'installer.ps1')) { Add-Check $noResult $false; return }
   Show-File $result
   Add-Check 'the user is told that PixInsight cannot be reached' (Test-FileText $result ('shown=' + (Get-Sentence 'cantReach')))
   Add-Check 'no helper was started' (-not (Test-Path -LiteralPath $statusFile))
}

function Test-CaseWindows {
   ''
   '== windows: both windows open for a second and close, with no mistake in their code =='
   if (-not (Initialize-Case -NoService)) { return }
   [IO.File]::WriteAllText((Join-Path $control 'action.txt'), "windows`n")
   $settings = @{
      PI_UA_TEST_DIR         = ConvertTo-SlashPath $control
      PI_UA_BASE             = "http://127.0.0.1:$port/dist/"
      PI_UA_TEST_INSTALL_DIR = ConvertTo-SlashPath $folder
   }
   if (-not (Start-RehearsalPixInsight $settings 'script-result-windows.txt')) { Add-Check $noResult $false; return }
   $again = Join-Path $control 'script-result-windows.txt'
   Show-File $again
   Add-Check 'the sign-in window was built, opened and closed' (Test-FileText $again 'signin_window=ok')
   Add-Check 'the progress window was built, opened and closed' (Test-FileText $again 'status_window=ok')
   Add-Check 'the progress sentence gives size, progress and time left' (Test-FileText $again 'status_text=Downloading PixInsight 1.9.6: 300 MB of 1.1 GB (27%). About 4 minutes left.')
   Add-Check 'no error was reported' (-not (Test-FileText $again 'error='))
}

# -----------------------------------------------------------------------------
# The cases that run the helper alone
# -----------------------------------------------------------------------------

# The three cases below run the helper without PixInsight. The runner does
# what the script does before it starts the helper: it puts the helper, the
# closing-message script and the helper's sentences into the working folder,
# writes the job and the starter file, and starts the starter. The program
# that the helper is told to reopen does not exist, so no PixInsight opens.
#
#   -Source <file>    the file to "download", in place of a made-up one
#   -RealSignature    let the helper ask Windows who signed the download
function Start-HelperAlone {
   param([string]$Installer, [string]$Source = '', [switch]$RealSignature)
   [void][IO.Directory]::CreateDirectory($work)
   Copy-Item -LiteralPath (Join-Path $UA_Root 'helper\windows\helper.ps1') -Destination (Join-Path $work 'helper.ps1')
   Copy-Item -LiteralPath (Join-Path $UA_Root 'helper\macos\message.js') -Destination (Join-Path $work 'message.js')

   # The helper's sentences, as the script writes them on Windows: "ready" and
   # "installing" with the version filled in, and the Windows form of the
   # sentence for a PixInsight that could not be reopened.
   foreach ($key in 'product', 'ok', 'cancel', 'downloadStopped', 'tryAgain', 'startAgain', 'notGenuine', 'ready', 'restartNow',
                    'later', 'installing', 'hide', 'done', 'notUpdated', 'notReopened', 'notInstalled') {
      $from = $key
      if ($key -eq 'notReopened') { $from = 'notReopenedWin' }
      $sentence = Get-Wording $from
      if ($key -eq 'ready' -or $key -eq 'installing') { $sentence = $sentence.Replace('%1', $new) }
      [IO.File]::WriteAllText((Join-Path $work "text-$key"), $sentence, $utf8)
   }

   # The download: two bytes that every Windows program starts with, and then
   # random bytes, so that no two runs have the same checksum.
   $name = $installerName
   if ($Source) {
      $name = Split-Path -Leaf $Source
   } else {
      $Source = Join-Path $out 'standin-download.exe'
      $bytes = New-Object byte[] 200002
      (New-Object Random).NextBytes($bytes)
      $bytes[0] = 0x4D
      $bytes[1] = 0x5A
      [IO.File]::WriteAllBytes($Source, $bytes)
   }

   # The program that the helper is told to reopen. It is not there, but its
   # folder is: the helper starts the program in the program's own folder, and
   # without that folder an attempt would fail on the folder, before Windows
   # had looked for the program.
   $unopenable = Join-Path $out 'Unopenable\PixInsight.exe'
   [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($unopenable))

   # The download tool fetches the file from this computer, through an address
   # that begins with file:///. The process number is the runner's own, which
   # is no PixInsight, so the helper finds PixInsight closed.
   $job = @(
      ('url=' + (New-Object System.Uri $Source).AbsoluteUri),
      'cookie=none=none',
      'client=rehearsal',
      "file=$name",
      ('sha1=' + (Get-FileHash -LiteralPath $Source -Algorithm SHA1).Hash.ToLower()),
      ('size=' + (Get-Item -LiteralPath $Source).Length),
      "new=$new",
      "old=$have",
      "pid=$PID",
      ('install_dir=' + (ConvertTo-SlashPath $folder)),
      'app=',
      ('exe=' + (ConvertTo-SlashPath $unopenable)),
      'test_answer=now',
      ('test_installer=' + (ConvertTo-SlashPath (Join-Path $PSScriptRoot "standin\$Installer")))
   )
   if (-not $RealSignature) { $job += 'test_signature=accept' }
   $job += ('test_downloads=' + (ConvertTo-SlashPath $downloads))
   $job += 'test_quiet=1'
   [IO.File]::WriteAllText((Join-Path $work 'job.conf'), (($job -join "`n") + "`n"), $utf8)

   # The starter file, as the script writes it: Windows does not run a
   # PowerShell file by its path, and PowerShell refuses script files unless
   # the command that starts it switches that rule off for the one run.
   $systemRoot = $env:SystemRoot
   if (-not $systemRoot) { $systemRoot = 'C:\Windows' }
   $powershell = Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
   $starter = Join-Path $work 'helper.cmd'
   $line = 'start "" /b "{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $powershell, (Join-Path $work 'helper.ps1')
   [IO.File]::WriteAllText($starter, "@echo off`r`n$line`r`n")

   $psi = New-Object System.Diagnostics.ProcessStartInfo
   $psi.FileName = $starter
   $psi.WorkingDirectory = $work
   $psi.UseShellExecute = $false
   $psi.CreateNoWindow = $true
   [void][System.Diagnostics.Process]::Start($psi)
}

# The user's Downloads folder, as Windows knows it. If Windows does not say,
# the folder of that name in the user's own folder.
function Get-DownloadsFolder {
   try {
      $path = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
      if ($path) { return $path }
   } catch {
   }
   return (Join-Path $env:USERPROFILE 'Downloads')
}

# The genuine PixInsight installer for Windows that was downloaded last, or
# nothing. Only a name that the helper accepts is taken, which leaves out a
# copy that a browser has renamed.
function Get-GenuineInstaller {
   $dir = Get-DownloadsFolder
   if (-not (Test-Path -LiteralPath $dir)) { return $null }
   $found = @(Get-ChildItem -LiteralPath $dir -File -Filter 'PI-windows-x64*.exe' |
      Where-Object { $_.Name -cmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{2,120}\.exe$' } |
      Sort-Object LastWriteTime -Descending)
   if ($found.Count -eq 0) { return $null }
   return $found[0].FullName
}

function Test-CaseNoReopen {
   ''
   '== noreopen: the update is installed, but PixInsight cannot be reopened (helper alone) =='
   if (-not (Initialize-Case -NoService)) { return }
   Start-HelperAlone 'installer.ps1'
   [void](Wait-Until 180 { Test-FileText $log 'helper finished' })
   Show-File $log
   Add-Check 'the new version was installed' (Test-FileText $versionFile 'new version')
   # The program is not there, so each attempt fails at its start, and the
   # helper never gets to look whether a PixInsight has come up. What this
   # case shows is the three attempts and what the helper does after them.
   Add-Check 'the helper tried to reopen PixInsight three times' (Test-FileText $log 'attempt 3 to reopen PixInsight')
   Add-Check 'it did not claim that PixInsight had reopened' (-not (Test-FileText $log 'PixInsight has reopened'))
   Add-Check 'the user is told to open PixInsight by hand' (Test-FileText $log ('would show: ' + (Get-Sentence 'notReopenedWin')))
   Add-Check 'the helper deleted the file with the installer''s address and cookie' (-not (Test-Path -LiteralPath (Join-Path $work 'job.conf')))
}

function Test-CaseUnsigned {
   ''
   '== unsigned: the download is not signed by PixInsight''s maker (helper alone, Windows'' own signature check) =='
   if (-not (Initialize-Case -NoService)) { return }
   Start-HelperAlone 'installer.ps1' -RealSignature
   [void](Wait-Until 90 { Test-FileText $log 'helper finished' })
   $ended = Wait-Until 15 { @(Get-HelperProcess).Count -eq 0 }
   Show-File $log
   Add-Check 'the checksum was right, so only the signature can have stopped it' (-not (Test-FileText $log 'not the installer that the page listed'))
   Add-Check 'the helper refused the download' (Test-FileText $log 'the installer is not signed by PixInsight''s maker')
   Add-Check 'the user is told so' (Test-FileText $log ('would show: ' + (Get-Sentence 'notGenuine')))
   Add-Check 'nothing was installed' (Test-FileText $versionFile 'old version')
   Add-Check 'the downloaded file was removed' (-not (Test-Path -LiteralPath (Join-Path $work $installerName)))
   Add-Check 'the helper ended there' $ended
}

function Test-CaseGenuine {
   ''
   '== genuine: a real PixInsight installer passes the signature check (helper alone, Windows'' own signature check) =='
   $genuine = Get-GenuineInstaller
   if (-not $genuine) {
      '   skipped: this case needs a genuine PixInsight installer for Windows, PI-windows-x64*.exe, in the Downloads folder'
      return
   }
   if (-not (Initialize-Case -NoService)) { return }
   $name = Split-Path -Leaf $genuine
   "   the installer is $name, as downloaded from PixInsight. It is read and copied, and never run."
   Start-HelperAlone 'installer.ps1' -Source $genuine -RealSignature
   [void](Wait-Until 300 { Test-FileText $log 'helper finished' })
   Show-File $log
   Add-Check 'the helper accepted it: signed by PixInsight''s maker' (Test-FileText $log 'the installer is signed by PixInsight''s maker (Pleiades Astrophoto S.L.)')
   Add-Check 'and went on to the install step' (Test-FileText $versionFile 'new version')
   Add-Check 'its copy of the installer was removed afterwards' (-not (Test-Path -LiteralPath (Join-Path $work $name)))
}

# -----------------------------------------------------------------------------
# The run
# -----------------------------------------------------------------------------

$exe = Get-PixInsightExe
if (-not $exe) {
   'No PixInsight was found. Nothing was started.'
   exit 2
}
if (Test-PixInsightRunning) {
   'PixInsight is running. Close it first. Nothing was started.'
   exit 2
}
$python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
if (-not $python -and @($Case | Where-Object { $serviceCases -contains $_ }).Count -gt 0) {
   'No python.exe was found, and the stand-in download service needs it. Nothing was started.'
   exit 2
}
$have = Get-InstalledVersion $exe

# PixInsight and the helper inherit the runner's environment. Each case sets
# what it needs. Anything of that kind that is there already is taken out
# first, so that a setting left from an earlier trial cannot change a case,
# and so that a real user name and password, which this rehearsal never
# needs, cannot reach any program that it starts.
foreach ($entry in @(Get-ChildItem Env:)) {
   if ($entry.Name -like 'PI_UA_*' -or $entry.Name -eq 'PI_USER' -or $entry.Name -eq 'PI_PASS') {
      [Environment]::SetEnvironmentVariable($entry.Name, $null, 'Process')
   }
}

# Build the add-on, once. The build is a shell script, which Git Bash runs.
# Its output goes to the temporary folder: the variable UA_DIST says where.
$sh = 'C:\Program Files\Git\bin\sh.exe'
if (-not (Test-Path -LiteralPath $sh)) {
   "Git Bash was not found at $sh, and the build needs it. Nothing was started."
   exit 2
}
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $sh
$psi.Arguments = '"{0}"' -f (ConvertTo-SlashPath (Join-Path $UA_Root 'build\build.sh'))
$psi.WorkingDirectory = $UA_Root
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$env:UA_DIST = ConvertTo-SlashPath $dist
try {
   $build = [System.Diagnostics.Process]::Start($psi)
   # One of the two outputs is read in the background, because a program that
   # fills one while the other is being read would wait for ever.
   $buildErrors = $build.StandardError.ReadToEndAsync()
   $buildOutput = $build.StandardOutput.ReadToEnd()
   $build.WaitForExit()
} finally {
   [Environment]::SetEnvironmentVariable('UA_DIST', $null, 'Process')
}
if ($build.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $scriptUnderTest)) {
   'The build failed. Nothing was started. What the build printed:'
   (($buildOutput + "`n" + $buildErrors.Result) -split "`r?`n") | Where-Object { $_ } | ForEach-Object { "   $_" }
   exit 2
}

"PixInsight on this computer: $have. The stand-in download page offers: $new."
foreach ($name in $Case) {
   if ($allCases -notcontains $name) {
      "unknown case: $name"
      continue
   }
   $caseName = $name.ToLower()
   try {
      & "Test-Case$name"
   } catch {
      Add-Check "the case ran to its end (it stopped with: $($_.Exception.Message))" $false
   } finally {
      Complete-Case
   }
   if ($refusal) { break }
}

''
if ($refusal) { "$refusal The run ends here." }
"RESULT: $passed checks passed, $failed failed."
if ($refusal) { exit 2 }
if ($failed -gt 0) { exit 1 }
exit 0
