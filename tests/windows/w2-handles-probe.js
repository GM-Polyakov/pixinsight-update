// PixInsight Update Assistant, Windows test W2, third part.
//
// Question: what does a helper inherit from PixInsight when it is started
// through a starter file, and does any of it lie inside the PixInsight folder,
// where it could be in the installer's way?
//
// PixInsight runs this file at startup, in an ordinary session, so that it
// has everything open that it has open when a person uses it. Use
// run-w2-handles.ps1. The helper, w2-handles.ps1, lists what it holds open and
// then asks PixInsight to close.
//
// Old-engine JavaScript only. No regular-expression literal here ends in an
// escaped slash (TESTING.md, trap 1).

function W2H_env( name )
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

function W2H_main()
{
   var here = File.extractDrive( #__FILE__ ) + File.extractDirectory( #__FILE__ );
   var out = W2H_env( "PI_UA_W_OUT" );
   if ( out.length == 0 )
      out = here + "/../out/windows/w2";
   if ( !File.directoryExists( out ) )
      File.createDirectory( out, true );

   var work = File.systemTempDirectory + "/PixInsightUpdateAssistant-w2handles";
   if ( !File.directoryExists( work ) )
      File.createDirectory( work, true );
   var root = W2H_env( "SystemRoot" ).split( "\\" ).join( "/" );
   var psWin = File.unixPathToWindows( root + "/System32/WindowsPowerShell/v1.0/powershell.exe" );
   var helper = work + "/w2-handles.ps1";
   File.copyFile( helper, here + "/w2-handles.ps1" );

   var starter = work + "/w2-handles-start.cmd";
   File.writeTextFile( starter, "@echo off\r\n\"" + psWin + "\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" +
      File.unixPathToWindows( helper ) + "\" -PixInsightPid " + CoreApplication.pid + " -Dir \"" + File.unixPathToWindows( work ) +
      "\" -Folder \"" + File.unixPathToWindows( String( CoreApplication.baseDirPath ) ) + "\"\r\n" );

   var L = [ "pid=" + CoreApplication.pid, "base_dir_path=" + CoreApplication.baseDirPath ];
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
   File.writeTextFile( out + "/w2-handles-script.txt", L.join( "\n" ) + "\n" );
}

try
{
   W2H_main();
}
catch ( x )
{
   try
   {
      File.writeTextFile( File.systemTempDirectory + "/pi-update-assistant-w2h-error.txt", "error=" + x + ( x.lineNumber ? " (line " + x.lineNumber + ")" : "" ) + "\n" );
   }
   catch ( y )
   {
   }
}
