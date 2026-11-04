# xembed-sni-proxy

KDE's proxy that shows the tray icons of old X11 (XEmbed) apps as StatusNotifierItems. KDE ships it
only inside `plasma-workspace`; the fork vendors it so a machine without `plasma-workspace` can still
show those icons (`scripts/lib/xembed-proxy.sh` builds and installs it).

- Source: `xembed-sni-proxy/` of `plasma-workspace` v6.8.2 (https://invent.kde.org/plasma/plasma-workspace),
  plus `c_ptr.h` from the repository's top level.
- Licences: each file keeps its SPDX header (GPL-2.0-or-later and LGPL-2.1-or-later).
- Changes: `#include "../c_ptr.h"` is `#include "c_ptr.h"`; `CMakeLists.txt` and `config-workspace.h.in`
  are new (a standalone build with a plain `GNUInstallDirs` install and the binary named
  `caelestia-xembedsniproxy`); `xembedsniproxy.desktop` and the unit template are not taken (the
  session starts the unit `src/session/plasma-xembedsniproxy-standalone.service`).
- Updating: copy the files again from a newer `plasma-workspace` tag and set `VERSION` in
  `CMakeLists.txt`. The proxy has few dependencies (Qt6, KF6 CoreAddons/DBusAddons/WindowSystem/Crash,
  XCB, libXtst), so most updates are a plain copy.
