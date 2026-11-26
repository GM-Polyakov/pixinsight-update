// PixInsight Update Assistant, Windows test W2.
//
// Question: which way of starting a helper works from the old script engine
// on Windows, does the helper outlive PixInsight, and how can the script tell
// that the helper is alive?
//
//    PixInsight.exe -n --automation-mode --no-focus-stealing -r=<this file> --force-exit
//
// It copies w2-helper.ps1 into a folder of its own in the temporary folder,
// as the add-on will do with its helper, and starts it in seven ways:
//
//    A  startDetached( starter file )           a .cmd file, by its path alone
//    B  startDetached( starter file, folder )
//    C  startDetached( program, [ arguments ], folder )
//    D  start( program, [ arguments ] ) of a short command that starts the
//       helper hidden and then ends
//    E  execute( program, [ arguments ] ) of the same short command
//    F  start( program, [ arguments ] ) as an ordinary child
//    G  startDetached( "program arguments" ) as one string
//
// and, with the starter file that the add-on writes, whose line begins with
// start "" /b :
//
//    H  startDetached( starter file, folder ), in a folder with a space in
//       its name, the path handed over as it is
//    I  the same, the path handed over in quotes
//    J  startDetached( starter file, folder ) of a helper that shows a window
//       of its own for three seconds (w2-form.ps1)
//    K  a starter that leaves out the switch against PowerShell's rule for
//       script files: this helper must not come up
//
// Then it asks, for every helper that came up, whether the file that the
// helper holds open can be removed. For the first one it also measures how
// long Windows' own tasklist takes to say whether a process exists, and
// whether the helper's status file reads cleanly while the helper replaces it
// ten times a second.
//
// Result: w2-result.txt in the folder named by PI_UA_W_OUT. The helpers write
// their logs into the working folder.
//
// Old-engine JavaScript only. No regular-expression literal here ends in an
// escaped slash (TESTING.md, trap 1).

// Processes that have to stay referenced while the script runs.
var W2_kept = [];

function W2_env( name )
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

// A value for the inside of a single-quoted PowerShell string.
function W2_q( s )
{
   return String( s ).split( "'" ).join( "''" );
}

// Run a program and wait for it: exit code, what it printed, time taken.
function W2_run( program, args )
{
   var r = { code: -1, out: "", ms: 0 };
   var t0 = ( new Date ).getTime();
   try
   {
      var P = new ExternalProcess;
      P.start( program, args );
      if ( P.waitForFinished( 15000 ) )
         r.code = P.exitCode;
      r.out = String( P.standardOutput.toString() );
   }
   catch ( x )
   {
      r.out = "ERROR " + x;
   }
   r.ms = ( new Date ).getTime() - t0;
   return r;
}

