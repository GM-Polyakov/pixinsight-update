# PixInsight Update Assistant, Windows test W3.
#
# Question: on Windows, do sign-in from the script, reading the page, the
# download with curl.exe and the session cookie, continuing a broken download,
# the checksum, and stopping a download all work?
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-w3.ps1
#
# Everything runs against the stand-in download service on this computer,
# tests\standin\dist-server.py, with its made-up account. Nothing is sent to
# pixinsight.com. Needs PixInsight closed and Python. It opens a second,
# separate PixInsight in the background once, which leaves by itself.
#
# Output: tests\out\windows\w3\
# Exit code: 0 every check passed, 1 a check failed, 2 nothing was started.

. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\download.ps1"

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
$python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
if (-not $python) {
   'No python.exe was found. Nothing was started.'
   exit 2
}

$port = 8719
$probeTcp = New-Object Net.Sockets.TcpClient
try {
   $probeTcp.Connect('127.0.0.1', $port)
   "Something already answers on port $port of this computer. Nothing was started."
   exit 2
} catch {
} finally {
   $probeTcp.Close()
}

$dir = Join-Path $UA_Out 'w3'
if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
New-Item -ItemType Directory -Force $dir | Out-Null
$work = Join-Path $env:TEMP 'PixInsightUpdateAssistant-w3'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
$result = Join-Path $dir 'w3-result.txt'
$problem = Join-Path $env:TEMP 'pi-update-assistant-w3-error.txt'
Remove-Item -LiteralPath $problem -ErrorAction SilentlyContinue
$serverLog = Join-Path $dir 'standin-server.log'
$sizeMb = 16

