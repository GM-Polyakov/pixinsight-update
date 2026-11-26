// PixInsight Update Assistant
//
// A free, independent add-on that updates PixInsight from inside PixInsight.
// It is not made or endorsed by Pleiades Astrophoto.
//
// What this script does:
//    1. shows the installed version and asks for the PixInsight user name and
//       password;
//    2. signs in to PixInsight's download service and reads the list of
//       installers;
//    3. if a newer version exists for this computer, writes a small helper
//       program into a private folder and starts it. The helper downloads the
//       installer in the background, asks "Restart now, or later?", and
//       installs once PixInsight has closed (see helper/macos/helper.sh and
//       helper/windows/helper.ps1);
//    4. if an update is already under way, shows its progress and offers to
//       cancel it.
//
// The user name and password are used for the one sign-in request and are
// not stored anywhere. The helper never receives them.
//
// Written for the old script engine, so that it runs on PixInsight 1.9.3 and
// earlier. See TESTING.md, "Traps found", before changing any of this:
// PixInsight 1.9.3 refuses a script whose regular-expression literals put two
// slashes side by side, and it does so without a message.

#feature-id    UpdatePixInsight : Utilities > Update PixInsight

#feature-info  Updates PixInsight to the newest version from inside PixInsight. \
               PixInsight Update Assistant is a free, independent add-on. \
               It is not made or endorsed by Pleiades Astrophoto.

#include <pjsr/StdIcon.jsh>
#include <pjsr/StdButton.jsh>
#include <pjsr/Sizer.jsh>
#include <pjsr/TextAlign.jsh>

#include "UpdateAssistant-wording.jsh"
#include "UpdateAssistant-page.jsh"
#include "UpdateAssistant-helper.jsh"

#define UA_VERSION "0.1.0"

var UA = {
   base:      "https://pixinsight.com/dist/",
   signInURL: "https://pixinsight.com/dist/browser.php",
   resetURL:  "https://pixinsight.com/dist/reset_password.html",
   issuesURL: "https://github.com/GM-Polyakov/pixinsight-update/issues",
   // The name under which the helper's download tool introduces itself.
   client:    "PixInsightUpdateAssistant/" + UA_VERSION,
   // Rehearsal settings. Empty in real use; see UA_rehearsal().
   test:      {}
};

// ----------------------------------------------------------------------------
// Small things
// ----------------------------------------------------------------------------

function UA_env( name )
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

function UA_megabytes( bytes )
{
   if ( bytes >= 1073741824 )
      return ( bytes/1073741824 ).toFixed( 1 ) + " GB";
   return Math.round( bytes/1048576 ) + " MB";
}

function UA_duration( seconds )
{
   if ( seconds < 90 )
      return "a minute";
   if ( seconds < 3600 )
      return Math.round( seconds/60 ) + " minutes";
   var h = Math.floor( seconds/3600 ), m = Math.round( ( seconds - 3600*h )/60 );
   return h + ( h == 1 ? " hour " : " hours " ) + m + " minutes";
}

// Run a program and wait for it. Returns its exit code and what it printed.
function UA_run( program, args )
{
   var r = { code: -1, out: "" };
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
   }
   return r;
}

// A whole number from a table of text values: zero if it is missing or is not
// a number. It asks before it reads, because PixInsight's old engine prints a
// warning whenever a script reads a property that is not there.
function UA_number( table, key )
{
   return table.hasOwnProperty( key ) ? ( parseInt( table[key], 10 ) || 0 ) : 0;
}

UA.installed = function()
{
   var parts = [ CoreApplication.versionMajor, CoreApplication.versionMinor, CoreApplication.versionRelease, CoreApplication.versionRevision ];
   return { version: parts, text: parts[0] + "." + parts[1] + "." + parts[2] + ( parts[3] > 0 ? "-" + parts[3] : "" ) };
};

UA.onMac = function()
{
   return /mac/i.test( String( CoreApplication.platform ) );
};

// The system this PixInsight runs on: "macos", "windows", or "" for any other
// system, on which the add-on does not work. On Windows, PixInsight 1.9.6
// reports its platform as "Windows" (TESTING.md, test W1).
UA.system = function()
{
   if ( UA.onMac() )
      return "macos";
   return /win/i.test( String( CoreApplication.platform ) ) ? "windows" : "";
};

// The chip of this Mac: "arm64" for an Apple chip, "x64" for an Intel chip.
// The installer is chosen by the chip, not by the PixInsight that is running:
// PixInsight 1.9.3 and earlier exist for Intel only and run on an Apple chip
// through Apple's translator, but the Intel build of 1.9.6 does not start
// there (TESTING.md, "The real update"). The system is asked directly,
// because everything else tells a translated program that the chip is Intel.
// On Windows nothing is asked and no program is started: PixInsight's
// download page offers one kind of Windows build, for x64.
UA.chip = function()
{
   if ( UA.system() == "windows" )
      return "x64";
   return UA_run( "/usr/sbin/sysctl", [ "-n", "hw.optional.arm64" ] ).out.replace( /\s+/g, "" ) == "1" ? "arm64" : "x64";
};

UA.workDir = function()
{
   return File.systemTempDirectory + "/PixInsightUpdateAssistant";
};

