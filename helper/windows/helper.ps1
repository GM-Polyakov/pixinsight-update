# PixInsight Update Assistant: the helper for Windows.
#
# The script inside PixInsight writes this file into a private folder and
# starts it through a small starter file, helper.cmd, because Windows does not
# run a PowerShell script by its path. From then on the helper works on its
# own:
#
#   1. downloads the installer with curl.exe, in the background;
#   2. checks the download against the checksum from the download page, and
#      checks that the installer is signed by PixInsight's maker;
#   3. asks "Restart now, or later?";
#   4. asks PixInsight to close the normal way, or waits until the user
#      closes it;
#   5. starts PixInsight's own installer, for which Windows asks the user for
#      administrator rights. That installer removes the old version and
#      empties the PixInsight folder by itself, so the helper moves nothing
#      aside, carries nothing over and can put nothing back. It judges the
#      outcome by the PixInsight program that is there afterwards;
#   6. reopens PixInsight and makes sure that it has opened. PixInsight then
#      says which version is running. If the install has failed and has left
#      no PixInsight, the helper puts the installer into the Downloads folder
#      and says so.
#
# It never receives the PixInsight user name or password. What it receives is
# the address of one installer and the session cookie that goes with it, in
# the file job.conf, which it deletes as soon as it has read it.
#
# Everything it shows the user comes from the text-* files next to it, which
# the script writes from its one table of wording.
#
# Nothing written by this project runs with administrator rights. Only
# PixInsight's own installer does, and only after the helper has checked who
# signed it.
#
# Windows PowerShell 5.1. This file is plain ASCII, because PowerShell 5.1
# reads a file without a byte-order mark in the system's own encoding. Its
# lines end in line feeds only, which the build checks.

$ErrorActionPreference = 'Stop'

$Dir = $PSScriptRoot
$Self = $PSCommandPath
$Log = Join-Path $Dir 'log.txt'
$Outcome = Join-Path $Dir 'outcome'
$MessageScript = Join-Path $Dir 'message.js'
# Whatever the script inside PixInsight reads is written as UTF-8 without a
# byte-order mark and with line feeds only. The script splits on line feeds
# and compares whole values, so a mark or a carriage return would break it
# without any message.
$Utf8 = New-Object Text.UTF8Encoding $false
# PixInsight's maker, Pleiades Astrophoto, as it is named in the certificate
# with which it signs its installers: the organisation in the certificate's
# subject. That name stays the same when the certificate is renewed. An
# installer must carry a valid signature made with a certificate of this
# organisation.
$Maker = 'Pleiades Astrophoto S.L.'

# The code the helper ends with. It stays 1 unless the work ends in a way that
# says otherwise, so that an error nobody foresaw counts as a failure.
$script:ExitCode = 1
# True once the work has ended on purpose, through Stop-Helper.
$script:Stopped = $false
# The file "alive", which the helper holds open for as long as it lives.
$script:Alive = $null
# curl, for as long as it runs.
$script:Curl = $null
# The sentences from the text-* files, by their names.
$script:Texts = @{}

# A small piece of C#, because PowerShell has no way of its own to find and
# close the files that a program inherited.
$HandleCode = @'
using System;
using System.Runtime.InteropServices;

public static class UAHandles
{
   [DllImport("kernel32.dll")] static extern bool GetHandleInformation( IntPtr h, out uint flags );
   [DllImport("kernel32.dll")] static extern uint GetFileType( IntPtr h );
   [DllImport("kernel32.dll")] static extern bool CloseHandle( IntPtr h );

   // Close every file or folder on a disk that this process holds open and
   // that is marked as inheritable. PowerShell opens its own files without
   // that mark, so these are the ones that came from the program that
   // started it. Returns how many were closed.
   public static int ReleaseInherited()
   {
      int closed = 0;
      for ( long v = 4; v <= 0x10000; v += 4 )
      {
         IntPtr h = new IntPtr( v );
         uint flags;
         if ( !GetHandleInformation( h, out flags ) )
            continue;
         if ( ( flags & 1 ) == 0 || GetFileType( h ) != 1 )
            continue;
         if ( CloseHandle( h ) )
            ++closed;
      }
      return closed;
   }
}
'@

