<div align="center">

<img src="assets/logo.svg" width="80" alt="Caelestia logo" />

# caelestia-kde

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793d1?logo=arch-linux&logoColor=white&style=for-the-badge&labelColor=101418)](https://archlinux.org)
[![Fedora](https://img.shields.io/badge/Fedora-51A2DA?logo=fedora&logoColor=white&style=for-the-badge&labelColor=101418)](https://fedoraproject.org)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white&style=for-the-badge&labelColor=101418)](https://ubuntu.com)
[![KDE Plasma](https://img.shields.io/badge/Plasma_6-1D99F3?logo=kde&logoColor=white&style=for-the-badge&labelColor=101418)](https://kde.org/plasma-desktop)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL--3.0--or--later-9bd0cc?style=for-the-badge&labelColor=101418)](LICENSE)

</div>

<!-- markdownlint-disable-next-line MD034 -- a bare URL is what GitHub turns into an inline video player -->
https://github.com/user-attachments/assets/38b24e7f-fdd9-43db-872b-8c0ac23a44fd

> [!NOTE]
> This repo is the KDE Plasma port of [`caelestia-dots/shell`](https://github.com/caelestia-dots/shell).
> Upstream runs on Hyprland; the port runs the same shell on KWin and Plasma. For the original
> Hyprland dotfiles, see [`caelestia-dots/caelestia`](https://github.com/caelestia-dots/caelestia).

## Installation

**Requirements:** Arch-based, Fedora, or Debian/Ubuntu - KDE Plasma 6 on Wayland, Qt 6.9+

```bash
curl -fsSL https://raw.githubusercontent.com/ladybug-me/caelestia-kde/main/install.sh | sh
```

> [!NOTE]
> The one-liner installs upstream's `main`. This branch, `independent-session`, adds an
> [independent session](#independent-session-arch-based-and-fedora); install it from a clone:
>
> ```bash
> git clone --recurse-submodules --branch independent-session https://github.com/albertsalendah/caelestia-kde.git
> cd caelestia-kde
> bash scripts/setup.sh
> ```
>
> The first run compiles the installer and the shell plugin on your machine, so it takes a while.
> The installer is a terminal UI: run it in a real terminal (over SSH, inside `tmux`, so a dropped
> connection does not stop it).

### Updating

- **Installer TUI:** run the installer and choose *Update*
- **GUI:** Nexus -> Updates -> select branch -> Install Updates
- **CLI:** `bash update.sh` and choose `main` (stable) or `dev` (bleeding edge)

Shell settings are preserved across updates.

Nexus -> Updates and `caelestia-update` update Caelestia only. The full system upgrade (pacman, dnf
or apt) is off by default: turn on *Update the System* under *Customize Installation*, or run
`CAELESTIA_UPDATE_SYSTEM=1 caelestia-update`, to include it. An upgrade of KWin or Qt can end the
running session partway through, so save your work first. If an upgrade replaced `kwin`,
`plasma-workspace`, `libplasma`, `qt6-base` or `qt6-declarative` and the session survived, the
update stops before it builds anything and asks you to log out and back in; run it again after
that. An install that came from a package updates through its package manager instead.

> [!NOTE]
> An install made from a fork follows that fork. Nexus -> Updates, the update notification and
> `caelestia-update` use the repository and branch recorded at install time (this fork's
> `independent-session`, not upstream's `main` and `dev`), and `update.sh` follows the branch its
> clone is on. They update the shell and its configuration. The session files in `/usr/local`, the
> SDDM theme and the `cliphist` unit are not among them: after pulling changes to those, run
> `bash scripts/setup.sh` again. An install made before the source was recorded (it has no
> `.update_source` in `~/.config/quickshell/caelestia`) keeps following upstream until `setup.sh`
> has been run once more.

### Uninstalling

Open *Settings*, go to the *About* page, and choose *Uninstall Caelestia*. That opens
the uninstaller in a terminal, where it asks for confirmation of its own.

You can also choose *Uninstall* from the installer TUI, or run the script from the
checkout directly:

```bash
bash ./uninstall.sh
```

A packaged install has no script to run: the row names the package manager's command
instead.

## Independent session (Arch-based and Fedora)

This branch installs one more login-screen entry, **Caelestia**, that starts KWin and the Caelestia
shell without `plasmashell`. Nothing is removed: the Plasma session and any other session stay as
they were, and you choose one at the login screen.

| Installed | Where |
| --- | --- |
| Session program | `/usr/local/bin/caelestia-wm-session` |
| KWin unit and session target | `/usr/local/lib/systemd/user/caelestia-kwin.service` and `caelestia-session.target` |
| Starts the shell in this session only (a drop-in for `caelestia-shell.service`, so a Plasma session does not get the Caelestia shell on top of `plasmashell`) | `/usr/local/lib/systemd/user/caelestia-shell.service.d/10-caelestia-session-only.conf`, refers to `caelestia-shell-session-only.conf` in the repository |
| Holds autostarted tray apps back until the shell provides the tray, and starts the proxy for old X11 tray icons (the apps would otherwise ask for a tray that is not there yet and give up; does nothing in a Plasma session) | `/usr/local/bin/caelestia-wait-for-tray`, with the drop-ins `app-.service.d/10-caelestia-wait-for-tray.conf` and `plasma-xembedsniproxy.service.d/10-caelestia-wait-for-tray.conf` under `/usr/local/lib/systemd/user/`, which refer to `app-wait-for-tray.conf` and `xembedsniproxy-wait-for-tray.conf` in the repository |
| The proxy for old X11 tray icons, built from `src/xembed-sni-proxy` on Fedora and on Arch, and installed only when `plasma-workspace` (which ships it) is not installed (on Arch that means the stand-in package below) | `/usr/local/bin/caelestia-xembedsniproxy` and `/usr/local/lib/systemd/user/plasma-xembedsniproxy.service`, which refers to `plasma-xembedsniproxy-standalone.service` in the repository |
| A stand-in for KDE's `org.kde.taskmanager` QML module, which the screen-sharing picker of `xdg-desktop-portal-kde` needs; installed only when that module is missing (no `plasma-workspace`) and removed again when it is back | `/usr/local/share/caelestia/qml/org/kde/taskmanager/` and the drop-in `/usr/local/lib/systemd/user/plasma-xdg-desktop-portal-kde.service.d/10-caelestia-taskmanager-stub.conf`, which refers to `src/session/taskmanager-stub` and `xdg-portal-taskmanager-stub.conf` in the repository |
| Login-screen entry | `/usr/local/share/wayland-sessions/caelestia.desktop` |
| Wayland greeter (SDDM only) | `/etc/sddm.conf.d/zz-wayland-greeter.conf` |
| Hides the Plasma login entry (SDDM only, and only with no Plasma desktop installed) | `/usr/local/share/wayland-sessions/plasma.desktop` |

The step looks at the login manager the machine uses:

| Login manager | What the step does |
| --- | --- |
| Plasma Login | installs the entry only |
| SDDM | installs the entry and a drop-in that switches SDDM to a Wayland greeter, and hides the Plasma entry if no Plasma desktop is installed |
| none enabled | installs SDDM, adds the drop-in and enables it, and hides the Plasma entry if no Plasma desktop is installed |
| anything else | installs the entry and warns that the login manager may not list it |

The Wayland greeter matters. With SDDM's default Xorg greeter, about 4 in 9 logins on the test
machine ended on a black screen. The Caelestia SDDM theme shows a session picker below the password
field (full variant), so you can pick Caelestia or Plasma.

**Packages.** (Arch; Fedora's list is under "Fedora" below.) The session installs `plasma-workspace`, `kscreenlocker`, `plasma5support`,
`layer-shell-qt`, `xdg-desktop-portal-kde`, `xorg-xwayland`, `polkit-kde-agent`, `powerdevil`,
`kscreen`, `plasma-integration`, `kde-cli-tools`, `kwin`, `konsole`, `dolphin`, `ark` and `systemsettings`,
because the shell calls their tools. `plasma-integration`, `kde-cli-tools` and `kwin` are named because the
`plasma-workspace` stand-in below brings none of the real package's dependencies; without
`plasma-integration`, `kwin_wayland` crashes at start and every login bounces back to the login screen.
`plasma-workspace` brings the `plasmashell` binary and a Plasma login entry with it, but nothing in
the Caelestia session starts `plasmashell`. With SDDM and no Plasma desktop (`plasma-desktop` not
installed) the installer hides that Plasma entry, so the login screen offers only Caelestia; it does
this with a file in `/usr/local/share/wayland-sessions`, and touches nothing the package owns. Install
`plasma-desktop` and run the installer again to show the entry. Chrome, Firefox and other apps that
draw their own title bar take the button layout from the GNOME setting `button-layout`, whose default is
a close button only; a Plasma session fills it from KWin's settings, so the Caelestia session does the same at
login (KWin's order, minimize, maximize and close). When foot is not installed and you have not chosen a
terminal, the installer records Konsole as the shell's terminal.

**Fedora.** The same step runs on Fedora, with the same files. A minimal install (Fedora Everything) boots to a text console, so with any of the three login managers above the step also sets the boot target to `graphical.target`; `uninstall.sh` sets it back. The packages are `plasma-integration` (the Qt platform theme that gives Qt apps the KDE colours and file dialogs),
`kwin` (it ships the `kwin_wayland_wrapper` the session starts), `kscreenlocker`, `plasma5support`,
`layer-shell-qt`, `xdg-desktop-portal-kde`, `xorg-x11-server-Xwayland`, `polkit-kde`, `powerdevil`,
`kscreen`, `konsole`, `dolphin`, `ark` and `plasma-systemsettings`, plus `pipewire-pulseaudio`,
`pipewire-alsa`, `bluedevil` and `bluez`; the same menu switches turn System Settings, PipeWire and
Bluetooth off. `plasma-workspace` and `plasma-desktop` are not installed on Fedora, and nothing in the list requires or
recommends them; the shell has fallbacks for the two things only `plasma-workspace` provided (the KDE colour-scheme command and the logout service). The icons of old X11 apps (Java and Compose apps such as AB Download Manager) need KDE's `xembedsniproxy`, which ships only inside `plasma-workspace`; when `plasma-workspace` is not installed the step builds a copy of it (`src/xembed-sni-proxy`, taken from `plasma-workspace` v6.8.2) with CMake and installs it under `/usr/local`, and a failed build only costs those icons. Debian is still skipped. The Fedora installer does not
guard a system upgrade the way the Arch one does (an upgrade of KWin or Qt inside a running session),
so run `sudo dnf upgrade` from a text console, not from inside the session. Running it over SSH is not
enough: on one machine an upgrade over SSH ended the login session (the login screen came back and the
screen froze), because the package scriptlets reload the user manager and the session program took its
moment of silence for KWin having exited (see the last row of the problem table).

**Removing the Plasma desktop on Fedora.** The installer does not do it. If a Plasma desktop is already
installed, remove it from the Caelestia session (not from a Plasma session), after
`sudo dnf history list` so you know where you started. `plasma-integration` must be marked as installed by
you first, or `dnf` removes it with the rest as an unused dependency and Qt apps lose the KDE colours.
`--assumeno` shows the list and removes nothing; `powerdevil`, `xdg-desktop-portal-kde`, `kscreenlocker`,
`kwin`, `sddm` and `konsole` stay. KDE Wallet (`kf6-kwallet`) cannot be removed with it (too many packages
depend on it); `kwriteconfig6 --file kwalletrc --group Wallet --key Enabled false` switches it off.

```bash
sudo dnf mark user plasma-integration
sudo dnf remove --assumeno plasma-workspace
sudo dnf remove plasma-workspace
bash scripts/setup.sh
```

Run `setup.sh` right after the removal, and do not lock the screen before it has run: on Fedora
`plasma-workspace` ships the lock screen's PAM services (`/etc/pam.d/kde`, `kde-fingerprint`,
`kde-smartcard`), and without them a locked screen cannot check any password and stays locked
(Ctrl+Alt+F3, log in, `loginctl unlock-session`). `setup.sh` writes those files when they are missing
(`uninstall.sh` leaves them: they are harmless), builds the old-tray proxy (a failed build only costs the
icons of old X11 apps) and removes the file that hid the Plasma login entry, which no longer exists once
`plasma-workspace` is gone. The lock screen draws the shell's current wallpaper itself, because KDE's
wallpaper plugin went with the package. System Settings loses its Users page with `plasma-desktop`; add an
account from a terminal (`sudo useradd -m -G wheel NAME && sudo passwd NAME`).

Screen sharing needs one more thing the package took with it. The picker of `xdg-desktop-portal-kde` (the
window that asks which screen or window to share) imports KDE's QML module `org.kde.taskmanager`, which only
`plasma-workspace` ships; without it the picker cannot open and a share from a browser fails without any
KDE dialog. `setup.sh` installs a small stand-in under `/usr/local/share/caelestia/qml` and a drop-in
(`plasma-xdg-desktop-portal-kde.service.d/10-caelestia-taskmanager-stub.conf`) that points the portal at it,
and removes both again as soon as the real module is installed. The picker lists your screens and windows
and returns the one you choose, but it shows the application's icon instead of a live thumbnail and writes
"No windows open" next to each screen. After `setup.sh` the change applies at the next login; to apply it in
the running session run `systemctl --user daemon-reload && systemctl --user restart plasma-xdg-desktop-portal-kde.service`.
Chrome shows its own "Choose what to share" window first and opens KDE's picker when you pick Window or Entire
Screen in it; that order is Chrome's, and Firefox shows only KDE's picker. To go back:
`sudo dnf history undo last`.

**Removing the Plasma desktop on Arch.** (Arch commands.) The installer does not do it. To do it yourself, from the Caelestia
session (not from a Plasma session): first mark the session's packages as explicitly installed, so that
removing `plasma-desktop` does not leave them as orphans for a later clean-up, then remove the desktop
without `-s`, which leaves its dependencies in place, and run the installer once more so the Plasma
entry is hidden. `pacman -Qq` keeps the commands to what is installed:

```bash
sudo pacman -D --asexplicit $(pacman -Qq kwin plasma-workspace libplasma powerdevil kscreen kscreenlocker plasma5support layer-shell-qt xdg-desktop-portal-kde polkit-kde-agent systemsettings plasma-integration breeze bluedevil konsole dolphin ark plasma-nm drkonqi kde-cli-tools 2>/dev/null)
sudo pacman -Rn $(pacman -Qq plasma-desktop plasma-meta kdeplasma-addons kmenuedit plasma-pa plasma-systemmonitor plasma-firewall plasma-thunderbolt plasma-vault kinfocenter print-manager discover 2>/dev/null)
env BUNDLE_DIR=$PWD BASE_DISTRO=arch bash scripts/12-independent-session.sh
```

`pacman` shows the list and asks before it removes anything. Take a Snapper snapshot first.

**`plasma-workspace` on Arch: a stand-in package instead of the Plasma desktop libraries.** `powerdevil` and
`xdg-desktop-portal-kde` depend on `plasma-workspace`, and `powerdevil` loads `libkworkspace6.so.6` from it.
On an Arch machine that has no `plasma-workspace` (a fresh install), `setup.sh` therefore installs a small
local package first, `caelestia-plasma-workspace-stub` (`scripts/arch-plasma-stub.sh`). It provides the name
and carries only that library, taken from the real package in pacman's cache, so the real package is never
installed and nothing is removed. A machine that already has the real package or the stand-in is left alone.
The installer then treats the stand-in as `plasma-workspace` (`pacman -Qq` answers through `Provides`). To get
the real package instead, set `CAELESTIA_ARCH_PLASMA_STUB=false` before `setup.sh`; to install a Plasma
desktop later, run `sudo caelestia-plasma-stub remove` first.

To replace a real `plasma-workspace` that is already installed (the installer never does that on its own):
take a Snapper snapshot, run the first command from the Caelestia session, then `setup.sh` (it installs the
screen-sharing stand-in described above, since the real module goes with the package) and log in again:

```bash
sudo bash scripts/arch-plasma-stub.sh install
env SKIP_SYSTEM_UPDATE=true bash scripts/setup.sh
```

Replacing the real package, `install` builds and checks the stand-in before it removes anything and puts
`plasma-workspace` back if the stand-in will not install; either way it adds a pacman hook (`/etc/pacman.d/hooks/90-caelestia-plasma-stub.hook`).
After every `powerdevil` or `xdg-desktop-portal-kde` upgrade the hook starts `caelestia-plasma-stub refresh`,
which downloads the matching `plasma-workspace` into pacman's cache (nothing of it is installed), takes the
library out of it and rebuilds the stand-in. If a refresh fails (the database stayed locked, no network),
`caelestia-plasma-stub status` says so; run `sudo caelestia-plasma-stub refresh` before the next login,
because a `powerdevil` newer than the library may not start. `sudo caelestia-plasma-stub remove` puts the
real package back. Because the real package, which ships `xembedsniproxy`, is gone, `setup.sh` builds the
old-tray proxy from `src/xembed-sni-proxy` (a failed build only costs the tray icons of old X11 programs); after
`remove` the real package's own copy is back, and the one under `/usr/local` does the same work.
If a package ever asks for a version of `plasma-workspace` newer than the stand-in's, `pacman` stops
the update before it changes anything: run `remove`, update, then `install` again. A stand-in made by hand
is adopted by `install` (it adds the script and the hook, then refreshes).

**Options.** Set these in the environment before you run `bash scripts/setup.sh`:

| Variable | Default | Effect |
| --- | --- | --- |
| `INSTALL_SYSTEMSETTINGS` | `true` | `false` skips System Settings, which hosts the display settings page |
| `INSTALL_PIPEWIRE` | `true` | `false` skips `pipewire`, `pipewire-pulse` and `pipewire-alsa` (Arch) |
| `INSTALL_BLUEDEVIL` | `true` | `false` skips `bluedevil` and `bluez`, and does not enable `bluetooth.service` (Arch) |
| `CAELESTIA_ARCH_PLASMA_STUB` | `true` | `false` installs the real `plasma-workspace` on an Arch machine that has none, instead of the stand-in package |
| `INSTALL_WALLPAPER_PACK` | `false` | `true` downloads the dharmx wallpaper pack (about 100 MB); otherwise the shell's bundled wallpaper is used |
| `INSTALL_GWENVIEW`, `INSTALL_KATE`, `INSTALL_KDECONNECT`, `INSTALL_KWRITE`, `INSTALL_PARTITIONMANAGER`, `INSTALL_FILELIGHT` | `false` | `true` installs that KDE application (Gwenview, Kate, KDE Connect, KWrite, KDE Partition Manager, Filelight). The installer's Applications menu has a switch for each. KDE Connect also gets ports 1714-1764 (TCP and UDP) opened in ufw or a running firewalld |

For example: `INSTALL_WALLPAPER_PACK=true bash scripts/setup.sh`.

**Tested on.** CachyOS with SDDM, and Fedora 44 with SDDM. The Plasma Login and no-login-manager paths have
only unit tests. Debian and packaged installs skip this step.

**Uninstalling.** `bash ./uninstall.sh` removes the session files listed above. It leaves the login
manager alone, except SDDM when this step was the one that enabled it.

## Keybinds

| Shortcut | Action |
| --- | --- |
| `Super` | App launcher |
| `Super + /` | Keybind cheatsheet |
| `Super + Enter` | Terminal |
| `Super + Tab` | Overview |
| `Super + 1-5` | Switch workspace |
| `Super + B` | Notification sidebar |
| `Super + V` | Clipboard history |
| `Super + Shift + S` | Screenshot |
| `Super + Shift + A` | Google Lens |
| `Super + Shift + D` | Text recognition |
| `Super + Ctrl + S` | Screen recorder |
| `Super + Shift + C` | Color picker |
| `Super + Shift + V` | Emoji selector |

## Configuring

Open Nexus (`Super`, then `>Settings`).

- Appearance: wallpaper, colors, fonts, and the wallpaper slideshow
- Panels: every bar element, dashboard, launcher, sidebar and overview
- Desktop: window rules, the context menu, Krohnkite
- Display: arrange monitors by dragging them, turn one on or off, choose the primary monitor or mirror
  it onto another, and set resolution, refresh rate, scale, orientation and brightness. It applies the
  change through KWin and asks you to keep it, or goes back
- Power: for plugged in, on battery and low battery, when to dim the screen, turn it off and suspend,
  the power profile, and what closing the lid and pressing the power button do. The low battery
  section also sets the charge at or below which its profile is used (10% by default; "Whenever
  unplugged" shows that profile at any charge). It writes `~/.config/powerdevilrc` and asks
  `powerdevil` to reload it
- Splash: a login splash, on by default (Caelestia's own, in the colors of your scheme, light or dark,
  with or without the logo, or a Plasma splash theme; a
  minimum time and a preview) and the boot splash, where you list the Plymouth themes, preview one and
  apply it, which rebuilds the boot image and asks for your password (take a Snapper snapshot first)
- Clipboard (under Utilities): how many entries the history keeps, whether clearing it asks first, and a
  clipboard icon among the status icons (off by default). The icon opens a popout with the history, which
  scrolls: click a clip to copy it, or clear the history from the header. Images show a thumbnail; copied
  files show a thumbnail (or the icon for their kind) and name each. A long strip of files scrolls with the
  mouse wheel over it (at either end the wheel goes on to the list), by dragging it, or with a touchpad
  swipe. "Open on hover" chooses between hovering the icon and clicking it (a clicked popout stays until you click elsewhere or press Escape).
  Meta+V opens the same popout, pinned; the launcher's clipboard list is the fallback when no bar can show it
- Shortcuts: rebind any built-in shortcut, or add a command shortcut
- Plugins: browse the store, or install a plugin you built yourself

Set the wallpaper from Appearance. The stock KDE wallpaper manager does not drive
the color scheme, so using it leaves the shell on stale colors.

Settings are written to `~/.config/caelestia/shell.json`. The login splash settings are in
`~/.config/caelestia-splashrc`; `uninstall.sh` leaves both in place.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Widgets not appearing | Log out and back in, or run `caelestia shell -d` |
| Colors not applying | Run `caelestia scheme set -n dynamic`, or `caelestia wallpaper -f <image>`. See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#34-colors-not-applying) |
| The shell restarts by itself and `coredumpctl info` shows a crash in `libpipewire` | The PipeWire thread behind "do not disturb while streaming" now runs only while that setting is on. To keep it off whatever the setting says, put `[Service]` and `Environment=CAELESTIA_STREAM_WATCHER=0` in `~/.config/systemd/user/caelestia-shell.service.d/stream-watcher.conf`, then `systemctl --user daemon-reload` and log in again |
| A black screen with only the cursor after logging out and straight back in | The session program now stops the graphical session at logout and clears a leftover one at login; install it with `bash ./scripts/setup.sh` (an update does not). Until then, wait 30 seconds at the login screen before logging in again. If the screen is already black, press Ctrl+Alt+F3, log in, and run `systemctl --user start caelestia-shell.service` |
| The login screen came back, or the screen froze, while a system upgrade was running | A system upgrade reloads systemd, which makes the user manager stop answering for a moment, and the session program used to read that as KWin having exited: it ended, the login manager closed the session, and KWin and the shell kept running without a display. The program now asks again for up to 30 seconds before it gives up, and writes what it saw to the journal (`journalctl --user -t caelestia-wm-session`: "no answer from the user manager ..."). Install it with `bash ./scripts/setup.sh` (an update does not). If the screen is frozen, log in over SSH or press Ctrl+Alt+F3 and run `sudo reboot`; anything open is lost |
| Install failed mid-way | Re-run `bash ./scripts/setup.sh` |
| Full reset needed | See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |

For detailed logs, enable Debug Mode in Nexus -> About -> Advanced, then run
`caelestia shell -l`. Bug reports and questions go to
[GitHub Issues](https://github.com/ladybug-me/caelestia-kde/issues).

## Repository layout

```
installer/     TUI installer and the per-distro package lists
  tui/         C++ TUI source and its CMakeLists
  data/        menu.json, theme.json, tui.version
  distro/      per-distro package installation (arch, debian, fedora)
scripts/       install/update pipeline: the numbered steps and their shared lib/
src/           files copied onto the system, plus the vendored submodules
shell/         the QML shell and its C++ QML plugin
docs/          guides, plus design notes under docs/architecture/
tests/         bash tests for the step-script helpers
tools/         repo maintenance scripts, never shipped
assets/        the logo and screenshots used by the docs
.github/       workflows, issue and PR templates, CI checks
```

<a href="https://www.star-history.com/?repos=ladybug-me%2Fcaelestia-kde&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ladybug-me/caelestia-kde&type=date&theme=dark&legend=top-left&sealed_token=NFI4jXcoZAI26MlGX2jEasHMRd1PIS09clm_CVDS7SFGajH3wiHlN72P8WzuOQT2k2F71ZOCGl_xoy8eVpWlWtA0ACY3koK0NIS1-vLecN0vbvYgrZDN9kp8sQn7NT2xPNeilgrmzYWTzgdQYgskaDMGophAKmy6r6LUfQj8iFjy-Gunuqnte3EY14fX" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ladybug-me/caelestia-kde&type=date&legend=top-left&sealed_token=NFI4jXcoZAI26MlGX2jEasHMRd1PIS09clm_CVDS7SFGajH3wiHlN72P8WzuOQT2k2F71ZOCGl_xoy8eVpWlWtA0ACY3koK0NIS1-vLecN0vbvYgrZDN9kp8sQn7NT2xPNeilgrmzYWTzgdQYgskaDMGophAKmy6r6LUfQj8iFjy-Gunuqnte3EY14fX" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=ladybug-me/caelestia-kde&type=date&legend=top-left&sealed_token=NFI4jXcoZAI26MlGX2jEasHMRd1PIS09clm_CVDS7SFGajH3wiHlN72P8WzuOQT2k2F71ZOCGl_xoy8eVpWlWtA0ACY3koK0NIS1-vLecN0vbvYgrZDN9kp8sQn7NT2xPNeilgrmzYWTzgdQYgskaDMGophAKmy6r6LUfQj8iFjy-Gunuqnte3EY14fX" />
 </picture>
</a>

## Credits

- [caelestia-dots/shell](https://github.com/caelestia-dots/shell) and the [Caelestia dotfiles](https://github.com/caelestia-dots/caelestia) by [@soramanew](https://github.com/soramanew) - the design language, shell and dotfiles this port is built on
- [ladybug-me](https://github.com/ladybug-me) - KDE port lead
- [0xSolanaceae](https://github.com/0xSolanaceae) - Head maintainer
- [Bali10050](https://github.com/Bali10050/Darkly) - Darkly Qt
- [wrymt](https://github.com/wrymt/darkly-gtk) - Darkly GTK
- [Haidir](https://bitbucket.org/dirn-typo/yet-another-monochrome-icon-set) - icon set
- [dim-ghub](https://github.com/dim-ghub/caelestia-shell) - v2.0.0 features
- [dharmx](https://github.com/dharmx/walls) - default wallpapers
  
## License

GPL-3.0-or-later - see [LICENSE](LICENSE).