// ----------------------------------------------------------------------------
// The update that is under way, if any
// ----------------------------------------------------------------------------

// True while the helper is running. On the Mac it is asked by its process
// number, which the status file gives.
UA.helperAlive = function( pid )
{
   if ( UA.system() == "windows" )
   {
      // The Windows helper holds the file "alive" open for as long as it
      // lives, and shares it with nobody. So the file cannot be removed while
      // the helper runs, and a file that can be removed was left over by a
      // helper that is gone (TESTING.md, test W2). Asking this way needs no
      // process number and starts no program.
      var path = UA.workDir() + "/alive";
      if ( !File.exists( path ) )
         return false;
      try
      {
         File.remove( path );
      }
      catch ( x )
      {
         return true;
      }
      return false;
   }
   return UA_run( "/bin/kill", [ "-0", pid ] ).code == 0;
};

// What the helper last reported, or null if no update is under way.
UA.status = function()
{
   if ( UA.system() == "windows" )
      return UA.statusOnWindows();
   var path = UA.workDir() + "/status";
   if ( !File.exists( path ) )
      return null;
   var s = {};
   try
   {
      var lines = File.readTextFile( path ).split( "\n" );
      for ( var i = 0; i < lines.length; ++i )
      {
         var eq = lines[i].indexOf( "=" );
         if ( eq > 0 )
            s[lines[i].substring( 0, eq )] = lines[i].substring( eq + 1 );
      }
   }
   catch ( x )
   {
      return null;
   }
   if ( !s.phase || !s.helper || !/^\d+$/.test( s.helper ) )
      return null;
   // A status file whose helper is gone is left over from an earlier run.
   if ( !UA.helperAlive( s.helper ) )
      return null;
   s.got = parseInt( s.got, 10 ) || 0;
   s.total = parseInt( s.total, 10 ) || 0;
   s.began = parseInt( s.began, 10 ) || 0;
   s.now = parseInt( s.now, 10 ) || 0;
   return s;
};

// The same on Windows. The helper is asked first, and if it is gone nothing
// is read: whatever lies in the folder then was left over. While the helper
// lives it replaces the status file once a second, and a reading made in that
// moment can fail or find no file (TESTING.md, test W2). One such reading
// would close the progress window, so the file is read up to five times,
// 40 ms apart, before the answer is that no update is under way.
UA.statusOnWindows = function()
{
   if ( !UA.helperAlive() )
      return null;
   var path = UA.workDir() + "/status";
   for ( var k = 0; k < 5; ++k )
   {
      if ( k > 0 )
         msleep( 40 );
      var s = {};
      try
      {
         if ( File.exists( path ) )
         {
            var lines = File.readTextFile( path ).split( "\n" );
            for ( var i = 0; i < lines.length; ++i )
            {
               var eq = lines[i].indexOf( "=" );
               if ( eq > 0 )
                  s[lines[i].substring( 0, eq )] = lines[i].substring( eq + 1 );
            }
         }
      }
      catch ( x )
      {
         s = {};
      }
      // A reading counts only if it holds the phase and the helper's number.
      if ( s.hasOwnProperty( "phase" ) && s.hasOwnProperty( "helper" ) && s.phase.length > 0 && s.helper.length > 0 )
      {
         s.got = UA_number( s, "got" );
         s.total = UA_number( s, "total" );
         s.began = UA_number( s, "began" );
         s.now = UA_number( s, "now" );
         return s;
      }
   }
   return null;
};

UA.statusText = function( s )
{
   if ( s.phase == "downloading" || s.phase == "stopped" )
   {
      var text = s.phase == "stopped" ? UA_TEXT.downloadStopped : "";
      if ( s.total > 0 )
      {
         var percent = Math.min( 100, Math.floor( 100*s.got/s.total ) );
         text = UA_fill( UA_TEXT.downloading, s.version, UA_megabytes( s.got ), UA_megabytes( s.total ), percent );
         var elapsed = s.now - s.began;
         if ( s.phase == "downloading" && elapsed > 5 && s.got > 0 && s.got < s.total )
            text += " " + UA_fill( UA_TEXT.timeLeft, UA_duration( ( s.total - s.got )*elapsed/s.got ) );
      }
      else if ( s.phase == "downloading" )
         text = UA_fill( UA_TEXT.downloading, s.version, UA_megabytes( s.got ), "?", "?" );
      return text;
   }
   if ( s.phase == "checking" )
      return UA_fill( UA_TEXT.checking, s.version );
   if ( s.phase == "asking" )
      return UA_fill( UA_TEXT.asking, s.version );
   return UA_fill( UA_TEXT.waiting, s.version );
};

UA.cancel = function()
{
   File.writeTextFile( UA.workDir() + "/cancel", "cancel\n" );
};

// PixInsight ignores a request to quit while a window of a script is open
// (TESTING.md, "The real update"). So while an update is under way, each of
// our windows is announced to the helper by the file "window-open". Before
// the helper asks PixInsight to quit, it reports the phase "restart", at which
// the progress window closes itself, and it waits for this file to go.
UA.windowOpen = function( open )
{
   var path = UA.workDir() + "/window-open";
   try
   {
      if ( open )
         File.writeTextFile( path, "open\n" );
      else if ( File.exists( path ) )
         File.remove( path );
   }
   catch ( x )
   {
   }
};

