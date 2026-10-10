<div align="center">

<img src="assets/logo.svg" width="64" alt="Caelestia logo" />

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
> [independent session](#independent-session-arch-based); install it from a clone:
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

> [!NOTE]
> The installer's *Update*, Nexus -> Updates and `update.sh` look at `ladybug-me/caelestia-kde`
> (`main` and `dev`), not at this branch. To pick up changes from this branch, run `git pull` in
> your clone and run `bash scripts/setup.sh` again.

### Uninstalling

Choose *Uninstall* from the installer TUI, or run:

```bash
bash ./uninstall.sh
```

## Independent session (Arch-based)

This branch installs one more login-screen entry, **Caelestia**, that starts KWin and the Caelestia
shell without `plasmashell`. Nothing is removed: the Plasma session and any other session stay as
they were, and you choose one at the login screen.

| Installed | Where |
| --- | --- |
| Session program | `/usr/local/bin/caelestia-wm-session` |
| KWin unit and session target | `/usr/local/lib/systemd/user/caelestia-kwin.service` and `caelestia-session.target` |
| Login-screen entry | `/usr/local/share/wayland-sessions/caelestia.desktop` |
| Wayland greeter (SDDM only) | `/etc/sddm.conf.d/zz-wayland-greeter.conf` |

The step looks at the login manager the machine uses:

| Login manager | What the step does |
| --- | --- |
| Plasma Login | installs the entry only |
| SDDM | installs the entry and a drop-in that switches SDDM to a Wayland greeter |
| none enabled | installs SDDM, adds the drop-in and enables it |
| anything else | installs the entry and warns that the login manager may not list it |

The Wayland greeter matters. With SDDM's default Xorg greeter, about 4 in 9 logins on the test
machine ended on a black screen. The Caelestia SDDM theme shows a session picker below the password
field (full variant), so you can pick Caelestia or Plasma.

**Packages.** The session installs `plasma-workspace`, `kscreenlocker`, `plasma5support`,
`layer-shell-qt`, `xdg-desktop-portal-kde`, `xorg-xwayland`, `polkit-kde-agent`, `powerdevil`,
`kscreen`, `konsole`, `dolphin`, `ark` and `systemsettings`, because the shell calls their tools.
`plasma-workspace` brings the `plasmashell` binary and a Plasma login entry with it, but nothing in
the Caelestia session starts `plasmashell`. When foot is not installed and you have not chosen a
terminal, the installer records Konsole as the shell's terminal.

**Options.** Set these in the environment before you run `bash scripts/setup.sh`:

| Variable | Default | Effect |
| --- | --- | --- |
| `INSTALL_SYSTEMSETTINGS` | `true` | `false` skips System Settings, which hosts the display settings page |
| `INSTALL_WALLPAPER_PACK` | `false` | `true` downloads the dharmx wallpaper pack (about 100 MB); otherwise the shell's bundled wallpaper is used |

For example: `INSTALL_WALLPAPER_PACK=true bash scripts/setup.sh`.

**Tested on.** CachyOS with SDDM. The Plasma Login and no-login-manager paths have only unit tests.
Fedora, Debian and packaged installs skip this step.

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
- Shortcuts: rebind any built-in shortcut, or add a command shortcut
- Plugins: browse the store, or install a plugin you built yourself

Set the wallpaper from Appearance. The stock KDE wallpaper manager does not drive
the color scheme, so using it leaves the shell on stale colors.

Settings are written to `~/.config/caelestia/shell.json`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Widgets not appearing | Log out and back in, or run `caelestia shell -d` |
| Colors not applying | Run `caelestia scheme set -n dynamic`, or `caelestia wallpaper -f <image>`. See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#34-colors-not-applying) |
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