# One line in the helper's log: the time, then the text. Line ends inside the
# text become spaces, so that a note is always one line. On Windows a program
# can fail to add to a file in the moment in which another one reads it, so a
# failed attempt is repeated for a second. A note that still cannot be written
# is dropped: the log must never stop an update.
function Add-Note {
   param([string]$Text)
   $line = (Get-Date).ToString('HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture) + ' ' +
      ($Text -replace '\s*[\r\n]+\s*', ' ').TrimEnd() + "`n"
   for ($i = 0; $i -lt 20; $i++) {
      try {
         [IO.File]::AppendAllText($Log, $line, $Utf8)
         return
      } catch {
         Start-Sleep -Milliseconds 50
      }
   }
}

# One of the sentences that the script wrote for the helper, by its name in
# the table of wording. An empty text if the script wrote none of that name.
function Get-Text {
   param([string]$Name)
   return [string]$script:Texts[$Name]
}

# The time as the Mac helper writes it: whole seconds since the start of 1970.
function Get-UnixSeconds {
   return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

# What the script's progress window shows: the same seven lines that the Mac
# helper writes. The file is replaced in one step, because the script may read
# it at any moment. The script may hold the file open just then, and the
# replacing then fails (TESTING.md, test W2). Some phases are written once,
# and the script depends on seeing the phase "restart". So a write that
# failed is repeated, for half a second at most.
function Write-Status {
   param([string]$Phase, [long]$Got = 0)
   $lines = "phase=$Phase", "got=$Got", "total=$Total", "version=$NewVersion", "helper=$PID", "began=$Began",
      ('now=' + (Get-UnixSeconds))
   $status = Join-Path $Dir 'status'
   $tmp = $status + '.tmp'
   for ($attempt = 0; $attempt -lt 10; $attempt++) {
      try {
         [IO.File]::WriteAllText($tmp, (($lines -join "`n") + "`n"), $Utf8)
         if ([IO.File]::Exists($status)) {
            [IO.File]::Replace($tmp, $status, [NullString]::Value)
         } else {
            [IO.File]::Move($tmp, $status)
         }
         return
      } catch {
         Start-Sleep -Milliseconds 50
      }
   }
}

# Delete one file. A file that is not there is no failure. On Windows a file
# that a program holds open can usually not be deleted, so a failed attempt
# is repeated for two seconds. After that the file is left where it is.
function Remove-HelperFile {
   param([string]$Path)
   for ($i = 0; $i -lt 20; $i++) {
      try {
         [IO.File]::Delete($Path)
         return
      } catch {
         Start-Sleep -Milliseconds 100
      }
   }
}

# Remove what is no longer needed. The logs stay for one more run.
function Remove-Leftovers {
   foreach ($name in $FileName, 'cancel', 'status', 'status.tmp', 'window-open', 'curl-instructions') {
      Remove-HelperFile (Join-Path $Dir $name)
   }
}

# End the work from wherever it is, and say what the helper is to end with.
# The lines at the bottom of this file catch this, tidy up after the helper
# itself and exit.
function Stop-Helper {
   param([int]$Code)
   $script:ExitCode = $Code
   $script:Stopped = $true
   throw 'the helper stops here'
}

# The script writes the file "cancel" when the user cancels the update. The
# helper looks for it at every step until PixInsight has closed. After that
# the update can no longer be cancelled.
function Stop-IfCancelled {
   if (-not [IO.File]::Exists((Join-Path $Dir 'cancel'))) { return }
   Add-Note 'cancelled by the user'
   if ($script:Curl) {
      # The partial download can only be deleted once curl has let go of it.
      try {
         if (-not $script:Curl.HasExited) { $script:Curl.Kill() }
         $script:Curl.WaitForExit()
      } catch {
      }
   }
   Remove-Leftovers
   Remove-HelperFile $MessageScript
   Stop-Helper 0
}

# One window for everything the helper says: a question with two buttons, a
# message with one, and the notice that stays on the screen during the
# install. The window is always on top and in the middle of the screen, has
# the add-on's name as its title, and wraps its sentence at 420 pixels. The
# buttons stand at the bottom right, and the first one is the one that the
# Enter key presses.
#
# Returns the text of the button that was clicked, or an empty text if the
# window was closed without one. With -Stay the window is shown and left on
# the screen, its button only hides it, and the window itself is returned, so
# that the caller can close it.
#
# In a rehearsal no window is shown. A message is written into the log
# instead, and a question comes back as if its window had been closed, which
# every caller takes for the careful answer.
function Show-Window {
   param([string]$Sentence, [string[]]$Buttons, [switch]$Stay)
   if ($TestQuiet) {
      if ($Buttons.Count -eq 1) { Add-Note "would show: $Sentence" }
      return ''
   }

   $form = New-Object System.Windows.Forms.Form
   $form.Text = Get-Text 'product'
   $form.Font = [System.Drawing.SystemFonts]::MessageBoxFont
   $form.TopMost = $true
   $form.StartPosition = 'CenterScreen'
   $form.FormBorderStyle = 'FixedDialog'
   $form.MaximizeBox = $false
   $form.MinimizeBox = $false
   # The notice has no box for closing it: its button hides it, and the helper
   # closes it when the install is over.
   $form.ControlBox = -not $Stay
   # A window of a program that runs in the background does not always get the
   # keyboard by itself, so it asks for it.
   $form.Add_Shown({ $this.Activate() })

   $label = New-Object System.Windows.Forms.Label
   $label.UseMnemonic = $false
   $label.AutoSize = $true
   $label.MaximumSize = New-Object System.Drawing.Size 420, 0
   $label.Location = New-Object System.Drawing.Point 16, 16
   $label.Text = $Sentence
   $form.Controls.Add($label)

   # The buttons are placed from the right edge leftwards, so the last one
   # comes first here.
   $top = 16 + $label.PreferredSize.Height + 20
   $right = 16 + 420
   for ($i = $Buttons.Count - 1; $i -ge 0; $i--) {
      $button = New-Object System.Windows.Forms.Button
      $button.Text = $Buttons[$i]
      $button.TabIndex = $i
      $width = [Math]::Max(90, [System.Windows.Forms.TextRenderer]::MeasureText($Buttons[$i], $form.Font).Width + 30)
      $left = $right - $width
      $button.Size = New-Object System.Drawing.Size $width, 28
      $button.Location = New-Object System.Drawing.Point $left, $top
      if ($Stay) {
         $button.Add_Click({ $this.FindForm().Hide() })
      } else {
         # The window remembers which button closed it.
         $button.Add_Click({
            $window = $this.FindForm()
            $window.Tag = $this.Text
            $window.Close()
         })
      }
      $form.Controls.Add($button)
      if ($i -eq 0) { $form.AcceptButton = $button }
      $right = $left - 8
   }
   $height = $top + 28 + 16
   $form.ClientSize = New-Object System.Drawing.Size 452, $height

   if ($Stay) {
      $form.Show()
      # Let Windows draw the window before the helper goes on to other work.
      [System.Windows.Forms.Application]::DoEvents()
      return $form
   }
   [void]$form.ShowDialog()
   $clicked = [string]$form.Tag
   $form.Dispose()
   return $clicked
}

# The size of a file while another program is still writing it. It is asked
# from the file itself: on Windows the size that a folder shows for a file can
# stay behind for as long as the file is open.
function Get-GrowingFileSize {
   param([string]$Path)
   try {
      $s = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
         ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
      try { return $s.Length } finally { $s.Close() }
   } catch {
      return 0
   }
}

# A value inside the quotes of a line in curl's list of instructions, where a
# backslash and a quote have to be written with a backslash in front.
function ConvertTo-CurlValue {
   param([string]$Text)
   return $Text.Replace('\', '\\').Replace('"', '\"')
}

# Start curl.exe, the download tool that comes with Windows, for one file.
#
# The address, the client name and the cookie reach curl in a small file of
# instructions in the working folder, never in a command line. On the Mac they
# go through curl's input. That is not safe here: when the system's encoding
# is UTF-8, .NET writes a byte-order mark into a program's input at the moment
# it starts the program, and curl then refuses its instructions (seen in test
# W3). The caller removes the file with Clear-DownloadInstructions as soon as
# curl has read it.
#
# The first thing curl is told is -q, so that it does not read a file of
# settings of the user's own, which could change any of this.
#
# The download is named without a folder and curl runs in the working folder,
# so no folder name has to pass through curl's instructions. curl continues a
# partial file.
#
# Returns the process. What curl printed about an error is in .ErrorText once
# it has ended.
function Start-Download {
   param([string]$Dir, [string]$Url, [string]$Client, [string]$Cookie, [string]$File)
   $lines = @(
      ('url = "{0}"' -f (ConvertTo-CurlValue $Url)),
      ('user-agent = "{0}"' -f (ConvertTo-CurlValue $Client)),
      ('cookie = "{0}"' -f (ConvertTo-CurlValue $Cookie)),
      'location',
      'fail',
      'silent',
      'show-error',
      'continue-at = "-"',
      ('output = "{0}"' -f (ConvertTo-CurlValue $File))
   )
   $instructions = Join-Path $Dir 'curl-instructions'
   [IO.File]::WriteAllText($instructions, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))

   $psi = New-Object System.Diagnostics.ProcessStartInfo
   $psi.FileName = Join-Path $env:SystemRoot 'System32\curl.exe'
   $psi.Arguments = '-q -K curl-instructions'
   $psi.WorkingDirectory = $Dir
   $psi.UseShellExecute = $false
   $psi.CreateNoWindow = $true
   $psi.RedirectStandardError = $true
   $p = [System.Diagnostics.Process]::Start($psi)
   $reading = $p.StandardError.ReadToEndAsync()
   $p | Add-Member -NotePropertyName ErrorReading -NotePropertyValue $reading
   $p | Add-Member -MemberType ScriptProperty -Name ErrorText -Value { $this.ErrorReading.Result }
   $p | Add-Member -NotePropertyName Instructions -NotePropertyValue $instructions
   $p | Add-Member -NotePropertyName Began -NotePropertyValue (Get-Date)
   $p | Add-Member -NotePropertyName SizeAtStart -NotePropertyValue (Get-GrowingFileSize (Join-Path $Dir $File))
   return $p
}

# Remove curl's instructions once curl has read them. curl reads them before
# it asks for anything, so they are no longer needed when the file has grown,
# when curl has ended, or after ten seconds. Call it at every look at the
# download, and once more at the end.
function Clear-DownloadInstructions {
   param($Download, [string]$File)
   if (-not [IO.File]::Exists($Download.Instructions)) { return }
   if ($Download.HasExited -or ((Get-Date) - $Download.Began).TotalSeconds -ge 10 -or
       (Get-GrowingFileSize $File) -gt $Download.SizeAtStart) {
      try { [IO.File]::Delete($Download.Instructions) } catch { }
   }
}

# The PixInsight that started the update, for as long as it runs. Its process
# number alone does not say so: Windows gives the number of a program that has
# ended to a new one.
function Get-PixInsight {
   return Get-Process -Id $PixInsightPid -ErrorAction SilentlyContinue |
      Where-Object { $_.ProcessName -eq 'PixInsight' }
}

# True while the PixInsight that started the update is running, or anything
# else from the same PixInsight folder: a second PixInsight, or PixInsight's
# own updater, which runs after PixInsight closes if add-on updates are
# pending and then starts PixInsight again. Windows does not tell where a
# program lies that runs with administrator rights, as that updater may. A
# program of one of these names whose place cannot be read counts as running.
function Test-PixInsightRunning {
   if (Get-PixInsight) { return $true }
   foreach ($name in 'PixInsight', 'PixInsightUpdater', 'updater2', 'updater3') {
      foreach ($process in [System.Diagnostics.Process]::GetProcessesByName($name)) {
         $program = ''
         try { $program = $process.MainModule.FileName } catch { }
         if (-not $program) { return $true }
         if ([IO.Path]::GetDirectoryName($program) -ieq $BinFolder) { return $true }
      }
   }
   return $false
}

# True once PixInsight has opened: its process is there and stays, or it has
# already read the file "outcome" in order to show its message.
function Test-Reopened {
   for ($i = 0; $i -lt 30; $i++) {
      if (-not [IO.File]::Exists($Outcome)) { return $true }
      if (Test-PixInsightRunning) {
         Start-Sleep -Seconds 5
         if (Test-PixInsightRunning) { return $true }
         return (-not [IO.File]::Exists($Outcome))
      }
      Start-Sleep -Seconds 1
   }
   return $false
}

# Put the installer into the user's Downloads folder, and return the name it
# has there. Windows lets the user move that folder, so Windows is asked where
# it is; the folder of that name in the user's profile is the second choice.
# A file that is already there keeps its name, and the installer gets a number
# in front of ".exe".
function Move-InstallerToDownloads {
   $folder = ''
   if ($TestDownloads) {
      # Rehearsal: a folder that stands for the user's Downloads folder.
      $folder = $TestDownloads.Replace('/', '\')
   } else {
      try {
         $folder = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
      } catch {
         $folder = ''
      }
      if (-not $folder) {
         $folder = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
      }
   }
   $name = $FileName
   $number = 1
   while (Test-Path -LiteralPath (Join-Path $folder $name)) {
      $number++
      $name = $FileName.Substring(0, $FileName.Length - 4) + " ($number).exe"
   }
   [IO.File]::Move($InstallerFile, (Join-Path $folder $name))
   return $name
}

# The whole update, from the first step to the last. Every way out of it goes
# through Stop-Helper.
function Invoke-Update {
   # --- Start -----------------------------------------------------------------
   # The script asks whether the helper is alive by trying to remove this
   # file. The helper holds it open and shares it with nobody for as long as
   # it lives, so that attempt fails until the helper has ended.
   $script:Alive = [IO.File]::Open((Join-Path $Dir 'alive'), [IO.FileMode]::OpenOrCreate,
      [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

   # A program that PixInsight starts inherits the files PixInsight has open.
   # One of them inside the PixInsight folder would be in the installer's way,
   # so the helper lets go of all of them. If that fails, the update goes on.
   try {
      Add-Type -TypeDefinition $HandleCode
      Add-Note ('inherited files closed: ' + [UAHandles]::ReleaseInherited())
   } catch {
      Add-Note ('the inherited files could not be closed: ' + $_.Exception.Message)
   }

   # The job. Its file holds the installer's address and the session cookie,
   # so it is deleted as soon as it has been read.
   $jobFile = Join-Path $Dir 'job.conf'
   $jobText = [IO.File]::ReadAllText($jobFile, [Text.Encoding]::UTF8)
   Remove-HelperFile $jobFile
   $job = @{}
   foreach ($line in ($jobText -split "`r?`n")) {
      $eq = $line.IndexOf('=')
      if ($eq -gt 0) { $job[$line.Substring(0, $eq)] = $line.Substring($eq + 1) }
   }
   $url = [string]$job['url']
   $cookie = [string]$job['cookie']
   $client = [string]$job['client']
   $script:FileName = [string]$job['file']
   $sha1 = [string]$job['sha1']
   $script:Total = [string]$job['size']
   if (-not $script:Total) { $script:Total = '0' }
   $script:NewVersion = [string]$job['new']
   $oldVersion = [string]$job['old']
   $pidText = [string]$job['pid']
   $number = 0
   [void][int]::TryParse($pidText, [ref]$number)
   $script:PixInsightPid = $number
   # PixInsight writes its paths with forward slashes. The folder must not end
   # in a backslash, which would swallow the quote that follows it in a
   # command line.
   $installDir = ([string]$job['install_dir']).Replace('/', '\').TrimEnd('\')
   $script:Exe = ([string]$job['exe']).Replace('/', '\')
   $script:BinFolder = ''
   if ($script:Exe) { $script:BinFolder = [IO.Path]::GetDirectoryName($script:Exe) }
   # Rehearsal only. Empty in real use.
   $testAnswer = [string]$job['test_answer']
   $testRetry = [string]$job['test_retry']
   $testInstaller = [string]$job['test_installer']
   $testSignature = [string]$job['test_signature']
   $script:TestDownloads = [string]$job['test_downloads']
   $script:TestQuiet = [string]$job['test_quiet']

   # The sentences, which the script wrote from its one table of wording.
   foreach ($path in [IO.Directory]::GetFiles($Dir, 'text-*')) {
      $script:Texts[[IO.Path]::GetFileName($path).Substring(5)] =
         [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).TrimEnd([char]13, [char]10)
      Remove-HelperFile $path
   }

   # The file name comes from a web page: accept a plain installer name only.
   if ($FileName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{2,120}\.exe$') {
      Add-Note 'refused the file name'
      Stop-Helper 1
   }
   $script:InstallerFile = Join-Path $Dir $FileName
   $script:Began = Get-UnixSeconds

   Add-Note "helper started for PixInsight $NewVersion (from $oldVersion); PixInsight is process $pidText"

   # The helper's windows are made with Windows Forms, which comes with
   # Windows.
   Add-Type -AssemblyName System.Windows.Forms
   Add-Type -AssemblyName System.Drawing
   [System.Windows.Forms.Application]::EnableVisualStyles()

   # --- 1. Download -----------------------------------------------------------
   while ($true) {
      Write-Status 'downloading' (Get-GrowingFileSize $InstallerFile)
      # curl continues a partial file, so a second attempt fetches only the
      # part that is missing.
      $script:Curl = Start-Download -Dir $Dir -Url $url -Client $client -Cookie $cookie -File $FileName
      while (-not $script:Curl.HasExited) {
         Clear-DownloadInstructions $script:Curl $InstallerFile
         Write-Status 'downloading' (Get-GrowingFileSize $InstallerFile)
         Stop-IfCancelled
         Start-Sleep -Seconds 1
      }
      $script:Curl.WaitForExit()
      Clear-DownloadInstructions $script:Curl $InstallerFile
      $code = $script:Curl.ExitCode
      $said = ([string]$script:Curl.ErrorText -replace '\s+', ' ').Trim()
      $script:Curl = $null
      Stop-IfCancelled
      if ($code -eq 0) { break }

      Add-Note "curl ended with code $code"
      if ($said) { Add-Note "what curl said: $said" }
      Write-Status 'stopped' (Get-GrowingFileSize $InstallerFile)
      if ($testRetry) {
         $choice = $testRetry
         $testRetry = 'cancel'
      } else {
         $clicked = Show-Window -Sentence (Get-Text 'downloadStopped') -Buttons (Get-Text 'tryAgain'), (Get-Text 'cancel')
         if ($clicked -and $clicked -ceq (Get-Text 'tryAgain')) { $choice = 'again' } else { $choice = 'cancel' }
      }
      if ($choice -ne 'again') {
         Add-Note 'the user gave up after the download stopped'
         Remove-Leftovers
         Stop-Helper 0
      }
   }

   # --- 2. Check the download -------------------------------------------------
   $size = Get-GrowingFileSize $InstallerFile
   Write-Status 'checking' $size
   # Every program file for Windows begins with the two letters MZ. A file
   # that cannot be read is no installer either.
   $good = $false
   try {
      $stream = [IO.File]::OpenRead($InstallerFile)
      try {
         $good = ($stream.ReadByte() -eq 0x4D -and $stream.ReadByte() -eq 0x5A)
      } finally {
         $stream.Close()
      }
      if ($good -and $sha1) {
         $good = ((Get-FileHash -LiteralPath $InstallerFile -Algorithm SHA1).Hash.ToLowerInvariant() -ceq $sha1)
      }
   } catch {
      $good = $false
   }
   if (-not $good) {
      Add-Note 'the download is not the installer that the page listed'
      Remove-Leftovers
      $null = Show-Window -Sentence (Get-Text 'startAgain') -Buttons (Get-Text 'ok')
      Stop-Helper 1
   }
   # The checksum shows that the file is the one the download page listed. The
   # signature shows who made it. The installer is going to run with
   # administrator rights, so the helper looks first: Windows must find the
   # signature valid, and the certificate must name PixInsight's maker as the
   # organisation. A rehearsal may leave the question out, but only together
   # with a stand-in installer, so that the real one is never started
   # unchecked.
   if ($testSignature -ceq 'accept' -and $testInstaller) {
      Add-Note 'rehearsal: the signature was not asked for'
   } else {
      $verdict = ''
      $subject = 'no certificate'
      $genuine = $false
      try {
         $signature = Get-AuthenticodeSignature -LiteralPath $InstallerFile
         $verdict = [string]$signature.Status
         if ($signature.SignerCertificate) {
            $subject = $signature.SignerCertificate.Subject
            # The subject, one part to a line. One line must be the maker's
            # organisation, whole and exact.
            $named = $false
            foreach ($line in ($signature.SignerCertificate.SubjectName.Format($true) -split "`r?`n")) {
               if ($line.Trim() -ceq ('O=' + $Maker)) { $named = $true }
            }
            $genuine = ($verdict -ceq 'Valid' -and [string]$signature.SignatureType -ceq 'Authenticode' -and $named)
         }
      } catch {
         # A signature that cannot be asked for is not accepted.
         $verdict = $_.Exception.Message
      }
      if (-not $genuine) {
         Add-Note "the installer is not signed by PixInsight's maker. What Windows says about it: $verdict; $subject"
         Remove-Leftovers
         $null = Show-Window -Sentence (Get-Text 'notGenuine') -Buttons (Get-Text 'ok')
         Stop-Helper 1
      }
      Add-Note "the installer is signed by PixInsight's maker ($Maker)"
   }
   Add-Note 'download complete and checked'
   Stop-IfCancelled

   # --- 3. Restart now, or later? ---------------------------------------------
   Write-Status 'asking' $size
   if ($testAnswer) {
      $answer = $testAnswer
   } else {
      $clicked = Show-Window -Sentence (Get-Text 'ready') -Buttons (Get-Text 'restartNow'), (Get-Text 'later')
      if ($clicked -and $clicked -ceq (Get-Text 'restartNow')) { $answer = 'now' } else { $answer = 'later' }
   }
   Add-Note "answer: $answer"
   Stop-IfCancelled

   # --- 4. PixInsight closes --------------------------------------------------
   if ($answer -eq 'now' -and (Test-PixInsightRunning)) {
      # PixInsight ignores a request to close while a window of a script is
      # open in it, and Windows still reports the request as delivered
      # (TESTING.md, test W4). The phase "restart" makes the add-on's progress
      # window close itself, and keeps it from opening. The file window-open
      # is there for as long as any window of the add-on is open: wait for it
      # to go, for a minute at most.
      Write-Status 'restart' $size
      if ([IO.File]::Exists((Join-Path $Dir 'window-open'))) {
         Add-Note 'a window of the add-on is open in PixInsight; it has to close first'
      }
      Start-Sleep -Seconds 1
      $waited = 0
      while ([IO.File]::Exists((Join-Path $Dir 'window-open')) -and $waited -lt 60 -and (Test-PixInsightRunning)) {
         Start-Sleep -Seconds 1
         $waited++
      }
      if ($waited -gt 0) { Add-Note "waited $waited s for a window of the add-on to close" }
      # One more second, so that the script behind the window has ended too.
      Start-Sleep -Seconds 1
      # The ordinary request to close, the one that the X button of
      # PixInsight's window sends. PixInsight shows its own question if images
      # are unsaved. If the user answers No, PixInsight stays open and the
      # update simply waits, as with "Later". While a question of PixInsight's
      # own is open, Windows cannot deliver the request, so it is tried again
      # once a second, for a minute at most.
      for ($i = 0; $i -lt 60; $i++) {
         $pixinsight = Get-PixInsight
         if (-not $pixinsight) { break }
         $pixinsight.Refresh()
         if ($pixinsight.CloseMainWindow()) { break }
         Start-Sleep -Seconds 1
      }
      Add-Note 'asked PixInsight to quit'
   }
   Write-Status 'waiting' $size
   while ($true) {
      while (Test-PixInsightRunning) {
         Stop-IfCancelled
         Start-Sleep -Seconds 1
      }
      # Look once more after a moment: PixInsight's own updater may be about to
      # start, or to start PixInsight again. It may also be asking for
      # administrator rights just then; the window in which Windows asks that
      # is a program named consent.
      Start-Sleep -Seconds 3
      if (-not (Test-PixInsightRunning) -and
          [System.Diagnostics.Process]::GetProcessesByName('consent').Length -eq 0) { break }
   }
   Add-Note 'PixInsight has closed'

   # --- 5. Install ------------------------------------------------------------
   Write-Status 'installing' $size
   $code = -1
   if ($testInstaller) {
      # Rehearsal: a stand-in installer and a stand-in folder; no
      # administrator rights and no window.
      $start = New-Object System.Diagnostics.ProcessStartInfo
      $start.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
      $start.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Folder "{1}" -Installer "{2}"' -f $testInstaller, $installDir, $InstallerFile
      $start.UseShellExecute = $false
      $start.CreateNoWindow = $true
      $running = [System.Diagnostics.Process]::Start($start)
      $running.WaitForExit()
      $code = $running.ExitCode
   } else {
      # PixInsight's installer shows nothing while it works, so a notice stays
      # on the screen for that time.
      $notice = $null
      if (-not $TestQuiet) {
         $notice = Show-Window -Sentence (Get-Text 'installing') -Buttons (Get-Text 'hide') -Stay
      }
      # PixInsight's own installer: without windows (/exenoui and /qn), with
      # its two logs in the working folder, and told to install into the
      # folder PixInsight is in now. Run without windows it does not ask for
      # administrator rights by itself, so it is started with the request for
      # them, which Windows puts to the user. Nothing written by this project
      # runs with administrator rights: only PixInsight's own signed installer
      # does.
      $exeLog = Join-Path $Dir 'install-exe.log'
      $msiLog = Join-Path $Dir 'install-msi.log'
      $start = New-Object System.Diagnostics.ProcessStartInfo
      $start.FileName = $InstallerFile
      $start.Arguments = '/exenoui /exelog "{0}" /qn /norestart /L*V "{1}" APPDIR="{2}"' -f $exeLog, $msiLog, $installDir
      $start.UseShellExecute = $true
      $start.Verb = 'runas'
      $start.ErrorDialog = $true
      if ($notice) { $start.ErrorDialogParentHandle = $notice.Handle }
      $start.WorkingDirectory = $Dir
      $running = $null
      try {
         $running = [System.Diagnostics.Process]::Start($start)
      } catch {
         # Windows reports the answer No to its question about administrator
         # rights as error 1223. Whatever else keeps the installer from
         # starting leaves the code at -1, and PixInsight as it was.
         $why = $_.Exception.GetBaseException()
         if ($why -is [System.ComponentModel.Win32Exception] -and $why.NativeErrorCode -eq 1223) {
            $code = 1223
         } else {
            Add-Note ('the installer could not be started: ' + $why.Message)
         }
      }
      if ($running) {
         # The notice is a window of this helper, so the helper has to keep
         # answering Windows on its behalf while it waits.
         while (-not $running.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 200
         }
         try { $code = $running.ExitCode } catch { $code = -1 }
      }
      if ($notice) {
         try { $notice.Close() } catch { }
      }
   }
   Add-Note "installer ended with code $code"
   if ($code -eq 1223) { Add-Note 'the administrator prompt was answered No' }

   # The installer removes the old version before it installs the new one, so
   # its code alone does not say whether a PixInsight is left. The outcome is
   # judged by the PixInsight program that is there afterwards. Code 3010
   # means success with a restart of Windows still to come.
   $program = $installDir + '\bin\PixInsight.exe'
   if ($code -eq 1223) {
      $result = 'untouched'
   } elseif ([IO.File]::Exists($program)) {
      if ($code -eq 0 -or $code -eq 3010) { $result = 'installed' } else { $result = 'untouched' }
   } else {
      $result = 'failed'
   }
   Add-Note "result: $result"

   # --- 6. Reopen -------------------------------------------------------------
   if ($result -eq 'failed') {
      # PixInsight's installer removes the old version before it installs the
      # new one, so after a failed install no PixInsight is left: there is
      # nothing to reopen and nothing to put back. What helps the user is the
      # installer itself, so it is kept where the user will look for it.
      $kept = Move-InstallerToDownloads
      Remove-Leftovers
      $sentence = (Get-Text 'notInstalled').Replace('%1', $kept)
      $null = Show-Window -Sentence $sentence -Buttons (Get-Text 'ok')
      Remove-HelperFile $MessageScript
      Add-Note "PixInsight is no longer installed; the installer was kept as $kept"
      Stop-Helper 1
   }

   # What the reopened PixInsight needs for its message. It compares "old"
   # with the version that is really running, and says which one that is.
   $lines = @(
      "old=$oldVersion",
      "expected=$NewVersion",
      "result=$result",
      'folder=',
      'why=',
      'left=',
      ('title=' + (Get-Text 'product')),
      ('done=' + (Get-Text 'done')),
      ('notUpdated=' + (Get-Text 'notUpdated')),
      "quiet=$TestQuiet"
   )
   [IO.File]::WriteAllText($Outcome, (($lines -join "`n") + "`n"), $Utf8)

   Remove-Leftovers

   # Start-Process joins its arguments with spaces and adds no quotes, so the
   # quotes around the path are written here. PixInsight wants the path with
   # forward slashes.
   $message = $MessageScript.Replace('\', '/')
   if ($TestQuiet) {
      # Rehearsal: PixInsight opens in the background, shows no message box
      # and leaves by itself. The option that keeps it from taking the
      # keyboard exists from PixInsight 1.9.5 on; an earlier PixInsight does
      # not start when it is given an option it does not know.
      $noFocus = ''
      try {
         $known = "$((Get-Item -LiteralPath $Exe).VersionInfo.FileVersion)"
         if ([version]$known -ge [version]'1.9.5') { $noFocus = ' --no-focus-stealing' }
      } catch { }
      $line = ('-n --automation-mode' + $noFocus + ' -r="{0}" --force-exit') -f $message
   } else {
      $line = '-r="{0}"' -f $message
   }
   # As on the Mac: up to three attempts, each one checked, because asking for
   # a program to be started says nothing about whether it came up. On Windows
   # this is also the only check that the new PixInsight starts at all.
   for ($attempt = 1; $attempt -le 3; $attempt++) {
      $why = ''
      try {
         Start-Process -FilePath $Exe -ArgumentList $line -WorkingDirectory $BinFolder
      } catch {
         $why = ' (' + $_.Exception.Message + ')'
      }
      if (-not $why -and (Test-Reopened)) {
         Add-Note "PixInsight has reopened (attempt $attempt)"
         Stop-Helper 0
      }
      Add-Note "attempt $attempt to reopen PixInsight did not work$why"
      Start-Sleep -Seconds 3
   }

   $null = Show-Window -Sentence (Get-Text 'notReopened') -Buttons (Get-Text 'ok')
   Remove-HelperFile $Outcome
   Remove-HelperFile $MessageScript
   Add-Note 'PixInsight did not reopen'
   Stop-Helper 1
}

# ------------------------------------------------------------------------------

try {
   # A process keeps its current folder open, and the folder that the helper
   # inherits is PixInsight's bin folder, which the installer has to delete.
   [Environment]::CurrentDirectory = $Dir
   Set-Location -LiteralPath $Dir
   # The helper has nobody to print to, so whatever a step would print is
   # dropped.
   $null = Invoke-Update
} catch {
   if (-not $script:Stopped) {
      try { Add-Note ('E ' + $_.Exception.Message) } catch { }
   }
} finally {
   # However the helper ends, it lets go of the file "alive", so that the
   # script sees that it is gone, and removes its own files. curl's
   # instructions hold the session cookie, so they must not outlive the
   # helper either.
   if ($script:Alive) {
      try { $script:Alive.Close() } catch { }
   }
   Remove-HelperFile (Join-Path $Dir 'alive')
   Remove-HelperFile (Join-Path $Dir 'curl-instructions')
   Remove-HelperFile (Join-Path $Dir 'helper.cmd')
   Remove-HelperFile $Self
   try { Add-Note 'helper finished' } catch { }
}
exit $script:ExitCode