// Show the progress window until the user closes it, the update ends, or
// PixInsight is about to be asked to quit.
UA.showStatus = function( s )
{
   var dialog = new UA_StatusDialog( s );
   UA.windowOpen( true );
   try
   {
      dialog.execute();
   }
   finally
   {
      UA.windowOpen( false );
   }
   return dialog.closedBy;
};

// ----------------------------------------------------------------------------
// Sign-in and choosing the installer
// ----------------------------------------------------------------------------

// Returns { ok: true, html } or { ok: false, why: "network" | "refused" }.
UA.signIn = function( user, password )
{
   var body = new ByteArray, ok = false;
   try
   {
      var T = new NetworkTransfer;
      T.setSSL( UA.signInURL.indexOf( "https:" ) == 0 );
      T.setConnectionTimeout( 30 );
      T.onDownloadDataAvailable = function( data )
      {
         body.add( data );
         return true;
      };
      T.setURL( UA.signInURL );
      ok = T.post( "user_name=" + encodeURIComponent( user ) + "&user_password=" + encodeURIComponent( password ) );
      if ( ok && String( T.responseCode ) != "200" )
         ok = false;
   }
   catch ( x )
   {
      ok = false;
   }
   if ( !ok )
      return { ok: false, why: "network" };
   var html = "";
   try
   {
      html = body.utf8ToString();
   }
   catch ( x )
   {
      html = body.toString();
   }
   body.secureFill();
   if ( UA_Page.refused( html ) )
      return { ok: false, why: "refused" };
   return { ok: true, html: html };
};

// The newest macOS installer on the page, whichever chip it is for. Null if
// the page offers none. Used only to say "you already have the newest version".
// On Windows it is the newest Windows installer: the page offers one kind of
// Windows build, for x64.
UA.newestOfAny = function( html )
{
   var list = UA_Page.installers( html, UA.signInURL );
   if ( UA.system() == "windows" )
      return UA_Page.newest( list, "windows", "x64" );
   var a = UA_Page.newest( list, "macos", "arm64" ), b = UA_Page.newest( list, "macos", "x64" );
   if ( a == null )
      return b;
   if ( b == null )
      return a;
   return UA_Page.compareVersions( a.version, b.version ) >= 0 ? a : b;
};

// The newest installer on the page for this Mac's chip, with what the helper
// needs to fetch and check it. Null if the page offers none. On Windows it is
// the newest Windows installer for x64.
UA.choose = function( html )
{
   var pick;
   if ( UA.system() == "windows" )
      pick = UA_Page.newest( UA_Page.installers( html, UA.signInURL ), "windows", "x64" );
   else
      pick = UA_Page.newest( UA_Page.installers( html, UA.signInURL ), "macos", UA.chip() );
   if ( pick == null )
      return null;
   pick.sha1 = UA_Page.checksumFor( html, pick.name );
   pick.size = UA_Page.sizeFor( html, pick.name );
   // The download service remembers the sign-in by a cookie. Its value is the
   // session value that the page puts into every link (TESTING.md, test 3).
   pick.cookie = "PHPSESSID=" + UA_Page.paramOf( pick.url, "session_id" );
   return pick;
};

// ----------------------------------------------------------------------------
// What stands in the way of an update
// ----------------------------------------------------------------------------

// The names at the top of a folder that are not PixInsight's own. An empty
// list if the folder cannot be listed.
UA.ownFiles = function( folder )
{
   // What PixInsight's installer puts at the top of its folder, in small
   // letters, because the names are compared without regard to capitals.
   // __MACOSX is not PixInsight's, but add-on packages leave it behind, and
   // nobody would miss it.
   var own = [ "bin", "color", "doc", "etc", "include", "lib", "library", "rsc", "src", "eula", "license", "__macosx" ];
   var names = [];
   try
   {
      var find = new FileFind;
      // "Everything in the folder" is written in two pieces as a precaution.
      // PixInsight 1.9.3 removes comments from a script without understanding
      // regular-expression literals (TESTING.md, trap 1), and whether it
      // understands the sign that opens a comment inside a text is untried.
      if ( find.begin( folder + "/" + "*" ) )
         do
         {
            var name = String( find.name );
            if ( name != "." && name != ".." && own.indexOf( name.toLowerCase() ) < 0 )
               names.push( name );
         }
         while ( find.next() );
      find.end();
   }
   catch ( x )
   {
      // A folder that cannot be listed leaves the list empty. What was found
      // before an error still counts: it would be deleted all the same.
   }
   return names;
};

// Why an update cannot work on this computer: a sentence for the user, or ""
// if nothing stands in its way. On Windows, PixInsight's installer empties
// the PixInsight folder before it installs, so whatever the user keeps there
// would be deleted for good (TESTING.md, "The installer, read and not run").
// The user is told to move it first. On the Mac the user's own folders are
// carried over, so nothing stands in the way there.
UA.cannotUpdate = function()
{
   if ( UA.system() == "windows" )
   {
      var names = UA.ownFiles( UA.test.installDir || String( CoreApplication.baseDirPath ) );
      if ( names.length > 0 )
         return UA_fill( UA_TEXT.ownFiles, names.join( ", " ) );
   }
   return "";
};

