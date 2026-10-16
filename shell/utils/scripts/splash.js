.pragma library

// Pure logic for the Nexus Splash page: the login splash's settings file, the command that
// previews it, and the boot splash (Plymouth) theme list and apply command. No service or
// config dependencies, so it can be tested on its own.

// The settings live in ~/.config/caelestia-splashrc, group [Login]. The session program reads
// the same file with kreadconfig6 before it starts the splash, so the keys and defaults here
// and in src/session/caelestia-wm-session have to agree.
var SETTINGS_FILE = "caelestia-splashrc";
var GROUP = "Login";
var DEFAULT_MIN_SECONDS = 2;
var MAX_MIN_SECONDS = 30;
var MIN_CHOICES = [1, 2, 3, 5, 8];

// The keys of one group, from the text of a kconfig file.
function parseGroup(text, group) {
    var result = {};
    var inGroup = false;
    String(text || "").split("\n").forEach(function (raw) {
        var line = raw.trim();
        if (line === "" || line[0] === "#" || line[0] === ";")
            return;
        var head = line.match(/^\[([^\]]+)\]$/);
        if (head) {
            inGroup = head[1] === group;
            return;
        }
        var eq = line.indexOf("=");
        if (!inGroup || eq < 1)
            return;
        result[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
    });
    return result;
}

// A missing key means the default: the login splash is off until the user turns it on.
function settingsFrom(text) {
    var login = parseGroup(text, GROUP);
    var seconds = parseInt(login.MinSeconds, 10);
    return {
        enabled: login.Enabled === "true",
        minSeconds: isNaN(seconds) ? DEFAULT_MIN_SECONDS : Math.min(MAX_MIN_SECONDS, Math.max(0, seconds)),
        showLogo: login.ShowLogo === undefined ? true : login.ShowLogo === "true"
    };
}

function formatSeconds(seconds) {
    return seconds + " s";
}

// The usual times, plus the one in the file when it is none of them.
function minChoices(current) {
    var values = MIN_CHOICES.slice();
    if (values.indexOf(current) < 0) {
        values.push(current);
        values.sort(function (a, b) {
            return a - b;
        });
    }
    return values.map(function (v) {
        return {
            value: v,
            label: formatSeconds(v)
        };
    });
}

// Arguments for one kwriteconfig6 call.
function writeArgs(key, value) {
    return ["--file", SETTINGS_FILE, "--group", GROUP, "--key", key, String(value)];
}

// Runs the splash now, as the session program does at login but with the preview flag, which
// shows it for at least 3 s and needs no signal from the shell. -n keeps a second click from
// starting a second copy.
function previewCommand(qmlPath, settings) {
    return ["env", "CAELESTIA_SPLASH_PREVIEW=1", "CAELESTIA_SPLASH_MIN=" + settings.minSeconds, "CAELESTIA_SPLASH_LOGO=" + (settings.showLogo ? "1" : "0"), "quickshell", "-n", "-p", qmlPath];
}

// Theme names, one per line, as plymouth-set-default-theme --list prints them.
function parseThemes(text) {
    return String(text || "").split("\n").map(function (line) {
        return line.trim();
    }).filter(function (line) {
        return line !== "";
    });
}

// The name goes to a root command, so only what a theme folder is called is accepted, and it
// cannot start with a dash, which the command would take for an option.
function validTheme(name) {
    return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(String(name || ""));
}

// -R rebuilds the initramfs, which is what puts the theme into the boot. pkexec asks for the
// password through the session's polkit agent.
function applyCommand(theme) {
    if (!validTheme(theme))
        return [];
    return ["pkexec", "plymouth-set-default-theme", "-R", theme];
}

// pkexec exits with 126 when the person is not authorised or closes the dialog, and with 127
// when authentication could not be obtained.
function applyResult(code) {
    if (code === 0)
        return "done";
    if (code === 126 || code === 127)
        return "cancelled";
    return "failed";
}
