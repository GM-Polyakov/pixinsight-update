// PixInsight Update Assistant: reading PixInsight's download page.
//
// What is known about the page (TESTING.md, test 3): after sign-in it is one
// long page. Each installer is a link whose visible text is the file name,
// for example PI-macosx-x64-1.9.6-20261119-c.pkg. The link's address holds a
// session value and a file number. The same table row gives the size in MiB
// and a SHA-1 checksum. A refused sign-in is a page that says ACCESS DENIED.
//
// Old-engine JavaScript only (PixInsight 1.9.3 and earlier). No regular-
// expression literal here ends in an escaped slash or holds a quote character:
// PixInsight 1.9.3 refuses a script that has one (TESTING.md, traps).

var UA_Page = {};

UA_Page.FILE_RE = /^[A-Za-z0-9][A-Za-z0-9._+-]{2,120}\.(pkg|exe|dmg|msi|run|zip|xz|gz|bz2|txz|tgz)$/;

UA_Page.decodeEntities = function( s )
{
   return String( s ).replace( /&nbsp;/g, " " ).replace( /&mdash;|&ndash;/g, "-" ).replace( /&lt;/g, "<" ).replace( /&gt;/g, ">" )
      .replace( /&quot;/g, "\"" ).replace( /&#0*39;/g, "'" ).replace( /&apos;/g, "'" )
      .replace( /&#(\d+);/g, function( m, n ) { return String.fromCharCode( parseInt( n, 10 ) ); } )
      .replace( /&amp;/g, "&" );
};

UA_Page.attrs = function( s )
{
   var m, o = {}, re = /([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:\x22([^\x22]*)\x22|\x27([^\x27]*)\x27|([^\s\x22\x27>]+))/g;
   while ( ( m = re.exec( s ) ) != null )
   {
      var v = m[2];
      if ( v === undefined || v === null ) v = m[3];
      if ( v === undefined || v === null ) v = m[4];
      if ( v === undefined || v === null ) v = "";
      o[m[1].toLowerCase()] = v;
   }
   return o;
};

// The text between a tag that ends at "from" and its closing tag.
UA_Page.innerText = function( html, from, tag )
{
   var rest = html.substring( from, from + 600 );
   var end = rest.toLowerCase().indexOf( "</" + tag );
   if ( end >= 0 )
      rest = rest.substring( 0, end );
   return UA_Page.decodeEntities( rest.replace( /<[^>]+>/g, " " ) ).replace( /\s+/g, " " ).replace( /^ | $/g, "" );
};

// A sign-in page has a field in which a password is typed.
UA_Page.hasSignInForm = function( html )
{
   var m, re = /<input\b([^>]*)>/gi;
   while ( ( m = re.exec( html ) ) != null )
      if ( ( UA_Page.attrs( m[1] ).type || "" ).toLowerCase() == "password" )
         return true;
   return false;
};

// True if the reply to a sign-in is not the signed-in page.
UA_Page.refused = function( html )
{
   return html.length == 0 || html.indexOf( "ACCESS DENIED" ) >= 0 || UA_Page.hasSignInForm( html );
};

UA_Page.normalizePath = function( path )
{
   var parts = path.split( "/" ), out = [];
   for ( var i = 0; i < parts.length; ++i )
   {
      if ( parts[i] == "." )
         continue;
      if ( parts[i] == ".." )
      {
         if ( out.length > 1 )
            out.pop();
         continue;
      }
      out.push( parts[i] );
   }
   return out.join( "/" );
};

UA_Page.absoluteURL = function( href, base )
{
   if ( /^[a-z][a-z0-9+.-]*:/i.test( href ) )
      return href;
   var m = /^([a-z][a-z0-9+.-]*:\/\/[^\/?#]+)([^?#]*)/i.exec( base );
   var origin = m[1], path = m[2].length > 0 ? m[2] : "/";
   if ( href.indexOf( "//" ) == 0 )
      return origin.substring( 0, origin.indexOf( ":" ) + 1 ) + href;
   if ( href.charAt( 0 ) == "/" )
      return origin + href;
   if ( href.length == 0 || href.charAt( 0 ) == "#" )
      return origin + path;
   if ( href.charAt( 0 ) == "?" )
      return origin + path + href;
   var q = "", i = href.indexOf( "?" );
   if ( i >= 0 )
   {
      q = href.substring( i );
      href = href.substring( 0, i );
   }
   return origin + UA_Page.normalizePath( path.substring( 0, path.lastIndexOf( "/" ) + 1 ) + href ) + q;
};

// One value from the part of an address after the question mark.
UA_Page.paramOf = function( url, key )
{
   var query = url.split( "#" )[0].split( "?" )[1] || "", pairs = query.split( "&" );
   for ( var i = 0; i < pairs.length; ++i )
   {
      var eq = pairs[i].indexOf( "=" );
      if ( eq > 0 && pairs[i].substring( 0, eq ) == key )
      {
         try
         {
            return decodeURIComponent( pairs[i].substring( eq + 1 ) );
         }
         catch ( x )
         {
            return pairs[i].substring( eq + 1 );
         }
      }
   }
   return "";
};

// Every installer on the page: { name, url }.
UA_Page.installers = function( html, baseURL )
{
   var found = [], seen = {}, m, re = /<a\b([^>]*)>/gi;
   while ( ( m = re.exec( html ) ) != null )
   {
      var href = UA_Page.decodeEntities( UA_Page.attrs( m[1] ).href || "" );
      var name = UA_Page.innerText( html, re.lastIndex, "a" );
      if ( !UA_Page.FILE_RE.test( name ) || href.length == 0 || href.charAt( 0 ) == "#" || /^(javascript|mailto):/i.test( href ) )
         continue;
      // Asked this way, and not by reading seen[...], because PixInsight's old
      // engine prints a warning whenever a script reads a property that is
      // not there.
      if ( seen.hasOwnProperty( "=" + name ) )
         continue;
      seen["=" + name] = true;
      found.push( { name: name, url: UA_Page.absoluteURL( href, baseURL ) } );
   }
   return found;
};

// The text of the table row that holds the link with the text "name", after the link.
UA_Page.rowAfter = function( html, name )
{
   var at = html.indexOf( ">" + name + "</a>" );
   if ( at < 0 )
      return "";
   var rest = html.substring( at + name.length + 5, at + 4000 );
   var end = rest.toLowerCase().indexOf( "</tr>" );
   if ( end >= 0 )
      rest = rest.substring( 0, end );
   return rest;
};

// The SHA-1 checksum shown in the same row: forty hexadecimal digits.
UA_Page.checksumFor = function( html, name )
{
   var m = /(^|[^0-9A-Fa-f])([0-9A-Fa-f]{40})(?![0-9A-Fa-f])/.exec( UA_Page.rowAfter( html, name ).replace( /<[^>]+>/g, " " ) );
   return m == null ? "" : m[2].toLowerCase();
};

// The size shown in the same row, in bytes. The page gives it in MiB with
// three decimals, so this is right to about a kilobyte. Zero if not found.
UA_Page.sizeFor = function( html, name )
{
   var m = /<td[^>]*>\s*(\d{1,6}(?:\.\d{1,3})?)\s*<\/td>/i.exec( UA_Page.rowAfter( html, name ) );
   return m == null ? 0 : Math.round( parseFloat( m[1] )*1048576 );
};

// PI-macosx-x64-1.9.6-20261119-c.pkg -> platform, build type, version, date.
UA_Page.parseName = function( name )
{
   var tokens = name.toLowerCase().split( /[-_.]/ ), has = {};
   for ( var i = 0; i < tokens.length; ++i )
      has["=" + tokens[i]] = true;
   var r = { name: name, platform: "", arch: "", version: [ 0, 0, 0, 0 ], versionText: "", date: "" };
   if ( has["=macosx"] || has["=macos"] || has["=osx"] ) r.platform = "macos";
   else if ( has["=windows"] || has["=win"] ) r.platform = "windows";
   else if ( has["=linux"] ) r.platform = "linux";
   else if ( has["=freebsd"] ) r.platform = "freebsd";
   if ( has["=arm64"] || has["=aarch64"] ) r.arch = "arm64";
   else if ( has["=x64"] || has["=x86_64"] || has["=amd64"] ) r.arch = "x64";
   var v = /(?:^|[-_])v?(\d{1,2})\.(\d{1,2})\.(\d{1,2})(?:[-.](\d{1,2})(?![0-9]))?/.exec( name );
   if ( v != null )
   {
      r.version = [ parseInt( v[1], 10 ), parseInt( v[2], 10 ), parseInt( v[3], 10 ), v[4] ? parseInt( v[4], 10 ) : 0 ];
      r.versionText = r.version[0] + "." + r.version[1] + "." + r.version[2] + ( r.version[3] > 0 ? "-" + r.version[3] : "" );
   }
   var d = /(?:^|[-_.])(20\d{6})(?![0-9])/.exec( name );
   if ( d != null )
      r.date = d[1];
   return r;
};

UA_Page.compareVersions = function( a, b )
{
   for ( var i = 0; i < 4; ++i )
      if ( a[i] != b[i] )
         return a[i] - b[i];
   return 0;
};

// The newest installer for one platform and build type, or null.
// On macOS only .pkg files count, and on Windows only .exe files.
UA_Page.newest = function( installers, platform, arch )
{
   var best = null, bestInfo = null;
   for ( var i = 0; i < installers.length; ++i )
   {
      var info = UA_Page.parseName( installers[i].name );
      if ( info.platform != platform || info.arch != arch || info.versionText.length == 0 )
         continue;
      if ( platform == "macos" && !/\.pkg$/i.test( info.name ) )
         continue;
      if ( platform == "windows" && !/\.exe$/i.test( info.name ) )
         continue;
      var c = best == null ? 1 : UA_Page.compareVersions( info.version, bestInfo.version );
      if ( c > 0 || ( c == 0 && info.date > bestInfo.date ) )
      {
         best = installers[i];
         bestInfo = info;
      }
   }
   if ( best == null )
      return null;
   return { name: best.name, url: best.url, version: bestInfo.version, versionText: bestInfo.versionText, date: bestInfo.date };
};
