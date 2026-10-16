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
    var spec = null;
    try {
        spec = login.ThemeSpec ? JSON.parse(login.ThemeSpec) : null;
    } catch (e) {
        spec = null;
    }
    return {
        enabled: login.Enabled === "true",
        minSeconds: isNaN(seconds) ? DEFAULT_MIN_SECONDS : Math.min(MAX_MIN_SECONDS, Math.max(0, seconds)),
        showLogo: login.ShowLogo === undefined ? true : login.ShowLogo === "true",
        // The Plymouth theme the login splash draws ("" is the Caelestia design) and what to draw.
        theme: login.Theme || "",
        themeSpec: spec && spec.kind ? spec : null
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
// starting a second copy. spec is the theme to draw (the one in the settings when left out);
// nothing is passed for the Caelestia design or a theme that cannot be drawn.
function previewCommand(qmlPath, settings, spec) {
    var s = spec !== undefined ? spec : settings.themeSpec;
    var env = ["CAELESTIA_SPLASH_PREVIEW=1", "CAELESTIA_SPLASH_MIN=" + settings.minSeconds, "CAELESTIA_SPLASH_LOGO=" + (settings.showLogo ? "1" : "0")];
    if (s && s.kind && s.kind !== "plain")
        env.push("CAELESTIA_SPLASH_THEME=" + JSON.stringify(s));
    return ["env"].concat(env, ["quickshell", "-n", "-p", qmlPath]);
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

// --- drawing the Plymouth themes ----------------------------------------------------------------
//
// A Plymouth theme is drawn by Plymouth itself, so the splash can only show what a theme keeps in
// plain files. The two-step themes (cachyos, spinner, glow ...) are a background colour, a ring of
// numbered frames and an optional watermark; fade-throbber (fade-in) is one star that fades. The
// script, space-flares, text, details and tribar modules are programs or text, and are shown as
// the Caelestia design ("plain"). What the splash gets is a small description (a "spec"), built
// here once and stored in the settings file, so that the session program only has to hand it on.

// Lists every theme: its .plymouth file, then the directory its images are in (ImageDir, or the
// theme's own folder) and the files in that directory. $1 is the themes folder.
var SURVEY_SCRIPT = 'for t in "$1"/*/; do n="$(basename "$t")"; f="$t$n.plymouth"; [ -r "$f" ] || continue; echo "@@THEME $n"; cat "$f"; echo; d="$(sed -n "s/^ImageDir=//p" "$f" | head -n 1 | tr -d "\\r")"; d="${d:-${t%/}}"; echo "@@DIR $d"; ls "$d" 2>/dev/null; done';
var THEMES_DIR = "/usr/share/plymouth/themes";

function surveyCommand(themesDir) {
    return ["sh", "-c", SURVEY_SCRIPT, "sh", themesDir || THEMES_DIR];
}

// {theme: {plymouth: text, dir: path, files: [names]}} from the survey's output.
function parseSurvey(text) {
    var result = {};
    var current = null;
    var mode = "";
    String(text || "").split("\n").forEach(function (line) {
        var theme = line.match(/^@@THEME (.+)$/);
        var dir = line.match(/^@@DIR (.*)$/);
        if (theme) {
            current = {
                plymouth: "",
                dir: "",
                files: []
            };
            result[theme[1]] = current;
            mode = "plymouth";
        } else if (dir && current) {
            current.dir = dir[1].trim().replace(/\/+/g, "/").replace(/\/$/, "");
            mode = "files";
        } else if (current && mode === "plymouth") {
            current.plymouth += line + "\n";
        } else if (current && mode === "files" && line.trim() !== "") {
            current.files.push(line.trim());
        }
    });
    return result;
}

function colorOf(value, fallback) {
    var m = /^0x([0-9a-fA-F]{6})$/.exec(String(value || "").trim());
    return m ? "#" + m[1].toLowerCase() : fallback;
}

function fraction(value, fallback) {
    var n = parseFloat(value);
    return isNaN(n) ? fallback : Math.min(1, Math.max(0, n));
}

// The numbered frames "<prefix>0001.png ..." among the files, or null when there are fewer than two.
function frameSet(files, prefix) {
    var re = new RegExp("^" + prefix + "(\\d+)\\.png$");
    var numbers = [];
    var pad = 0;
    files.forEach(function (f) {
        var m = re.exec(f);
        if (m) {
            numbers.push(parseInt(m[1], 10));
            pad = m[1].length;
        }
    });
    if (numbers.length < 2)
        return null;
    return {
        prefix: prefix,
        first: Math.min.apply(null, numbers),
        count: numbers.length,
        pad: pad
    };
}

// What the splash draws for one surveyed theme.
function buildSpec(entry) {
    var module = parseGroup(entry.plymouth, "Plymouth Theme").ModuleName;
    if (module === "two-step") {
        var cfg = parseGroup(entry.plymouth, "two-step");
        // The ring that turns while the system boots is the throbber; animation- is the end animation.
        var frames = frameSet(entry.files, "throbber-") || frameSet(entry.files, "animation-");
        if (frames) {
            var spec = {
                kind: "frames",
                dir: entry.dir,
                prefix: frames.prefix,
                first: frames.first,
                count: frames.count,
                pad: frames.pad,
                fps: 25,
                bg: [colorOf(cfg.BackgroundStartColor, "#000000"), colorOf(cfg.BackgroundEndColor, "#000000")],
                x: fraction(cfg.HorizontalAlignment, 0.5),
                y: fraction(cfg.VerticalAlignment, 0.5)
            };
            if (entry.files.indexOf("watermark.png") >= 0)
                spec.watermark = {
                    file: "watermark.png",
                    x: fraction(cfg.WatermarkHorizontalAlignment, 1),
                    y: fraction(cfg.WatermarkVerticalAlignment, 0.5)
                };
            return spec;
        }
    }
    if (module === "fade-throbber" && entry.files.indexOf("star.png") >= 0)
        return {
            kind: "star",
            dir: entry.dir,
            file: "star.png",
            bg: ["#000000", "#000000"]
        };
    return {
        kind: "plain"
    };
}

// {theme: spec} for every surveyed theme.
function specsFrom(text) {
    var survey = parseSurvey(text);
    var specs = {};
    Object.keys(survey).forEach(function (name) {
        specs[name] = buildSpec(survey[name]);
    });
    return specs;
}

// The login splash's list: the Caelestia design, then every Plymouth theme. A theme that cannot
// be drawn is marked, because it would show the Caelestia design.
function loginChoices(names, specs) {
    var list = [
        {
            value: "",
            label: "Caelestia"
        }
    ];
    names.forEach(function (name) {
        var spec = specs[name];
        list.push({
            value: name,
            label: spec && spec.kind === "plain" ? name + " (simple)" : name
        });
    });
    return list;
}

// What to store for a login theme: the name and its spec as one line of JSON ("" for none).
function themeWrites(name, spec) {
    var drawable = name !== "" && spec && spec.kind && spec.kind !== "plain";
    return [writeArgs("Theme", name), writeArgs("ThemeSpec", drawable ? JSON.stringify(spec) : "")];
}
