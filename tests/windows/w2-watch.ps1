# PixInsight Update Assistant, Windows test W2: the window watcher.
#
# While the test runs, this looks at the screen's list of visible top-level
# windows about sixty times a second and records every window that was not
# there when the watcher started. That is how the test learns whether a way
# of starting the helper lets a console window show, even for a moment.
#
# A window's title is recorded only for console windows and for the programs
# the test itself starts. For every other window only the program's name and
# the kind of window are kept.
#
#    -Out    the file that gets the record
#    -Ready  written when the watcher has taken its first look
#    -Stop   the watcher ends when this file appears
#    -Also   more program names whose window titles are recorded, with commas
#            between them. Test W4 names PixInsight here.
#
# Windows PowerShell 5.1, plain ASCII.

param([string]$Out, [string]$Ready, [string]$Stop, [string]$Also = '')

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class UAWindows
{
   delegate bool EnumProc( IntPtr h, IntPtr l );
   [DllImport("user32.dll")] static extern bool EnumWindows( EnumProc f, IntPtr l );
   [DllImport("user32.dll")] static extern bool IsWindowVisible( IntPtr h );
   [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId( IntPtr h, out uint pid );
   [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName( IntPtr h, StringBuilder s, int n );
   [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText( IntPtr h, StringBuilder s, int n );

   public static List<long> Visible()
   {
      List<long> found = new List<long>();
      EnumWindows( delegate( IntPtr h, IntPtr l ) { if ( IsWindowVisible( h ) ) found.Add( h.ToInt64() ); return true; }, IntPtr.Zero );
      return found;
   }

   public static uint Owner( long h )
   {
      uint pid;
      GetWindowThreadProcessId( new IntPtr( h ), out pid );
      return pid;
   }

   public static string Kind( long h )
   {
      StringBuilder s = new StringBuilder( 256 );
      GetClassName( new IntPtr( h ), s, 256 );
      return s.ToString();
   }

   public static string Title( long h )
   {
      StringBuilder s = new StringBuilder( 256 );
      GetWindowText( new IntPtr( h ), s, 256 );
      return s.ToString();
   }

   [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
   [DllImport("user32.dll")] static extern bool GetLastInputInfo( ref LASTINPUTINFO info );

   // Seconds since anybody last touched the keyboard or the mouse.
   public static double IdleSeconds()
   {
      LASTINPUTINFO info = new LASTINPUTINFO();
      info.cbSize = (uint)Marshal.SizeOf( typeof( LASTINPUTINFO ) );
      if ( !GetLastInputInfo( ref info ) )
         return -1;
      return unchecked( (uint)Environment.TickCount - info.dwTime )/1000.0;
   }
}
'@

$ours = @('powershell', 'cmd', 'conhost', 'OpenConsole', 'WindowsTerminal', 'wscript', 'cscript', 'tasklist', 'curl')
if ($Also) { $ours += ($Also -split ',') }
$consoleKinds = 'ConsoleWindowClass', 'CASCADIA_HOSTING_WINDOW_CLASS'

$known = New-Object 'System.Collections.Generic.HashSet[long]'
foreach ($h in [UAWindows]::Visible()) { [void]$known.Add($h) }
$lines = New-Object 'System.Collections.Generic.List[string]'
$began = Get-Date
[IO.File]::WriteAllText($Ready, "ready`n")

# Windows of the test's own programs are also watched for the moment they go
# away, together with the time since anybody last touched the keyboard or the
# mouse. That time tells a window that a person closed from one that closed
# by itself.
$tracked = @{}

while (-not [IO.File]::Exists($Stop)) {
   $now = New-Object 'System.Collections.Generic.HashSet[long]'
   foreach ($h in [UAWindows]::Visible()) {
      [void]$now.Add($h)
      if ($known.Add($h)) {
         $ms = [int]((Get-Date) - $began).TotalMilliseconds
         $owner = [UAWindows]::Owner($h)
         $name = (Get-Process -Id $owner -ErrorAction SilentlyContinue).ProcessName
         $kind = [UAWindows]::Kind($h)
         $line = "$ms ms  program=$name ($owner)  kind=$kind"
         if (($ours -contains $name) -or ($consoleKinds -contains $kind)) {
            $what = "program=$name ($owner)  kind=$kind  title=" + [UAWindows]::Title($h)
            $line = "$ms ms  appeared: $what"
            $tracked[$h] = $what
         }
         $lines.Add($line)
      }
   }
   foreach ($h in @($tracked.Keys)) {
      if (-not $now.Contains($h)) {
         $ms = [int]((Get-Date) - $began).TotalMilliseconds
         $idle = [math]::Round([UAWindows]::IdleSeconds(), 1)
         $lines.Add("$ms ms  went away: $($tracked[$h])  last keyboard or mouse input $idle s before")
         $tracked.Remove($h)
      }
   }
   Start-Sleep -Milliseconds 15
}

[IO.File]::WriteAllLines($Out, $lines)
