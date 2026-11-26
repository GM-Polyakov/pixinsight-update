// PixInsight Update Assistant: every sentence the user can read.
//
// This is the only place where wording lives. The script uses it for its
// windows, and writes the helper's sentences from it into small text files,
// so that the script and the helper can never disagree, and so that macOS and
// Windows show the same words.
//
// %1, %2 ... are filled in when a sentence is shown.
//
// Old-engine JavaScript only (PixInsight 1.9.3 and earlier).

var UA_TEXT = {

   // Names
   product:       "PixInsight Update Assistant",
   windowTitle:   "Update PixInsight",

   // What the user is told before being asked to trust the add-on
   independent:   "PixInsight Update Assistant is a free, independent add-on. It is not made or endorsed by Pleiades Astrophoto.",
   trust:         "Your user name and password are sent only to PixInsight's download service. Update Assistant does not save them.",
   noCollection:  "Update Assistant collects no information about you or your use of PixInsight.",
   reportProblem: "To report a problem, open the issues page of the project on GitHub:",

   // Start and sign-in
   installed:     "You have PixInsight %1.",
   signInPrompt:  "Sign in to see the newest version. If there is one, the download starts right away.",
   userName:      "User name:",
   password:      "Password:",
   forgot:        "Forgot your user name or password?",
   signIn:        "Sign In",
   cancel:        "Cancel",
   about:         "About",
   close:         "Close",
   ok:            "OK",
   needBoth:      "Enter your PixInsight user name and password.",
   signingIn:     "Signing in. This takes a few seconds.",
   cantReach:     "Can't reach PixInsight right now. PixInsight is working normally.",
   refused:       "That user name or password wasn't accepted.",
   upToDate:      "You already have the newest version, PixInsight %1.",
   noInstaller:   "No installer for this computer was found on PixInsight's download page. Nothing was changed.",
   notThisSystem: "Update Assistant works on macOS and Windows. Nothing was changed.",
   notInApplications: "This PixInsight is not in the Applications folder, where PixInsight's installer puts the new version. Update Assistant can't update it. Nothing was changed.",
   otherInstance: "Another PixInsight window is running as a second instance. Close it, then pick Update PixInsight again. Nothing was changed.",
   ownFiles:      "The PixInsight folder holds things that are not part of PixInsight: %1. PixInsight's installer would delete them. Move them somewhere else, then pick Update PixInsight again. Nothing was changed.",
   cantStart:     "The update could not be started. Nothing was changed.",

   // Download, in the background
   started:       "PixInsight %1 is downloading in the background (%2). You'll be asked when it's ready to install. To see progress or to cancel, pick Update PixInsight again.",
   downloading:   "Downloading PixInsight %1: %2 of %3 (%4%).",
   timeLeft:      "About %1 left.",
   checking:      "Checking the download of PixInsight %1.",
   waiting:       "PixInsight %1 is ready. It will be installed when you quit PixInsight.",
   asking:        "PixInsight %1 is ready to install. Answer the question in the small window.",
   cancelUpdate:  "Cancel Update",
   stopped:       "The update was stopped. Nothing was changed.",
   downloadStopped: "The download stopped.",
   tryAgain:      "Try Again",
   startAgain:    "The download stopped. To start again, pick Update PixInsight in PixInsight.",
   notGenuine:    "The downloaded installer is not signed by PixInsight's maker, so it was not installed. Nothing was changed.",

   // Restart and install: shown by the helper, outside PixInsight
   ready:         "PixInsight %1 is ready to install. Restart now, or later?",
   restartNow:    "Restart Now",
   later:         "Later",
   laterNote:     "PixInsight %1 will be installed when you next quit PixInsight.",
   installing:    "Updating PixInsight to %1. This takes a few minutes. PixInsight will reopen when it's done. The update can no longer be cancelled.",
   hide:          "Hide",
   adminPrompt:   "PixInsight Update Assistant needs your password to install PixInsight %1.",

   // Reopen
   done:          "You're now on PixInsight %1.",
   notUpdated:    "PixInsight was not updated. You're still on PixInsight %1.",
   oldFolderTrash: "Your previous PixInsight is in the Trash, as %1. It is safe to delete once the new version works for you.",
   oldFolderLeft: "Your previous PixInsight is still in Applications, as %1. Delete that folder once the new version works for you.",
   oldFolderCheck: "Some of your own folders could not be moved into the new PixInsight folder. They are still in %1, in Applications. Do not delete that folder.",
   wontStart:     "The new version does not start on this Mac, so your previous PixInsight was put back.",
   failedFolder:  "What the installer left is in Applications as %1. You can delete that folder.",

   // Shown by the helper when PixInsight cannot show the result itself. Two of
   // these are for Windows only. There PixInsight is opened from another
   // place, and a failed install leaves no PixInsight, because PixInsight's
   // installer removes the old version before it installs the new one.
   notReopened:   "PixInsight could not be reopened. Open it from the Applications folder.",
   notReopenedWin: "PixInsight could not be reopened. Open it from the Start menu.",
   notInstalled:  "The update failed, and PixInsight is no longer installed. Its installer is in your Downloads folder as %1. Run it to install PixInsight.",
   folderLost:    "The update failed, and your previous PixInsight could not be put back. It is in Applications as %1. To use it, rename that folder to PixInsight, replacing any folder of that name."
};

// Fill %1, %2 ... in a sentence.
function UA_fill( text )
{
   var s = String( text );
   for ( var i = 1; i < arguments.length; ++i )
      s = s.split( "%" + i ).join( String( arguments[i] ) );
   return s;
}
