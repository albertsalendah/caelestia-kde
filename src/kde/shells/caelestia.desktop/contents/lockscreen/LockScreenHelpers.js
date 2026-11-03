.pragma library

// Plain-JavaScript helpers for the lock screen's replacements of three plasma-workspace modules
// (Caps Lock state, the keyboard layout button, the session actions). They only parse what
// shell commands print, so the tests can run them under node.

// Caps Lock: every keyboard with a Caps Lock LED has /sys/class/leds/<name>::capslock/brightness,
// which holds 1 while it is on. Any LED that is on means Caps Lock is on.
function capsLockOn(stdout) {
    var lines = String(stdout || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var text = lines[i].trim();
        if (text !== "" && Number(text) > 0)
            return true;
    }
    return false;
}

// What the system lets this session do. The probe prints one Name=value line for each of
// CanSuspend, CanHibernate, CanReboot and CanPowerOff (logind answers yes, no, na or challenge;
// challenge means it asks for authorisation, which the user can give) and SwitchUser=yes|no.
function parseCapabilities(stdout) {
    var values = {};
    var lines = String(stdout || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var match = /^\s*(\w+)=(\w*)\s*$/.exec(lines[i]);
        if (match)
            values[match[1]] = match[2];
    }
    var allowed = function (name) {
        return values[name] === "yes" || values[name] === "challenge";
    };
    return {
        suspend: allowed("CanSuspend"),
        hibernate: allowed("CanHibernate"),
        reboot: allowed("CanReboot"),
        shutdown: allowed("CanPowerOff"),
        switchUser: values.SwitchUser === "yes"
    };
}

function unquote(text) {
    return text.replace(/\\(["\\])/g, "$1");
}

// busctl prints getLayoutsList (a(sss)) as: a(sss) 2 "us" "English (US)" "English (US)" "ru" ...
function parseLayouts(stdout) {
    var strings = [];
    var re = /"((?:[^"\\]|\\.)*)"/g;
    var match;
    var text = String(stdout || "");
    while ((match = re.exec(text)) !== null)
        strings.push(unquote(match[1]));

    var layouts = [];
    for (var i = 0; i + 2 < strings.length; i += 3)
        layouts.push({ shortName: strings[i], displayName: strings[i + 1], longName: strings[i + 2] });
    return layouts;
}

// busctl prints a uint32 reply as: u 1
function parseUint(stdout) {
    var match = /^\s*u\s+(\d+)/.exec(String(stdout || ""));
    return match ? Number(match[1]) : 0;
}
