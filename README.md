# PixInsight Update Assistant

Updates PixInsight to the newest version from inside PixInsight. You pick one menu item, sign in with your PixInsight user name and password, and keep working. When the download is ready you choose when to restart, and PixInsight closes, installs the new version and reopens.

PixInsight Update Assistant is a free, independent add-on. It is not made or endorsed by Pleiades Astrophoto.

**Status:** first version, for macOS and Windows. It has updated one real PixInsight on one Mac, and made two real updates on one Windows PC.

- **It works from end to end.** On 2026-11-24 it took the test Mac from PixInsight 1.9.3 to 1.9.6, from sign-in to the closing message.
- **The add-ons came back.** At its next update check the new PixInsight fetched them again by itself, 14 packages in all.
- **That was the second attempt.** The first, the same day, installed the Intel build, which cannot start on a Mac with an Apple chip. It was undone, and the faults it showed were fixed.
- **It passes a rehearsal** with stand-ins for the download service and the installer: 18 cases on PixInsight 1.9.6, and the 16 cases it then had on 1.9.3.
- **It installs through a repository link.** Tried privately on PixInsight 1.9.6: PixInsight fetched the add-on from an address on the test Mac, installed it and put it in the Script menu.
- **On Windows it passes a rehearsal** of 17 cases on PixInsight 1.9.3, 1.9.4 and 1.9.6, and has made two real updates on one PC on 2026-11-25: from 1.9.5 to 1.9.6, and from 1.9.3 to 1.9.6.
- **Not shown yet:** installing from a public address.

## Install

1. In PixInsight, open **Resources > Updates > Manage Repositories** and add `https://gm-polyakov.github.io/pixinsight-update/`. Type it with the slash at the end.
2. Run **Resources > Updates > Check for Updates** and press Apply. PixInsight warns that the repository is not signed, and asks before it downloads. Answer Yes.
3. Quit PixInsight. Its updater asks whether to install now. Answer Yes, and PixInsight reopens by itself.
4. Pick **Script > Utilities > Update PixInsight**.

## What happens when you update

1. **Start.** A window shows the version you have.
2. **Sign in.** You enter your PixInsight user name and password in the same window.
3. **Download.** If a newer version exists, it downloads in the background and you can keep working. Pick **Update PixInsight** again to see the progress or to cancel.
4. **Restart now, or later.** When the download is ready, a small window asks. "Later" means the update installs when you next quit PixInsight.
5. **Install.** PixInsight closes the normal way, so it warns you first if images are unsaved. If you answer No, PixInsight stays open and the update waits until you quit. macOS then asks once for your Mac password. Windows asks whether PixInsight's installer may change the PC.
6. **Reopen.** PixInsight opens by itself and says which version is running. If the new PixInsight first shows a notice of its own, the message comes once you have answered it.

## What it does with your sign-in details

- Your user name and password are sent only to PixInsight's download service, `pixinsight.com`, in the one request that signs you in.
- Update Assistant does not save them. The helper program that downloads and installs never receives them.
- Update Assistant collects no information about you or your use of PixInsight.

## What it changes on your Mac

PixInsight's installer refuses to run while the folder `/Applications/PixInsight` exists. So Update Assistant does what PixInsight's own instructions ask you to do by hand, and a little more. In this order:

1. **It checks the download twice:** against the checksum shown on PixInsight's download page, and against macOS's record of who signed the package. An installer that is not signed by PixInsight's maker is deleted and not installed.
2. **It gives the old folder another name,** `PixInsight (before update)`, in Applications, and runs PixInsight's installer. The installer leaves no other choice, and a rename is undone in a moment.
3. **It checks that the new PixInsight starts** on your Mac, before anything else is touched.
4. **It carries your own folders over.** Anything at the top of the old folder that is not part of PixInsight, such as folders of star catalogues, is moved into the new folder.
5. **Only then does it put the old folder in the Trash,** as `PixInsight (before update)`. It takes a few GB (2.7 GB on the test Mac) until you empty the Trash. macOS may ask for your Mac password when you do, because the folder belongs to the system.

What else to know:

- **Add-ons are not carried over.** PixInsight fetches them again for the new version at its next update check, as after an update by hand. Your repository links are kept. Update Assistant does not touch them: if a maker has changed its link for the new version, you enter the new one yourself.
- **If the installer fails, or the new PixInsight does not start,** the old folder gets its name back and PixInsight reopens as it was. Nothing goes to the Trash. What the installer left stays in Applications as `PixInsight (failed update)`, and you are told that you can delete it.
- **If one of your own folders cannot be carried over,** the old folder stays in Applications, and you are told not to delete it.
- **It deletes nothing.**

## What it changes on your Windows PC

PixInsight's Windows installer removes the old version itself, and it empties the PixInsight folder before it installs. So on Windows nothing is renamed, carried over or put in the Recycle Bin. In this order:

1. **It looks for your own things first.** Before anything is downloaded, it looks at the top of the PixInsight folder for anything that is not part of PixInsight. If it finds something, it names it, changes nothing, and asks you to move it out. The installer would delete it.
2. **It checks the download twice:** against the checksum shown on PixInsight's download page, and against Windows' record of who signed the installer. An installer that is not signed by PixInsight's maker is deleted and not installed.
3. **It runs PixInsight's installer without windows,** into the folder PixInsight is in now. Windows asks whether the installer may change the PC.
4. **It reopens PixInsight,** which says which version is running.

What else to know:

- **It looks at the top of the folder only.** A file of your own that lies deeper inside one of PixInsight's folders is not found, and the installer deletes it.
- **Add-ons are not carried over.** After an update by hand on the test PC, PixInsight fetched them again by itself. That has not been watched after an update by the add-on.
- **If you answer No to Windows' question,** nothing is changed, and PixInsight reopens as it was.
- **The update cannot be undone.** Nothing of the old version is kept.
- **If the installer fails after it has removed the old version,** no PixInsight is left. Update Assistant then keeps the downloaded installer in your Downloads folder and tells you, so that you can run it by hand.

## Going back to the previous version

This is for macOS. Until you empty the Trash, the update can be undone. Open the Trash and drag `PixInsight (before update)` into Applications; macOS lets only the Finder take things out of the Trash. Then quit PixInsight and run this from a copy of this project:

```bash
sudo sh tools/undo-update.sh
```

It moves the new folder aside, moves the previous one back, and returns your own folders to it. To see what it would do without changing anything:

```bash
sh tools/undo-update.sh --check
```

## Limits of this version

- **macOS and Windows.** Linux is not covered.
- **PixInsight 1.9.3 and later.** On a Mac: a real update from 1.9.3, and the rehearsal on 1.9.3 and 1.9.6. On a Windows PC: real updates from 1.9.3 and from 1.9.5, and the rehearsal on 1.9.3, 1.9.4 and 1.9.6. Not tried yet: a real update from 1.9.4 on Windows, 1.9.4 and 1.9.5 on a Mac, and versions before 1.9.3 on either system.
- **On Windows, two real updates, from PixInsight 1.9.5 and from 1.9.3, both to 1.9.6.** One PC, with Windows 11 and an administrator account. Not tried: an account without administrator rights, and a PixInsight outside `C:\Program Files`.
- **On Windows the helper is a PowerShell script.** Where an organisation forbids such scripts, the helper cannot start, and Update Assistant says that the update could not be started.
- **On Windows it needs room for the download, about 2 GB, and about as much again while the installer runs.** The second figure is inferred, not measured.
- **It installs the build for your Mac's chip.** On a Mac with an Apple chip that is the build for Apple chips, also when the PixInsight you have now is the Intel build. PixInsight 1.9.3 and earlier exist for Intel only, so every such Mac changes build with this update. Add-ons that exist only for Intel will not work afterwards. The add-on does not mention this when it runs.
- **On a Mac it needs about 3 GB free** for the download and the new folder, while the old folder is still on the disk.
- **If PixInsight does not close after "Restart Now",** quit it yourself. The update then continues. PixInsight ignores a request to quit while a script's window is open in it. Update Assistant closes its own window first; a window of another script would still hold PixInsight.
- **One real update, from PixInsight 1.9.3, on one Mac.** On PixInsight 1.9.6 the add-on has been rehearsed, and not yet used for a real update. The script is written for the old script engine, which every version up to 1.9.6 still contains.
- **No scheduling and no updates without asking.**

## Report a problem

Open an issue at `https://github.com/GM-Polyakov/pixinsight-update/issues`.

## For developers

| Path | What it is |
| --- | --- |
| `src/` | The script that runs inside PixInsight, with all wording in `UpdateAssistant-wording.jsh` |
| `helper/macos/` | The Mac helper that downloads, installs and reopens, and the one part that runs as administrator. Its closing-message script, `message.js`, serves Windows too |
| `helper/windows/` | The Windows helper, a PowerShell script |
| `build/build.sh` | Builds the repository files into `dist/repository/`. One package holds both helpers |
| `tools/undo-update.sh` | Puts the previous PixInsight back after an update on a Mac |
| `tests/` | The feasibility tests and the rehearsal for the Mac; `tests/windows/` holds those for Windows |

On a Mac:

```bash
sh build/build.sh
```

```bash
sh tests/run-rehearsal.sh
```

On Windows, in PowerShell. The rehearsal builds the add-on itself, with the shell that comes with Git for Windows, and needs Python for the stand-in download service:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-rehearsal.ps1
```

The rehearsal runs the real add-on in the real PixInsight, against a stand-in download service and a stand-in installer. It does not contact pixinsight.com and does not touch the installed PixInsight folder. It opens and closes PixInsight about twenty times, in the background, so run it only when you are not using PixInsight.

Publish only a package that was built on a Mac. A package built on Windows records every file as writable by everyone, and the build says so.

Comments in the code point to `TESTING.md`, the project's test record. It is kept with the working notes and is not part of this repository.