# The stand-in service. Its first download is cut after 3 MiB on purpose, and
# every piece of 64 KiB is held back for 20 ms, so that progress can be seen.
$serverLine = '-I "{0}" --port {1} --layout real --cdn other --refuse-curl --newest 9.9.9 --size-mb {2} --slow-ms 20 --drop-first-mb 3 --log "{3}"' -f `
   (Join-Path $UA_Root 'tests\standin\dist-server.py'), $port, $sizeMb, $serverLog
$server = Start-Process -FilePath $python -ArgumentList $serverLine -WindowStyle Hidden -PassThru

try {
   # Wait until it answers, and make sure that the answer is the stand-in's.
   $answers = $false
   for ($i = 0; $i -lt 60 -and -not $answers; $i++) {
      try {
         $req = [Net.WebRequest]::Create("http://127.0.0.1:$port/dist/")
         $req.UserAgent = 'w3-runner'
         $req.Timeout = 2000
         $resp = $req.GetResponse()
         $page = (New-Object IO.StreamReader $resp.GetResponseStream()).ReadToEnd()
         $resp.Close()
         $answers = $page.Contains('user_password')
      } catch {
         Start-Sleep -Milliseconds 250
      }
   }
   if (-not $answers -or $server.HasExited) {
      'The stand-in service did not start. PixInsight was not opened.'
      exit 2
   }

   # --- Inside PixInsight: sign-in and reading the page ----------------------
   $env:PI_UA_W_OUT = ConvertTo-SlashPath $dir
   $env:PI_UA_W_BASE = "http://127.0.0.1:$port/dist/"
   $env:PI_USER = 'standin-user'
   $env:PI_PASS = 'standin-pass!1'
   $p = Start-PixInsightScript -Exe $exe -Script (Join-Path $PSScriptRoot 'w3-probe.js')
   "started $exe as process $($p.Id)"
   $came = Wait-ForFile -Path $result, $problem -Seconds 240
   [void]$p.WaitForExit(120000)
   Remove-Item Env:PI_USER, Env:PI_PASS, Env:PI_UA_W_BASE

   ''
   if ($came -ne $result) {
      if ($came) { '--- the probe stopped with an error'; Get-ResultText $problem } else { '--- the probe wrote nothing within 240 s' }
      exit 1
   }
   '--- what the probe reported'
   Get-ResultText $result

   # The job, as the helper will get it. It holds the session cookie, so it is
   # read and deleted at once.
   $jobFile = Join-Path $work 'job.conf'
   $job = @{}
   if (Test-Path -LiteralPath $jobFile) {
      foreach ($line in ((Get-ResultText $jobFile) -split "`r?`n")) {
         $eq = $line.IndexOf('=')
         if ($eq -gt 0) { $job[$line.Substring(0, $eq)] = $line.Substring($eq + 1) }
      }
      Remove-Item -LiteralPath $jobFile -Force
   }
   $session = ''
   if ($job['cookie']) { $session = $job['cookie'] -replace '^PHPSESSID=', '' }
   $expected = $sizeMb * 1048576

   '--- checks on the sign-in and the page'
   Add-Check 'a wrong password is refused, and recognised as a refusal' ((Get-ResultValue $result 'wrong_password').StartsWith('refused'))
   Add-Check 'a service that cannot be reached is reported as such' ((Get-ResultValue $result 'nothing_listening') -eq 'network')
   Add-Check 'the sign-in with the right details is accepted' ((Get-ResultValue $result 'signin').StartsWith('ok'))
   Add-Check 'the newest Windows installer is chosen' ((Get-ResultValue $result 'newest_for_windows') -ceq 'PI-windows-x64-gpu-9.9.9-20991231-c.exe')
   Add-Check 'its version is read as 9.9.9' ((Get-ResultValue $result 'version') -eq '9.9.9')
   Add-Check 'the checksum on the page is read: forty hexadecimal digits' ((Get-ResultValue $result 'sha1') -cmatch '^[0-9a-f]{40}$')
   Add-Check "the size on the page is read: $expected bytes" ((Get-ResultValue $result 'size') -eq "$expected")
   Add-Check 'the session value is found in the link' ((Get-ResultValue $result 'session_value_length') -eq '32')
   Add-Check 'the job for the helper was written' ($job.Count -ge 6)
   if ($job.Count -lt 6) { exit 1 }

   $file = Join-Path $work $job['file']

   # --- Download, first attempt: the service cuts it after 3 MiB -------------
   ''
   '--- download, first attempt (the stand-in cuts it after 3 MiB)'
   $seenOpen = @()
   $seenFolder = @()
   $d = Start-Download -Dir $work -Url $job['url'] -Client $job['client'] -Cookie $job['cookie'] -File $job['file']
   $instructionsSeen = $false
   while (-not $d.HasExited) {
      if ([IO.File]::Exists($d.Instructions)) { $instructionsSeen = $true }
      Clear-DownloadInstructions $d $file
      $seenOpen += (Get-GrowingFileSize $file)
      $seenFolder += $(if (Test-Path -LiteralPath $file) { (Get-Item -LiteralPath $file).Length } else { 0 })
      Start-Sleep -Milliseconds 100
   }
   $d.WaitForExit()
   Clear-DownloadInstructions $d $file
   $partial = Get-GrowingFileSize $file
   "curl ended with code $($d.ExitCode): $(($d.ErrorText -replace '\s+', ' ').Trim())"
   "sizes seen while it ran, asked from the file itself: $($seenOpen -join ' ')"
   "sizes seen while it ran, as the folder shows them:   $($seenFolder -join ' ')"
   Add-Check 'curl reports that the download broke off' ($d.ExitCode -ne 0)
   Add-Check 'a partial file of about 3 MiB is left' ($partial -ge 3 * 1048576 -and $partial -lt $expected)
   Add-Check 'the size asked from the file itself grew while curl ran' (@($seenOpen | Where-Object { $_ -gt 0 -and $_ -lt $partial }).Count -gt 0)
   Add-Check 'curl''s instructions, which hold the cookie, are deleted' (-not [IO.File]::Exists($d.Instructions))

   # --- Download, second attempt: curl continues ------------------------------
   ''
   '--- download, second attempt (curl continues the partial file)'
   $seenOpen = @()
   $d = Start-Download -Dir $work -Url $job['url'] -Client $job['client'] -Cookie $job['cookie'] -File $job['file']
   $goneAfterMs = -1
   while (-not $d.HasExited) {
      Clear-DownloadInstructions $d $file
      if ($goneAfterMs -lt 0 -and -not [IO.File]::Exists($d.Instructions)) { $goneAfterMs = [int]((Get-Date) - $d.Began).TotalMilliseconds }
      $seenOpen += (Get-GrowingFileSize $file)
      Start-Sleep -Milliseconds 250
   }
   $d.WaitForExit()
   Clear-DownloadInstructions $d $file
   "curl ended with code $($d.ExitCode): $(($d.ErrorText -replace '\s+', ' ').Trim())"
   "sizes seen while it ran: $($seenOpen -join ' ')"
   "curl's instructions were deleted $goneAfterMs ms after curl started"
   $final = Get-GrowingFileSize $file
   $sha1 = ''
   if (Test-Path -LiteralPath $file) { $sha1 = (Get-FileHash -LiteralPath $file -Algorithm SHA1).Hash.ToLower() }
   Add-Check 'curl ends without an error' ($d.ExitCode -eq 0)
   Add-Check "the file has the size from the page, $expected bytes" ($final -eq $expected)
   Add-Check 'the file has the checksum from the page' ($sha1 -ceq $job['sha1'])
   $logText = [IO.File]::ReadAllText($serverLog)
   Add-Check 'the second request asked only for the missing part' ($logText.Contains("(bytes $partial-"))
   Add-Check 'the service saw the add-on''s own client name' ($logText.Contains('agent=PixInsightUpdateAssistant/'))
   Add-Check 'the download went through the redirect to another host name' ($logText.Contains('download redirected'))

   # --- Stopping a download ---------------------------------------------------
   ''
   '--- stopping a download, as Cancel will'
   Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
   $d = Start-Download -Dir $work -Url $job['url'] -Client $job['client'] -Cookie $job['cookie'] -File $job['file']
   Start-Sleep -Milliseconds 1200
   $atStop = Get-GrowingFileSize $file
   $stopBegan = Get-Date
   if (-not $d.HasExited) { $d.Kill() }
   $d.WaitForExit()
   Clear-DownloadInstructions $d $file
   $tries = 0
   while ((Test-Path -LiteralPath $file) -and $tries -lt 50) {
      try { Remove-Item -LiteralPath $file -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 100 }
      $tries++
   }
   $stopMs = [int]((Get-Date) - $stopBegan).TotalMilliseconds
   "curl was stopped with $atStop bytes written; the partial file was gone $stopMs ms later, after $tries attempt(s) to remove it"
   Add-Check 'the download was under way when it was stopped' ($atStop -gt 0 -and $atStop -lt $expected)
   Add-Check 'the partial file could be removed' (-not (Test-Path -LiteralPath $file))

   # --- What must never happen ------------------------------------------------
   ''
   '--- what must never happen'
   $logText = [IO.File]::ReadAllText($serverLog)
   Add-Check 'the sign-out link was never followed' (-not $logText.Contains('LOGOUT LINK FOLLOWED'))
   $leaks = @()
   foreach ($f in @(Get-ChildItem -LiteralPath $dir -File) + @(Get-ChildItem -LiteralPath $work -File -ErrorAction SilentlyContinue)) {
      if ($f.Name -eq 'standin-server.log') { continue }
      $text = [IO.File]::ReadAllText($f.FullName)
      if ($text.Contains('standin-pass') -or $text.Contains('standin-user') -or ($session -and $text.Contains($session))) { $leaks += $f.Name }
   }
   Add-Check 'no file left by the test holds the user name, the password or the session value' ($leaks.Count -eq 0)
   if ($leaks.Count) { "      found in: $($leaks -join ', ')" }
   Add-Check 'no PixInsight is left running' (-not (Test-PixInsightRunning))
} finally {
   if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
   Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

''
"RESULT: $passed checks passed, $failed failed."
if ($failed -gt 0) { exit 1 }
exit 0
