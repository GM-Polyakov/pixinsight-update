// Test 5: can a helper ask PixInsight to quit the normal way, so that
// PixInsight shows its own warning about unsaved work, and can the helper
// tell "the user said no" from "the user has not answered yet"?
//
// PixInsight runs this file at startup, in a normal session (not automation
// mode), and stays open. Use run-t5.sh.
//
// What it does, all of it harmless:
//    1. In "unsaved" mode, creates a small grey image that was never saved.
//       In "clean" mode, creates nothing.
//    2. Writes a helper, out/t5-helper.sh, and starts it detached.
// The helper waits eight seconds, then asks PixInsight to quit, the way the
// Dock or Cmd-Q does. It logs what came back and whether PixInsight is still
// running. If PixInsight is still running, it asks again, up to three times.
//
// Written for the old script engine (PixInsight 1.9.3 and earlier).

function main()
{
   var dir = File.extractDrive( #__FILE__ ) + File.extractDirectory( #__FILE__ );
   var out = dir + "/out";
   if ( !File.directoryExists( out ) )
      File.createDirectory( out, true );

   var mode = "clean";
   if ( File.exists( out + "/t5-mode.txt" ) )
      mode = File.readTextFile( out + "/t5-mode.txt" ).replace( /\s+/g, "" );

   var L = [ "mode: " + mode ];

   // 1. An unsaved image.
   if ( mode == "unsaved" )
   {
      var w = new ImageWindow( 256, 256, 1, 32, true, false, "update_assistant_test" );
      w.mainView.beginProcess();
      w.mainView.image.fill( 0.25 );
      w.mainView.endProcess();
      w.show();
      L.push( "unsaved image created: " + w.mainView.id );
   }

   // 2. The helper.
   var pid = String( CoreApplication.pid );
   var helperPath = out + "/t5-helper.sh";
   File.writeTextFile( helperPath,
      "#!/bin/sh\n" +
      "# Written by t5-quit-with-prompts.js.\n" +
      "OUT='" + out + "'\n" +
      "LOG=\"$OUT/t5-helper-log.txt\"\n" +
      "PI=" + pid + "\n" +
      "say() { echo \"$(date '+%H:%M:%S') $*\" >> \"$LOG\"; }\n" +
      "say \"helper started; helper parent $(ps -o ppid= -p $$ | tr -d ' '); PixInsight is pid $PI\"\n" +
      "sleep 8\n" +
      "round=1\n" +
      "while [ $round -le 3 ]; do\n" +
      "   kill -0 $PI 2>/dev/null || { say \"PixInsight had already exited before round $round\"; break; }\n" +
      "   say \"round $round: sending the quit request\"\n" +
      "   t0=$(date +%s)\n" +
      "   reply=$(/usr/bin/osascript -e 'with timeout of 120 seconds' -e 'tell application id \"software.pleiades.PixInsight\" to quit' -e 'end timeout' 2>&1); rc=$?\n" +
      "   t1=$(date +%s)\n" +
      "   say \"round $round: the request returned after $((t1-t0)) s with status $rc and text: [$reply]\"\n" +
      "   m=0\n" +
      "   while kill -0 $PI 2>/dev/null && [ $m -lt 10 ]; do sleep 1; m=$((m+1)); done\n" +
      "   if kill -0 $PI 2>/dev/null; then\n" +
      "      say \"round $round: PixInsight is still running 10 s after the reply\"\n" +
      "   else\n" +
      "      say \"round $round: PixInsight exited ${m} s after the reply\"\n" +
      "      break\n" +
      "   fi\n" +
      "   round=$((round+1))\n" +
      "   sleep 10\n" +
      "done\n" +
      "say \"helper finished\"\n" );
   File.setPermissions( helperPath, 0x55700000 );
   var started = ExternalProcess.startDetached( helperPath );
   L.push( "helper started, process id " + started );

   File.writeTextFile( out + "/t5-script.txt", L.join( "\n" ) + "\n" );
}

try
{
   main();
}
catch ( x )
{
   try
   {
      File.writeTextFile( File.systemTempDirectory + "/pi-update-assistant-t5-error.txt", String( x ) + "\n" );
   }
   catch ( y )
   {
   }
}
