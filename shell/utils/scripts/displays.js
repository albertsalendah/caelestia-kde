.pragma library

// Pure logic for the Nexus Display page: reading the monitors from
// `kscreen-doctor --json`, listing resolutions, refresh rates and scales, and
// building the `kscreen-doctor` arguments that apply or undo a change. It has no
// service or config dependencies so that it can be tested on its own.
//
// The arrangement of the monitors (positions, which one is primary, which one copies another) is
// kept to rules that make every layout a valid one: no two monitors overlap and the monitors
// stay in one piece, so that the pointer can always cross from one to the next.
//
// Brightness is kept apart from the monitor list (parseBrightness): it changes while a slider is
// dragged, and a changed list rebuilds the rows of the page, slider included.
//
// It also reads the name of a monitor from its EDID, which the kernel exposes under
// /sys/class/drm: `kscreen-doctor --json` has no model field, System Settings gets its
// "Acer XV242Y" from the same place.

var SCALE_PRESETS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];

// kscreen-doctor's names for the orientations, and the numbers kscreen-doctor --json gives them
// (KScreen's Output::Rotation: None = 1, Left = 2, Inverted = 4, Right = 8).
var ROTATIONS = ["none", "left", "inverted", "right"];
var ROTATION_NUMBERS = {
    1: "none",
    2: "left",
    4: "inverted",
    8: "right"
};

// Dragging a slider to the end must not leave a screen black, so brightness does not go below this.
var MIN_BRIGHTNESS = 5;

function rotationName(value) {
    if (typeof value === "string" && ROTATIONS.indexOf(value) !== -1)
        return value;
    return ROTATION_NUMBERS[value] || "none";
}

function resolutionKey(mode) {
    return mode.width + "x" + mode.height;
}

// Connected monitors only; a disconnected one cannot be configured.
// pos is where the monitor is in the layout (logical pixels), priority 1 is the primary monitor,
// and mirrorOf is the name of the monitor this one copies ("" when it extends the desktop).
function parseOutputs(text) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return [];
    }
    var list = (data && data.outputs) || [];
    var parsed = list.filter(function (o) {
        return o && o.connected && o.name;
    }).map(function (o) {
        return {
            id: o.id,
            source: typeof o.replicationSource === "number" ? o.replicationSource : 0,
            out: {
                name: o.name,
                enabled: !!o.enabled,
                currentModeId: o.currentModeId !== undefined ? String(o.currentModeId) : "",
                scale: typeof o.scale === "number" ? o.scale : 1,
                rotation: rotationName(o.rotation),
                priority: typeof o.priority === "number" ? o.priority : 0,
                pos: {
                    x: o.pos && typeof o.pos.x === "number" ? Math.round(o.pos.x) : 0,
                    y: o.pos && typeof o.pos.y === "number" ? Math.round(o.pos.y) : 0
                },
                mirrorOf: "",
                modes: (o.modes || []).filter(function (m) {
                    return m && m.size;
                }).map(function (m) {
                    return {
                        id: String(m.id),
                        width: m.size.width,
                        height: m.size.height,
                        refresh: m.refreshRate
                    };
                })
            }
        };
    });
    parsed.forEach(function (p) {
        if (p.source === 0)
            return;
        var source = parsed.filter(function (q) {
            return q.id === p.source && q !== p;
        })[0];
        if (source)
            p.out.mirrorOf = source.out.name;
    });
    return parsed.map(function (p) {
        return p.out;
    });
}

// {"HDMI-A-1": 41}: the brightness of every connected monitor that reports one, in percent.
function parseBrightness(text) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return {};
    }
    var result = {};
    ((data && data.outputs) || []).forEach(function (o) {
        if (o && o.connected && o.name && typeof o.brightness === "number")
            result[o.name] = Math.round(Math.min(1, Math.max(0, o.brightness)) * 100);
    });
    return result;
}

// The slider's value (0 to 1) as a percentage kscreen-doctor accepts, never below MIN_BRIGHTNESS.
function brightnessPercent(value) {
    return Math.min(100, Math.max(MIN_BRIGHTNESS, Math.round(value * 100)));
}

