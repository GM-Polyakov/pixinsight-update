# PixInsight Update Assistant

**Update PixInsight without leaving PixInsight.**

A free, open-source updater for **macOS and Windows**. Start it from inside PixInsight, sign in with your existing PixInsight account, and keep working while the new version downloads. When you're ready, the updater installs it and reopens PixInsight.

No separate app, subscription, or always-running background service. You choose when to check for an update.

**Unofficial project:** not made, endorsed, or supported by Pleiades Astrophoto.

> **Early release (v0.1.0).** Tested on one Mac and one Windows 11 PC, upgrading from PixInsight 1.9.3 and 1.9.5 to 1.9.6. Please read the platform warnings below before installing.

## Install

1. In PixInsight, open **Resources → Updates → Manage Repositories**.
2. Add this repository URL, **including the final slash**:
   `https://gm-polyakov.github.io/pixinsight-update/`
3. Go to **Resources → Updates → Check for Updates**, then select **Apply**. PixInsight will warn that this repository is unsigned; accept that warning if you wish to install the add-on.
4. Quit PixInsight and approve installation of the script update when prompted. PixInsight will reopen.

Then run **Script → Utilities → Update PixInsight** whenever you want to check for a new version.

## How it works

1. **Sign in** using the credentials for your PixInsight download account.
2. **Download** the latest version in the background while you continue working. Open the script again to see progress or cancel.
3. **Install now or later.** Choose **Restart Now** or **Later**; selecting Later installs the update the next time you quit PixInsight.
4. **Return to work.** PixInsight asks about unsaved images before quitting, the official installer runs with your system's permission, and PixInsight reopens.

The updater checks the downloaded installer against PixInsight's published checksum and verifies the publisher's signature before installation. It does not store your PixInsight credentials or collect usage data. Your configured repositories remain in place; PixInsight retrieves add-ons again at its next update check.

## Requirements and important warnings

- **Supported:** PixInsight **1.9.3 or later**, on macOS or Windows. **Linux is not supported yet.**
- **Account and permissions:** a PixInsight download account and permission to install software as an administrator. On macOS, PixInsight must be installed in `/Applications`.
- **Disk space:** the add-on itself is a 45 KB download, about 200 KB installed. The update needs the same free space as updating PixInsight by hand.
- **Apple Silicon Macs:** updating an Intel installation replaces it with the Apple Silicon version. **Intel-only add-ons will no longer work.** The updater does not warn about this during the update.
- **Windows:** PixInsight's installer clears its installation folder. The updater checks for your files **only at the top level**; personal files inside PixInsight subfolders **may be deleted**. Back them up first. There is **no automatic rollback** on Windows.
- **Mac recovery:** the previous installation is moved to the Trash and can be restored until you empty it. See the [detailed recovery procedure](DETAILS.md#going-back-to-the-previous-version-mac-only).

This project is new and has been tested on limited configurations. Back up important custom files before updating.

## Documentation and feedback

- [Detailed installation behavior, platform limitations, recovery steps, and developer instructions](DETAILS.md)
- [Report a problem or suggest an improvement](https://github.com/GM-Polyakov/pixinsight-update/issues)
- [MIT license](LICENSE)

The updater was built with AI assistance. The source is public, and contributions are welcome.

*Software should update itself. This should not be a philosophical controversy.*
