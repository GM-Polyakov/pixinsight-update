# PixInsight Update Assistant, Windows test W2, third part: what a helper
# inherits from PixInsight.
#
# A program that PixInsight starts through a starter file can inherit files
# that PixInsight has open. A helper that keeps such a file open while
# PixInsight's installer runs could be in the installer's way. So this helper
# lists every file and folder that it holds open at its start, says for each
# whether it came by inheritance, and marks those inside the PixInsight folder.
# Then it asks PixInsight to close, the normal way.
#
#    -PixInsightPid  the process number of the PixInsight that started it
#    -Dir            the working folder; the log is w2-handles-log.txt there
#    -Folder         the PixInsight folder
#    -Release        after the first list, close every inherited file and
#                    list again, to show that a helper can let go of them
#
# Windows PowerShell 5.1, plain ASCII.

param([int]$PixInsightPid = 0, [string]$Dir = '.', [string]$Folder = '', [switch]$Release)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding $false
$log = Join-Path $Dir 'w2-handles-log.txt'

function Add-Note {
   param([string]$Text)
   [IO.File]::AppendAllText($log, ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $Text + "`n"), $utf8)
}

try {
   Add-Note ("helper started; process $PID; current folder " + [Environment]::CurrentDirectory)

   Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class UAHandles
{
   [DllImport("kernel32.dll")] static extern bool GetHandleInformation( IntPtr h, out uint flags );
   [DllImport("kernel32.dll")] static extern uint GetFileType( IntPtr h );
   [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern uint GetFinalPathNameByHandleW( IntPtr h, StringBuilder s, uint n, uint flags );

   // Every file or folder on a disk that this process holds open, as
   // "inheritable|path" or "own|path". A handle that a process inherited is
   // still marked as inheritable in that process.
   public static List<string> DiskFiles()
   {
      List<string> found = new List<string>();
      for ( long v = 4; v <= 0x10000; v += 4 )
      {
         IntPtr h = new IntPtr( v );
         uint flags;
         if ( !GetHandleInformation( h, out flags ) )
            continue;
         if ( GetFileType( h ) != 1 )
            continue;
         StringBuilder s = new StringBuilder( 2048 );
         uint n = GetFinalPathNameByHandleW( h, s, 2048, 0 );
         if ( n == 0 || n >= 2048 )
            continue;
         found.Add( ( ( flags & 1 ) != 0 ? "inheritable" : "own" ) + "|" + s.ToString() );
      }
      return found;
   }

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

   $all = [UAHandles]::DiskFiles()
   $inherited = @($all | Where-Object { $_.StartsWith('inheritable|') })
   $inside = @()
   if ($Folder) {
      $needle = ('\\?\' + ($Folder -replace '/', '\')).TrimEnd('\')
      $inside = @($all | Where-Object { ($_ -split '\|', 2)[1].StartsWith($needle, [StringComparison]::OrdinalIgnoreCase) })
   }
   Add-Note "files and folders held open: $($all.Count); of them marked as inheritable: $($inherited.Count); of them inside the PixInsight folder: $($inside.Count)"
   foreach ($line in $inherited) { Add-Note "  inheritable: $(($line -split '\|', 2)[1])" }
   foreach ($line in $inside) { Add-Note "  inside the PixInsight folder: $line" }

   $me = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
   $parent = Get-Process -Id $me.ParentProcessId -ErrorAction SilentlyContinue
   Add-Note ("the program that started this helper, process $($me.ParentProcessId), is " +
      $(if ($parent) { "still running ($($parent.ProcessName))" } else { 'gone' }))

   if ($Release) {
      $closed = [UAHandles]::ReleaseInherited()
      $after = @([UAHandles]::DiskFiles() | Where-Object { $_.StartsWith('inheritable|') })
      Add-Note "inherited files closed: $closed; still marked as inheritable afterwards: $($after.Count)"
   }

   # Close PixInsight the normal way, so that the test leaves nothing open.
   Start-Sleep -Seconds 2
   $p = Get-Process -Id $PixInsightPid -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq 'PixInsight' }
   if ($p) {
      $sent = $p.CloseMainWindow()
      Add-Note "close request sent to PixInsight: $sent"
      if ($p.WaitForExit(20000)) { Add-Note 'PixInsight exited' } else { Add-Note 'PixInsight is still running 20 s later' }
   } else {
      Add-Note 'PixInsight was not running'
   }
} catch {
   try { Add-Note ('E ' + $_.Exception.Message) } catch { }
}
try { Add-Note 'helper finished' } catch { }
