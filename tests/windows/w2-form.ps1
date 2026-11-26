# PixInsight Update Assistant, Windows test W2, second part: a helper that
# shows a window of its own.
#
# The helper asks "Restart now, or later?" in a small window. This file shows
# such a window for three seconds and writes down whether Windows really put
# it on the screen. run-w2-form.ps1 starts it in the ways in which a helper
# can be started hidden, because Windows may also hide the window of a program
# that was itself started hidden.
#
#    -Tag       a name for this run, used in the window's title and the log
#    -Dir       the folder for the log, w2-form-<Tag>.txt
#    -Modeless  show the window with Show() and keep it alive in a loop of
#               this script, where the plain way is ShowDialog(), which waits
#               inside Windows Forms until the window closes
#
# Windows PowerShell 5.1, plain ASCII.

param([string]$Tag = 'test', [string]$Dir = '.', [switch]$Modeless)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding $false
$log = Join-Path $Dir "w2-form-$Tag.txt"

function Add-Note {
   param([string]$Text)
   [IO.File]::AppendAllText($log, ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $Text + "`n"), $utf8)
}

try {
   Add-Type -AssemblyName System.Windows.Forms
   $native = Add-Type -Name W2FormNative -Namespace UA -PassThru -MemberDefinition (
      '[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h); ' +
      '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();')
   $console = $native::GetConsoleWindow()
   if ($console -eq [IntPtr]::Zero) {
      Add-Note 'started; console window: none'
   } else {
      Add-Note ('started; console window: exists; visible: ' + $native::IsWindowVisible($console))
   }

   $form = New-Object System.Windows.Forms.Form
   $form.Text = "Update Assistant window test ($Tag)"
   $form.TopMost = $true
   $form.StartPosition = 'CenterScreen'
   $form.Width = 460
   $form.Height = 150
   $label = New-Object System.Windows.Forms.Label
   $label.Text = 'A test of PixInsight Update Assistant. This window closes by itself in three seconds.'
   $label.Dock = 'Fill'
   $label.TextAlign = 'MiddleCenter'
   $form.Controls.Add($label)

   $script:ticks = 0
   $timer = New-Object System.Windows.Forms.Timer
   $timer.Interval = 1000
   $timer.Add_Tick({
      $script:ticks++
      if ($script:ticks -eq 1) {
         Add-Note ('one second after it was shown: Windows says the window is visible: ' +
            $native::IsWindowVisible($form.Handle) + '; the window itself says: ' + $form.Visible)
      }
      if ($script:ticks -ge 3) {
         $timer.Stop()
         $form.Close()
      }
   })
   $form.Add_Shown({ $timer.Start() })
   if ($Modeless) {
      $form.Show()
      while ($form.Visible) {
         [System.Windows.Forms.Application]::DoEvents()
         Start-Sleep -Milliseconds 30
      }
   } else {
      [void]$form.ShowDialog()
   }
   Add-Note 'closed'
} catch {
   try { Add-Note ('E ' + $_.Exception.Message) } catch { }
}
