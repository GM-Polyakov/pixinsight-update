// Test 3: can a script inside PixInsight sign in to the PixInsight download
// service, find the newest installer and fetch it?
//
// Start it with run-t3.sh. It reads the PixInsight user name and password from
// the environment variables PI_USER and PI_PASS, sends them only to
// https://pixinsight.com/dist/, and writes a report to out/t3-report.txt.
//
// What the report may contain: response codes, sizes, installer file names,
// version numbers read from those names, checksums of installers, host names
// and the names of cookies. It never contains the user name, the password, a
// session value, a cookie's value, or any text from the account page.
//
// What is known about the service (2026-11-24): a sign-in is remembered by a
// cookie named PHPSESSID. A request for an installer without that cookie is
// answered with a redirect to the sign-in page. PixInsight's network calls
// neither keep cookies nor follow redirects, so three routes are tried:
//
//    1. PixInsight signs in and fetches the installer, sending the session
//       value that the page puts into its links as the cookie.
//    2. PixInsight signs in, and curl fetches the installer with that cookie.
//       curl is the download tool that comes with macOS. It follows redirects.
//    3. curl signs in and fetches the installer. The password reaches curl
//       through its input, never through a file or a command line.
//
// Steps:
//    A. Request the sign-in page with no details.
//    B. Only with the file out/t3-anonymous-only present: sign in with a
//       made-up user name, to see what a refusal looks like, and stop.
//    C. Sign in with the real details and list the installers on the page.
//    D. Pick the newest macOS installer of this build type and try the three
//       routes in turn, asking only for the start of the file.
// With PI_T3_MODE=download it signs in again and downloads the file named in
// PI_T3_FILE into out/download/, by the route named in PI_T3_HOW.
//
// With PI_T3_BASE=http://127.0.0.1:<port>/dist/ it talks to the stand-in
// service in tests/standin/ instead. Any other address is ignored, so the
// details can only ever go to pixinsight.com or to this computer.
//
// Old-engine JavaScript only (PixInsight 1.9.3 and earlier).

#include "lib/page-shape.js"

var BASE = "https://pixinsight.com/dist/";
var SIGNIN = "https://pixinsight.com/dist/browser.php";

// curl gives its client name honestly; the site refuses curl's default name.
var CURL = "/usr/bin/curl";
var CURL_NAME = "update-test/0.1";
// Printed by curl in front of its figures about a transfer. It must not start
// with an at sign: curl would take the rest for the name of a file to read.
var MARK = "::curl-result::";

var REPORT = [];

function say( s )
{
   REPORT.push( String( s ) );
}

function env( name )
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

// Never write a line that holds the user name or the password, whatever the
// code above it did.
function writeReport( path )
{
   var lines = REPORT.join( "\n" ).split( "\n" ), out = [];
   for ( var i = 0; i < lines.length; ++i )
      out.push( Shape.containsSecret( lines[i] ) ? "[a line was withheld: it held your user name or password]" : lines[i] );
   File.writeTextFile( path, out.join( "\n" ) + "\n" );
}

function sayList( title, lines, limit )
{
   say( title );
   for ( var i = 0; i < lines.length && i < limit; ++i )
      say( lines[i].length > 220 ? lines[i].substring( 0, 220 ) + " ..." : lines[i] );
   if ( lines.length > limit )
      say( "   (" + ( lines.length - limit ) + " more lines not shown)" );
   if ( lines.length == 0 )
      say( "   (none)" );
}

function megabytes( n )
{
   return n + " bytes (" + ( n/1048576 ).toFixed( 1 ) + " MB)";
}

function remove( path )
{
   try
   {
      if ( File.exists( path ) )
         File.remove( path );
   }
   catch ( x )
   {
   }
}

