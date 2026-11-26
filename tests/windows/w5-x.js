// PixInsight Update Assistant, Windows test W5, last part.
//
// Question: does a PixInsight that is already open run a script that a second
// start of the program hands to it with -x=<this file>? The rehearsal needs
// that to pick the add-on's menu item a second time.
//
// It writes one file, w5-x-ran.txt, into the folder of this script.
//
// Old-engine JavaScript only.

try
{
   var dir = File.extractDrive( #__FILE__ ) + File.extractDirectory( #__FILE__ );
   File.writeTextFile( dir + "/w5-x-ran.txt", "pid=" + CoreApplication.pid + "\ninstance=" + CoreApplication.instance + "\n" );
}
catch ( x )
{
}