// A copy of the brightness table with one monitor changed (a new object, so that bindings to it
// notice).
function withBrightness(table, name, percent) {
    var copy = {};
    Object.keys(table).forEach(function (n) {
        copy[n] = table[n];
    });
    copy[name] = percent;
    return copy;
}

// One kscreen-doctor argument per monitor: {"HDMI-A-1": 41} -> ["output.HDMI-A-1.brightness.41"].
function buildBrightnessArgs(table) {
    return Object.keys(table).map(function (n) {
        return "output." + n + ".brightness." + table[n];
    });
}

// ---- Arrangement ----

// The enabled monitor with the lowest priority number, "" when none is enabled.
function primaryName(outputs) {
    var best = null;
    outputs.forEach(function (o) {
        if (o.enabled && (best === null || o.priority < best.priority))
            best = o;
    });
    return best ? best.name : "";
}

// How big a monitor is in the layout: its mode divided by its scale, turned on its side when it
// is rotated left or right. Rounded the way Qt (and so KWin) rounds it.
function logicalSize(output) {
    var mode = currentMode(output);
    if (!mode)
        return {
            w: 0,
            h: 0
        };
    var scale = output.scale > 0 ? output.scale : 1;
    var w = Math.round(mode.width / scale);
    var h = Math.round(mode.height / scale);
    if (output.rotation === "left" || output.rotation === "right")
        return {
            w: h,
            h: w
        };
    return {
        w: w,
        h: h
    };
}

// What the arrangement is made of: the enabled monitors that extend the desktop. A monitor that
// copies another has no place of its own, and one that is off has none either.
function layoutRects(outputs) {
    var rects = [];
    outputs.forEach(function (o) {
        if (!o.enabled || o.mirrorOf !== "")
            return;
        var size = logicalSize(o);
        if (size.w > 0 && size.h > 0)
            rects.push({
                name: o.name,
                x: o.pos.x,
                y: o.pos.y,
                w: size.w,
                h: size.h
            });
    });
    return rects;
}

function overlaps(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

// Whether two monitors share part of an edge (meeting only at a corner does not count).
function touching(a, b) {
    var sideBySide = (a.x + a.w === b.x || b.x + b.w === a.x) && Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y) > 0;
    var stacked = (a.y + a.h === b.y || b.y + b.h === a.y) && Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x) > 0;
    return sideBySide || stacked;
}

function overlapsAny(rect, rects) {
    return rects.some(function (r) {
        return r.name !== rect.name && overlaps(rect, r);
    });
}

// Whether the monitors form one piece, each reaching the next through a shared edge.
function isConnected(rects) {
    if (rects.length < 2)
        return true;
    var seen = {};
    seen[rects[0].name] = true;
    var queue = [rects[0]];
    while (queue.length > 0) {
        var current = queue.shift();
        rects.forEach(function (r) {
            if (!seen[r.name] && touching(current, r)) {
                seen[r.name] = true;
                queue.push(r);
            }
        });
    }
    return Object.keys(seen).length === rects.length;
}

function layoutBounds(rects) {
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    rects.forEach(function (r) {
        minX = Math.min(minX, r.x);
        minY = Math.min(minY, r.y);
        maxX = Math.max(maxX, r.x + r.w);
        maxY = Math.max(maxY, r.y + r.h);
    });
    return {
        x: minX,
        y: minY,
        w: maxX - minX,
        h: maxY - minY
    };
}

// The area the canvas shows: the monitors with room around them to drag a monitor into.
function canvasView(rects) {
    if (rects.length === 0)
        return {
            x: 0,
            y: 0,
            w: 1,
            h: 1
        };
    var b = layoutBounds(rects);
    var widest = 0;
    var tallest = 0;
    rects.forEach(function (r) {
        widest = Math.max(widest, r.w);
        tallest = Math.max(tallest, r.h);
    });
    // Half a monitor of room on each side: enough to drop one next to the others, and the
    // rectangles stay as big as the canvas allows.
    var marginX = Math.round(widest * 0.5);
    var marginY = Math.round(tallest * 0.5);
    return {
        x: b.x - marginX,
        y: b.y - marginY,
        w: b.w + marginX * 2,
        h: b.h + marginY * 2
    };
}

