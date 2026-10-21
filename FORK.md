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
| `installer/tui/UI.cpp`, `UI.hpp`, `Runner.cpp`, `StepPolicy.cpp`, `main.cpp` | the `only_if` menu filter (`Conditions`), the Plasma removal dialog (`PlasmaRemoval`), the step "Remove Plasma desktop" and its skip rule |
| `installer/data/menu.json` | the Packages, Applications and "Theming for other apps" menus, `PLASMA_MODE` |
| `scripts/04-deploy-kde.sh` | the cliphist unit is wanted by `graphical-session.target` |
| `scripts/setup.sh` | the compiled installer is reused only when its stamp (`tui.version` plus a hash of `installer/tui` and `installer/data`) matches the sources: `installer_stamp`, `compiled_installer_is_current` |
| `scripts/06-services.sh`, `07-kde-apps.sh`, `08-build-shell.sh` | Bluetooth, ydotoold clean-up, KDE apps and the KDE Connect firewall rules, stale `m3shapes` record |
| `src/bin/caelestia-update`, `caelestia-check-updates`, `shell/services/UpdateChecker.qml` | an install made from a fork follows that fork's repository and branch (`resolve_update_source`) and the opt-in system upgrade (`CAELESTIA_UPDATE_SYSTEM`) |
| `shell/modules/nexus/pages/UpdatesPage.qml`, `Launch.qml` | the system upgrade switch; Konsole-style terminals get their `-e` |
| `shell/shell.qml` | writes `$XDG_RUNTIME_DIR/caelestia-shell-ready` for the login splash |
| `PageDictionary.qml`, `PageCompRegistry.qml` | the Display, Power and Splash pages (matched by position in both lists) |

Everything else the fork adds lives in files of its own: `scripts/12-independent-session.sh`,
`13-remove-plasma.sh`, `scripts/lib/plasma-removal.sh`, `src/session/`, the Display, Power and
Splash pages and services, `shell/modules/splash/`, and the tests that go with them.

## Dropped on purpose

Upstream (since 2.6) runs the updater in the user's terminal. The fork's own in-app update log and
progress bar were dropped with it. The incremental build (build folders kept between updates)
stays in the update script.
