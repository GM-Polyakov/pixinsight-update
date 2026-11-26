// PixInsight Update Assistant, Windows test W4.
//
// Question: can a helper ask PixInsight on Windows to close the normal way,
// and what happens when a window of a script is open, or an image is unsaved?
//
// PixInsight runs this file at startup, in an ordinary session (not automation
// mode, which would answer PixInsight's own questions by itself), and stays
// open. Use run-w4.ps1.
//
// What it does, all of it harmless:
//    1. In the mode "unsaved", creates a small grey image that was never
//       saved. In the other modes, creates nothing.
//    2. Copies w4-helper.ps1 into a working folder, writes a starter file and
//       starts the helper through it, the way test W2 found to work.
//    3. In the mode "window", opens a window of its own for sixteen seconds,
//       as the add-on's progress window would be open, and marks it with the
//       file w4-window-open for as long as it is open.
//
// The mode comes from the environment variable PI_UA_W_MODE: clean, window or
// unsaved. The result goes to w4-script-<mode>.txt in the folder named by
// PI_UA_W_OUT.
//
// Old-engine JavaScript only. No regular-expression literal here ends in an
// escaped slash (TESTING.md, trap 1).

#include <pjsr/Sizer.jsh>

function W4_env( name )
{
   var v = "";
   try
   {
      v = getEnvironmentVariable( name );
   }
   catch ( x )
   {
   }
   return ( v === undefined || v === null ) ? "" : String( v );
}

function W4_main()
{
   var here = File.extractDrive( #__FILE__ ) + File.extractDirectory( #__FILE__ );
   var out = W4_env( "PI_UA_W_OUT" );
   if ( out.length == 0 )
      out = here + "/../out/windows/w4";
   if ( !File.directoryExists( out ) )
      File.createDirectory( out, true );
   var mode = W4_env( "PI_UA_W_MODE" );
   if ( mode != "window" && mode != "unsaved" )
      mode = "clean";
   var resultPath = out + "/w4-script-" + mode + ".txt";

   var work = File.systemTempDirectory + "/PixInsightUpdateAssistant-w4";
   if ( !File.directoryExists( work ) )
      File.createDirectory( work, true );
   var workWin = File.unixPathToWindows( work );
   var root = W4_env( "SystemRoot" ).split( "\\" ).join( "/" );
   var psWin = File.unixPathToWindows( root + "/System32/WindowsPowerShell/v1.0/powershell.exe" );
   var helper = work + "/w4-helper.ps1";
   var pid = String( CoreApplication.pid );

   var L = [ "mode=" + mode, "pid=" + pid, "instance=" + CoreApplication.instance ];

   // 1. An unsaved image.
   if ( mode == "unsaved" )
   {
      var w = new ImageWindow( 256, 256, 1, 32, true, false, "update_assistant_test" );
      w.mainView.beginProcess();
      w.mainView.image.fill( 0.25 );
      w.mainView.endProcess();
      w.show();
      L.push( "unsaved_image=" + w.mainView.id );
   }

   // 2. The helper, through a starter file.
   File.copyFile( helper, here + "/w4-helper.ps1" );
   var starter = work + "/w4-start.cmd";
   File.writeTextFile( starter, "@echo off\r\n\"" + psWin + "\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" +
      File.unixPathToWindows( helper ) + "\" -Mode " + mode + " -PixInsightPid " + pid + " -Dir \"" + workWin + "\"\r\n" );
   var started = 0;
   try
   {
      started = ExternalProcess.startDetached( File.unixPathToWindows( starter ), work );
   }
   catch ( x )
   {
      L.push( "start_error=" + x );
   }
   L.push( "helper_started=" + started );
   File.writeTextFile( resultPath, L.join( "\n" ) + "\n" );

   // 3. A window of this script, open for sixteen seconds.
   if ( mode == "window" )
   {
      var dialog = new Dialog;
      dialog.windowTitle = "Update Assistant test W4";
      var label = new Label( dialog );
      label.text = "A test of PixInsight Update Assistant. This window closes by itself in 16 seconds.";
      dialog.sizer = new VerticalSizer;
      dialog.sizer.margin = 12;
      dialog.sizer.add( label );
      dialog.adjustToContents();

      var closer = new Timer( 16, false );
      closer.dialog = dialog;
      closer.onTimeout = function()
      {
         this.dialog.cancel();
      };

      var mark = work + "/w4-window-open";
      File.writeTextFile( mark, "open\n" );
      closer.start();
      try
      {
         dialog.execute();
      }
      finally
      {
         try
         {
            File.remove( mark );
         }
         catch ( x )
         {
         }
      }
      L.push( "window_closed=yes" );
      File.writeTextFile( resultPath, L.join( "\n" ) + "\n" );
   }
}

try
{
   W4_main();
}
catch ( x )
{
   try
   {
      File.writeTextFile( File.systemTempDirectory + "/pi-update-assistant-w4-error.txt", "error=" + x + ( x.lineNumber ? " (line " + x.lineNumber + ")" : "" ) + "\n" );
   }
   catch ( y )
   {
   }
}