// Canvas pixels per logical pixel, so that the whole view fits.
function fitScale(view, width, height) {
    return Math.min(width / view.w, height / view.h);
}

// Where a monitor that was dropped at (x, y) ends up: at the nearest place where it touches
// another monitor, overlaps none and leaves the monitors in one piece. It sits at the top,
// middle or bottom of the other's edge (left, middle or right of a top or bottom edge) when it
// is dropped within `snap` of that, and anywhere along the edge otherwise.
// `sides` ({otherName: "left"|"right"|"above"|"below"}, optional) keeps the monitor on the side
// of another monitor that it is on now: used when a monitor changes size, so that it does not
// jump to another side. Returns {x, y, changed}; a monitor that has no valid place stays where
// it was.
function snapLayout(rects, name, x, y, snap, sides) {
    var self = rects.filter(function (r) {
        return r.name === name;
    })[0];
    if (!self)
        return {
            x: x,
            y: y,
            changed: false
        };
    var others = rects.filter(function (r) {
        return r.name !== name;
    });
    var unchanged = {
        x: self.x,
        y: self.y,
        changed: false
    };
    if (others.length === 0)
        return unchanged;

    // A coordinate along an edge: held to the stretch where the two monitors still share the
    // edge, and pulled to an aligned value that is within `snap`.
    function along(free, low, high, aligned) {
        var value = Math.min(high, Math.max(low, free));
        var best = null;
        aligned.forEach(function (a) {
            if (Math.abs(a - value) <= snap && (best === null || Math.abs(a - value) < Math.abs(best - value)))
                best = a;
        });
        return best === null ? value : best;
    }

    var candidates = [];
    others.forEach(function (o) {
        var overlapY = Math.min(64, self.h, o.h);
        var overlapX = Math.min(64, self.w, o.w);
        var cy = along(y, o.y - self.h + overlapY, o.y + o.h - overlapY, [o.y, o.y + o.h - self.h, o.y + Math.round((o.h - self.h) / 2)]);
        var cx = along(x, o.x - self.w + overlapX, o.x + o.w - overlapX, [o.x, o.x + o.w - self.w, o.x + Math.round((o.w - self.w) / 2)]);
        var only = sides ? sides[o.name] : undefined;
        if (!only || only === "right")
            candidates.push({
                x: o.x + o.w,
                y: cy
            });
        if (!only || only === "left")
            candidates.push({
                x: o.x - self.w,
                y: cy
            });
        if (!only || only === "below")
            candidates.push({
                x: cx,
                y: o.y + o.h
            });
        if (!only || only === "above")
            candidates.push({
                x: cx,
                y: o.y - self.h
            });
    });

    var best = null;
    var bestDistance = Infinity;
    candidates.forEach(function (c) {
        var rect = {
            name: name,
            x: c.x,
            y: c.y,
            w: self.w,
            h: self.h
        };
        if (overlapsAny(rect, others) || !isConnected(others.concat([rect])))
            return;
        var distance = (c.x - x) * (c.x - x) + (c.y - y) * (c.y - y);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = c;
        }
    });
    if (best === null)
        return unchanged;
    return {
        x: best.x,
        y: best.y,
        changed: best.x !== self.x || best.y !== self.y
    };
}

// The monitors as they would be after the changes (a copy; the list is not touched).
function applyToOutputs(outputs, changes) {
    var after = JSON.parse(JSON.stringify(outputs));
    changes.forEach(function (c) {
        var o = after.filter(function (x) {
            return x.name === c.name;
        })[0];
        if (!o)
            return;
        if (c.enabled !== undefined)
            o.enabled = !!c.enabled;
        if (c.modeId !== undefined && c.modeId !== "")
            o.currentModeId = String(c.modeId);
        if (c.scale !== undefined)
            o.scale = c.scale;
        if (c.rotation !== undefined)
            o.rotation = c.rotation;
        if (c.pos !== undefined)
            o.pos = {
                x: c.pos.x,
                y: c.pos.y
            };
        if (c.mirror !== undefined)
            o.mirrorOf = c.mirror === "none" ? "" : c.mirror;
    });
    return after;
}

