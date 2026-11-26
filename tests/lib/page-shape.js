// Functions that describe the shape of a web page without revealing what is
// private in it. Used by t3-signin-probe.js inside PixInsight and by
// selftest-page-shape.sh outside it.
//
// The rule for everything printed: a value from the page is shown only if it
// is an installer file name, a version number, a plain word from a fixed list,
// a small number, or the path part of a web address. Anything else is replaced
// by its length. A value equal to, or containing, the user name or password is
// never shown.
//
// Old-engine JavaScript only (PixInsight 1.9.3 and earlier).
//
// A trap in PixInsight 1.9.3: its script loader removes comments without
// understanding regular-expression literals. A literal that ends in an escaped
// slash puts two slashes side by side, the loader cuts the line there, and
// PixInsight then refuses the whole file without any message. Write \/{2}
// for two slashes. Quote characters inside a literal are written as \x22 and
// \x27 here for the same reason, as a precaution.

var Shape = {};

Shape.user = "";
Shape.pass = "";

Shape.FILE_RE = /^[A-Za-z0-9][A-Za-z0-9._+-]{2,120}\.(pkg|exe|dmg|msi|run|zip|xz|gz|bz2|txz|tgz)$/;
Shape.FILE_SCAN = "[A-Za-z0-9][A-Za-z0-9._+-]{2,120}\\.(?:pkg|exe|dmg|msi|run|zip|tar\\.xz|tar\\.gz|tar\\.bz2|txz|tgz)(?![A-Za-z0-9])";

Shape.WORDS = (function()
{
   var list = "macos mac os x osx macosx windows win linux freebsd x64 x86_64 amd64 arm64 aarch64 intel apple silicon " +
      "lockhart ripley pixinsight pleiades astrophoto core application installer installers installation install package packages " +
      "download downloads file files size mb gb kb mib gib kib bytes build version versions release released date " +
      "license licenses licensed trial commercial software distribution current latest new old previous legacy " +
      "compatibility native for and the of on a an to is are was be this that with by or not no your you we our " +
      "login logout log out in sign username user name password invalid incorrect wrong unknown error failed failure denied " +
      "please try again required must enter valid account data access expired forgot reset " +
      "sha1 sha256 md5 checksum notes readme changelog documentation platform platforms architecture bit 64-bit " +
      "available select choose click here link links list all none items item home back next";
   var words = list.split( " " ), set = {};
   for ( var i = 0; i < words.length; ++i )
      set[words[i]] = true;
   return set;
})();