// ----------------------------------------------------------------------------
// Starting the helper
// ----------------------------------------------------------------------------

UA.writeHelperFile = function( dir, name, executable )
{
   var path = dir + "/" + name;
   File.writeFile( path, ByteArray.fromHex( UA_HELPER[name] ) );
   // Owner may read and write, and run it if it is a program. Nobody else.
   File.setPermissions( path, executable ? 0x00700000 : 0x00300000 );
   return path;
};

// Returns true if the helper is running and has reported its first status.
UA.startHelper = function( pick )
{
   if ( UA.system() == "windows" )
      return UA.startHelperOnWindows( pick );
   var dir = UA.workDir();
   if ( !File.directoryExists( dir ) )
      File.createDirectory( dir, true );
   // Only this user may look into the folder: it will hold the installer's
   // address and the session cookie for a moment.
   File.setPermissions( dir, 0x00700000 );

   var leftovers = [ "status", "status.tmp", "cancel", "outcome", "job.conf", "message-shown.txt", "install-log.txt", "install-log.txt.result", "install-log.txt.start", "log.txt", "window-open" ];
   for ( var i = 0; i < leftovers.length; ++i )
      if ( File.exists( dir + "/" + leftovers[i] ) )
         File.remove( dir + "/" + leftovers[i] );

   // The helper's sentences, from the one table of wording.
   var version = pick.versionText;
   var texts = {
      product: UA_TEXT.product, ok: UA_TEXT.ok, cancel: UA_TEXT.cancel,
      downloadStopped: UA_TEXT.downloadStopped, tryAgain: UA_TEXT.tryAgain, startAgain: UA_TEXT.startAgain,
      notGenuine: UA_TEXT.notGenuine,
      ready: UA_fill( UA_TEXT.ready, version ), restartNow: UA_TEXT.restartNow, later: UA_TEXT.later,
      installing: UA_fill( UA_TEXT.installing, version ), hide: UA_TEXT.hide,
      adminPrompt: UA_fill( UA_TEXT.adminPrompt, version ),
      done: UA_TEXT.done, notUpdated: UA_TEXT.notUpdated,
      oldFolderTrash: UA_TEXT.oldFolderTrash, oldFolderLeft: UA_TEXT.oldFolderLeft, oldFolderCheck: UA_TEXT.oldFolderCheck,
      wontStart: UA_TEXT.wontStart, failedFolder: UA_TEXT.failedFolder,
      notReopened: UA_TEXT.notReopened, folderLost: UA_TEXT.folderLost
   };
   for ( var key in texts )
      if ( texts.hasOwnProperty( key ) )
         File.writeTextFile( dir + "/text-" + key, texts[key] );

   UA.writeHelperFile( dir, "install.sh", true );
   UA.writeHelperFile( dir, "message.js", false );
   var helper = UA.writeHelperFile( dir, "helper.sh", true );

   var installDir = UA.test.installDir || String( CoreApplication.baseDirPath );
   var job = [
      "url=" + pick.url,
      "cookie=" + pick.cookie,
      "client=" + UA.client,
      "file=" + pick.name,
      "sha1=" + pick.sha1,
      "size=" + pick.size,
      "new=" + version,
      "old=" + ( UA.test.test_old || UA.installed().text ),
      "pid=" + String( CoreApplication.pid ),
      "install_dir=" + installDir,
      "app=" + String( CoreApplication.appDirPath )
   ];
   for ( var name in UA.test )
      if ( UA.test.hasOwnProperty( name ) && name.indexOf( "test_" ) == 0 )
         job.push( name + "=" + UA.test[name] );
   var jobPath = dir + "/job.conf";
   File.writeTextFile( jobPath, "" );
   File.setPermissions( jobPath, 0x00300000 );
   File.writeTextFile( jobPath, job.join( "\n" ) + "\n" );
   File.setPermissions( jobPath, 0x00300000 );

   // A detached program keeps running when PixInsight closes. On PixInsight
   // 1.9.3 it has to be started by its path alone, without arguments.
   var started = 0;
   try
   {
      started = ExternalProcess.startDetached( helper );
   }
   catch ( x )
   {
      started = 0;
   }
   if ( !started )
   {
      if ( File.exists( jobPath ) )
         File.remove( jobPath );
      return false;
   }
   for ( var k = 0; k < 50; ++k )
   {
      if ( File.exists( dir + "/status" ) )
         return true;
      msleep( 100 );
   }
   return File.exists( dir + "/status" );
};