// Which side of `other` the monitor `rect` is on: "left", "right", "above" or "below" ("" when
// they overlap or sit diagonally).
function sideOf(rect, other) {
    if (rect.x + rect.w <= other.x)
        return "left";
    if (other.x + other.w <= rect.x)
        return "right";
    if (rect.y + rect.h <= other.y)
        return "above";
    if (other.y + other.h <= rect.y)
        return "below";
    return "";
}

// A place at the right end of the layout, level with the monitor that is furthest right: always
// valid. Used for a monitor that comes back (turned on, or no longer copying).
function placeAtEnd(rects, name) {
    var others = rects.filter(function (r) {
        return r.name !== name;
    });
    var self = rects.filter(function (r) {
        return r.name === name;
    })[0];
    if (!self || others.length === 0)
        return {
            x: self ? self.x : 0,
            y: self ? self.y : 0,
            changed: false
        };
    var last = others[0];
    others.forEach(function (r) {
        if (r.x + r.w > last.x + last.w)
            last = r;
    });
    return {
        x: last.x + last.w,
        y: last.y,
        changed: true
    };
}

// The changes, plus a new position for a monitor that the changes would leave on top of another
// monitor or cut off from the rest, so that the layout stays valid without the user fixing it by
// hand. A monitor whose size changed (mode, scale, orientation) stays on the same side of its
// neighbours and moves just as far as it has to. A monitor that comes back (turned on, no longer
// copying) goes to the right end of the layout.
function settleLayout(outputs, changes) {
    var before = layoutRects(outputs);
    var after = applyToOutputs(outputs, changes);
    var rects = layoutRects(after);
    var result = changes.slice();
    var settled = {};
    changes.forEach(function (c) {
        if (c.pos !== undefined || settled[c.name])
            return;
        var resized = c.modeId !== undefined || c.scale !== undefined || c.rotation !== undefined;
        var returned = c.enabled === true || c.mirror === "none";
        if (!resized && !returned)
            return;
        var rect = rects.filter(function (r) {
            return r.name === c.name;
        })[0];
        if (!rect || (!overlapsAny(rect, rects) && isConnected(rects)))
            return;

        var snapped;
        var old = before.filter(function (r) {
            return r.name === c.name;
        })[0];
        if (resized && old) {
            var sides = {};
            rects.forEach(function (r) {
                if (r.name !== c.name)
                    sides[r.name] = sideOf(old, r);
            });
            snapped = snapLayout(rects, c.name, rect.x, rect.y, 0, sides);
            if (!snapped.changed)
                snapped = snapLayout(rects, c.name, rect.x, rect.y, 0);
        } else {
            snapped = placeAtEnd(rects, c.name);
        }
        if (!snapped.changed)
            return;
        settled[c.name] = true;
        rect.x = snapped.x;
        rect.y = snapped.y;
        result.push({
            name: c.name,
            pos: {
                x: snapped.x,
                y: snapped.y
            }
        });
    });
    return normalizeLayout(outputs, result);
}

