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
| `installer/data/menu.json` | the Packages, Applications and "Theming for other apps" menus |
| `src/bin/caelestia-color`, `src/dots-extra/fish/config.fish`, `src/matugen/README.md` | terminals reached over SSH and Konsole are not sent the palette; `theme.enableKonsole` is off unless set, so Konsole keeps its own colours |
| `scripts/08-build-shell.sh`, `scripts/10-autostart.sh` | with the independent session `plasmashellrc` and `kscreenlockerrc` are not written (the lock screen package is selected by the Caelestia session through `PLASMA_DEFAULT_SHELL`); other installs keep the old self-heal |
| `scripts/09-system-tweaks.sh` | the OSD, panel and splash tweaks are skipped with the independent session (`scripts/lib/independent-session.sh`) |
| `scripts/04-deploy-kde.sh` | the cliphist unit is wanted by `graphical-session.target` |
| `scripts/setup.sh` | the compiled installer is reused only when its stamp (`tui.version` plus a hash of `installer/tui` and `installer/data`) matches the sources: `installer_stamp`, `compiled_installer_is_current` |
| `scripts/06-services.sh`, `07-kde-apps.sh`, `08-build-shell.sh` | Bluetooth, ydotoold clean-up, KDE apps and the KDE Connect firewall rules, stale `m3shapes` record |
| `src/bin/caelestia-update`, `caelestia-check-updates`, `shell/services/UpdateChecker.qml` | an install made from a fork follows that fork's repository and branch (`resolve_update_source`) and the opt-in system upgrade (`CAELESTIA_UPDATE_SYSTEM`) |
| `shell/modules/nexus/pages/UpdatesPage.qml`, `Launch.qml` | the system upgrade switch; Konsole-style terminals get their `-e` |
| `shell/shell.qml` | writes `$XDG_RUNTIME_DIR/caelestia-shell-ready` for the login splash |
| `PageDictionary.qml`, `PageCompRegistry.qml` | the Display, Power and Splash pages (matched by position in both lists) |
| `shell/modules/bar/components/StatusIcons.qml`, `shell/modules/bar/popouts/Content.qml`, `shell/plugin/src/Caelestia/Config/barconfig.hpp`, `shell/modules/nexus/pages/panels/taskbar/BarStatusIcons.qml` | the `clipboard` status icon: a list entry (off by default), a case in the icon loader and its click handler, the `clipboard` popout, `bar.status.clipboardEntries` and `bar.status.clipboardOpenOnHover`, and the "Clipboard popout" section of the Status icons page (upstream 2.6.3 dropped the Utilities clipboard page); the popout itself is in `shell/modules/bar/popouts/ClipHistory.qml`, its file-name parsing in `shell/utils/scripts/clipfiles.js` |
| `shell/modules/bar/popouts/Wrapper.qml`, `shell/modules/bar/Bar.qml`, `shell/modules/drawers/Interactions.qml`, `shell/modules/drawers/ContentWindow.qml`, `shell/modules/Shortcuts.qml`, `shell/services/Visibilities.qml` | a "pinned" popout (`Wrapper.pinned`: the bar's hover routing, the hide timer and the focus grab leave it alone until it is dismissed), used by the clipboard popout when it is clicked or opened with Meta+V; `Visibilities.openClipboardPopout()` finds the status icons of the screen under the pointer, and the `clipboard` shortcut tries it before the launcher's list |
| `shell/modules/drawers/Exclusions.qml`, `shell/plugin/src/Caelestia/Config/borderconfig.hpp`, `shell/modules/nexus/pages/wallandstyle/AppearancePage.qml` | the four edge-reserving windows: one that reserves nothing is not created (each is a full Qt Quick window with its own graphics context), and `border.reserveSpace` (on by default) turns the border part of the reservation off |
| `src/bin/caelestia-color`, `src/bin/caelestia`, `shell/modules/nexus/pages/wallandstyle/ColourSelect.qml`, `shell/modules/nexus/PageDictionary.qml` | wallpaper palettes: `scheme set -s N` builds a dynamic palette from the Nth color matugen finds in the wallpaper (it was always the first; the choice is kept per wallpaper in `wallpaper/source.txt`), `scheme set --seed #rrggbb` builds it from a picked color instead (the Custom card, which uses KWin's eyedropper; it is forgotten with the wallpaper like `-s`), and `scheme palettes` lists the cards the Colors page shows (`WallpaperPalettes.qml`, a file of its own): the wallpaper's distinct colors, then variants of the first |
| `shell/modules/bar/components/performance/PerfCpu.qml`, `PerfGpu.qml`, `PerfMemory.qml`, `PerfNetwork.qml` | the maintainer's own bar edits (commit "bar: performance widgets changes"); keep them when a merge touches these files |

Everything else the fork adds lives in files of its own: `scripts/12-independent-session.sh`,
`scripts/lib/independent-session.sh`, `src/session/`, the Display, Power and
Splash pages and services, `shell/modules/splash/`, and the tests that go with them.

## Dropped on purpose

Upstream (since 2.6) runs the updater in the user's terminal. The fork's own in-app update log and
progress bar were dropped with it. The incremental build (build folders kept between updates)
stays in the update script.
