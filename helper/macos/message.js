// PixInsight Update Assistant: the message shown when PixInsight reopens.
//
// The helper starts PixInsight with this file. It reads the file "outcome"
// next to it, looks at which version of PixInsight is really running, and
// says so. Then it removes both files.
//
// No engine is named, so PixInsight runs this on its old script engine, which
// 1.9.6 still ships. The icon and the button are given as numbers, because
// their names differ between the two engines.

function UA_messageMain()
{
   var dir = File.extractDrive( #__FILE__ ) + File.extractDirectory( #__FILE__ );
   var o = {};
   try
   {
      var lines = File.readTextFile( dir + "/outcome" ).split( "\n" );
      for ( var i = 0; i < lines.length; ++i )
      {
         var eq = lines[i].indexOf( "=" );
         if ( eq > 0 )
            o[lines[i].substring( 0, eq )] = lines[i].substring( eq + 1 );
      }
   }
   catch ( x )
   {
      return;
   }

   var running = CoreApplication.versionMajor + "." + CoreApplication.versionMinor + "." + CoreApplication.versionRelease;
   if ( CoreApplication.versionRevision > 0 )
      running += "-" + CoreApplication.versionRevision;

   var text = ( running != o.old ? o.done : o.notUpdated ).split( "%1" ).join( running );
   // Why the previous PixInsight was put back, if that is what happened.
   if ( o.why == "nostart" && o.wontStart )
      text += "\n\n" + o.wontStart;
   // Where the previous PixInsight folder is, after an update that worked.
   if ( o.folder && o.folder.indexOf( "trash:" ) == 0 )
      text += "\n\n" + o.oldFolderTrash.split( "%1" ).join( o.folder.substring( 6 ) );
   else if ( o.folder && o.folder.indexOf( "kept:" ) == 0 )
      text += "\n\n" + o.oldFolderLeft.split( "%1" ).join( o.folder.substring( 5 ) );
   else if ( o.folder && o.folder.indexOf( "check:" ) == 0 )
      text += "\n\n" + o.oldFolderCheck.split( "%1" ).join( o.folder.substring( 6 ) );
   // Where to find what a failed install left behind.
   if ( o.left && o.left.length > 0 && o.failedFolder )
      text += "\n\n" + o.failedFolder.split( "%1" ).join( o.left );

   try { File.remove( dir + "/outcome" ); } catch ( x ) {}

   if ( o.quiet && o.quiet.length > 0 )
      File.writeTextFile( dir + "/message-shown.txt", "running=" + running + "\n" + text + "\n" );
   else
      ( new MessageBox( text, o.title, 2, 1 ) ).execute();

   try { File.remove( #__FILE__ ); } catch ( x ) {}
}

UA_messageMain();