// KWin refuses a negative position for a monitor that is on, so a layout with a monitor to the
// left of or above the one at 0,0 cannot be sent as it is. Like KScreen does, every monitor that
// is on is moved by the same amount so that the top left of the layout is 0,0: the arrangement
// is the same, only the numbers are different.
function normalizeLayout(outputs, changes) {
    var after = applyToOutputs(outputs, changes);
    var on = after.filter(function (o) {
        return o.enabled;
    });
    if (on.length === 0)
        return changes;
    var minX = Math.min.apply(null, on.map(function (o) {
        return o.pos.x;
    }));
    var minY = Math.min.apply(null, on.map(function (o) {
        return o.pos.y;
    }));
    if (minX >= 0 && minY >= 0)
        return changes;
    var shiftX = Math.min(0, minX);
    var shiftY = Math.min(0, minY);
    var names = {};
    on.forEach(function (o) {
        names[o.name] = true;
    });
    var result = changes.filter(function (c) {
        return !(c.pos !== undefined && names[c.name]);
    });
    on.forEach(function (o) {
        var place = {
            x: o.pos.x - shiftX,
            y: o.pos.y - shiftY
        };
        var before = outputs.filter(function (q) {
            return q.name === o.name;
        })[0];
        if (!before || before.pos.x !== place.x || before.pos.y !== place.y)
            result.push({
                name: o.name,
                pos: place
            });
    });
    return result;
}

// Making a monitor primary. A monitor that copied the old primary copies the new one. A monitor
// that is copying cannot be primary: it stops copying first.
function primaryChanges(outputs, name) {
    var current = primaryName(outputs);
    var target = outputs.filter(function (o) {
        return o.name === name;
    })[0];
    var first = {
        name: name,
        primary: true
    };
    if (target && target.mirrorOf !== "")
        first.mirror = "none";
    var changes = [first];
    outputs.forEach(function (o) {
        if (o.name !== name && o.enabled && o.mirrorOf !== "" && o.mirrorOf === current)
            changes.push({
                name: o.name,
                mirror: name
            });
    });
    return changes;
}

// Copy the primary monitor, or go back to extending the desktop.
function copyChanges(outputs, name, copy) {
    return [
        {
            name: name,
            mirror: copy ? primaryName(outputs) : "none"
        }
    ];
}

// Whether kscreen-doctor's output is a monitor listing at all. A reading that failed or was cut
// short (the machine was busy) is not, and must not replace the monitors the page shows.
function isListing(text) {
    try {
        var data = JSON.parse(text);
        return !!data && Array.isArray(data.outputs);
    } catch (e) {
        return false;
    }
}

// Prints "changed" whenever a monitor port is plugged or unplugged: it looks at the status of
// every connector (connected or not, from /sys/class/drm) every few seconds, reading files only,
// and says something only when that is different from the last time. Run as
// `bash -c <script> hotplug /sys/class/drm 2`; the folder and the pause are arguments so that a
// test can use a copy and a short pause.
var HOTPLUG_SCRIPT = [
    'dir="$1"; every="$2"',
    'state() {',
    '    for f in "$dir"/card*-*/status; do',
    '        [ -r "$f" ] || continue',
    '        read -r s < "$f"',
    '        printf "%s=%s " "${f%/status}" "$s"',
    '    done',
    '}',
    'last="$(state)"',
    'while sleep "$every"; do',
    '    now="$(state)"',
    '    if [ "$now" != "$last" ]; then',
    '        last="$now"',
    '        echo changed',
    '    fi',
    'done'
].join("\n");

// Whether two parsed monitor lists are the same, so that the page only rebuilds its rows when
// something it shows has changed (plugging or unplugging a monitor, or a change made elsewhere).
function sameOutputs(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
}

// ---- Monitor names (EDID) ----

// Prints "<connector> <first 128 bytes of its EDID as hex>" for every connector that has one.
// Run as `bash -c <script> edid /sys/class/drm`; the folder is an argument so that a test can
// point it at a copy. A connector with nothing plugged in has an empty edid file and prints
// nothing.
var EDID_SCRIPT = [
    'for d in "$1"/card*-*; do',
    '    [ -r "$d/edid" ] || continue',
    '    n="${d##*/}"',
    '    n="${n#card*-}"',
    '    h="$(od -An -tx1 -v -N128 "$d/edid" 2>/dev/null | tr -d " \\n")"',
    '    [ -n "$h" ] && printf "%s %s\\n" "$n" "$h"',
    'done'
].join("\n");

