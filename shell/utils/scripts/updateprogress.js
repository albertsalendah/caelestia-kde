.pragma library

// Pure logic for the Install Updates progress display: reading ninja's "[n/m]" lines, turning
// them into a bar position and keeping the on-screen log short. No service or config
// dependencies, so it can be tested on its own.

// Stage 4 of 5 ("Building the Caelestia shell UI...") starts at 0.8; the last stage is "done".
var BUILD_START = 0.8;
var BUILD_END = 0.99;

var HIDDEN_NOTE = "[Earlier output hidden. The full build output is in ~/.cache/caelestia-kde/shell-build.log]\n";

// 08-build-shell.sh prints this right before the compile. Configuring (cmake downloads
// m3shapes with a small ninja of its own, "[1/9] ...") happens before it, so only "[n/m]"
// lines seen after this one belong to the build of the shell.
function isBuildStart(line) {
    return /Building with \d+ parallel jobs/.test(line);
}

// "[12/345] Building CXX object ..." -> {current: 12, total: 345}, anything else -> null.
function parseBuildStep(line) {
    var m = /^\[(\d+)\/(\d+)\]\s/.exec(String(line).trim());
    if (!m)
        return null;
    var current = parseInt(m[1], 10);
    var total = parseInt(m[2], 10);
    if (total <= 0 || current > total)
        return null;
    return { current: current, total: total };
}

function buildProgress(step) {
    return BUILD_START + (BUILD_END - BUILD_START) * step.current / step.total;
}

// The bar never moves back: a stray line must not undo progress already shown.
function nextProgress(shown, step) {
    return Math.max(shown, buildProgress(step));
}

// Keeps the last `maxLines` lines of the log and starts with a note once something was cut.
// An earlier note is the first line, so it is cut with the rest and never stacks.
function capLog(text, maxLines) {
    var lines = text.split("\n");
    if (lines.length <= maxLines)
        return text;
    return HIDDEN_NOTE + lines.slice(lines.length - maxLines).join("\n");
}
