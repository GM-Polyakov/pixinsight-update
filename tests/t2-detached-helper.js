// Test 1 (what PixInsight reports about itself) and
// test 2 (can an unsigned script start a helper that outlives PixInsight?).
//
// PixInsight runs this file at startup and then exits by itself:
//    PixInsight -n --automation-mode -r=<this file> --force-exit
// Use run-t2.sh, which does that and prints the results.
//
// Everything this file does is harmless:
//    1. It writes what PixInsight reports about itself to out/t1-runtime.txt.
//    2. It writes six copies of a small shell script, out/t2-helper-<way>.sh.
//    3. It starts each copy in a different way, and ends.
// Each shell script waits until PixInsight has exited, then adds two lines to
// its own log, out/t2-log-<way>.txt. A log that reaches line 3 shows that this
// way of starting a helper outlives PixInsight.
//
// Written for the old script engine (PixInsight 1.9.3 and earlier):
// no classes, no template strings.

function typeOf( f )
{
   try
   {
      return typeof f();
   }
   catch ( x )
   {
      return "missing (" + x + ")";
   }
}

function valueOf( f )
{
   try
   {
      return String( f() );
   }
   catch ( x )
   {
      return "failed (" + x + ")";
   }
}

function compiles( source )
{
   try
   {
      new Function( source );
      return "yes";
   }
   catch ( x )
   {
      return "no";
   }
}

// Plain child processes must stay referenced, or the engine may discard them.
var keepAlive = [];

