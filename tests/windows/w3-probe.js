// PixInsight Update Assistant, Windows test W3, the part inside PixInsight.
//
// Question: on Windows, can the script sign in, read the download page and
// pick the Windows installer, with the add-on's own page reader?
//
//    PixInsight.exe -n --automation-mode --no-focus-stealing -r=<this file> --force-exit
//
// It talks only to a stand-in download service on this computer. The address
// comes from the environment variable PI_UA_W_BASE and is accepted only in the
// form http://127.0.0.1:<port>/dist/ , so this probe can never send anything
// to pixinsight.com. The user name and password, PI_USER and PI_PASS, belong
// to the stand-in's made-up account.
//
// It writes:
//    w3-result.txt  into the folder named by PI_UA_W_OUT. It holds no user
//                   name, no password and no session value;
//    job.conf       into a working folder in the temporary folder: the
//                   installer's address and the session cookie, for the
//                   download that the runner then makes with curl.exe. The
//                   runner deletes it as soon as it has read it.
//
// Old-engine JavaScript only. No regular-expression literal here ends in an
// escaped slash (TESTING.md, trap 1).

#include "../../src/UpdateAssistant-page.jsh"

function W3_env( name )
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

// The same request as UA.signIn in src/UpdateAssistant.js.
// Returns { ok: true, html } or { ok: false, why: "network" | "refused" }.
function W3_signIn( url, user, password )
{
   var body = new ByteArray, ok = false, code = "";
   try
   {
      var T = new NetworkTransfer;
      T.setSSL( url.indexOf( "https:" ) == 0 );
      T.setConnectionTimeout( 30 );
      T.onDownloadDataAvailable = function( data )
      {
         body.add( data );
         return true;
      };
      T.setURL( url );
      ok = T.post( "user_name=" + encodeURIComponent( user ) + "&user_password=" + encodeURIComponent( password ) );
      code = String( T.responseCode );
      if ( ok && code != "200" )
         ok = false;
   }
   catch ( x )
   {
      ok = false;
   }
   if ( !ok )
      return { ok: false, why: "network", code: code };
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
      return { ok: false, why: "refused", code: code };
   return { ok: true, html: html, code: code };
}

function W3_main()
{
   var lines = [];
   function add( key, value )
   {
      lines.push( key + "=" + value );
   }

   var out = W3_env( "PI_UA_W_OUT" ), base = W3_env( "PI_UA_W_BASE" );
   if ( out.length == 0 )
      return;
   if ( !/^http:\/\/127\.0\.0\.1:\d{2,5}\/dist\/$/.test( base ) )
   {
      File.writeTextFile( out + "/w3-result.txt", "refused_base=the address is not a stand-in on this computer\n" );
      return;
   }
   var signInURL = base + "browser.php";
   var user = W3_env( "PI_USER" ), password = W3_env( "PI_PASS" );

   // A wrong password first, then a port where nothing listens, then the
   // real thing.
   var wrong = W3_signIn( signInURL, user, "not-the-password" );
   add( "wrong_password", wrong.ok ? "accepted" : wrong.why + " (response code " + wrong.code + ")" );

   var nowhere = W3_signIn( "http://127.0.0.1:9/dist/browser.php", user, password );
   add( "nothing_listening", nowhere.ok ? "accepted" : nowhere.why );

   var r = W3_signIn( signInURL, user, password );
   add( "signin", r.ok ? "ok (response code " + r.code + ")" : r.why + " (response code " + r.code + ")" );
   if ( r.ok )
   {
      var list = UA_Page.installers( r.html, signInURL );
      add( "installers_on_page", list.length );
      var names = [];
      for ( var i = 0; i < list.length; ++i )
         names.push( list[i].name );
      add( "names", names.join( " " ) );

      var pick = UA_Page.newest( list, "windows", "x64" );
      add( "newest_for_windows", pick == null ? "none" : pick.name );
      if ( pick != null )
      {
         var sha1 = UA_Page.checksumFor( r.html, pick.name );
         var size = UA_Page.sizeFor( r.html, pick.name );
         var session = UA_Page.paramOf( pick.url, "session_id" );
         add( "version", pick.versionText );
         add( "date", pick.date );
         add( "sha1", sha1 );
         add( "size", size );
         add( "session_value_length", session.length );
         add( "address_is_on_the_stand_in", pick.url.indexOf( base ) == 0 );

         var work = File.systemTempDirectory + "/PixInsightUpdateAssistant-w3";
         if ( !File.directoryExists( work ) )
            File.createDirectory( work, true );
         File.writeTextFile( work + "/job.conf", [
            "url=" + pick.url,
            "cookie=PHPSESSID=" + session,
            "client=PixInsightUpdateAssistant/0.1.0",
            "file=" + pick.name,
            "sha1=" + sha1,
            "size=" + size ].join( "\n" ) + "\n" );
         add( "job_written", File.exists( work + "/job.conf" ) );
      }
   }

   File.writeTextFile( out + "/w3-result.txt", lines.join( "\n" ) + "\n" );
}

try
{
   W3_main();
}
catch ( x )
{
   try
   {
      File.writeTextFile( File.systemTempDirectory + "/pi-update-assistant-w3-error.txt", "error=" + x + ( x.lineNumber ? " (line " + x.lineNumber + ")" : "" ) + "\n" );
   }
   catch ( y )
   {
   }
}
