// Checks tests/lib/page-shape.js against made-up pages, outside PixInsight.
// Run:  osascript -l JavaScript tests/selftest-page-shape.jxa.js tests/lib/page-shape.js
//
// The made-up pages hold a made-up user name, password, real name, e-mail
// address, customer number and session value. The checks confirm that none of
// them survives into the text the probe would print.

function run( argv )
{
   ObjC.import( "Foundation" );
   var src = $.NSString.stringWithContentsOfFileEncodingError( argv[0], $.NSUTF8StringEncoding, null ).js;
   ( 0, eval )( src );

   var out = [], failed = 0;
   function check( name, ok, detail )
   {
      if ( !ok ) ++failed;
      out.push( ( ok ? "ok    " : "FAIL  " ) + name + ( !ok && detail !== undefined ? "\n         got: " + detail : "" ) );
   }

   var USER = "janeastro", PASS = "S3cret!pass", SID = "9f8e7d6c5b4a39281716aabbccddeeff";
   Shape.user = USER;
   Shape.pass = PASS;
   var BASE = "https://pixinsight.com/dist/browser.php";

   var anonymous =
      "<html><head><title>PixInsight — Software Distribution</title></head><body>" +
      "<a href=\"https://pixinsight.com/\">Home</a>" +
      "<form action=\"browser.php\" method=\"post\"><input type=\"text\" name=\"user_name\" id=\"user_name\">" +
      "<input type=\"password\" name=\"user_password\"><input type=\"submit\" value=\"&gt; Login\"></form>" +
      "<a href=\"reset_password.html\">Forgot your password or username?</a></body></html>";

   var withLinks =
      "<html><head><title>PixInsight — Software Distribution</title></head><body>" +
      "<a href=\"https://pixinsight.com/\">Home</a>" +
      "<p>Welcome, Jane Q. Astronomer (jane@example.org). Customer 12345678. Logged in as janeastro.</p>" +
      "<h2>PixInsight 1.9.4 Lockhart</h2><table>" +
      "<tr><td>macOS ARM64</td><td><a href=\"download.php?file=PI-macosx-arm64-1.9.4-20260901-c.pkg&amp;sid=" + SID + "\">PI-macosx-arm64-1.9.4-20260901-c.pkg</a></td><td>734 MB</td></tr>" +
      "<tr><td>macOS x64</td><td><a href=\"download.php?file=PI-macosx-x64-1.9.4-20260901-c.pkg&amp;sid=" + SID + "\">PI-macosx-x64-1.9.4-20260901-c.pkg</a></td><td>751 MB</td></tr>" +
      "<tr><td>macOS x64, previous</td><td><a href=\"download.php?file=PI-macosx-x64-1.9.3-20250402-c.pkg&amp;sid=" + SID + "\">PI-macosx-x64-1.9.3-20250402-c.pkg</a></td></tr>" +
      "<tr><td>Windows</td><td><a href=\"/dist/files/" + SID + "/PI-windows-x64-1.9.4-20260901-c.exe\">Windows installer</a></td></tr>" +
      "<tr><td>Linux</td><td><a href=\"download.php?file=PI-linux-x64-1.9.4-20260901-c.tar.xz&amp;sid=" + SID + "\">Linux</a></td></tr>" +
      "</table><a href=\"logout.php?sid=" + SID + "\">Logout</a>" +
      "<script>var session = \"" + SID + "\"; var who = 'janeastro'; var id = 12345678;</script></body></html>";

   var withForms =
      "<html><head><title>Downloads</title></head><body>" +
      "<form action=\"/dist/download.php\" method=\"post\">" +
      "<input type=\"hidden\" name=\"user_name\" value=\"" + USER + "\"><input type=\"hidden\" name=\"user_password\" value=\"S3cret!pass\">" +
      "<input type=\"hidden\" name=\"token\" value=\"" + SID + "\">" +
      "<select name=\"file\"><option value=\"PI-macosx-x64-1.9.4-20260901-c.pkg\">macOS x64</option>" +
      "<option value=\"PI-macosx-arm64-1.9.4-20260901-c.pkg\">macOS ARM64</option>" +
      "<option value=\"PI-windows-x64-1.9.4-20260901-c.exe\">Windows</option></select>" +
      "<input type=\"submit\" name=\"go\" value=\"Download\"></form></body></html>";

   var SECRETS = [ USER, PASS, SID, "Jane", "Astronomer", "example.org", "12345678" ];
   function leak( text )
   {
      for ( var i = 0; i < SECRETS.length; ++i )
         if ( text.indexOf( SECRETS[i] ) >= 0 )
            return SECRETS[i];
      return null;
   }

   // --- what the probe would print for each page ---
   function printed( html )
   {
      var lines = [];
      lines.push( Shape.showTextLine( Shape.title( html ) ) );
      lines = lines.concat( Shape.outline( html, Shape.linkSet( anonymous ) ) );
      lines = lines.concat( Shape.inlineScripts( html, anonymous ) );
      var text = Shape.newLines( Shape.visibleLines( html ), Shape.visibleLines( anonymous ) );
      for ( var i = 0; i < text.length; ++i )
         lines.push( Shape.showTextLine( text[i] ) );
      lines.push( Shape.fileNames( html ).join( ", " ) );
      lines.push( Shape.versions( Shape.visibleLines( html ).join( "\n" ) ).join( ", " ) );
      return lines.join( "\n" );
   }

   var p1 = printed( withLinks ), p2 = printed( withForms );
   check( "page with links: nothing private is printed", leak( p1 ) == null, leak( p1 ) );
   check( "page with forms: nothing private is printed", leak( p2 ) == null, leak( p2 ) );
   check( "page with forms: the user-name field is flagged", p2.indexOf( "[your user name]" ) >= 0, p2 );
   check( "page with forms: the password field is flagged", p2.indexOf( "[your password]" ) >= 0, p2 );
   check( "page with links: installer names are printed", p1.indexOf( "PI-macosx-x64-1.9.4-20260901-c.pkg" ) >= 0, p1 );
   check( "page with links: sizes and platforms are printed", p1.indexOf( "751 MB" ) >= 0 && p1.indexOf( "macOS x64" ) >= 0, p1 );
   check( "page with links: both versions found", Shape.versions( Shape.visibleLines( withLinks ).join( "\n" ) ).join( "," ) == "1.9.4,1.9.3", Shape.versions( Shape.visibleLines( withLinks ).join( "\n" ) ).join( "," ) );

   // --- sign-in form detection ---
   check( "sign-in form found on the plain page", Shape.hasSignInForm( anonymous ) );
   check( "no sign-in form on the page with links", !Shape.hasSignInForm( withLinks ) );
   check( "a hidden password field is not a sign-in form", !Shape.hasSignInForm( withForms ) );

   // --- folder links ---
   var folders = "<a href=\"https://pixinsight.com/\">Home</a><a href=\"browser.php?dir=PixInsight%2F1.9.4\">1.9.4</a>" +
      "<a href=\"browser.php?dir=PixInsight\">PixInsight</a><a href=\"browser.php?action=logout\">Logout</a>" +
      "<a href=\"browser.php?do=delete&amp;id=7\">Remove</a><a href=\"other.php?x=1\">Other</a>" +
      "<a href=\"download.php?file=PI-macosx-x64-1.9.4-20260901-c.pkg\">file</a>";
   var nav = Shape.navLinks( folders, BASE, Shape.linkSet( anonymous ) );
   check( "folder links: only the two folders are followed", nav.length == 2 && nav[0] == BASE + "?dir=PixInsight%2F1.9.4" && nav[1] == BASE + "?dir=PixInsight", nav.join( " , " ) );
   check( "folder path in an address is shown part by part", Shape.showValue( "browser.php?dir=PixInsight%2F1.9.4%2Fmacosx" ) == "browser.php?dir=PixInsight/1.9.4/macosx", Shape.showValue( "browser.php?dir=PixInsight%2F1.9.4%2Fmacosx" ) );
   check( "a private part of a folder path is hidden", Shape.showValue( "browser.php?dir=users%2F" + SID ).indexOf( SID ) < 0, Shape.showValue( "browser.php?dir=users%2F" + SID ) );

   // --- finding downloads ---
   var d1 = Shape.findDownloads( withLinks, BASE );
   check( "page with links: five downloads found", d1.length == 5, d1.length );
   var m1 = Shape.pickForMac( d1, "x64" );
   check( "page with links: newest Intel Mac installer chosen", m1 != null && m1.name == "PI-macosx-x64-1.9.4-20260901-c.pkg", m1 && m1.name );
   check( "page with links: its address is complete", m1 != null && m1.method == "GET" && m1.fields == null &&
          m1.url == "https://pixinsight.com/dist/download.php?file=PI-macosx-x64-1.9.4-20260901-c.pkg&sid=" + SID, m1 && m1.url );
   var m1a = Shape.pickForMac( d1, "arm64" );
   check( "page with links: Apple-silicon installer chosen when asked", m1a != null && m1a.name == "PI-macosx-arm64-1.9.4-20260901-c.pkg", m1a && m1a.name );
   var win = null;
   for ( var i = 0; i < d1.length; ++i ) if ( /\.exe$/.test( d1[i].name ) ) win = d1[i];
   check( "page with links: a file named in the path is found", win != null && win.url == "https://pixinsight.com/dist/files/" + SID + "/PI-windows-x64-1.9.4-20260901-c.exe", win && win.url );

   var d2 = Shape.findDownloads( withForms, BASE );
   check( "page with forms: three downloads found", d2.length == 3, d2.length );
   var m2 = Shape.pickForMac( d2, "x64" );
   check( "page with forms: Intel Mac installer chosen", m2 != null && m2.name == "PI-macosx-x64-1.9.4-20260901-c.pkg", m2 && m2.name );
   check( "page with forms: posts to the form's address", m2 != null && m2.method == "POST" && m2.url == "https://pixinsight.com/dist/download.php", m2 && ( m2.method + " " + m2.url ) );
   check( "page with forms: all fields are sent", m2 != null && m2.fields ==
          "user_name=janeastro&user_password=S3cret!pass&token=" + SID + "&file=PI-macosx-x64-1.9.4-20260901-c.pkg&go=Download", m2 && m2.fields );

   // --- the real service's layout: the file name is only in the link text ---
   var real = "<h4>PixInsight Installation Files</h4>" +
      "<a href=\"download_inst.php?session_id=" + SID + "&amp;file_id=0123456789abcdef0123456789abcdef01234567\">PI-macosx-x64-1.9.6-20261119-c.pkg</a>" +
      "<a href=\"download_inst.php?session_id=" + SID + "&amp;file_id=1123456789abcdef0123456789abcdef01234567\">PI-windows-x64-gpu-1.9.6-20261119-c.exe</a>" +
      "<a href=\"download_xpsd.php?session_id=" + SID + "&amp;file_id=2123456789abcdef0123456789abcdef01234567\">Download</a>";
   var d3 = Shape.findDownloads( real, BASE );
   check( "real layout: two installers found by their link text", d3.length == 2 && d3[0].name == "PI-macosx-x64-1.9.6-20261119-c.pkg", d3.length );
   check( "real layout: the address keeps its session value for the request", d3.length > 0 && d3[0].url.indexOf( "session_id=" + SID ) > 0 );
   var gpu = Shape.parseInstallerName( "PI-windows-x64-gpu-1.9.6-20261119-c.exe" );
   check( "installer name with an extra word is read", gpu.platform == "windows" && gpu.versionText == "1.9.6" && gpu.date == "20261119", JSON.stringify( gpu ) );
   var old = Shape.parseInstallerName( "PI-macosx-x64-1.8.9-3-20241124-c.pkg" );
   check( "installer name with a revision is read", old.versionText == "1.8.9-3" && old.date == "20241124", JSON.stringify( old ) );
   check( "1.9.6 is newer than 1.8.9-3", Shape.compareInstallers( gpu, old ) > 0 );

   // --- account details that the first real report let through ---
   check( "an internet address is hidden", Shape.showTextLine( "from 203.0.113.77 today" ).indexOf( "203" ) < 0, Shape.showTextLine( "from 203.0.113.77 today" ) );
   check( "a date and a bare count are hidden", Shape.showTextLine( "You logged in 16 times, last on 2026/11/24" ).search( /16|2026/ ) < 0, Shape.showTextLine( "You logged in 16 times, last on 2026/11/24" ) );
   check( "a size keeps its number", Shape.showTextLine( "size 734 MB" ) == "size 734 MB", Shape.showTextLine( "size 734 MB" ) );

   // --- small pieces ---
   var info = Shape.parseInstallerName( "PI-macosx-x64-1.9.3-20250402-c.pkg" );
   check( "installer name is read", info.platform == "macos" && info.arch == "x64" && info.versionText == "1.9.3" && info.date == "20250402", JSON.stringify( info ) );
   check( "relative address", Shape.absoluteURL( "a/b.php?x=1", BASE ) == "https://pixinsight.com/dist/a/b.php?x=1", Shape.absoluteURL( "a/b.php?x=1", BASE ) );
   check( "parent address", Shape.absoluteURL( "../download/x.pkg", BASE ) == "https://pixinsight.com/download/x.pkg", Shape.absoluteURL( "../download/x.pkg", BASE ) );
   check( "root address", Shape.absoluteURL( "/x/y", BASE ) == "https://pixinsight.com/x/y" );
   check( "query-only address", Shape.absoluteURL( "?f=1", BASE ) == BASE + "?f=1" );
   check( "long mixed value is hidden", Shape.showValue( SID ).indexOf( "characters" ) > 0, Shape.showValue( SID ) );
   check( "e-mail address is hidden", Shape.showTextLine( "Contact jane@example.org today" ).indexOf( "example" ) < 0, Shape.showTextLine( "Contact jane@example.org today" ) );
   check( "refusal text keeps its plain words", Shape.showTextLine( "Invalid user name or password. Please try again." ) == "Invalid user name or password. Please try again.", Shape.showTextLine( "Invalid user name or password. Please try again." ) );
   check( "user name inside a longer word is hidden", Shape.showTextLine( "file-janeastro-1.zip" ).indexOf( USER ) < 0, Shape.showTextLine( "file-janeastro-1.zip" ) );

   out.push( "" );
   out.push( failed == 0 ? "ALL CHECKS PASSED" : failed + " CHECK(S) FAILED" );
   out.push( "" );
   out.push( "--- what the probe would print for the made-up page with links ---" );
   out.push( p1 );
   out.push( "" );
   out.push( "--- what the probe would print for the made-up page with forms ---" );
   out.push( p2 );
   return out.join( "\n" );
}
