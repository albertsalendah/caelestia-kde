.pragma library

// Pure logic for the Nexus Display page: reading the monitors from
// `kscreen-doctor --json`, listing resolutions, refresh rates and scales, and
// building the `kscreen-doctor` arguments that apply or undo a change. It has no
// service or config dependencies so that it can be tested on its own.

var SCALE_PRESETS = [1, 1.25, 1.5, 1.75, 2, 2.5, 3];

function resolutionKey(mode) {
    return mode.width + "x" + mode.height;
}

// Connected monitors only; a disconnected one cannot be configured.
function parseOutputs(text) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return [];
    }
    var list = (data && data.outputs) || [];
    return list.filter(function (o) {
        return o && o.connected && o.name;
    }).map(function (o) {
        return {
            name: o.name,
            enabled: !!o.enabled,
            currentModeId: o.currentModeId !== undefined ? String(o.currentModeId) : "",
            scale: typeof o.scale === "number" ? o.scale : 1,
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
        };
    });
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
    return outputs.map(function (o) {
        return {
            name: o.name,
            enabled: o.enabled,
            modeId: o.currentModeId,
            scale: o.scale
        };
    });
}

// Returns "" when the change may be applied, otherwise a code:
// "unknown-output", "unknown-mode" or "last-enabled".
function validate(outputs, changes) {
    var byName = {};
    outputs.forEach(function (o) {
        byName[o.name] = o;
    });
    var enabledAfter = {};
    outputs.forEach(function (o) {
        enabledAfter[o.name] = o.enabled;
    });
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
        if (c.enabled !== undefined)
            enabledAfter[c.name] = !!c.enabled;
    }
    var anyEnabled = Object.keys(enabledAfter).some(function (n) {
        return enabledAfter[n];
    });
    return anyEnabled ? "" : "last-enabled";
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
        if (c.enabled === false)
            args.push(p + "disable");
    });
    return args;
}

// Arguments that put a snapshot back. A monitor that was off is only switched
// off again; its mode and scale are left alone.
function buildRevertArgs(previous) {
    return buildApplyArgs(previous.map(function (s) {
        return s.enabled ? {
            name: s.name,
            enabled: true,
            modeId: s.modeId,
            scale: s.scale
        } : {
            name: s.name,
            enabled: false
        };
    }));
}