Shape.decodeEntities = function( s )
{
   return String( s ).replace( /&nbsp;/g, " " ).replace( /&mdash;|&ndash;/g, "-" ).replace( /&lt;/g, "<" ).replace( /&gt;/g, ">" )
      .replace( /&quot;/g, "\"" ).replace( /&#0*39;/g, "'" ).replace( /&apos;/g, "'" )
      .replace( /&#(\d+);/g, function( m, n ) { return String.fromCharCode( parseInt( n, 10 ) ); } )
      .replace( /&amp;/g, "&" );
};

Shape.safeDecode = function( s )
{
   try
   {
      return decodeURIComponent( String( s ).replace( /\+/g, " " ) );
   }
   catch ( x )
   {
      return String( s );
   }
};

Shape.containsSecret = function( v )
{
   var forms = [ String( v ), Shape.safeDecode( v ) ];
   for ( var i = 0; i < forms.length; ++i )
   {
      if ( Shape.user.length >= 3 && forms[i].toLowerCase().indexOf( Shape.user.toLowerCase() ) >= 0 )
         return true;
      if ( Shape.pass.length >= 3 && forms[i].indexOf( Shape.pass ) >= 0 )
         return true;
   }
   return false;
};

Shape.kind = function( v )
{
   var k = [];
   if ( /[A-Za-z]/.test( v ) ) k.push( "letters" );
   if ( /\d/.test( v ) ) k.push( "digits" );
   if ( /[^A-Za-z0-9]/.test( v ) ) k.push( "other characters" );
   return k.join( ", " );
};

Shape.hidden = function( v )
{
   return "[" + v.length + " characters: " + Shape.kind( v ) + "]";
};

Shape.looksLikeToken = function( v )
{
   return v.length >= 16 && /\d/.test( v ) && /[A-Za-z]/.test( v ) && !Shape.FILE_RE.test( v );
};

// One part of a web address between two slashes.
Shape.showSegment = function( p )
{
   if ( p.length == 0 || p == "." || p == ".." || /^https?:$/i.test( p ) )
      return p;
   var d = Shape.safeDecode( p );
   if ( d == Shape.user && d.length > 0 ) return "[your user name]";
   if ( d == Shape.pass && d.length > 0 ) return "[your password]";
   if ( Shape.containsSecret( d ) ) return "[" + d.length + " characters, contains your user name or password]";
   if ( Shape.FILE_RE.test( d ) ) return d;
   if ( /^[A-Za-z][A-Za-z0-9_.-]{0,39}$/.test( d ) && !Shape.looksLikeToken( d ) ) return d;
   if ( /^\d{1,4}$/.test( d ) ) return d;
   if ( /^v?\d{1,2}(\.\d{1,2}){1,2}(-\d{1,3})?$/.test( d ) ) return d;
   return "[" + d.length + " characters]";
};

// A value after the question mark of a web address, or a field value: shown
// if it passes the plain rule; shown part by part if it is a folder path;
// otherwise replaced by its length.
Shape.showQueryValue = function( v )
{
   var plain = Shape.showPlain( v );
   if ( plain != null )
      return plain;
   if ( /^[^\/?#\s]*(\/[^\/?#\s]*)+$/.test( v ) && !/^[a-z][a-z0-9+.-]*:/i.test( v ) )
   {
      var parts = v.split( "/" ), shown = [];
      for ( var i = 0; i < parts.length; ++i )
         shown.push( Shape.showSegment( parts[i] ) );
      return shown.join( "/" );
   }
   return Shape.hidden( v );
};

Shape.showPlain = function( v )
{
   if ( v.length == 0 ) return "\"\"";
   if ( v == Shape.user ) return "[your user name]";
   if ( v == Shape.pass ) return "[your password]";
   if ( Shape.containsSecret( v ) ) return "[" + v.length + " characters, contains your user name or password]";
   if ( Shape.FILE_RE.test( v ) ) return "\"" + v + "\"";
   if ( /^[A-Za-z][A-Za-z_-]{0,19}$/.test( v ) ) return "\"" + v + "\"";
   if ( /^\d{1,3}$/.test( v ) ) return "\"" + v + "\"";
   if ( /^v?\d{1,2}(\.\d{1,2}){1,2}(-\d{1,3})?$/.test( v ) ) return "\"" + v + "\"";
   return null;
};

// A web address: the path is shown part by part, and each value after the
// question mark is shown only if it passes the same rule.
Shape.showURL = function( u )
{
   var q = "", i = u.indexOf( "#" );
   if ( i >= 0 ) u = u.substring( 0, i );
   i = u.indexOf( "?" );
   if ( i >= 0 )
   {
      q = u.substring( i + 1 );
      u = u.substring( 0, i );
   }
   var parts = u.split( "/" ), shown = [];
   for ( i = 0; i < parts.length; ++i )
      shown.push( Shape.showSegment( parts[i] ) );
   var s = shown.join( "/" );
   if ( q.length > 0 )
   {
      var pairs = q.split( "&" ), qs = [];
      for ( i = 0; i < pairs.length; ++i )
      {
         var eq = pairs[i].indexOf( "=" );
         var k = eq < 0 ? pairs[i] : pairs[i].substring( 0, eq );
         var v = eq < 0 ? "" : Shape.safeDecode( pairs[i].substring( eq + 1 ) );
         qs.push( Shape.showSegment( k ) + "=" + Shape.showQueryValue( v ) );
      }
      s += "?" + qs.join( "&" );
   }
   return s;
};

Shape.showValue = function( v )
{
   v = Shape.decodeEntities( v );
   var plain = Shape.showPlain( v );
   if ( plain != null )
      return plain;
   if ( /^(https?:)?\/{2}/i.test( v ) || /^[.\/?]/.test( v ) || /^[A-Za-z0-9_.\/-]+\.(php|html?|js|css|cgi)([?#]|$)/.test( v ) )
      return Shape.showURL( v );
   return Shape.showQueryValue( v );
};

// Links that move around inside the same page script, for example from one
// folder of a file browser to another: same address as `pageURL` up to the
// question mark, with a different query. Links that name an installer file,
// links that the plain sign-in page also has, and links whose address or text
// suggests an action (sign out, delete, change, buy and so on) are left out.
Shape.navLinks = function( html, pageURL, skipLinks )
{
   var m, re = /<a\b([^>]*)>/gi, out = [], seen = {};
   var self = pageURL.split( "#" )[0].split( "?" )[0];
   var action = /(log.?out|log.?off|sign.?out|exit|delete|remove|reset|cancel|deactivat|revoke|renew|purchase|buy|order|pay|change|edit|profile|password|unsubscribe|activate|register|transfer)/i;
   while ( ( m = re.exec( html ) ) != null )
   {
      var raw = Shape.attrs( m[1] ).href || "";
      if ( skipLinks && skipLinks["=" + raw] === true )
         continue;
      var href = Shape.decodeEntities( raw );
      if ( href.length == 0 || href.charAt( 0 ) == "#" || /^(javascript|mailto):/i.test( href ) )
         continue;
      var url = Shape.absoluteURL( href, pageURL ).split( "#" )[0];
      if ( url.split( "?" )[0] != self || url.indexOf( "?" ) < 0 )
         continue;
      if ( Shape.fileNameIn( url ) != null )
         continue;
      var text = Shape.innerText( html, re.lastIndex, "a" );
      if ( action.test( url.substring( self.length ) ) || action.test( text ) )
         continue;
      if ( seen["=" + url] !== true )
      {
         seen["=" + url] = true;
         out.push( url );
      }
   }
   return out;
};

// A piece of script, such as an onclick attribute: quoted strings and long
// numbers are passed through the rule above, the rest is kept.
Shape.showCode = function( s )
{
   s = Shape.decodeEntities( s );
   var t = s.replace( /\x22([^\x22\\]*)\x22|\x27([^\x27\\]*)\x27/g, function( m, a, b )
   {
      return Shape.showValue( a !== undefined && a !== null && m.charAt( 0 ) == "\"" ? a : ( b === undefined || b === null ? "" : b ) );
   } ).replace( /\d{5,}/g, function( m ) { return "[" + m.length + " digits]"; } );
   if ( Shape.containsSecret( t ) )
      return "[" + s.length + " characters, contains your user name or password]";
   return t.length > 300 ? t.substring( 0, 300 ) + " ..." : t;
};

Shape.attrs = function( s )
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

Shape.title = function( html )
{
   var m = /<title[^>]*>([\s\S]*?)<\/title>/i.exec( html );
   return m == null ? "" : Shape.decodeEntities( m[1] ).replace( /\s+/g, " " ).replace( /^ | $/g, "" );
};

// A page asks for a sign-in if it has a field in which a password is typed.
// A hidden field that merely carries the password along does not count.
Shape.hasSignInForm = function( html )
{
   var m, re = /<input\b([^>]*)>/gi;
   while ( ( m = re.exec( html ) ) != null )
      if ( ( Shape.attrs( m[1] ).type || "" ).toLowerCase() == "password" )
         return true;
   return false;
};

// The text a reader would see, one line per block; table cells are joined by " | ".
Shape.visibleLines = function( html )
{
   var s = String( html ).replace( /<script\b[\s\S]*?<\/script>/gi, " " ).replace( /<style\b[\s\S]*?<\/style>/gi, " " )
      .replace( /<!--[\s\S]*?-->/g, " " ).replace( /<title\b[\s\S]*?<\/title>/gi, " " );
   s = s.replace( /<\/t[dh]\s*>/gi, " | " );
   s = s.replace( /<(br|\/p|\/div|\/tr|\/li|\/h[1-6]|\/table|\/form|\/option|\/ul|\/ol)\b[^>]*>/gi, "\n" );
   s = s.replace( /<[^>]+>/g, " " );
   s = Shape.decodeEntities( s );
   var lines = s.split( "\n" ), out = [];
   for ( var i = 0; i < lines.length; ++i )
   {
      var t = lines[i].replace( /\s+/g, " " ).replace( /^[ |]+|[ |]+$/g, "" );
      if ( t.length > 0 )
         out.push( t );
   }
   return out;
};

// Lines of `lines` that do not appear in `base`.
Shape.newLines = function( lines, base )
{
   var set = {}, out = [], i;
   for ( i = 0; i < base.length; ++i )
      set["=" + base[i]] = true;
   for ( i = 0; i < lines.length; ++i )
      if ( set["=" + lines[i]] !== true )
         out.push( lines[i] );
   return out;
};

// A line of visible text with every word hidden except installer file names,
// version numbers with two or three parts, a number that is followed by a size
// unit, and the words in Shape.WORDS. Hidden words appear as one middle dot.
// Bare numbers, dates and four-part numbers are hidden: on a real account page
// they turned out to be login counts, login dates and an internet address.
Shape.showTextLine = function( line )
{
   var tokens = String( line ).split( /\s+/ ), out = [], hiddenRun = false;
   for ( var i = 0; i < tokens.length; ++i )
   {
      var t = tokens[i];
      if ( t.length == 0 )
         continue;
      var core = t.replace( /^[(\x22\x27\[<]+/, "" ).replace( /[)\x22\x27\]>.,;:!?]+$/, "" );
      var next = i + 1 < tokens.length ? tokens[i + 1].toLowerCase().replace( /[^a-z]/g, "" ) : "";
      var keep = false;
      if ( core.length == 0 )
         keep = !/[A-Za-z0-9]/.test( t );
      else if ( Shape.containsSecret( core ) )
         keep = false;
      else if ( Shape.FILE_RE.test( core ) )
         keep = true;
      else if ( /^v?\d{1,2}(\.\d{1,2}){1,2}(-\d{1,3})?$/.test( core ) && !/^(mb|gb|kb|mib|gib|kib|bytes)$/.test( next ) )
         keep = /^v?\d\./.test( core );
      else if ( /^\d{1,12}([.,]\d{1,3})?$/.test( core ) && /^(mb|gb|kb|mib|gib|kib|bytes)$/.test( next ) )
         keep = true;
      else if ( Shape.WORDS[core.toLowerCase()] === true )
         keep = true;
      if ( keep )
      {
         out.push( t );
         hiddenRun = false;
      }
      else if ( !hiddenRun )
      {
         out.push( "\u00B7" );
         hiddenRun = true;
      }
   }
   return out.join( " " );
};

Shape.unique = function( list )
{
   var set = {}, out = [];
   for ( var i = 0; i < list.length; ++i )
      if ( set["=" + list[i]] !== true )
      {
         set["=" + list[i]] = true;
         out.push( list[i] );
      }
   return out;
};

Shape.fileNames = function( html )
{
   var text = Shape.safeDecode( Shape.decodeEntities( html ) );
   var m, re = new RegExp( Shape.FILE_SCAN, "g" ), out = [];
   while ( ( m = re.exec( text ) ) != null )
      if ( !Shape.containsSecret( m[0] ) )
         out.push( m[0] );
   return Shape.unique( out );
};

Shape.fileNameIn = function( s )
{
   var m = new RegExp( Shape.FILE_SCAN ).exec( Shape.safeDecode( Shape.decodeEntities( s ) ) );
   return m == null ? null : m[0];
};

Shape.versions = function( text )
{
   var m, re = /(^|[^0-9.])(\d\.\d{1,2}\.\d{1,2}(?:-\d{1,2})?)(?![0-9.])/g, out = [];
   while ( ( m = re.exec( text ) ) != null )
      out.push( m[2] );
   return Shape.unique( out );
};

Shape.linkSet = function( html )
{
   var m, re = /<a\b([^>]*)>/gi, set = {};
   while ( ( m = re.exec( html ) ) != null )
      set["=" + ( Shape.attrs( m[1] ).href || "" )] = true;
   return set;
};

Shape.innerText = function( html, from, tag )
{
   var rest = html.substring( from, from + 600 );
   var end = rest.toLowerCase().indexOf( "</" + tag );
   if ( end >= 0 )
      rest = rest.substring( 0, end );
   return Shape.decodeEntities( rest.replace( /<[^>]+>/g, " " ) ).replace( /\s+/g, " " ).replace( /^ | $/g, "" );
};

// The parts of the page that matter for signing in and downloading: forms and
// their fields, links that the plain sign-in page does not have, frames,
// redirects and headings. Values follow the rule at the top of this file.
Shape.outline = function( html, skipLinks )
{
   var lines = [], re = /<(\/?)([A-Za-z][A-Za-z0-9]*)\b([^>]*)>/g, m, inForm = 0, tables = 0, skipped = 0;
   while ( ( m = re.exec( html ) ) != null )
   {
      var closing = m[1] == "/", tag = m[2].toLowerCase();
      var a = closing ? {} : Shape.attrs( m[3] );
      var pad = inForm > 0 ? "      " : "   ";
      if ( tag == "form" )
      {
         if ( closing )
         {
            inForm = Math.max( 0, inForm - 1 );
            continue;
         }
         lines.push( "   form: method=" + ( a.method || "get" ).toLowerCase() + " action=" + Shape.showValue( a.action || "" ) +
                     ( a.onsubmit ? " onsubmit=" + Shape.showCode( a.onsubmit ) : "" ) );
         ++inForm;
      }
      else if ( closing )
         continue;
      else if ( tag == "input" || tag == "button" || tag == "textarea" || tag == "select" )
         lines.push( pad + tag + ": type=" + ( a.type || "" ) + " name=" + Shape.showValue( a.name || "" ) +
                     ( a.value !== undefined ? " value=" + Shape.showValue( a.value ) : "" ) +
                     ( a.onclick ? " onclick=" + Shape.showCode( a.onclick ) : "" ) );
      else if ( tag == "option" )
         lines.push( pad + "   option: value=" + Shape.showValue( a.value || "" ) + " text=" + Shape.showTextLine( Shape.innerText( html, re.lastIndex, "option" ) ) );
      else if ( tag == "a" )
      {
         var href = a.href || "";
         if ( skipLinks && skipLinks["=" + href] === true )
         {
            ++skipped;
            continue;
         }
         lines.push( pad + "link: href=" + Shape.showValue( href ) + ( a.onclick ? " onclick=" + Shape.showCode( a.onclick ) : "" ) +
                     " text=" + Shape.showTextLine( Shape.innerText( html, re.lastIndex, "a" ) ) );
      }
      else if ( tag == "iframe" || tag == "frame" )
         lines.push( pad + tag + ": src=" + Shape.showValue( a.src || "" ) );
      else if ( tag == "meta" && ( a["http-equiv"] || "" ).toLowerCase() == "refresh" )
         lines.push( pad + "meta refresh: " + Shape.showCode( a.content || "" ) );
      else if ( /^h[1-4]$/.test( tag ) )
         lines.push( pad + tag + ": " + Shape.showTextLine( Shape.innerText( html, re.lastIndex, tag ) ) );
      else if ( tag == "table" )
         ++tables;
   }
   lines.push( "   (tables on the page: " + tables + "; links also on the plain sign-in page, not listed: " + skipped + ")" );
   return lines;
};

// Scripts written into the page itself, shortened, with their quoted strings
// and long numbers passed through the rule at the top of this file.
Shape.inlineScripts = function( html, baseHtml )
{
   var m, re = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi, out = [];
   while ( ( m = re.exec( html ) ) != null )
   {
      var a = Shape.attrs( m[1] ), body = m[2].replace( /\s+/g, " " ).replace( /^ | $/g, "" );
      if ( a.src )
      {
         if ( baseHtml.indexOf( a.src ) < 0 )
            out.push( "   script file: " + Shape.showValue( a.src ) );
      }
      else if ( body.length > 0 && baseHtml.indexOf( m[2] ) < 0 )
         out.push( "   script in the page, " + body.length + " characters: " + Shape.showCode( body ) );
   }
   return out;
};

Shape.normalizePath = function( path )
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

Shape.absoluteURL = function( href, base )
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
   return origin + Shape.normalizePath( path.substring( 0, path.lastIndexOf( "/" ) + 1 ) + href ) + q;
};

Shape.encodeForm = function( pairs )
{
   var out = [];
   for ( var i = 0; i < pairs.length; ++i )
      out.push( encodeURIComponent( pairs[i][0] ) + "=" + encodeURIComponent( pairs[i][1] ) );
   return out.join( "&" );
};

// Every way the page offers to fetch an installer file:
//    { name, method, url, fields }
// For a link, method is GET and fields is null. For a form, fields is the
// text to post. The fields may hold private values: never print them.
Shape.findDownloads = function( html, baseURL )
{
   var found = [], seen = {}, m, re;

   function add( name, method, url, fields )
   {
      if ( method == "GET" && fields != null && fields.length > 0 )
      {
         url += ( url.indexOf( "?" ) < 0 ? "?" : "&" ) + fields;
         fields = null;
      }
      var key = name + "|" + method + "|" + url + "|" + ( fields == null ? "" : fields );
      if ( seen[key] !== true )
      {
         seen[key] = true;
         found.push( { name: name, method: method, url: url, fields: fields } );
      }
   }

   // 1. Links whose address names an installer file.
   re = /<a\b([^>]*)>/gi;
   while ( ( m = re.exec( html ) ) != null )
   {
      var href = Shape.decodeEntities( Shape.attrs( m[1] ).href || "" );
      var linkName = Shape.fileNameIn( href );
      if ( linkName != null && !/^(javascript|mailto):/i.test( href ) )
         add( linkName, "GET", Shape.absoluteURL( href, baseURL ), null );
   }

   // 2. Links whose visible text is an installer file name. This is what the
   //    real service does: the address holds only a session value and a file
   //    number, and the name is what the user reads and clicks.
   re = /<a\b([^>]*)>/gi;
   while ( ( m = re.exec( html ) ) != null )
   {
      var textHref = Shape.decodeEntities( Shape.attrs( m[1] ).href || "" );
      var textName = Shape.innerText( html, re.lastIndex, "a" );
      if ( Shape.FILE_RE.test( textName ) && textHref.length > 0 && textHref.charAt( 0 ) != "#" &&
           !/^(javascript|mailto):/i.test( textHref ) && Shape.fileNameIn( textHref ) == null )
         add( textName, "GET", Shape.absoluteURL( textHref, baseURL ), null );
   }

   // 3. Forms that carry an installer file name in their address or fields.
   re = /<form\b([^>]*)>([\s\S]*?)<\/form>/gi;
   while ( ( m = re.exec( html ) ) != null )
   {
      var fa = Shape.attrs( m[1] ), inner = m[2];
      var method = ( fa.method || "get" ).toUpperCase();
      var action = Shape.absoluteURL( Shape.decodeEntities( fa.action || "" ), baseURL );
      var fixed = [], groups = {}, groupOrder = [], fm;

      function choice( name, value )
      {
         if ( groups["=" + name] === undefined )
         {
            groups["=" + name] = [];
            groupOrder.push( name );
         }
         groups["=" + name].push( value );
      }

      var selectName = null;
      var fre = /<(\/?)(input|select|button|option|textarea)\b([^>]*)>/gi;
      while ( ( fm = fre.exec( inner ) ) != null )
      {
         var tag = fm[2].toLowerCase(), a = Shape.attrs( fm[3] );
         if ( fm[1] == "/" )
         {
            if ( tag == "select" )
               selectName = null;
            continue;
         }
         var type = ( a.type || "" ).toLowerCase();
         var value = Shape.decodeEntities( a.value === undefined ? "" : a.value );
         if ( tag == "select" )
            selectName = a.name || null;
         else if ( tag == "option" )
         {
            if ( selectName != null )
               choice( selectName, value );
         }
         else if ( !a.name )
            continue;
         else if ( type == "submit" || type == "image" || tag == "button" )
            choice( "\u0001submit", a.name + "\u0002" + value );
         else if ( type == "radio" )
            choice( a.name, value );
         else if ( type == "checkbox" || type == "reset" || type == "file" || type == "password" )
            continue;
         else
            fixed.push( [ a.name, value ] );
      }

      function fieldsWith( groupName, groupValue )
      {
         var pairs = fixed.slice( 0 );
         for ( var g = 0; g < groupOrder.length; ++g )
         {
            var name = groupOrder[g], v = ( name == groupName ) ? groupValue : groups["=" + name][0];
            if ( name == "\u0001submit" )
            {
               var parts = v.split( "\u0002" );
               pairs.push( [ parts[0], parts[1] ] );
            }
            else
               pairs.push( [ name, v ] );
         }
         return Shape.encodeForm( pairs );
      }

      var any = false, i, j;
      for ( i = 0; i < fixed.length; ++i )
      {
         var fixedName = Shape.fileNameIn( fixed[i][1] );
         if ( fixedName != null )
         {
            add( fixedName, method, action, fieldsWith( null, null ) );
            any = true;
         }
      }
      for ( i = 0; i < groupOrder.length; ++i )
      {
         var values = groups["=" + groupOrder[i]];
         for ( j = 0; j < values.length; ++j )
         {
            var choiceName = Shape.fileNameIn( values[j] );
            if ( choiceName != null )
            {
               add( choiceName, method, action, fieldsWith( groupOrder[i], values[j] ) );
               any = true;
            }
         }
      }
      if ( !any )
      {
         var actionName = Shape.fileNameIn( action );
         if ( actionName != null )
            add( actionName, method, action, fieldsWith( null, null ) );
      }
   }
   return found;
};

// One value from the part of an address after the question mark.
Shape.paramOf = function( url, key )
{
   var query = url.split( "#" )[0].split( "?" )[1] || "", pairs = query.split( "&" );
   for ( var i = 0; i < pairs.length; ++i )
   {
      var eq = pairs[i].indexOf( "=" );
      if ( eq > 0 && pairs[i].substring( 0, eq ) == key )
         return Shape.safeDecode( pairs[i].substring( eq + 1 ) );
   }
   return "";
};

// The SHA-1 checksum that the page shows in the same table row as the link
// whose text is `name`: forty hexadecimal digits. Empty if there is none.
// The search starts after the link, so the file number in the link's own
// address, which is also forty digits long, is not mistaken for it.
Shape.checksumFor = function( html, name )
{
   var at = html.indexOf( ">" + name + "</a>" );
   if ( at < 0 )
      return "";
   var rest = html.substring( at, at + 4000 );
   var end = rest.toLowerCase().indexOf( "</tr>" );
   if ( end >= 0 )
      rest = rest.substring( 0, end );
   var m = /(^|[^0-9A-Fa-f])([0-9A-Fa-f]{40})(?![0-9A-Fa-f])/.exec( rest.replace( /<[^>]+>/g, " " ) );
   return m == null ? "" : m[2].toLowerCase();
};

// PI-macosx-x64-1.9.3-20250402-c.pkg -> platform, chip type, version, date.
Shape.parseInstallerName = function( name )
{
   var lower = name.toLowerCase(), r = { name: name, platform: "", arch: "", version: [ 0, 0, 0, 0 ], versionText: "", date: "" };
   if ( /mac|osx/.test( lower ) ) r.platform = "macos";
   else if ( /win/.test( lower ) || /\.(exe|msi)$/.test( lower ) ) r.platform = "windows";
   else if ( /linux/.test( lower ) ) r.platform = "linux";
   else if ( /freebsd/.test( lower ) ) r.platform = "freebsd";
   if ( /arm64|aarch64/.test( lower ) ) r.arch = "arm64";
   else if ( /x64|x86_64|amd64/.test( lower ) ) r.arch = "x64";
   var v = /(?:^|[-_])v?(\d{1,2})\.(\d{1,2})\.(\d{1,2})(?:[-.](\d{1,2})(?![0-9]))?/.exec( name );
   if ( v != null )
   {
      r.version = [ parseInt( v[1], 10 ), parseInt( v[2], 10 ), parseInt( v[3], 10 ), v[4] ? parseInt( v[4], 10 ) : 0 ];
      r.versionText = v[1] + "." + parseInt( v[2], 10 ) + "." + parseInt( v[3], 10 ) + ( v[4] ? "-" + parseInt( v[4], 10 ) : "" );
   }
   var d = /(?:^|[-_.])(20\d{6})(?![0-9])/.exec( name );
   if ( d != null )
      r.date = d[1];
   return r;
};

Shape.compareInstallers = function( a, b )
{
   for ( var i = 0; i < 4; ++i )
      if ( a.version[i] != b.version[i] )
         return a.version[i] - b.version[i];
   return a.date < b.date ? -1 : ( a.date > b.date ? 1 : 0 );
};

// The newest macOS installer among `downloads`, preferring the given chip type.
Shape.pickForMac = function( downloads, preferArch )
{
   var best = null, bestInfo = null;
   for ( var pass = 0; pass < 2 && best == null; ++pass )
      for ( var i = 0; i < downloads.length; ++i )
      {
         var info = Shape.parseInstallerName( downloads[i].name );
         if ( info.platform != "macos" || !/\.(pkg|dmg)$/i.test( downloads[i].name ) )
            continue;
         if ( pass == 0 && info.arch != preferArch )
            continue;
         if ( best == null || Shape.compareInstallers( info, bestInfo ) > 0 )
         {
            best = downloads[i];
            bestInfo = info;
         }
      }
   return best;
};