// The three-letter manufacturer codes of common monitor makers. An unknown code is not shown.
var VENDORS = {
    ACR: "Acer",
    AOC: "AOC",
    APP: "Apple",
    AUS: "ASUS",
    BNQ: "BenQ",
    DEL: "Dell",
    EIZ: "Eizo",
    GBT: "Gigabyte",
    GSM: "LG",
    HPN: "HP",
    HWP: "HP",
    IVM: "Iiyama",
    LEN: "Lenovo",
    MSI: "MSI",
    NEC: "NEC",
    PHL: "Philips",
    SAM: "Samsung",
    SNY: "Sony",
    VSC: "ViewSonic"
};

// The 128 bytes of the base block, or null when the text is too short or not hex.
function edidBytes(hex) {
    var clean = String(hex).replace(/\s/g, "");
    if (clean.length < 256 || /[^0-9a-fA-F]/.test(clean.slice(0, 256)))
        return null;
    var bytes = [];
    for (var i = 0; i < 128; i++)
        bytes.push(parseInt(clean.substr(i * 2, 2), 16));
    return bytes;
}

// {vendor: "ACR", model: "XV242Y"} from the hex of an EDID, or null when it is not one.
// vendor is "" when the code is not three letters; model is "" when the monitor gives no name
// (a laptop panel usually only has a part number, which is not shown).
function decodeEdid(hex) {
    var b = edidBytes(hex);
    if (!b)
        return null;
    var header = [0, 255, 255, 255, 255, 255, 255, 0];
    for (var h = 0; h < 8; h++) {
        if (b[h] !== header[h])
            return null;
    }

    var id = (b[8] << 8) | b[9];
    var vendor = String.fromCharCode(((id >> 10) & 31) + 64, ((id >> 5) & 31) + 64, (id & 31) + 64);
    if (!/^[A-Z]{3}$/.test(vendor))
        vendor = "";

    // Four 18-byte descriptors; "00 00 00 fc 00" starts the monitor name, ended by a newline.
    var model = "";
    [54, 72, 90, 108].forEach(function (at) {
        if (model !== "" || b[at] !== 0 || b[at + 1] !== 0 || b[at + 2] !== 0 || b[at + 3] !== 0xfc)
            return;
        var text = "";
        for (var i = at + 5; i < at + 18 && b[i] !== 0x0a; i++) {
            if (b[i] >= 32 && b[i] < 127)
                text += String.fromCharCode(b[i]);
        }
        model = text.trim();
    });
    return {
        vendor: vendor,
        model: model
    };
}

// The output of EDID_SCRIPT as {"HDMI-A-1": {vendor, model}}; lines that are not an EDID are skipped.
function parseEdidList(text) {
    var result = {};
    String(text).split("\n").forEach(function (line) {
        var at = line.indexOf(" ");
        if (at <= 0)
            return;
        var decoded = decodeEdid(line.slice(at + 1));
        if (decoded)
            result[line.slice(0, at)] = decoded;
    });
    return result;
}

// A laptop's own panel: it is shown as "Built-in Screen" whatever its EDID says.
function isBuiltIn(name) {
    return /^(eDP|LVDS|DSI)/i.test(name);
}

// "Acer XV242Y": the maker's name and the model, or just the model when it already starts with
// the maker's name ("DELL U2720Q"), or "" when the monitor gives no name.
function modelName(name, edids) {
    var e = edids && edids[name];
    if (!e || e.model === "")
        return "";
    var vendor = VENDORS[e.vendor] || "";
    if (vendor !== "" && e.model.toLowerCase().indexOf(vendor.toLowerCase()) !== 0)
        return vendor + " " + e.model;
    return e.model;
}

function currentMode(output) {
    for (var i = 0; i < output.modes.length; i++) {
        if (output.modes[i].id === output.currentModeId)
            return output.modes[i];
    }
    return null;
}

function currentResolutionKey(output) {
    var m = currentMode(output);
    return m ? resolutionKey(m) : "";
}

