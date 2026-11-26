# PixInsight Update Assistant: the download step for Windows, on its own, so
# that test W3 can try it before the helper exists. The helper carries the
# same functions.
#
# Windows PowerShell 5.1, plain ASCII.

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
   $psi.Arguments = '-K curl-instructions'
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