function W2_main()
{
   var lines = [];
   function add( key, value )
   {
      lines.push( key + "=" + value );
   }

   var here = File.extractDrive( #__FILE__ ) + File.extractDirectory( #__FILE__ );
   var out = W2_env( "PI_UA_W_OUT" );
   if ( out.length == 0 )
      out = here + "/../out/windows/w2";
   if ( !File.directoryExists( out ) )
      File.createDirectory( out, true );

   var work = File.systemTempDirectory + "/PixInsightUpdateAssistant-w2";
   if ( !File.directoryExists( work ) )
      File.createDirectory( work, true );
   var workWin = File.unixPathToWindows( work );

   var root = W2_env( "SystemRoot" ).split( "\\" ).join( "/" );
   var ps = root + "/System32/WindowsPowerShell/v1.0/powershell.exe";
   var psWin = File.unixPathToWindows( ps );
   var tasklist = root + "/System32/tasklist.exe";
   var pid = String( CoreApplication.pid );
   var helper = work + "/w2-helper.ps1";
   var helperWin = File.unixPathToWindows( helper );

   File.copyFile( helper, here + "/w2-helper.ps1" );

   add( "pixinsight_pid", pid );
   add( "work", work );
   add( "powershell", ps );
   add( "powershell_exists", File.exists( ps ) );
   add( "helper_copied", File.exists( helper ) );

   var ways = [ "A", "B", "C", "D", "E", "F", "G" ];

   // The arguments that run the helper file, for one way.
   function helperArgs( way )
   {
      return [ "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", helper,
               "-Way", way, "-PixInsightPid", pid, "-Dir", work ];
   }

   // The same as one line of text, with Windows paths in quotes.
   function helperLine( way )
   {
      return "\"" + psWin + "\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + helperWin +
             "\" -Way " + way + " -PixInsightPid " + pid + " -Dir \"" + workWin + "\"";
   }

   // A starter file: that one line, with Windows line ends.
   function starter( way )
   {
      var path = work + "/w2-start-" + way + ".cmd";
      File.writeTextFile( path, "@echo off\r\n" + helperLine( way ) + "\r\n" );
      return File.unixPathToWindows( path );
   }

   // A short PowerShell command that starts the helper hidden and then ends.
   function hiddenStart( way )
   {
      return "Start-Process -FilePath '" + W2_q( ps ) + "' -WindowStyle Hidden -ArgumentList " +
             "'-NoProfile -ExecutionPolicy Bypass -File \"" + W2_q( helper ) + "\" -Way " + way +
             " -PixInsightPid " + pid + " -Dir \"" + W2_q( work ) + "\"'";
   }

   function attempt( way, f )
   {
      var r;
      try
      {
         r = "returned " + String( f() );
      }
      catch ( x )
      {
         r = "threw " + x;
      }
      add( "start_" + way, r );
   }

   attempt( "A", function()
   {
      return ExternalProcess.startDetached( starter( "A" ) );
   } );
   attempt( "B", function()
   {
      return ExternalProcess.startDetached( starter( "B" ), work );
   } );
   attempt( "C", function()
   {
      return ExternalProcess.startDetached( ps, helperArgs( "C" ), work );
   } );
   attempt( "D", function()
   {
      var P = new ExternalProcess;
      P.start( ps, [ "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", hiddenStart( "D" ) ] );
      var done = P.waitForFinished( 30000 );
      return "finished " + done + ", exit code " + P.exitCode;
   } );
   attempt( "E", function()
   {
      return "exit code " + ExternalProcess.execute( ps, [ "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", hiddenStart( "E" ) ] );
   } );
   attempt( "F", function()
   {
      var Q = new ExternalProcess;
      Q.start( ps, helperArgs( "F" ) );
      W2_kept.push( Q );
      return "started " + Q.waitForStarted( 10000 );
   } );
   attempt( "G", function()
   {
      return ExternalProcess.startDetached( helperLine( "G" ) );
   } );

   // Three more ways, added after the first run of this test. They use the
   // starter that the add-on writes: its line begins with  start "" /b , so
   // that the command interpreter that runs the starter ends at once and
   // keeps nothing open.
   function quickStarter( dir, way, line )
   {
      var path = dir + "/w2-start-" + way + ".cmd";
      File.writeTextFile( path, "@echo off\r\nstart \"\" /b " + line + "\r\n" );
      return File.unixPathToWindows( path );
   }

   // H and I: a working folder with a space in its name, as the temporary
   // folder of a user whose name has a space. H hands the starter's path over
   // as it is, I hands it over in quotes.
   var spaced = File.systemTempDirectory + "/PixInsightUpdateAssistant w2 space";
   if ( !File.directoryExists( spaced ) )
      File.createDirectory( spaced, true );
   File.copyFile( spaced + "/w2-helper.ps1", here + "/w2-helper.ps1" );
   function spacedLine( way )
   {
      return "\"" + psWin + "\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" +
             File.unixPathToWindows( spaced + "/w2-helper.ps1" ) + "\" -Way " + way + " -PixInsightPid " + pid +
             " -Dir \"" + File.unixPathToWindows( spaced ) + "\"";
   }
   attempt( "H", function()
   {
      return ExternalProcess.startDetached( quickStarter( spaced, "H", spacedLine( "H" ) ), spaced );
   } );
   attempt( "I", function()
   {
      return ExternalProcess.startDetached( "\"" + quickStarter( spaced, "I", spacedLine( "I" ) ) + "\"", spaced );
   } );

   // J: a helper that shows a window of its own for three seconds, started
   // by PixInsight exactly as the add-on starts its helper. The runner's
   // window watcher records whether the window came onto the screen.
   File.copyFile( work + "/w2-form.ps1", here + "/w2-form.ps1" );
   attempt( "J", function()
   {
      return ExternalProcess.startDetached( quickStarter( work, "J", "\"" + psWin +
         "\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + File.unixPathToWindows( work + "/w2-form.ps1" ) +
         "\" -Tag from-pixinsight -Dir \"" + workWin + "\"" ), work );
   } );

   // K: the counter-test for PowerShell's rule against script files. Its
   // starter leaves out the switch that lifts the rule for the one run. If
   // this PixInsight was started without that switch in its environment, as
   // one opened from the Start menu is, this helper must NOT come up.
   add( "rule_for_script_files_in_the_environment", W2_env( "PSExecutionPolicyPreference" ).length > 0 ? W2_env( "PSExecutionPolicyPreference" ) : "none" );
   attempt( "K", function()
   {
      return ExternalProcess.startDetached( quickStarter( work, "K", "\"" + psWin +
         "\" -NoProfile -WindowStyle Hidden -File \"" + helperWin + "\" -Way K -PixInsightPid " + pid + " -Dir \"" + workWin + "\"" ), work );
   } );

   // Give the helpers up to eight seconds to come up.
   for ( var k = 0; k < 80; ++k )
   {
      var n = 0;
      for ( var i = 0; i < ways.length; ++i )
         if ( File.exists( work + "/w2-pid-" + ways[i] + ".txt" ) )
            ++n;
      if ( n == ways.length )
         break;
      msleep( 100 );
   }
   // One more moment, so that each has opened the file it holds.
   msleep( 1000 );

   var first = "", firstPid = "";
   for ( var j = 0; j < ways.length; ++j )
   {
      var w = ways[j], pidFile = work + "/w2-pid-" + w + ".txt";
      if ( !File.exists( pidFile ) )
      {
         add( "helper_" + w, "did not come up" );
         continue;
      }
      var hp = "";
      try
      {
         hp = File.readTextFile( pidFile ).replace( /\s+/g, "" );
      }
      catch ( x )
      {
      }
      add( "helper_" + w, "process " + hp );

      // The helper holds this file open and shares it with nobody.
      var lock = work + "/w2-lock-" + w, held;
      try
      {
         File.remove( lock );
         held = "no error from the attempt to remove it";
      }
      catch ( x )
      {
         held = "the attempt to remove it failed: " + x;
      }
      add( "held_file_" + w, held );
      add( "held_file_still_there_" + w, File.exists( lock ) );

      if ( first.length == 0 && hp.length > 0 )
      {
         first = w;
         firstPid = hp;
      }
   }

   // The three later ways.
   var later = [ "H", "I" ];
   for ( var m = 0; m < later.length; ++m )
   {
      var hpFile = spaced + "/w2-pid-" + later[m] + ".txt", hpText = "did not come up";
      if ( File.exists( hpFile ) )
         try
         {
            hpText = "process " + File.readTextFile( hpFile ).replace( /\s+/g, "" );
         }
         catch ( x )
         {
         }
      add( "helper_" + later[m], hpText );
   }
   add( "helper_J", File.exists( work + "/w2-form-from-pixinsight.txt" ) ? "came up" : "did not come up" );
   add( "helper_K", File.exists( work + "/w2-pid-K.txt" ) ? "came up, although its starter leaves out the switch" : "did not come up, as it must not" );

   add( "first_helper", first.length > 0 ? first : "none" );
   if ( first.length > 0 )
   {
      // Windows' own list of processes, asked for one process number.
      var t = W2_run( tasklist, [ "/FI", "PID eq " + firstPid, "/FO", "CSV", "/NH" ] );
      add( "tasklist_exit_code", t.code );
      add( "tasklist_ms", t.ms );
      add( "tasklist_finds_helper", t.out.indexOf( "\"" + firstPid + "\"" ) >= 0 );
      // Process numbers on Windows are multiples of four, so this one is free.
      var u = W2_run( tasklist, [ "/FI", "PID eq 999999", "/FO", "CSV", "/NH" ] );
      add( "tasklist_absent_exit_code", u.code );
      add( "tasklist_absent_ms", u.ms );
      add( "tasklist_absent_says", u.out.replace( /\s+/g, " " ).substring( 0, 80 ) );

      // The status file, read 300 times while the helper keeps replacing it.
      var statusPath = work + "/w2-status-" + first;
      for ( var s = 0; s < 100 && !File.exists( statusPath ); ++s )
         msleep( 100 );
      var whole = 0, incomplete = 0, missing = 0, errors = 0, lastError = "", firstCount = "", lastCount = "";
      for ( var q = 0; q < 300; ++q )
      {
         try
         {
            if ( !File.exists( statusPath ) )
               ++missing;
            else
            {
               var text = File.readTextFile( statusPath );
               if ( text.indexOf( "phase=testing\n" ) == 0 && text.indexOf( "\nend=1\n" ) > 0 )
               {
                  ++whole;
                  var c = text.split( "\n" )[1];
                  if ( firstCount.length == 0 )
                     firstCount = c;
                  lastCount = c;
               }
               else
                  ++incomplete;
            }
         }
         catch ( x )
         {
            ++errors;
            lastError = String( x );
         }
         msleep( 20 );
      }
      add( "status_reads", "300 reads: " + whole + " whole, " + incomplete + " incomplete, " + missing + " missing, " + errors + " errors" );
      add( "status_first_read", firstCount );
      add( "status_last_read", lastCount );
      if ( errors > 0 )
         add( "status_last_error", lastError );
   }

   File.writeTextFile( out + "/w2-result.txt", lines.join( "\n" ) + "\n" );
}

try
{
   W2_main();
}
catch ( x )
{
   try
   {
      File.writeTextFile( File.systemTempDirectory + "/pi-update-assistant-w2-error.txt", "error=" + x + ( x.lineNumber ? " (line " + x.lineNumber + ")" : "" ) + "\n" );
   }
   catch ( y )
   {
   }
}
