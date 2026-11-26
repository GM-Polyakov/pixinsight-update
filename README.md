# PixInsight Update Assistant

Update PixInsight to the newest version from inside PixInsight. You pick one menu item, sign in with your PixInsight user name and password, and keep working while it downloads. When it's ready, you choose when to restart. PixInsight then closes, installs the new version and reopens.

PixInsight Update Assistant is free, independent and open source. It is not made or endorsed by Pleiades Astrophoto.

Version 0.1.0, released 26 November 2026. This is a first version. It has been tested on one Mac and one Windows 11 PC, updating from PixInsight 1.9.3 and 1.9.5 to 1.9.6.

## Before you start

You need:

- **PixInsight 1.9.3 or later**, on macOS or Windows. Linux is not supported yet.
- **A PixInsight account**, the same user name and password you use to download PixInsight.
- **Your computer's administrator password.** macOS asks for it once, and Windows asks whether the installer may make changes.
- **Free disk space:** about 3 GB on a Mac and about 4 GB on Windows.
- **On a Mac, PixInsight in the Applications folder**, where PixInsight's installer puts it.

Please read the warning for your system:

- **Mac with an Apple chip:** if you now run the Intel version of PixInsight, the update replaces it with the Apple chip version. Every PixInsight up to 1.9.3 is Intel only, so this applies to all of those. Add-ons that only exist for Intel Macs will stop working afterwards. Update Assistant doesn't warn you about this while it runs.
- **Windows:** PixInsight's installer empties the PixInsight folder before it installs. Update Assistant checks the top of that folder for files of your own and stops if it finds any, but it doesn't look inside PixInsight's own subfolders. Anything of yours stored there will be deleted. On Windows the update can't be undone.

## Install

1. In PixInsight, open **Resources > Updates > Manage Repositories** and add this address, including the slash at the end:
   `https://gm-polyakov.github.io/pixinsight-update/`
2. Run **Resources > Updates > Check for Updates** and press **Apply**. PixInsight warns that the repository is not signed. This is expected, so answer **Yes**.
3. Quit PixInsight. When it asks whether to install the updates now, answer **Yes**. PixInsight reopens by itself.

The new menu item is **Script > Utilities > Update PixInsight**.

## How an update works

1. **Start.** Pick **Script > Utilities > Update PixInsight**. A window shows the version you have.
2. **Sign in.** Enter your PixInsight user name and password in the same window.
3. **Download.** If there is a newer version, it downloads in the background and you can keep working. Pick **Update PixInsight** again to see the progress or to cancel.
4. **Restart now or later.** When the download is ready, choose **Restart Now** or **Later**. Later means the update installs the next time you quit PixInsight.
5. **Install.** PixInsight closes the normal way, so it asks about unsaved images first. If you answer No, PixInsight stays open, and the update waits until you quit. Your Mac then asks for your password, or Windows asks whether the installer may make changes.
6. **Reopen.** PixInsight opens by itself and tells you which version is running.

Your add-ons aren't copied to the new version. PixInsight downloads them again at its next update check, just as it would after an update by hand. Your list of repositories is kept.

## Your sign-in details

- Your user name and password go only to PixInsight's download service at `pixinsight.com`, in the one request that signs you in.
- Update Assistant doesn't save them anywhere, and the program that downloads and installs the update never sees them.
- Update Assistant collects no information about you or how you use PixInsight.

## What it changes on a Mac

PixInsight's installer won't run while the folder `/Applications/PixInsight` exists, so Update Assistant moves the old version out of the way first. In this order, it:

1. **Checks the download** against the checksum on PixInsight's download page, and checks that Pleiades Astrophoto signed it. If either check fails, it throws the download away and installs nothing.
2. **Renames the old folder** to `PixInsight (before update)` and runs PixInsight's installer.
3. **Checks that the new PixInsight starts** before it changes anything else.
4. **Moves your own folders over.** Anything at the top of the old folder that isn't part of PixInsight, such as star catalogues, goes into the new folder.
5. **Moves the old folder to the Trash.** It takes about 3 GB until you empty the Trash. Your Mac may ask for your password when you do, because the folder belongs to the system.

If something goes wrong:

- **If the installer fails or the new PixInsight won't start,** the old folder gets its name back and PixInsight reopens as it was. Whatever the installer left behind stays in Applications as `PixInsight (failed update)`, and you can delete it.
- **If one of your own folders can't be moved,** the old folder stays in Applications and you're told not to delete it.

Update Assistant never deletes your files or your old PixInsight. It only removes its own temporary files, including the download once the update is done.

## What it changes on Windows

PixInsight's Windows installer removes the old version by itself, so nothing is renamed or kept. In this order, Update Assistant:

1. **Checks for your own files** at the top of the PixInsight folder, before it downloads anything. If it finds any, it tells you what they are, changes nothing, and asks you to move them out.
2. **Checks the download** against the checksum on PixInsight's download page, and checks that Pleiades Astrophoto signed it. If either check fails, it throws the download away and installs nothing.
3. **Runs PixInsight's installer** in the background, into the folder PixInsight is in now. Windows asks whether the installer may make changes.
4. **Reopens PixInsight.**

If something goes wrong:

- **If you answer No when Windows asks,** nothing changes and PixInsight reopens as it was.
- **If the installer fails after it has removed the old version,** no PixInsight is left. Update Assistant keeps the downloaded installer in your Downloads folder and tells you, so you can run it by hand.

## Going back to the previous version (Mac only)

You can undo an update until you empty the Trash.

1. Quit PixInsight.
2. Open the Trash in the Finder and drag `PixInsight (before update)` into Applications.
3. Download this project: at the top of this page, click **Code > Download ZIP**. If your browser didn't unpack it, double-click the ZIP in your Downloads folder.
4. Open Terminal and run these two lines. Enter your Mac password when it asks.

```bash
cd ~/Downloads/pixinsight-update-main
sudo sh tools/undo-update.sh
```

This puts the new version aside as `PixInsight (undone update)`, puts the previous version back, and moves your own folders back into it. To see what it would do without changing anything, run `sh tools/undo-update.sh --check` instead.

## Known limits

- **Tested on one Mac and one PC.** On the Mac, a real update from 1.9.3 to 1.9.6. On Windows 11 with an administrator account, real updates from 1.9.3 and from 1.9.5 to 1.9.6. Not tried yet: updating from 1.9.4 or 1.9.5 on a Mac, from 1.9.4 on Windows, a Windows account without administrator rights, or a PixInsight installed outside `C:\Program Files`.
- **Close other scripts first.** PixInsight won't quit while another script's window is open. If PixInsight doesn't close after **Restart Now**, quit it yourself, and the update carries on.
- **On Windows, the update needs PowerShell scripts to be allowed.** If your organisation blocks them, Update Assistant tells you that the update could not start.
- **It never runs by itself.** Nothing happens unless you pick the menu item.

## Report a problem

Open an issue at <https://github.com/GM-Polyakov/pixinsight-update/issues>.

## For developers

| Path | What it is |
| --- | --- |
| `src/` | The script that runs inside PixInsight. All the wording the user sees is in `UpdateAssistant-wording.jsh`. |
| `helper/macos/` | The Mac helper program, which downloads, installs and reopens PixInsight, and is the only part that runs as administrator. Its closing message, `message.js`, is used on Windows too. |
| `helper/windows/` | The Windows helper program, a PowerShell script. |
| `build/build.sh` | Builds the repository files into `dist/repository/`. One package holds both helpers. |
| `tools/undo-update.sh` | Puts the previous PixInsight back after an update on a Mac. |
| `tests/` | Tests for the Mac. `tests/windows/` holds the Windows tests. |
| `docs/` | The published repository that PixInsight reads. |

To build, on a Mac:

```bash
sh build/build.sh
```

Publish only a package built on a Mac. A package built on Windows marks every file as writable by everyone, and the build warns you if that happens.

The test suite runs the real script in the real PixInsight, but against a fake download service and a fake installer. It never contacts pixinsight.com and never touches your installed PixInsight. It opens and closes PixInsight about twenty times in the background, so run it only when you aren't using PixInsight.

On a Mac:

```bash
sh tests/run-rehearsal.sh
```

On Windows, in PowerShell. This needs Git for Windows, whose shell the tests use to build the package, and Python, which runs the fake download service:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-rehearsal.ps1
```

Comments in the code refer to `TESTING.md`, the project's private test notes. You don't need them to build or change the code.

## License

MIT. See [LICENSE](LICENSE).