function main()
{
   var dir = File.extractDrive( #__FILE__ ) + File.extractDirectory( #__FILE__ );
   var out = dir + "/out";
   if ( !File.directoryExists( out ) )
      File.createDirectory( out, true );

   var L = [];

   // --- Test 1: version, platform and paths -------------------------------
   L.push( "version = " + valueOf( function() { return CoreApplication.versionMajor + "." + CoreApplication.versionMinor + "." + CoreApplication.versionRelease + "-" + CoreApplication.versionRevision; } ) );
   L.push( "build = " + valueOf( function() { return CoreApplication.versionBuild; } ) );
   L.push( "codename = " + valueOf( function() { return CoreApplication.versionCodename; } ) );
   L.push( "platform = " + valueOf( function() { return CoreApplication.platform; } ) );
   L.push( "client name sent to servers = " + valueOf( function() { return CoreApplication.agentName; } ) );
   L.push( "instance slot = " + valueOf( function() { return CoreApplication.instance; } ) );
   L.push( "program file = " + valueOf( function() { return CoreApplication.filePath; } ) );
   L.push( "install folder = " + valueOf( function() { return CoreApplication.baseDirPath; } ) );
   L.push( "application folder = " + valueOf( function() { return CoreApplication.appDirPath; } ) );

   // --- Test 1: which language features the script engine accepts ---------
   L.push( "engine control (plain function compiles) = " + compiles( "return 1;" ) );
   L.push( "engine accepts 'let' = " + compiles( "let a = 1; return a;" ) );
   L.push( "engine accepts arrow functions = " + compiles( "var f = (x) => x; return f;" ) );
   L.push( "engine accepts classes = " + compiles( "class A {}; return A;" ) );
   L.push( "engine accepts template strings = " + compiles( "return `a`;" ) );
   L.push( "typeof Promise = " + typeOf( function() { return Promise; } ) );
   L.push( "typeof Symbol = " + typeOf( function() { return Symbol; } ) );

   // --- Test 1: the functions the add-on needs -----------------------------
   L.push( "ExternalProcess.startDetached = " + typeOf( function() { return ExternalProcess.startDetached; } ) );
   L.push( "ExternalProcess.execute = " + typeOf( function() { return ExternalProcess.execute; } ) );
   L.push( "NetworkTransfer = " + typeOf( function() { return NetworkTransfer; } ) );
   L.push( "Dialog = " + typeOf( function() { return Dialog; } ) );
   L.push( "Timer = " + typeOf( function() { return Timer; } ) );
   L.push( "Edit = " + typeOf( function() { return Edit; } ) );
   L.push( "ByteArray secureFill = " + typeOf( function() { return ( new ByteArray ).secureFill; } ) );
   L.push( "File.setPermissions = " + typeOf( function() { return File.setPermissions; } ) );
   L.push( "old global coreVersionMajor = " + typeOf( function() { return coreVersionMajor; } ) );
   L.push( "old global getEnvironmentVariable = " + typeOf( function() { return getEnvironmentVariable; } ) );
   L.push( "new object Runtime = " + typeOf( function() { return Runtime; } ) );
   L.push( "new object System = " + typeOf( function() { return System; } ) );

   // --- Test 2: six ways of starting a helper ------------------------------
   var pid = String( CoreApplication.pid );

   function writeHelper( way )
   {
      var path = out + "/t2-helper-" + way + ".sh";
      var log = out + "/t2-log-" + way + ".txt";
      File.writeTextFile( path,
         "#!/bin/sh\n" +
         "# Written by t2-detached-helper.js. Waits for PixInsight to exit, then reports.\n" +
         "LOG='" + log + "'\n" +
         "PI=" + pid + "\n" +
         "alive=no; kill -0 $PI 2>/dev/null && alive=yes\n" +
         "echo \"1 helper started at $(date '+%H:%M:%S'); helper parent $(ps -o ppid= -p $$ | tr -d ' '); PixInsight is pid $PI, running: $alive\" >> \"$LOG\"\n" +
         "n=0\n" +
         "while kill -0 $PI 2>/dev/null; do\n" +
         "   sleep 1; n=$((n+1))\n" +
         "   if [ $n -ge 240 ]; then echo \"X gave up: PixInsight still running after 240 s\" >> \"$LOG\"; exit 1; fi\n" +
         "done\n" +
         "echo \"2 PixInsight exited at $(date '+%H:%M:%S'), ${n} s after the helper started\" >> \"$LOG\"\n" +
         "sleep 10\n" +
         "echo \"3 helper still running at $(date '+%H:%M:%S'), 10 s after PixInsight exited; helper parent is now $(ps -o ppid= -p $$ | tr -d ' ')\" >> \"$LOG\"\n" );
      // Owner read, write, execute; group and others read, execute (0755).
      try { File.setPermissions( path, 0x55700000 ); } catch ( x ) { L.push( "setPermissions failed for " + way + ": " + x ); }
      return path;
   }

   function wroteFirstLine( way )
   {
      var log = out + "/t2-log-" + way + ".txt";
      for ( var k = 0; k < 20; ++k )
      {
         if ( File.exists( log ) )
            return true;
         msleep( 100 );
      }
      return false;
   }

   function attempt( way, description, f )
   {
      var path = writeHelper( way );
      var r = valueOf( function() { return f( path ); } );
      L.push( "way " + way + " (" + description + "): call returned " + r + "; helper wrote its first line = " + wroteFirstLine( way ) );
   }

   attempt( "A", "startDetached( helper file )", function( path )
   {
      return ExternalProcess.startDetached( path );
   } );

   attempt( "B", "startDetached( helper file, folder )", function( path )
   {
      return ExternalProcess.startDetached( path, out );
   } );

   attempt( "C", "startDetached( /bin/sh, [helper file], folder )", function( path )
   {
      return ExternalProcess.startDetached( "/bin/sh", [ path ], out );
   } );

   attempt( "D", "start( /bin/sh -c 'nohup helper &' ), then wait for the shell", function( path )
   {
      var P = new ExternalProcess;
      P.start( "/bin/sh", [ "-c", "nohup /bin/sh '" + path + "' >/dev/null 2>&1 &" ] );
      var finished = P.waitForFinished( 5000 );
      return "shell finished=" + finished + ", exit code=" + P.exitCode;
   } );

   attempt( "E", "execute( /bin/sh -c 'nohup helper &' )", function( path )
   {
      return ExternalProcess.execute( "/bin/sh", [ "-c", "nohup /bin/sh '" + path + "' >/dev/null 2>&1 &" ] );
   } );

   attempt( "F", "start( /bin/sh helper ) as a plain child, not detached", function( path )
   {
      var Q = new ExternalProcess;
      keepAlive.push( Q );
      Q.start( "/bin/sh", [ path ] );
      return "started=" + Q.waitForStarted( 3000 );
   } );

   File.writeTextFile( out + "/t1-runtime.txt", L.join( "\n" ) + "\n" );
   console.writeln( L.join( "\n" ) );
}

try
{
   main();
}
catch ( x )
{
   console.criticalln( "t2-detached-helper.js failed: " + x );
   try
   {
      File.writeTextFile( File.systemTempDirectory + "/pi-update-assistant-t2-error.txt", String( x ) + "\n" );
   }
   catch ( y )
   {
   }
}