// Largest first.
function resolutionsOf(output) {
    var seen = {};
    var list = [];
    output.modes.forEach(function (m) {
        var key = resolutionKey(m);
        if (seen[key])
            return;
        seen[key] = true;
        list.push({
            key: key,
            width: m.width,
            height: m.height,
            label: m.width + " \u00d7 " + m.height
        });
    });
    list.sort(function (a, b) {
        return (b.width * b.height - a.width * a.height) || (b.width - a.width);
    });
    return list;
}

function formatRefresh(rate) {
    return (Math.round(rate * 100) / 100) + " Hz";
}

// Fastest first. Two modes that read the same (for example 1280x720 at 60 Hz
// listed twice) show once; the current mode wins that tie so that it stays
// selectable, then the lower id.
function refreshRatesFor(output, key) {
    var seen = {};
    var list = [];
    output.modes.filter(function (m) {
        return resolutionKey(m) === key;
    }).sort(function (a, b) {
        var byRate = b.refresh - a.refresh;
        if (Math.abs(byRate) > 0.005)
            return byRate;
        var aCur = a.id === output.currentModeId ? 0 : 1;
        var bCur = b.id === output.currentModeId ? 0 : 1;
        return (aCur - bCur) || (Number(a.id) - Number(b.id));
    }).forEach(function (m) {
        var label = formatRefresh(m.refresh);
        if (seen[label])
            return;
        seen[label] = true;
        list.push({
            id: m.id,
            refresh: m.refresh,
            label: label
        });
    });
    return list;
}

// The mode id at a resolution whose refresh rate is closest to the current one,
// so that changing the resolution keeps the rate where the monitor allows it.
function bestModeId(output, key) {
    var cur = currentMode(output);
    var target = cur ? cur.refresh : 60;
    var best = null;
    output.modes.forEach(function (m) {
        if (resolutionKey(m) !== key)
            return;
        var dist = Math.abs(m.refresh - target);
        if (best === null || dist < best.dist - 0.005)
            best = {
                id: m.id,
                dist: dist
            };
    });
    return best ? best.id : "";
}

function sameScale(a, b) {
    return Math.abs(a - b) < 0.005;
}

// A scale below 100% is expensive on weak graphics (kwin_wayland used half a CPU on the test
// laptop with it), so the Scale row says so.
function belowFullScale(scale) {
    return scale < 0.995;
}