// The same on Windows, where the helper is a PowerShell script. Windows does
// not run such a script by its path, and PixInsight passes no arguments to a
// detached program. So the script also writes a starter file, two lines for
// Windows' command interpreter, and has PixInsight start that file by its
// path (TESTING.md, test W2).
UA.startHelperOnWindows = function( pick )
{
   var dir = UA.workDir();
   if ( !File.directoryExists( dir ) )
      File.createDirectory( dir, true );
   // The folder will hold the installer's address and the session cookie for
   // a moment. No permissions are set on it: Unix permissions mean nothing
   // on Windows, and the folder lies in the user's own temporary folder.

   // What an earlier update left behind. Each file is removed on its own: on
   // Windows a file that a program still holds open cannot be removed, and
   // one such file must not keep the others in place or stop this update.
   var leftovers = [ "status", "status.tmp", "cancel", "outcome", "job.conf", "message-shown.txt", "install-log.txt", "install-log.txt.result", "install-log.txt.start", "log.txt", "window-open",
                     "alive", "curl-instructions", "helper.cmd", "helper.ps1", "install-exe.log", "install-msi.log" ];
   for ( var i = 0; i < leftovers.length; ++i )
      try
      {
         if ( File.exists( dir + "/" + leftovers[i] ) )
            File.remove( dir + "/" + leftovers[i] );
      }
      catch ( x )
      {
      }

   // The helper's sentences, from the one table of wording. The Windows
   // helper has no use for the sentences about the Mac password, the
   // Applications folder and the Trash. Under the name "notReopened" it gets
   // the sentence that names the Start menu.
   var version = pick.versionText;
   var texts = {
      product: UA_TEXT.product, ok: UA_TEXT.ok, cancel: UA_TEXT.cancel,
      downloadStopped: UA_TEXT.downloadStopped, tryAgain: UA_TEXT.tryAgain, startAgain: UA_TEXT.startAgain,
      notGenuine: UA_TEXT.notGenuine,
      ready: UA_fill( UA_TEXT.ready, version ), restartNow: UA_TEXT.restartNow, later: UA_TEXT.later,
      installing: UA_fill( UA_TEXT.installing, version ), hide: UA_TEXT.hide,
      done: UA_TEXT.done, notUpdated: UA_TEXT.notUpdated,
      notReopened: UA_TEXT.notReopenedWin, notInstalled: UA_TEXT.notInstalled
   };
   for ( var key in texts )
      if ( texts.hasOwnProperty( key ) )
         File.writeTextFile( dir + "/text-" + key, texts[key] );

   UA.writeHelperFile( dir, "message.js", false );
   var helper = UA.writeHelperFile( dir, "helper.ps1", false );

   // The job: the lines that the Mac helper gets, and the program file of this
   // PixInsight. On Windows PixInsight reports no application folder, so
   // "app" is empty, and the helper finds and reopens PixInsight by "exe"
   // (TESTING.md, the first of the Windows traps).
   var installDir = UA.test.installDir || String( CoreApplication.baseDirPath );
   var job = [
      "url=" + pick.url,
      "cookie=" + pick.cookie,
      "client=" + UA.client,
      "file=" + pick.name,
      "sha1=" + pick.sha1,
      "size=" + pick.size,
      "new=" + version,
      "old=" + ( UA.test.test_old || UA.installed().text ),
      "pid=" + String( CoreApplication.pid ),
      "install_dir=" + installDir,
      "app=" + String( CoreApplication.appDirPath ),
      "exe=" + String( CoreApplication.filePath )
   ];
   for ( var name in UA.test )
      if ( UA.test.hasOwnProperty( name ) && name.indexOf( "test_" ) == 0 )
         job.push( name + "=" + UA.test[name] );
   var jobPath = dir + "/job.conf";
   File.writeTextFile( jobPath, job.join( "\n" ) + "\n" );

   // The starter file. Its second line starts PowerShell with the helper and
   // does not wait for it, so the command interpreter that runs the starter
   // is gone at once and keeps nothing open. That line also switches off, for
   // this one run, PowerShell's rule of refusing script files. Both lines end
   // the way Windows' command interpreter expects.
   var root = UA_env( "SystemRoot" );
   if ( root.length == 0 )
      root = "C:/Windows";
   var powershell = File.unixPathToWindows( File.windowsPathToUnix( root ) + "/System32/WindowsPowerShell/v1.0/powershell.exe" );
   var starter = dir + "/helper.cmd";
   File.writeTextFile( starter, "@echo off\r\n" +
      "start \"\" /b \"" + powershell + "\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + File.unixPathToWindows( helper ) + "\"\r\n" );

   // PixInsight starts the starter file by its path alone, with the working
   // folder as the helper's current folder. It rejects the form that takes a
   // list of arguments. The path is handed over in quotes, which leaves
   // Windows no choice of how to read a path that holds a space
   // (TESTING.md, test W2, way I).
   var started = 0;
   try
   {
      started = ExternalProcess.startDetached( "\"" + File.unixPathToWindows( starter ) + "\"", dir );
   }
   catch ( x )
   {
      started = 0;
   }
   if ( started )
   {
      // PowerShell starts more slowly than a shell, so the first status may
      // take longer than on the Mac: up to twenty seconds.
      for ( var k = 0; k < 200; ++k )
      {
         if ( File.exists( dir + "/status" ) )
            return true;
         msleep( 100 );
      }
      if ( File.exists( dir + "/status" ) )
         return true;
      // No helper has reported. Should one come up late after all, the file
      // "cancel" makes it stop at once.
      try
      {
         UA.cancel();
      }
      catch ( x )
      {
      }
   }
   // Without a helper, the installer's address and the cookie must not stay.
   try
   {
      if ( File.exists( jobPath ) )
         File.remove( jobPath );
   }
   catch ( x )
   {
   }
   return false;
};

// ----------------------------------------------------------------------------
// Windows
// ----------------------------------------------------------------------------

function UA_message( text )
{
   ( new MessageBox( text, UA_TEXT.windowTitle, StdIcon_Information, StdButton_Ok ) ).execute();
}

