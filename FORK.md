# This fork and upstream

This branch (`independent-session`) is `ladybug-me/caelestia-kde` plus an independent
KWin + Caelestia session, Nexus pages, and installer changes. Upstream is merged in, never
rebased onto, so each sync is one merge and the next one only brings what is new.

## Syncing with upstream

```bash
git remote add upstream https://github.com/ladybug-me/caelestia-kde.git   # once
git fetch upstream --tags
git checkout -b sync-<tag> independent-session
git merge <tag>                      # a release tag, not a moving branch
# resolve, then: bash tests/run-tests.sh and the scripts in .github/scripts
```

## Where the fork changes files that upstream also changes

When a merge conflicts, it is almost always in one of these. Take upstream's structure and
re-attach the fork's part.

| File | What the fork adds |
|---|---|
| `installer/tui/Runner.cpp` | the step "Install independent session" (`scripts/12-independent-session.sh`), the only fork change left in the installer's C++ |
| `installer/distro/fedora/packages.sh` | the session package set (`SESSION_PACKAGES`, the `session` group, System Settings, PipeWire and Bluetooth switches), under Fedora's package names, as `installer/distro/arch/packages.sh` has it |
| `installer/data/menu.json` | the Packages, Applications and "Theming for other apps" menus |
| `src/bin/caelestia-color`, `src/dots-extra/fish/config.fish`, `src/matugen/README.md` | terminals reached over SSH and Konsole are not sent the palette; `theme.enableKonsole` is off unless set, so Konsole keeps its own colours |
| `scripts/08-build-shell.sh`, `scripts/10-autostart.sh` | with the independent session `plasmashellrc` and `kscreenlockerrc` are not written (the lock screen package is selected by the Caelestia session through `PLASMA_DEFAULT_SHELL`); other installs keep the old self-heal |
| `uninstall.sh` | the boot target set by the session step on a minimal Fedora install is set back, with the SDDM flag |
| `scripts/09-system-tweaks.sh` | the OSD, panel and splash tweaks are skipped with the independent session (`scripts/lib/independent-session.sh`) |
| `src/bin/caelestia-color` | `apply_kde_directly`: without `plasma-apply-colorscheme` (plasma-workspace) the scheme is merged into kdeglobals and `KGlobalSettings.notifyChange` is sent |
| `shell/modules/launcher/Content.qml`, `shell/modules/session/Content.qml`, `shell/modules/nexus/pages/desktop/KrohnkitePage.qml`, the lock screen's `Session.qml` | logout falls back to `systemctl --user stop caelestia-kwin.service` when `org.kde.Shutdown` is missing |
| `src/kde/shells/caelestia.desktop/contents/lockscreen/LockScreenUi.qml`, `components/Session.qml`, `components/PasswordPill.qml` | no import of `org.kde.plasma.private.sessions`, `org.kde.plasma.private.keyboardindicator` or `org.kde.plasma.workspace.components` (all plasma-workspace): Caps Lock comes from the keyboard LED (`CapsLockState.qml`), the layout button from KWin's `org.kde.keyboard` (`KeyboardLayoutState.qml`), the session actions from logind and the display manager (`Session.qml`, probe + `LockScreenHelpers.js`) |
| lock screen QML (`LockScreenUi.qml`, `components/DinoGame.qml`, `GreetingPill.qml`, `NotifDock.qml`, `PasswordPill.qml`, `Session.qml`, `WeatherCard.qml`) and the SDDM theme's `SessionPicker.qml` | every `Text` in the Rubik font (`LockScreenConfig.fontBody`) has `renderType: Text.NativeRendering`: with the default renderer on Qt 6.11 that text comes out blank |
| `scripts/12-independent-session.sh`, `uninstall.sh` | on a machine without plasma-workspace (Fedora) step 12 builds the vendored `src/xembed-sni-proxy` and installs `caelestia-xembedsniproxy` and a `plasma-xembedsniproxy.service` under `/usr/local`; uninstall removes them |
| `src/session/pam.d/*`, `src/kde/shells/caelestia.desktop/contents/lockscreen/LockScreenUi.qml` | the lock screen's PAM services written on Fedora when `plasma-workspace` is absent (it ships them); the lock screen draws the shell's wallpaper when KDE's wallpaper plugin is missing |
| `installer/distro/fedora/packages.sh`, `installer/distro/debian/packages.sh` | no `foot` in the shell packages (Konsole is the terminal, as on Arch); on Fedora the custom fonts step fetches only missing fonts and refreshes only the user's font folder, without the stdbuf preload |
| `installer/distro/fedora/packages.sh`, `scripts/12-independent-session.sh`, `installer/tui/main.cpp`, `uninstall.sh` | Fedora's session set has `plasma-integration` and no `plasma-workspace`; step 12 hides the Plasma entry only when `plasma-workspace` is installed (and removes its own hiding file when it is gone); the installer's and `uninstall.sh`'s logout fall back like the shell's |
| `scripts/04-deploy-kde.sh` | the cliphist unit is wanted by `graphical-session.target`; the runner keeps the `wl-paste` watchers alive when `wl-clip-persist` cannot start (Fedora's 0.4.1 speaks wlr-data-control only) |
| `shell/modules/dashboard/Wrapper.qml` | a new profile picture runs `shell/scripts/sync_greeter.sh`, so the login screen shows it |
| `src/sddm/themes/full/components/SessionPicker.qml` | the list and the label are built each time a session appears (`refresh()`), not once at completion; the label is anchored and drawn natively so it shows on Qt 6.11 |
| `src/sddm/themes/full/components/Avatar.qml` | the Image gets its `source` from the candidate list (upstream never set it) |
| `src/sddm/themes/full/components/RandomQuote.qml` | the quote uses `config.text`, not white |
| `scripts/05-sddm-theme.sh` | `install_greeter_icon_font` copies the Material Symbols font to `/usr/local/share/fonts/caelestia` when only the user's home has it (Fedora, Debian), so the greeter's icons are not boxes |
| `scripts/setup.sh` | the compiled installer is reused only when its stamp (`tui.version` plus a hash of `installer/tui` and `installer/data`) matches the sources: `installer_stamp`, `compiled_installer_is_current` |
| `scripts/06-services.sh`, `07-kde-apps.sh`, `08-build-shell.sh` | Bluetooth, ydotoold clean-up, KDE apps and the KDE Connect firewall rules, stale `m3shapes` record |
| `src/bin/caelestia-update`, `caelestia-check-updates`, `shell/services/UpdateChecker.qml` | an install made from a fork follows that fork's repository and branch (`resolve_update_source`) and the opt-in system upgrade (`CAELESTIA_UPDATE_SYSTEM`) |
| `shell/modules/nexus/pages/UpdatesPage.qml`, `Launch.qml` | the system upgrade switch; Konsole-style terminals get their `-e` |
| `shell/shell.qml` | writes `$XDG_RUNTIME_DIR/caelestia-shell-ready` for the login splash |
| `PageDictionary.qml`, `PageCompRegistry.qml` | the Display, Power and Splash pages (matched by position in both lists) |
| `shell/modules/bar/components/StatusIcons.qml`, `shell/modules/bar/popouts/Content.qml`, `shell/plugin/src/Caelestia/Config/barconfig.hpp`, `shell/modules/nexus/pages/panels/taskbar/BarStatusIcons.qml` | the `clipboard` status icon: a list entry (off by default), a case in the icon loader and its click handler, the `clipboard` popout, `bar.status.clipboardEntries` and `bar.status.clipboardOpenOnHover`, and the "Clipboard popout" section of the Status icons page (upstream 2.6.3 dropped the Utilities clipboard page); the popout itself is in `shell/modules/bar/popouts/ClipHistory.qml`, its file-name parsing in `shell/utils/scripts/clipfiles.js` |
| `shell/modules/bar/popouts/Wrapper.qml`, `shell/modules/bar/Bar.qml`, `shell/modules/drawers/Interactions.qml`, `shell/modules/drawers/ContentWindow.qml`, `shell/modules/Shortcuts.qml`, `shell/services/Visibilities.qml` | a "pinned" popout (`Wrapper.pinned`: the bar's hover routing, the hide timer and the focus grab leave it alone until it is dismissed), used by the clipboard popout when it is clicked or opened with Meta+V; `Visibilities.openClipboardPopout()` finds the status icons of the screen under the pointer, and the `clipboard` shortcut tries it before the launcher's list |
| `shell/modules/drawers/Exclusions.qml`, `shell/plugin/src/Caelestia/Config/borderconfig.hpp`, `shell/modules/nexus/pages/wallandstyle/AppearancePage.qml` | the four edge-reserving windows: one that reserves nothing is not created (each is a full Qt Quick window with its own graphics context), and `border.reserveSpace` (on by default) turns the border part of the reservation off |
| `shell/modules/nexus/pages/wallandstyle/ColourSelect.qml` | the Colors page: Variants come right after the Dynamic card, then Light and Dark; each of the three is a section that opens and closes (closed to begin with); a variant shows the colors it gives (read from `scheme set --preview` when its section is first opened, parsed by `shell/utils/scripts/variantcolours.js`) instead of an icon |
| `shell/modules/bar/components/performance/PerfCpu.qml`, `PerfGpu.qml`, `PerfMemory.qml`, `PerfNetwork.qml` | the maintainer's own bar edits (commit "bar: performance widgets changes"); keep them when a merge touches these files |

Everything else the fork adds lives in files of its own: `scripts/12-independent-session.sh`,
`scripts/lib/independent-session.sh`, `src/session/`, the Display, Power and
Splash pages and services, `shell/modules/splash/`, and the tests that go with them.

## Dropped on purpose

Upstream (since 2.6) runs the updater in the user's terminal. The fork's own in-app update log and
progress bar were dropped with it. The incremental build (build folders kept between updates)
stays in the update script.
