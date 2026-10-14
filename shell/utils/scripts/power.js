.pragma library

// Pure logic for the Nexus Power page: reading powerdevil's settings file, listing the
// choices for each setting and building the kwriteconfig6 arguments that change them.
// No service or config dependencies, so it can be tested on its own.
//
// Keys and defaults are those of powerdevil 6.7.5 (PowerDevilProfileSettings.kcfg and
// powerdevilsettingsdefaults.cpp). powerdevil only writes a value to powerdevilrc when it
// differs from its default, so a missing key means "the default", not "unset".

var DEFAULTS = {
    AC: {
        dimSec: 300,
        offSec: 600,
        suspendSec: 900
    },
    Battery: {
        dimSec: 120,
        offSec: 300,
        suspendSec: 600
    }
};

var ACTION_NONE = 0;
var ACTION_SLEEP = 1;

// Seconds; 0 stands for "Never". The screen cannot be switched off sooner than 30 s.
var DELAYS = [30, 60, 120, 300, 600, 900, 1800, 3600];

// "[AC][Display]" becomes the key "AC/Display", "[AC]" becomes "AC".
function parseIni(text) {
    var result = {};
    var section = "";
    String(text || "").split("\n").forEach(function (raw) {
        var line = raw.trim();
        if (line === "" || line[0] === "#" || line[0] === ";")
            return;
        var head = line.match(/^\[([^\]]+)\](?:\[([^\]]+)\])?$/);
        if (head) {
            section = head[2] !== undefined ? head[1] + "/" + head[2] : head[1];
            if (!result[section])
                result[section] = {};
            return;
        }
        var eq = line.indexOf("=");
        if (eq < 1 || section === "")
            return;
        result[section][line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
    });
    return result;
}

function value(config, profile, group, key) {
    var sec = config && config[profile + "/" + group];
    return sec && sec[key] !== undefined ? sec[key] : undefined;
}

function boolOr(v, fallback) {
    if (v === undefined)
        return fallback;
    return v === "true";
}

function intOr(v, fallback) {
    var n = parseInt(v, 10);
    return isNaN(n) ? fallback : n;
}

// What powerdevil does for one profile ("AC" or "Battery"), with its defaults filled in.
function settingsFor(config, profile) {
    var d = DEFAULTS[profile] || DEFAULTS.AC;
    return {
        dim: {
            enabled: boolOr(value(config, profile, "Display", "DimDisplayWhenIdle"), true),
            seconds: intOr(value(config, profile, "Display", "DimDisplayIdleTimeoutSec"), d.dimSec)
        },
        off: {
            enabled: boolOr(value(config, profile, "Display", "TurnOffDisplayWhenIdle"), true),
            seconds: intOr(value(config, profile, "Display", "TurnOffDisplayIdleTimeoutSec"), d.offSec)
        },
        suspend: {
            action: intOr(value(config, profile, "SuspendAndShutdown", "AutoSuspendAction"), ACTION_SLEEP),
            seconds: intOr(value(config, profile, "SuspendAndShutdown", "AutoSuspendIdleTimeoutSec"), d.suspendSec)
        },
        powerProfile: value(config, profile, "Performance", "PowerProfile") || ""
    };
}

function formatDelay(seconds) {
    if (seconds <= 0)
        return "Never";
    if (seconds % 3600 === 0)
        return seconds === 3600 ? "1 hour" : (seconds / 3600) + " hours";
    if (seconds % 60 === 0)
        return (seconds / 60) + " min";
    return seconds + " s";
}

// The choice that is selected now: 0 for Never, otherwise the delay in seconds.
// kind is "dim", "off" or "suspend".
function currentDelay(kind, settings) {
    var s = settings[kind];
    if (kind === "suspend") {
        if (s.action === ACTION_NONE)
            return 0;
    } else if (!s.enabled) {
        return 0;
    }
    return s.seconds > 0 ? s.seconds : 0;
}

// Never plus the usual delays; a delay set elsewhere (45 s from System Settings, say)
// is added so that the row can show it.
function delayChoices(current) {
    var values = [0].concat(DELAYS);
    if (current > 0 && values.indexOf(current) < 0) {
        values.push(current);
        values.sort(function (a, b) {
            return a - b;
        });
    }
    return values.map(function (v) {
        return {
            value: v,
            label: formatDelay(v)
        };
    });
}

// Offers "Don't change" and the profiles the system has; a profile that is stored but not
// offered (Performance on a machine without it) stays in the list so the row is not blank.
function profileChoices(hasPerformance, stored) {
    var list = [
        {
            value: "",
            label: "Don't change"
        },
        {
            value: "power-saver",
            label: "Power saver"
        },
        {
            value: "balanced",
            label: "Balanced"
        }
    ];
    if (hasPerformance || stored === "performance")
        list.push({
            value: "performance",
            label: "Performance"
        });
    if (stored && !list.some(function (c) {
        return c.value === stored;
    }))
        list.push({
            value: stored,
            label: stored
        });
    return list;
}

// Each change is {group, key, value} or {group, key, remove: true}.
function changesForDelay(kind, seconds, settings) {
    var dim = kind === "dim";
    if (kind === "suspend") {
        if (seconds <= 0)
            return [
                {
                    group: "SuspendAndShutdown",
                    key: "AutoSuspendAction",
                    value: String(ACTION_NONE)
                }
            ];
        // Keep hibernate or shutdown if that is what the user set; only "do nothing" becomes sleep.
        var action = settings.suspend.action !== ACTION_NONE ? settings.suspend.action : ACTION_SLEEP;
        return [
            {
                group: "SuspendAndShutdown",
                key: "AutoSuspendAction",
                value: String(action)
            },
            {
                group: "SuspendAndShutdown",
                key: "AutoSuspendIdleTimeoutSec",
                value: String(seconds)
            }
        ];
    }
    var flag = dim ? "DimDisplayWhenIdle" : "TurnOffDisplayWhenIdle";
    var secs = dim ? "DimDisplayIdleTimeoutSec" : "TurnOffDisplayIdleTimeoutSec";
    if (seconds <= 0)
        return [
            {
                group: "Display",
                key: flag,
                value: "false"
            }
        ];
    return [
        {
            group: "Display",
            key: flag,
            value: "true"
        },
        {
            group: "Display",
            key: secs,
            value: String(seconds)
        }
    ];
}

// "" means "Don't change", which is how powerdevil ships: the key goes away.
function changesForProfile(name) {
    if (!name)
        return [
            {
                group: "Performance",
                key: "PowerProfile",
                remove: true
            }
        ];
    return [
        {
            group: "Performance",
            key: "PowerProfile",
            value: name
        }
    ];
}

// Arguments for one kwriteconfig6 call.
function buildWriteArgs(profile, change) {
    var args = ["--file", "powerdevilrc", "--group", profile, "--group", change.group, "--key", change.key];
    if (change.remove)
        args.push("--delete");
    else
        args.push(change.value);
    return args;
}