function UA_about()
{
   UA_message( "<p><b>" + UA_TEXT.product + " " + UA_VERSION + "</b></p>" +
               "<p>" + UA_TEXT.independent + "</p>" +
               "<p>" + UA_TEXT.trust + "</p>" +
               "<p>" + UA_TEXT.noCollection + "</p>" +
               "<p>" + UA_TEXT.reportProblem + "<br/>" + UA.issuesURL + "</p>" );
}

function UA_label( parent, text )
{
   var label = new Label( parent );
   label.useRichText = true;
   label.wordWrapping = true;
   label.text = text;
   label.setScaledMinWidth( 460 );
   return label;
}

// The window for signing in.
function UA_SignInDialog()
{
   this.__base__ = Dialog;
   this.__base__();

   var dialog = this;
   this.windowTitle = UA_TEXT.windowTitle;

   this.installed_Label = UA_label( this, "<b>" + UA_fill( UA_TEXT.installed, UA.installed().text ) + "</b> " + UA_TEXT.signInPrompt );
   this.trust_Label = UA_label( this, UA_TEXT.trust );

   var labelWidth = this.font.width( UA_TEXT.userName + "M" );

   this.user_Label = new Label( this );
   this.user_Label.text = UA_TEXT.userName;
   this.user_Label.textAlignment = TextAlign_Right | TextAlign_VertCenter;
   this.user_Label.setFixedWidth( labelWidth );
   this.user_Edit = new Edit( this );

   this.user_Sizer = new HorizontalSizer;
   this.user_Sizer.spacing = 6;
   this.user_Sizer.add( this.user_Label );
   this.user_Sizer.add( this.user_Edit, 100 );

   this.password_Label = new Label( this );
   this.password_Label.text = UA_TEXT.password;
   this.password_Label.textAlignment = TextAlign_Right | TextAlign_VertCenter;
   this.password_Label.setFixedWidth( labelWidth );
   this.password_Edit = new Edit( this );
   this.password_Edit.passwordMode = true;

   this.password_Sizer = new HorizontalSizer;
   this.password_Sizer.spacing = 6;
   this.password_Sizer.add( this.password_Label );
   this.password_Sizer.add( this.password_Edit, 100 );

   this.forgot_Button = new PushButton( this );
   this.forgot_Button.text = UA_TEXT.forgot;
   this.forgot_Button.onClick = function()
   {
      Dialog.openBrowser( UA.resetURL );
   };

   this.forgot_Sizer = new HorizontalSizer;
   this.forgot_Sizer.addSpacing( labelWidth + 6 );
   this.forgot_Sizer.add( this.forgot_Button );
   this.forgot_Sizer.addStretch();

   // Room for two lines, so that a message never has to squeeze the window.
   this.message_Label = UA_label( this, "" );
   this.message_Label.setScaledMinHeight( 40 );
   this.independent_Label = UA_label( this, UA_TEXT.independent );

   this.about_Button = new PushButton( this );
   this.about_Button.text = UA_TEXT.about;
   this.about_Button.onClick = function()
   {
      UA_about();
   };

   this.signIn_Button = new PushButton( this );
   this.signIn_Button.text = UA_TEXT.signIn;
   this.signIn_Button.defaultButton = true;
   this.signIn_Button.onClick = function()
   {
      dialog.signIn();
   };

   this.cancel_Button = new PushButton( this );
   this.cancel_Button.text = UA_TEXT.cancel;
   this.cancel_Button.onClick = function()
   {
      dialog.cancel();
   };

   this.buttons_Sizer = new HorizontalSizer;
   this.buttons_Sizer.spacing = 8;
   this.buttons_Sizer.add( this.about_Button );
   this.buttons_Sizer.addStretch();
   this.buttons_Sizer.add( this.signIn_Button );
   this.buttons_Sizer.add( this.cancel_Button );

   this.sizer = new VerticalSizer;
   this.sizer.margin = 12;
   this.sizer.spacing = 8;
   this.sizer.add( this.installed_Label );
   this.sizer.add( this.trust_Label );
   this.sizer.add( this.user_Sizer );
   this.sizer.add( this.password_Sizer );
   this.sizer.add( this.forgot_Sizer );
   this.sizer.add( this.message_Label );
   this.sizer.add( this.independent_Label );
   this.sizer.addSpacing( 4 );
   this.sizer.add( this.buttons_Sizer );

   this.adjustToContents();

   this.say = function( text )
   {
      this.message_Label.text = text.length > 0 ? "<b>" + text + "</b>" : "";
      processEvents();
   };

   this.busy = function( on )
   {
      this.user_Edit.enabled = !on;
      this.password_Edit.enabled = !on;
      this.signIn_Button.enabled = !on;
      this.forgot_Button.enabled = !on;
      processEvents();
   };

   this.signIn = function()
   {
      var user = this.user_Edit.text.trim(), password = this.password_Edit.text;
      if ( user.length == 0 || password.length == 0 )
      {
         this.say( UA_TEXT.needBoth );
         return;
      }
      this.busy( true );
      this.say( UA_TEXT.signingIn );
      var r = UA.signIn( user, password );
      // The password is needed for that one request only.
      this.password_Edit.text = "";
      password = "";
      if ( !r.ok )
      {
         this.busy( false );
         this.say( r.why == "refused" ? UA_TEXT.refused : UA_TEXT.cantReach );
         try
         {
            if ( r.why == "refused" )
               this.password_Edit.hasFocus = true;
         }
         catch ( x )
         {
         }
         return;
      }
      var outcome = UA.afterSignIn( r.html );
      this.say( "" );
      this.ok();
      UA.windowOpen( true );
      try
      {
         UA_message( outcome );
      }
      finally
      {
         UA.windowOpen( false );
      }
   };
}