// What kscreen-doctor said when KWin refused a change, cut down to a line or two for the page:
// colour codes and empty lines removed, the last three lines kept (the reason is at the end),
// at most 240 characters.
function errorDetail(text) {
    var lines = String(text || "").replace(/\u001b\[[0-9;]*m/g, "").split("\n").map(function (line) {
        return line.trim();
    }).filter(function (line) {
        return line !== "";
    });
    var detail = lines.slice(-3).join(" ");
    return detail.length > 240 ? detail.slice(0, 239) + "\u2026" : detail;
}

function formatScale(scale) {
    return String(Math.round(scale * 100) / 100);
}

// The presets, plus the current scale when it is not one of them.
function scalePresets(current) {
    var values = SCALE_PRESETS.slice();
    var known = values.some(function (v) {
        return sameScale(v, current);
    });
    if (!known) {
        values.push(Math.round(current * 100) / 100);
        values.sort(function (a, b) {
            return a - b;
        });
    }
    return values.map(function (v) {
        return {
            value: v,
            label: Math.round(v * 100) + "%"
        };
    });
}

// What each connected monitor looks like now, to put back if a change is not kept.
function snapshot(outputs) {
    var primary = primaryName(outputs);
    return outputs.map(function (o) {
        return {
            name: o.name,
            enabled: o.enabled,
            modeId: o.currentModeId,
            scale: o.scale,
            rotation: o.rotation,
            pos: {
                x: o.pos.x,
                y: o.pos.y
            },
            mirrorOf: o.mirrorOf,
            primary: o.name === primary
        };
    });
}

// Returns "" when the change may be applied, otherwise a code: "unknown-output",
// "unknown-mode", "unknown-rotation", "invalid-position", "invalid-mirror", "overlap" or
// "last-enabled".
function validate(outputs, changes) {
    var byName = {};
    outputs.forEach(function (o) {
        byName[o.name] = o;
    });
    var enabledAfter = {};
    var mirrorAfter = {};
    outputs.forEach(function (o) {
        enabledAfter[o.name] = o.enabled;
        mirrorAfter[o.name] = o.mirrorOf;
    });
    var copiers = [];
    var positioned = [];
    for (var i = 0; i < changes.length; i++) {
        var c = changes[i];
        var out = byName[c.name];
        if (!out)
            return "unknown-output";
        if (c.modeId !== undefined && c.modeId !== "") {
            var found = out.modes.some(function (m) {
                return m.id === String(c.modeId);
            });
            if (!found)
                return "unknown-mode";
        }
        if (c.rotation !== undefined && ROTATIONS.indexOf(c.rotation) === -1)
            return "unknown-rotation";
        if (c.pos !== undefined) {
            if (!c.pos || typeof c.pos.x !== "number" || typeof c.pos.y !== "number" || !isFinite(c.pos.x) || !isFinite(c.pos.y))
                return "invalid-position";
            positioned.push(c.name);
        }
        if (c.enabled !== undefined)
            enabledAfter[c.name] = !!c.enabled;
        if (c.mirror !== undefined) {
            if (c.mirror !== "none" && (c.mirror === c.name || !byName[c.mirror]))
                return "invalid-mirror";
            mirrorAfter[c.name] = c.mirror === "none" ? "" : c.mirror;
            if (c.mirror !== "none")
                copiers.push(c.name);
        }
    }

    // A monitor copies one that is on and is not copying anything itself, and nothing copies a
    // monitor that copies another (one step only).
    var badCopy = copiers.some(function (name) {
        var target = mirrorAfter[name];
        if (!enabledAfter[target] || mirrorAfter[target] !== "")
            return true;
        return Object.keys(mirrorAfter).some(function (other) {
            return enabledAfter[other] && mirrorAfter[other] === name;
        });
    });
    if (badCopy)
        return "invalid-mirror";

    var anyEnabled = Object.keys(enabledAfter).some(function (n) {
        return enabledAfter[n];
    });
    if (!anyEnabled)
        return "last-enabled";

    // A position that was asked for must not put a monitor on top of another.
    if (positioned.length > 0) {
        var rects = layoutRects(applyToOutputs(outputs, changes));
        var clash = positioned.some(function (name) {
            var rect = rects.filter(function (r) {
                return r.name === name;
            })[0];
            return rect && overlapsAny(rect, rects);
        });
        if (clash)
            return "overlap";
    }
    return "";
}

// Arguments for one atomic `kscreen-doctor` call.
function buildApplyArgs(changes) {
    var args = [];
    changes.forEach(function (c) {
        var p = "output." + c.name + ".";
        if (c.enabled === true)
            args.push(p + "enable");
        if (c.modeId !== undefined && c.modeId !== "")
            args.push(p + "mode." + c.modeId);
        if (c.scale !== undefined)
            args.push(p + "scale." + formatScale(c.scale));
        if (c.rotation !== undefined)
            args.push(p + "rotation." + c.rotation);
        if (c.pos !== undefined)
            args.push(p + "position." + c.pos.x + "," + c.pos.y);
        if (c.mirror !== undefined)
            args.push(p + "mirror." + c.mirror);
        if (c.primary === true)
            args.push(p + "primary");
        if (c.enabled === false)
            args.push(p + "disable");
    });
    return args;
}

// Arguments that put a snapshot back. A monitor that was off is only switched
// off again; its mode, scale, orientation and place are left alone.
function buildRevertArgs(previous) {
    return buildApplyArgs(previous.map(function (s) {
        return s.enabled ? {
            name: s.name,
            enabled: true,
            modeId: s.modeId,
            scale: s.scale,
            rotation: s.rotation,
            pos: s.pos,
            mirror: s.mirrorOf === "" ? "none" : s.mirrorOf,
            primary: s.primary ? true : undefined
        } : {
            name: s.name,
            enabled: false
        };
    }));
}