function hostOf( url )
{
   var m = /^[a-z]+:\/\/([^\/?#:]+)/i.exec( url );
   return m == null ? "" : m[1];
}

// The page script that an address points at, without anything that follows
// the question mark: download_inst.php, for example.
function scriptOf( url )
{
   var path = url.split( "#" )[0].split( "?" )[0];
   return Shape.showSegment( path.substring( path.lastIndexOf( "/" ) + 1 ) );
}

// Where a redirect points, in words that give nothing private away.
function describeTarget( location, from )
{
   if ( location.length == 0 )
      return "nowhere";
   var url = Shape.absoluteURL( location, from );
   var path = url.split( "#" )[0].split( "?" )[0];
   var last = path.substring( path.lastIndexOf( "/" ) + 1 );
   if ( hostOf( url ) == hostOf( SIGNIN ) && ( last == "index.html" || last.length == 0 ) )
      return "the sign-in page";
   return ( Shape.FILE_RE.test( last ) ? "a file named " + last : "another address" ) + " on the host " + hostOf( url );
}

function buildChip()
{
   try
   {
      var P = new ExternalProcess;
      P.start( "/usr/bin/uname", [ "-m" ] );
      P.waitForFinished( 5000 );
      var m = String( P.standardOutput.toString() ).replace( /\s+/g, "" );
      return m == "arm64" ? "arm64" : "x64";
   }
   catch ( x )
   {
      return "x64";
   }
}

// The newest installer of each kind among `downloads`.
function newestOfEachKind( downloads )
{
   var best = {}, order = [];
   for ( var i = 0; i < downloads.length; ++i )
   {
      var info = Shape.parseInstallerName( downloads[i].name );
      if ( info.platform.length == 0 || info.versionText.length == 0 )
         continue;
      var kind = info.platform + ( info.arch.length > 0 ? ", " + info.arch : "" );
      if ( best["=" + kind] === undefined )
         order.push( kind );
      if ( best["=" + kind] === undefined || Shape.compareInstallers( info, best["=" + kind] ) > 0 )
         best["=" + kind] = info;
   }
   var lines = [];
   for ( i = 0; i < order.length; ++i )
      lines.push( "   | " + order[i] + ": version " + best["=" + order[i]].versionText + ", file " + best["=" + order[i]].name );
   return lines;
}

function findByName( downloads, name )
{
   for ( var i = 0; i < downloads.length; ++i )
      if ( downloads[i].name == name && downloads[i].method == "GET" )
         return downloads[i];
   return null;
}

// ----------------------------------------------------------------------------
// PixInsight's own network calls
// ----------------------------------------------------------------------------

function newTransfer()
{
   var T = new NetworkTransfer;
   T.setSSL( BASE.indexOf( "https:" ) == 0 );
   T.setConnectionTimeout( 30 );
   return T;
}

// Send one request for `url`. Without a cookie it is an ordinary GET. With a
// cookie it is a POST with no fields, because PixInsight 1.9.3 sends custom
// headers only with a POST, and only if they are set after the address.
function send( T, url, cookie )
{
   T.setURL( url );
   if ( cookie )
   {
      T.setCustomHTTPHeaders( [ "Cookie: " + cookie ] );
      return T.post( "" );
   }
   return T.download();
}

function details()
{
   return "user_name=" + encodeURIComponent( Shape.user ) + "&user_password=" + encodeURIComponent( Shape.pass );
}

// GET when fields is null, POST otherwise. The whole reply is kept in memory,
// so use this for pages only.
function request( T, url, fields )
{
   var body = new ByteArray;
   T.onDownloadDataAvailable = function( data )
   {
      body.add( data );
      return true;
   };
   T.onTransferProgress = function()
   {
      return true;
   };
   T.setURL( url );
   var t0 = Date.now(), ok = false, failure = "";
   try
   {
      ok = ( fields === null ) ? T.download() : T.post( fields );
   }
   catch ( x )
   {
      failure = "exception: " + x;
   }
   var r = { ok: ok, code: String( T.responseCode ), type: String( T.contentType ), bytes: body.length, seconds: ( Date.now() - t0 )/1000 };
   r.error = ok ? "" : ( failure.length > 0 ? failure : String( T.errorInformation ) );
   try
   {
      r.html = body.utf8ToString();
   }
   catch ( x )
   {
      r.html = body.toString();
   }
   return r;
}

function signedOut( html )
{
   return html.length == 0 || Shape.hasSignInForm( html ) || html.indexOf( "ACCESS DENIED" ) >= 0;
}

function describe( label, r )
{
   say( "" );
   say( label );
   say( "   request completed = " + r.ok + ( r.error.length > 0 ? " (" + r.error.replace( /\s+/g, " " ) + ")" : "" ) );
   say( "   response code = " + r.code + "; content type = " + r.type + "; size = " + r.bytes + " bytes; time = " + r.seconds.toFixed( 1 ) + " s" );
   say( "   has the sign-in form = " + Shape.hasSignInForm( r.html ) + "; says ACCESS DENIED = " + ( r.html.indexOf( "ACCESS DENIED" ) >= 0 ) );
}

// Start fetching one installer and stop as soon as its size is known.
function peek( T, url, cookie )
{
   var r = { total: 0, got: 0, magic: "", ok: false };
   T.onDownloadDataAvailable = function( data )
   {
      if ( r.got == 0 && data.length >= 4 )
         r.magic = data.toString( 0, 4 );
      r.got += data.length;
      return r.total == 0 && r.got < 262144;
   };
   T.onTransferProgress = function( dlTotal, dlCurrent, ulTotal, ulCurrent )
   {
      if ( dlTotal > 0 )
         r.total = dlTotal;
      return !( r.total > 0 && r.got > 0 );
   };
   try
   {
      r.ok = send( T, url, cookie );
   }
   catch ( x )
   {
   }
   r.code = String( T.responseCode );
   r.type = String( T.contentType );
   r.reached = r.magic == "xar!" && r.total > 0;
   return r;
}

function peekLine( r )
{
   return "response code = " + r.code + "; content type = " + r.type + "; announced size = " + megabytes( r.total ) +
          "; bytes read before stopping = " + r.got + "; starts like a macOS installer package = " + ( r.magic == "xar!" );
}

// ----------------------------------------------------------------------------
// curl
// ----------------------------------------------------------------------------

function textOf( bytes )
{
   try
   {
      return String( bytes.utf8ToString() );
   }
   catch ( x )
   {
      try
      {
         return String( bytes.toString() );
      }
      catch ( y )
      {
         return "";
      }
   }
}

function curlError( text )
{
   return text.replace( /https?:\S+/g, "[address]" ).replace( /\s+/g, " " ).substring( 0, 200 );
}

// The text that tells curl what to do: one option per line, values in quotes.
// The quote and the backslash are built from their character codes, so that
// this file holds no escaped quote for PixInsight's loader to trip over.
function curlConfig( pairs )
{
   var quote = String.fromCharCode( 34 ), backslash = String.fromCharCode( 92 ), lines = [];
   for ( var i = 0; i < pairs.length; ++i )
      if ( pairs[i].length == 1 )
         lines.push( pairs[i][0] );
      else
         lines.push( pairs[i][0] + " = " + quote +
                     String( pairs[i][1] ).split( backslash ).join( backslash + backslash ).split( quote ).join( backslash + quote ) + quote );
   return lines.join( "\n" ) + "\n";
}

function common( url, cookie )
{
   var pairs = [ [ "url", url ], [ "user-agent", CURL_NAME ], [ "silent" ], [ "show-error" ] ];
   if ( cookie )
      pairs.push( [ "cookie", cookie ] );
   return pairs;
}

// Start curl and feed it its instructions through its input. An address or a
// cookie that holds a session value, and the password in route 3, therefore
// never reach a file or a command line.
function startCurl( pairs )
{
   var P = new ExternalProcess;
   P.start( CURL, [ "-K", "-" ] );
   P.waitForStarted( 10000 );
   P.stdin = curlConfig( pairs );
   P.closeStandardInput();
   return P;
}

// Run curl to the end and return what it printed, split into the header
// blocks of every reply in the chain, the body of the last reply, and the
// values that curl reports about the transfer.
function curl( pairs, timeoutMs )
{
   var r = { exit: -1, headers: [], body: "", info: [], error: "" };
   try
   {
      var P = startCurl( pairs.concat( [ [ "include" ], [ "write-out", MARK + "%{http_code}|%{num_redirects}|%{content_type}|%{url_effective}" ] ] ) );
      var finished = P.waitForFinished( timeoutMs );
      if ( !finished && P.isRunning )
         P.kill();
      r.exit = finished ? P.exitCode : -2;
      r.error = curlError( textOf( P.standardError ) );
      var out = textOf( P.standardOutput ), at = out.lastIndexOf( MARK );
      if ( at >= 0 )
      {
         r.info = out.substring( at + MARK.length ).split( "|" );
         out = out.substring( 0, at );
      }
      while ( out.indexOf( "HTTP/" ) == 0 )
      {
         var end = out.indexOf( "\r\n\r\n" ), skip = 4;
         if ( end < 0 )
         {
            end = out.indexOf( "\n\n" );
            skip = 2;
         }
         if ( end < 0 )
            break;
         r.headers.push( out.substring( 0, end ) );
         out = out.substring( end + skip );
      }
      r.body = out;
   }
   catch ( x )
   {
      r.error = "curl could not be run: " + x;
   }
   r.code = r.info[0] || "";
   r.redirects = r.info[1] || "";
   r.type = r.info[2] || "";
   r.host = hostOf( r.info.slice( 3 ).join( "|" ) );
   return r;
}

function headerOf( block, name )
{
   var lines = block.split( "\n" ), value = "";
   for ( var i = 0; i < lines.length; ++i )
   {
      var colon = lines[i].indexOf( ":" );
      if ( colon > 0 && lines[i].substring( 0, colon ).toLowerCase() == name )
         value = lines[i].substring( colon + 1 ).replace( /^\s+|\s+$/g, "" );
   }
   return value;
}

// Every cookie that a reply sets, as the text to send back: name=value; ...
function cookiesFrom( block )
{
   var lines = block.split( "\n" ), out = [];
   for ( var i = 0; i < lines.length; ++i )
   {
      var m = /^set-cookie:\s*([^=;\s]+)=([^;\r\n]*)/i.exec( lines[i] );
      if ( m != null )
         out.push( m[1] + "=" + m[2] );
   }
   return out.join( "; " );
}

function cookieNames( cookie )
{
   var parts = cookie.split( "; " ), names = [];
   for ( var i = 0; i < parts.length; ++i )
      if ( parts[i].indexOf( "=" ) > 0 )
         names.push( Shape.showSegment( parts[i].substring( 0, parts[i].indexOf( "=" ) ) ) );
   return names.length > 0 ? names.join( ", " ) : "none";
}

// Ask for the first four bytes of an installer, following redirects.
function curlPeek( url, cookie )
{
   var r = curl( common( url, cookie ).concat( [ [ "location" ], [ "range", "0-3" ], [ "max-time", "60" ], [ "max-filesize", "1048576" ] ] ), 90000 );
   r.total = 0;
   r.magic = r.body.substring( 0, 4 );
   r.firstCode = "";
   r.firstTarget = "";
   if ( r.headers.length > 0 )
   {
      var first = r.headers[0], last = r.headers[r.headers.length - 1];
      r.firstCode = ( /^HTTP\/\S+\s+(\d+)/.exec( first ) || [ "", "" ] )[1];
      if ( r.headers.length > 1 )
         r.firstTarget = describeTarget( headerOf( first, "location" ), url );
      var m = /bytes\s+\d+-\d+\/(\d+)/i.exec( headerOf( last, "content-range" ) );
      if ( m != null )
         r.total = parseInt( m[1], 10 );
      else
         r.total = parseInt( headerOf( last, "content-length" ), 10 ) || 0;
   }
   // Exit 63 means the server ignored the request for four bytes and announced
   // the whole file, which is larger than the limit set above.
   r.reached = r.type.indexOf( "html" ) < 0 && ( r.magic == "xar!" || ( r.exit == 63 && r.total > 4 ) );
   return r;
}

function curlPeekLine( r )
{
   return "curl exit code = " + r.exit + "; first reply = " + r.firstCode +
          ( r.firstTarget.length > 0 ? ", a redirect to " + r.firstTarget : "" ) +
          "; redirects followed = " + r.redirects + "; last reply = " + r.code + " from the host " + r.host + "; content type = " + r.type +
          "; size = " + megabytes( r.total ) + "; starts like a macOS installer package = " + ( r.magic == "xar!" ) +
          ( r.error.length > 0 ? "; curl said: " + r.error : "" );
}

// Sign in with curl. Returns the page and the cookies that the reply set.
function curlSignIn()
{
   var r = curl( [ [ "url", SIGNIN ], [ "user-agent", CURL_NAME ], [ "silent" ], [ "show-error" ], [ "max-time", "60" ],
                   [ "data-urlencode", "user_name=" + Shape.user ], [ "data-urlencode", "user_password=" + Shape.pass ] ], 90000 );
   r.cookie = r.headers.length > 0 ? cookiesFrom( r.headers[r.headers.length - 1] ) : "";
   r.signedIn = r.exit == 0 && r.code == "200" && !signedOut( r.body );
   return r;
}

// Download a whole installer with curl, writing progress once a second.
function curlDownload( url, cookie, path, progressPath, total )
{
   var r = { exit: -1, info: [], error: "" };
   try
   {
      var P = startCurl( common( url, cookie ).concat( [ [ "location" ], [ "fail" ], [ "output", path ],
                                                         [ "write-out", MARK + "%{http_code}|%{num_redirects}|%{content_type}" ] ] ) );
      var done = false, ticks = 0;
      while ( !done && ticks < 6*3600 )
      {
         done = P.waitForFinished( 1000 ) || !( P.isRunning || P.isStarting );
         ++ticks;
         var got = 0;
         try { got = ( new FileInfo( path ) ).size; } catch ( x ) {}
         try { File.writeTextFile( progressPath, got + " " + total + "\n" ); } catch ( x ) {}
      }
      if ( !done )
         P.kill();
      r.exit = done ? P.exitCode : -2;
      r.error = curlError( textOf( P.standardError ) );
      var out = textOf( P.standardOutput ), at = out.lastIndexOf( MARK );
      if ( at >= 0 )
         r.info = out.substring( at + MARK.length ).split( "|" );
   }
   catch ( x )
   {
      r.error = "curl could not be run: " + x;
   }
   return r;
}

// ----------------------------------------------------------------------------

function probe( out )
{
   var anonymousOnly = File.exists( out + "/t3-anonymous-only" );

   say( "Test 3 report, written " + ( new Date ).toISOString() );
   say( "Service: " + ( BASE.indexOf( "https://pixinsight.com/" ) == 0 ? BASE : "the stand-in on this computer, " + BASE ) );
   say( "PixInsight " + CoreApplication.versionMajor + "." + CoreApplication.versionMinor + "." + CoreApplication.versionRelease + "-" + CoreApplication.versionRevision +
        ", build " + CoreApplication.versionBuild + "; client name sent to servers: " + CoreApplication.agentName );
   say( "PI_USER is " + ( Shape.user.length > 0 ? "set" : "not set" ) + "; PI_PASS is " + ( Shape.pass.length > 0 ? "set" : "not set" ) +
        ( anonymousOnly ? "; this run was told to stop after step B" : "" ) );

   // --- A ------------------------------------------------------------------
   var T = newTransfer();
   var a = request( T, BASE, null );
   describe( "A. The sign-in page, requested with no details (GET " + BASE + ")", a );
   if ( !a.ok || a.code != "200" )
   {
      say( "" );
      say( "STOPPED: the server did not serve the sign-in page to a script. The other steps were not run." );
      return;
   }

   // --- B ------------------------------------------------------------------
   if ( anonymousOnly )
   {
      var madeUpUser = "update-assistant-test-" + Math.floor( 100000 + 900000*Math.random() );
      var b = request( T, SIGNIN, "user_name=" + encodeURIComponent( madeUpUser ) + "&user_password=" + encodeURIComponent( "not-a-real-password" ) );
      describe( "B. Sign-in with a made-up user name and password (POST " + SIGNIN + ")", b );
      var refused = Shape.newLines( Shape.visibleLines( b.html ), Shape.visibleLines( a.html ) ), shown = [];
      for ( var i = 0; i < refused.length; ++i )
         shown.push( "   | " + refused[i].split( madeUpUser ).join( "[the made-up user name]" ) );
      sayList( "   text on this page that the sign-in page does not have:", shown, 15 );
      say( "" );
      say( "The other steps were skipped: this run was told to stop after step B." );
      return;
   }
   if ( Shape.user.length == 0 || Shape.pass.length == 0 )
   {
      say( "" );
      say( "The other steps were skipped: PI_USER and PI_PASS are not both set." );
      return;
   }

   // --- C ------------------------------------------------------------------
   var c = request( newTransfer(), SIGNIN, details() );
   describe( "C. Sign-in with your details, by PixInsight (POST " + SIGNIN + ")", c );
   if ( !c.ok || signedOut( c.html ) )
   {
      say( "" );
      say( "The reply to C is empty, a refusal or the sign-in form again, so the sign-in did not succeed. The other steps were not run." );
      return;
   }
   var downloads = Shape.findDownloads( c.html, SIGNIN ), lines = [];
   for ( var k = 0; k < downloads.length; ++k )
      lines.push( "   | " + downloads[k].name + "  <-  " + ( downloads[k].method == "GET" ? "a link to " : "a form sent to " ) + scriptOf( downloads[k].url ) );
   say( "   files on the page: " + downloads.length );
   sayList( "   newest installer of each kind:", newestOfEachKind( downloads ), 12 );

   // --- D ------------------------------------------------------------------
   var chip = buildChip();
   say( "" );
   say( "D. This PixInsight is the " + ( chip == "arm64" ? "Apple-silicon" : "Intel" ) + " build." );
   var pick = Shape.pickForMac( downloads, chip );
   if ( pick == null || pick.method != "GET" )
   {
      say( "   No macOS installer link could be picked, so no route was tried." );
      return;
   }
   var info = Shape.parseInstallerName( pick.name ), sha1 = Shape.checksumFor( c.html, pick.name );
   say( "   newest macOS installer for this build: " + pick.name + " (version " + info.versionText + ", file dated " + info.date + ")" );
   say( "   SHA-1 checksum shown on the page: " + ( sha1.length > 0 ? sha1 : "none found" ) );
   say( "   it is a link to " + scriptOf( pick.url ) + " on " + hostOf( pick.url ) );

   var how = "", total = 0;
   var session = Shape.paramOf( pick.url, "session_id" ), cookie = session.length > 0 ? "PHPSESSID=" + session : "";

   // Route 0: the plain link, as PixInsight sends it.
   var plain = peek( newTransfer(), pick.url, null );
   say( "   route 0, PixInsight with no cookie: " + peekLine( plain ) );
   if ( plain.reached )
   {
      how = "pixinsight";
      total = plain.total;
   }

   // Route 1: PixInsight, sending the link's session value as the cookie.
   if ( how.length == 0 && cookie.length > 0 )
   {
      var withCookie = peek( newTransfer(), pick.url, cookie );
      say( "   route 1, PixInsight sending the link's session value as the cookie PHPSESSID, in a POST: " + peekLine( withCookie ) );
      if ( withCookie.reached )
      {
         how = "pixinsight-cookie";
         total = withCookie.total;
      }
   }
   else if ( how.length == 0 )
      say( "   route 1 was skipped: the link carries no session value." );

   // Route 2: curl with that cookie, after PixInsight's sign-in.
   if ( how.length == 0 && cookie.length > 0 )
   {
      var second = curlPeek( pick.url, cookie );
      say( "   route 2, curl (client name " + CURL_NAME + ") with that cookie, after PixInsight's sign-in: " + curlPeekLine( second ) );
      if ( second.reached )
      {
         how = "curl-cookie";
         total = second.total;
      }
   }

   // Route 3: curl signs in itself and keeps the cookies it is given.
   if ( how.length == 0 )
   {
      var signIn = curlSignIn();
      say( "   route 3, curl signs in: curl exit code = " + signIn.exit + "; response code = " + signIn.code + "; page size = " + signIn.body.length +
           " characters; signed in = " + signIn.signedIn + "; cookies set by the reply: " + cookieNames( signIn.cookie ) +
           ( signIn.error.length > 0 ? "; curl said: " + signIn.error : "" ) );
      if ( signIn.signedIn )
      {
         var again = findByName( Shape.findDownloads( signIn.body, SIGNIN ), pick.name );
         if ( again == null )
            say( "   route 3: the page that curl received does not list " + pick.name );
         else
         {
            var third = curlPeek( again.url, signIn.cookie );
            say( "   route 3, curl fetches with the cookies from its own sign-in: " + curlPeekLine( third ) );
            if ( !third.reached && signIn.cookie.length == 0 )
               say( "   (the sign-in reply set no cookie, so curl had none to send)" );
            if ( third.reached )
            {
               how = "curl-all";
               total = third.total;
               if ( sha1.length == 0 )
                  sha1 = Shape.checksumFor( signIn.body, pick.name );
            }
         }
      }
   }

   say( "" );
   if ( how.length > 0 )
   {
      var words = { "pixinsight": "PixInsight alone, with no cookie",
                    "pixinsight-cookie": "PixInsight alone, sending the session value from the link as a cookie",
                    "curl-cookie": "curl, using the session of PixInsight's sign-in; the password never leaves PixInsight",
                    "curl-all": "curl for sign-in and download; the password reaches curl through its input only" };
      say( "RESULT: the installer can be fetched. Route that worked: " + words[how] + "." );
      say( "Size: " + megabytes( total ) + "." );
      File.writeTextFile( out + "/t3-choice.txt", "name=" + pick.name + "\nsize=" + total + "\nhow=" + how + "\nsha1=" + sha1 + "\n" );
   }
   else
      say( "RESULT: the installer could not be reached by any route, so no download is offered." );
}

function download( out )
{
   var wanted = env( "PI_T3_FILE" ), how = env( "PI_T3_HOW" ), total = parseInt( env( "PI_T3_SIZE" ), 10 ) || 0, started = Date.now();
   say( "Test 3 download, started " + ( new Date ).toISOString() );
   if ( !Shape.FILE_RE.test( wanted ) )
   {
      say( "result = failed: no installer file was named" );
      return;
   }

   // A fresh sign-in, by whoever signs in on this route.
   var html = "", cookie = "";
   if ( how == "curl-all" )
   {
      var signIn = curlSignIn();
      if ( !signIn.signedIn )
      {
         say( "result = failed: the sign-in by curl did not succeed" );
         return;
      }
      html = signIn.body;
      cookie = signIn.cookie;
   }
   else
   {
      var page = request( newTransfer(), SIGNIN, details() );
      if ( !page.ok || signedOut( page.html ) )
      {
         say( "result = failed: the sign-in did not succeed" );
         return;
      }
      html = page.html;
   }
   var target = findByName( Shape.findDownloads( html, SIGNIN ), wanted );
   if ( target == null )
   {
      say( "result = failed: the signed-in page did not offer that file" );
      return;
   }
   if ( how == "pixinsight-cookie" || how == "curl-cookie" )
      cookie = "PHPSESSID=" + Shape.paramOf( target.url, "session_id" );

   var dir = out + "/download";
   if ( !File.directoryExists( dir ) )
      File.createDirectory( dir, true );
   var path = dir + "/" + wanted, progressPath = out + "/t3-progress.txt";
   remove( path );

   var ok = false, got = 0, note = "";
   if ( how == "curl-cookie" || how == "curl-all" )
   {
      var r = curlDownload( target.url, cookie, path, progressPath, total );
      try { got = ( new FileInfo( path ) ).size; } catch ( x ) {}
      ok = r.exit == 0;
      note = "fetched by curl under the client name " + CURL_NAME + "; curl exit code = " + r.exit + "; response code = " + ( r.info[0] || "" ) +
             "; redirects followed = " + ( r.info[1] || "" ) + "; content type = " + ( r.info[2] || "" ) + ( r.error.length > 0 ? "; curl said: " + r.error : "" );
   }
   else
   {
      var T = newTransfer(), f = null, last = 0;
      T.onDownloadDataAvailable = function( data )
      {
         if ( f == null )
         {
            f = new File;
            f.createForWriting( path );
         }
         f.write( data );
         got += data.length;
         return true;
      };
      T.onTransferProgress = function( dlTotal, dlCurrent, ulTotal, ulCurrent )
      {
         if ( dlTotal > 0 )
            total = dlTotal;
         var now = Date.now();
         if ( now - last >= 1000 )
         {
            last = now;
            try { File.writeTextFile( progressPath, got + " " + total + "\n" ); } catch ( x ) {}
         }
         return true;
      };
      var failure = "";
      try
      {
         ok = send( T, target.url, how == "pixinsight-cookie" ? cookie : null );
      }
      catch ( x )
      {
         failure = String( x );
      }
      if ( f != null )
      {
         f.flush();
         f.close();
      }
      note = "fetched by PixInsight's own network call; response code = " + T.responseCode + "; content type = " + T.contentType +
             ( ok ? "" : "; error: " + ( failure.length > 0 ? failure : String( T.errorInformation ) ).replace( /\s+/g, " " ) );
   }

   say( "file = " + wanted );
   say( "saved to = tests/out/download/" + wanted );
   say( note );
   say( "bytes written = " + got + "; expected = " + total + "; time = " + ( ( Date.now() - started )/1000 ).toFixed( 0 ) + " s" );
   say( "result = " + ( ok && got > 0 && ( total == 0 || got == total ) ? "complete" : "failed" ) );
}

function main()
{
   var dir = File.extractDrive( #__FILE__ ) + File.extractDirectory( #__FILE__ );
   var out = dir + "/out";
   if ( !File.directoryExists( out ) )
      File.createDirectory( out, true );

   Shape.user = env( "PI_USER" );
   Shape.pass = env( "PI_PASS" );

   var standin = env( "PI_T3_BASE" );
   if ( standin.length > 0 )
   {
      if ( /^http:\/\/(127\.0\.0\.1|localhost):\d{2,5}\/dist\/$/.test( standin ) )
      {
         BASE = standin;
         SIGNIN = standin + "browser.php";
      }
      else
         say( "PI_T3_BASE was ignored: only a stand-in on this computer is accepted." );
   }

   var downloading = env( "PI_T3_MODE" ) == "download";
   var reportPath = out + ( downloading ? "/t3-download.txt" : "/t3-report.txt" );
   try
   {
      if ( downloading )
         download( out );
      else
         probe( out );
   }
   catch ( x )
   {
      say( "" );
      say( "The probe stopped on an error: " + x + ( x.lineNumber ? " (line " + x.lineNumber + ")" : "" ) );
   }
   writeReport( reportPath );
}

main();