UA_SignInDialog.prototype = new Dialog;

// What happens after a successful sign-in. Returns the sentence to show.
UA.afterSignIn = function( html )
{
   var have = UA.installed(), any = UA.newestOfAny( html );
   if ( any == null )
      return UA_TEXT.noInstaller;
   if ( UA_Page.compareVersions( any.version, have.version ) <= 0 )
      return UA_fill( UA_TEXT.upToDate, have.text );
   // Something newer exists. Is it there for this Mac's chip?
   var pick = UA.choose( html );
   if ( pick == null || UA_Page.compareVersions( pick.version, have.version ) <= 0 )
      return UA_TEXT.noInstaller;
   if ( !UA.startHelper( pick ) )
      return UA_TEXT.cantStart;
   return UA_fill( UA_TEXT.started, pick.versionText, pick.size > 0 ? UA_megabytes( pick.size ) : "?" );
};

// The window shown while an update is under way: progress, and a way to cancel.
function UA_StatusDialog( first )
{
   this.__base__ = Dialog;
   this.__base__();

   var dialog = this;
   this.windowTitle = UA_TEXT.windowTitle;

   // Room for three lines: the sentence grows when a time estimate is added.
   this.status_Label = UA_label( this, "<b>" + UA.statusText( first ) + "</b>" );
   this.status_Label.setScaledMinHeight( 60 );

   this.cancelUpdate_Button = new PushButton( this );
   this.cancelUpdate_Button.text = UA_TEXT.cancelUpdate;
   this.cancelUpdate_Button.onClick = function()
   {
      dialog.timer.stop();
      UA.cancel();
      dialog.ok();
      UA_message( UA_TEXT.stopped );
   };

   this.close_Button = new PushButton( this );
   this.close_Button.text = UA_TEXT.close;
   this.close_Button.defaultButton = true;
   this.close_Button.onClick = function()
   {
      dialog.timer.stop();
      dialog.ok();
   };

   this.buttons_Sizer = new HorizontalSizer;
   this.buttons_Sizer.spacing = 8;
   this.buttons_Sizer.add( this.cancelUpdate_Button );
   this.buttons_Sizer.addStretch();
   this.buttons_Sizer.add( this.close_Button );

   this.sizer = new VerticalSizer;
   this.sizer.margin = 12;
   this.sizer.spacing = 12;
   this.sizer.add( this.status_Label );
   this.sizer.add( this.buttons_Sizer );

   this.adjustToContents();

   // Why the window closed: "user", "ended" (no update is under way any more)
   // or "restart" (PixInsight is about to be asked to quit).
   this.closedBy = "user";

   // Once a second, show what the helper last reported.
   this.timer = new Timer;
   this.timer.interval = 1;
   this.timer.periodic = true;
   this.timer.dialog = this;
   this.timer.onTimeout = function()
   {
      var s = UA.status();
      if ( s == null || s.phase == "restart" )
      {
         this.stop();
         this.dialog.closedBy = s == null ? "ended" : "restart";
         this.dialog.ok();
         return;
      }
      this.dialog.status_Label.text = "<b>" + UA.statusText( s ) + "</b>";
      // Once PixInsight has to close, cancelling is over.
      this.dialog.cancelUpdate_Button.enabled = s.phase != "installing";
   };
   this.timer.start();
}

UA_StatusDialog.prototype = new Dialog;

// ----------------------------------------------------------------------------
// Rehearsal: the same steps without windows, against the stand-in service
// ----------------------------------------------------------------------------

