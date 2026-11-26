// PixInsight Update Assistant, Windows test W1.
//
// Question: does a script written for PixInsight's old script engine load on
// Windows, and what does PixInsight report about itself there?
//
//    PixInsight.exe -n --automation-mode --no-focus-stealing -r=<this file> --force-exit
//
// It starts no program, contacts nothing and changes nothing in PixInsight.
// It writes w1-result.txt, and for a moment w1-scratch.txt, into the folder
// named by the environment variable PI_UA_W_OUT, or into ../out/windows next
// to this file.
//
// Old-engine JavaScript only. No regular-expression literal here ends in an
// escaped slash (TESTING.md, trap 1).

function W1_env( name )
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

// What f() gives, as text, or the error it throws.
function W1_ask( f )
{
   try
   {
      return String( f() );
   }
   catch ( x )
   {
      return "ERROR " + x;
   }
}

// Does the engine accept this piece of JavaScript?
function W1_accepts( code )
{
   try
   {
      new Function( code );
      return "yes";
   }
   catch ( x )
   {
      return "no";
   }
}

function W1_main()
{
   var lines = [];
   function add( key, value )
   {
      lines.push( key + "=" + value );
   }

   var here = File.extractDrive( #__FILE__ ) + File.extractDirectory( #__FILE__ );
   var out = W1_env( "PI_UA_W_OUT" );
   if ( out.length == 0 )
      out = here + "/../out/windows";
   if ( !File.directoryExists( out ) )
      File.createDirectory( out, true );

   // --- What PixInsight says it is ------------------------------------------
   add( "version", CoreApplication.versionMajor + "." + CoreApplication.versionMinor + "." + CoreApplication.versionRelease + "-" + CoreApplication.versionRevision );
   add( "build", W1_ask( function() { return CoreApplication.versionBuild; } ) );
   add( "codename", W1_ask( function() { return CoreApplication.versionCodename; } ) );
   add( "beta", W1_ask( function() { return CoreApplication.versionBeta; } ) );
   add( "platform", W1_ask( function() { return CoreApplication.platform; } ) );
   add( "platform_matches_mac", /mac/i.test( String( CoreApplication.platform ) ) );
   add( "platform_matches_win", /win/i.test( String( CoreApplication.platform ) ) );
   add( "agent", W1_ask( function() { return CoreApplication.agentName; } ) );
   add( "instance", W1_ask( function() { return CoreApplication.instance; } ) );
   add( "pid", W1_ask( function() { return CoreApplication.pid; } ) );
   add( "automation_mode", W1_ask( function() { return CoreApplication.automationMode; } ) );
   add( "other_instances_running", W1_ask( function() { return CoreApplication.otherInstancesRunning(); } ) );

   // --- Where it is, in the form it uses for paths --------------------------
   add( "file_path", W1_ask( function() { return CoreApplication.filePath; } ) );
   add( "dir_path", W1_ask( function() { return CoreApplication.dirPath; } ) );
   add( "base_dir_path", W1_ask( function() { return CoreApplication.baseDirPath; } ) );
   add( "app_dir_path", W1_ask( function() { return CoreApplication.appDirPath; } ) );
   add( "bin_dir_path", W1_ask( function() { return CoreApplication.binDirPath; } ) );
   add( "src_dir_path", W1_ask( function() { return CoreApplication.srcDirPath; } ) );
   add( "temp_dir", W1_ask( function() { return File.systemTempDirectory; } ) );
   add( "home_dir", W1_ask( function() { return File.homeDirectory; } ) );
   add( "this_file", #__FILE__ );
   add( "this_file_drive", W1_ask( function() { return File.extractDrive( #__FILE__ ); } ) );
   add( "this_file_dir", W1_ask( function() { return File.extractDirectory( #__FILE__ ); } ) );
   add( "env_TEMP", W1_env( "TEMP" ) );
   add( "env_SystemRoot", W1_env( "SystemRoot" ) );
   add( "env_PI_UA_W_OUT", W1_env( "PI_UA_W_OUT" ) );

   // --- Which script engine ran this ----------------------------------------
   add( "accepts_let", W1_accepts( "let a = 1; return a;" ) );
   add( "accepts_arrow", W1_accepts( "var f = ( a ) => a + 1; return f( 1 );" ) );
   add( "accepts_class", W1_accepts( "class A { constructor() { this.a = 1; } } return new A;" ) );
   add( "accepts_template", W1_accepts( "var s = " + String.fromCharCode( 96 ) + "a" + String.fromCharCode( 96 ) + "; return s;" ) );
   add( "has_Promise", typeof Promise );
   add( "has_Symbol", typeof Symbol );

   // --- What the add-on needs -----------------------------------------------
   add( "ExternalProcess.startDetached", W1_ask( function() { return typeof ExternalProcess.startDetached; } ) );
   add( "ExternalProcess.execute", W1_ask( function() { return typeof ExternalProcess.execute; } ) );
   add( "NetworkTransfer", typeof NetworkTransfer );
   add( "Dialog", typeof Dialog );
   add( "Timer", typeof Timer );
   add( "Edit", typeof Edit );
   add( "MessageBox", typeof MessageBox );
   add( "ByteArray.fromHex", W1_ask( function() { return typeof ByteArray.fromHex; } ) );
   add( "ByteArray.secureFill", W1_ask( function() { return typeof ( new ByteArray ).secureFill; } ) );
   add( "File.writeFile", W1_ask( function() { return typeof File.writeFile; } ) );
   add( "File.setPermissions", W1_ask( function() { return typeof File.setPermissions; } ) );
   add( "getEnvironmentVariable", typeof getEnvironmentVariable );
   add( "msleep", typeof msleep );
   add( "processEvents", typeof processEvents );
   add( "encodeURIComponent", typeof encodeURIComponent );
   add( "Runtime", typeof Runtime );
   add( "System", typeof System );

   // --- Files, as the add-on uses them --------------------------------------
   var scratch = out + "/w1-scratch.txt";
   add( "write_text", W1_ask( function() { File.writeTextFile( scratch, "one\ntwo\n" ); return "ok"; } ) );
   // Eight characters and eight bytes if a line end stays a line feed.
   add( "read_text_length", W1_ask( function() { return File.readTextFile( scratch ).length; } ) );
   add( "read_bytes_length", W1_ask( function() { return File.readFile( scratch ).length; } ) );
   add( "exists_with_slashes", W1_ask( function() { return File.exists( scratch ); } ) );
   add( "exists_with_backslashes", W1_ask( function() { return File.exists( scratch.split( "/" ).join( "\\" ) ); } ) );
   add( "set_permissions_owner_only", W1_ask( function() { File.setPermissions( scratch, 0x00300000 ); return "ok"; } ) );
   add( "readable_after_permissions", W1_ask( function() { return File.readTextFile( scratch ).length; } ) );
   add( "write_bytes", W1_ask( function() { File.writeFile( scratch, ByteArray.fromHex( "4d5a0a" ) ); return "ok"; } ) );
   add( "read_bytes_back", W1_ask( function() { return File.readFile( scratch ).toHex(); } ) );
   add( "remove", W1_ask( function() { File.remove( scratch ); return "ok"; } ) );
   add( "exists_after_remove", W1_ask( function() { return File.exists( scratch ); } ) );
   add( "unix_path_to_windows", W1_ask( function() { return File.unixPathToWindows( scratch ); } ) );
   add( "windows_path_to_unix", W1_ask( function() { return File.windowsPathToUnix( "C:\\one\\two" ); } ) );

   // --- Listing a folder, as the add-on does to look into the PixInsight folder
   add( "FileFind", typeof FileFind );
   add( "top_of_the_pixinsight_folder", W1_ask( function()
   {
      var names = [], find = new FileFind;
      if ( find.begin( String( CoreApplication.baseDirPath ) + "/*" ) )
         do
         {
            if ( find.name != "." && find.name != ".." )
               names.push( find.name + ( find.isDirectory ? "/" : "" ) );
         }
         while ( find.next() );
      find.end();
      names.sort();
      return names.join( " " );
   } ) );

   File.writeTextFile( out + "/w1-result.txt", lines.join( "\n" ) + "\n" );
}

try
{
   W1_main();
}
catch ( x )
{
   try
   {
      File.writeTextFile( File.systemTempDirectory + "/pi-update-assistant-w1-error.txt", "error=" + x + ( x.lineNumber ? " (line " + x.lineNumber + ")" : "" ) + "\n" );
   }
   catch ( y )
   {
   }
}