// A rehearsal is run by tests/run-rehearsal.sh, and on Windows by
// tests/windows/run-rehearsal.ps1. It is accepted only together with a
// stand-in download service on this computer, so it can never send anything
// to pixinsight.com. The user name and password it uses belong to the
// stand-in's made-up account.
function UA_rehearsal()
{
   var out = UA_env( "PI_UA_TEST_DIR" ), base = UA_env( "PI_UA_BASE" );
   if ( out.length == 0 )
      return false;
   if ( !/^http:\/\/127\.0\.0\.1:\d{2,5}\/dist\/$/.test( base ) )
      return false;
   UA.base = base;
   UA.signInURL = base + "browser.php";
   UA.resetURL = base + "reset_password.html";

   var names = [ "test_answer", "test_retry", "test_installer", "test_home", "test_pkgutil", "test_signature", "test_downloads", "test_quiet", "test_old" ];
   for ( var i = 0; i < names.length; ++i )
   {
      var v = UA_env( "PI_UA_" + names[i].toUpperCase() );
      if ( v.length > 0 )
         UA.test[names[i]] = v;
   }
   UA.test.installDir = UA_env( "PI_UA_TEST_INSTALL_DIR" );

   // An attended rehearsal shows the real windows to a person, and only the
   // download service, the installer and the folder are stand-ins.
   if ( UA_env( "PI_UA_TEST_WINDOWS" ) == "1" )
      return false;

   // What to do: sign in and start an update, unless the file action.txt
   // asks for the status of the update under way, for cancelling it, or for
   // the progress window ("progress"), which then stays open as it would for
   // a person who never closes it.
   var lines = [], action = "", result = "script-result.txt";
   if ( File.exists( out + "/action.txt" ) )
   {
      action = File.readTextFile( out + "/action.txt" ).replace( /\s+/g, "" );
      File.remove( out + "/action.txt" );
      result = "script-result-" + action + ".txt";
   }
   try
   {
      if ( action == "cancel" )
      {
         var s = UA.status();
         lines.push( "status=" + ( s == null ? "none" : s.phase ) );
         if ( s != null )
         {
            lines.push( "status_text=" + UA.statusText( s ) );
            UA.cancel();
            lines.push( "shown=" + UA_TEXT.stopped );
         }
      }
      else if ( action == "status" )
      {
         var t = UA.status();
         lines.push( "status=" + ( t == null ? "none" : t.phase ) );
         if ( t != null )
            lines.push( "status_text=" + UA.statusText( t ) );
      }
      else if ( action == "progress" )
      {
         var u = UA.status();
         lines.push( "status=" + ( u == null ? "none" : u.phase ) );
         if ( u != null )
            lines.push( "closed_by=" + UA.showStatus( u ) );
      }
      else if ( action == "windows" )
      {
         // Build both windows, open each for a second and close it again, so
         // that a mistake in the window code shows up without anyone clicking.
         var w1 = new UA_SignInDialog;
         w1.say( UA_TEXT.signingIn );
         w1.busy( true );
         w1.busy( false );
         w1.say( "" );
         var closer = new Timer( 1, false );
         closer.dialog = w1;
         closer.onTimeout = function()
         {
            this.dialog.cancel();
         };
         closer.start();
         w1.execute();
         lines.push( "signin_window=ok" );

         var sample = { phase: "downloading", got: 300*1048576, total: 1100*1048576, version: "1.9.6", began: 1000, now: 1100, helper: "1" };
         lines.push( "status_text=" + UA.statusText( sample ) );
         // With no update under way, this window closes itself at its first tick.
         ( new UA_StatusDialog( sample ) ).execute();
         lines.push( "status_window=ok" );
      }
      else if ( UA.cannotUpdate().length > 0 )
      {
         // An update cannot work on this computer. As in UA_main(), the user
         // is told why and is not asked to sign in.
         lines.push( "installed=" + UA.installed().text );
         lines.push( "chip=" + UA.chip() );
         lines.push( "shown=" + UA.cannotUpdate() );
      }
      else
      {
         lines.push( "installed=" + UA.installed().text );
         lines.push( "chip=" + UA.chip() );
         var r = UA.signIn( UA_env( "PI_USER" ), UA_env( "PI_PASS" ) );
         lines.push( "signin=" + ( r.ok ? "ok" : r.why ) );
         if ( r.ok )
         {
            var pick = UA.choose( r.html );
            lines.push( "newest=" + ( pick == null ? "none" : pick.versionText ) );
            lines.push( "file=" + ( pick == null ? "" : pick.name ) );
            lines.push( "shown=" + UA.afterSignIn( r.html ) );
         }
         else
            lines.push( "shown=" + ( r.why == "refused" ? UA_TEXT.refused : UA_TEXT.cantReach ) );
      }
   }
   catch ( x )
   {
      lines.push( "error=" + x + ( x.lineNumber ? " (line " + x.lineNumber + ")" : "" ) );
   }
   File.writeTextFile( out + "/" + result, lines.join( "\n" ) + "\n" );
   return true;
}

// ----------------------------------------------------------------------------

function UA_main()
{
   if ( UA_rehearsal() )
      return;

   if ( UA.system() == "" )
   {
      UA_message( UA_TEXT.notThisSystem );
      return;
   }

   var s = UA.status();
   if ( s != null )
   {
      // While PixInsight is being asked to quit, a window would stop it.
      if ( s.phase != "restart" )
         UA.showStatus( s );
      return;
   }

   // Two situations in which an update cannot work. Say so before asking for
   // a password. Neither applies to a rehearsal, which uses a stand-in folder.
   // The first one is a matter of the Mac only: on Windows the installer is
   // told which folder PixInsight is in.
   if ( !UA.test.installDir )
   {
      if ( UA.onMac() && String( CoreApplication.baseDirPath ) != "/Applications/PixInsight" )
      {
         UA_message( UA_TEXT.notInApplications );
         return;
      }
      var others = false;
      try
      {
         others = CoreApplication.otherInstancesRunning();
      }
      catch ( x )
      {
      }
      if ( others )
      {
         UA_message( UA_TEXT.otherInstance );
         return;
      }
   }

   // A third situation, which a rehearsal looks for too: on Windows, things
   // in the PixInsight folder that PixInsight's installer would delete.
   var why = UA.cannotUpdate();
   if ( why.length > 0 )
   {
      UA_message( why );
      return;
   }

   ( new UA_SignInDialog ).execute();
}

UA_main();
