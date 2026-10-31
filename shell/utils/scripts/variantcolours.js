.pragma library

// What the Colors page reads to draw the swatch of each variant: one line per variant, the variant,
// a tab, and the scheme `caelestia scheme set --preview -v <variant>` printed on one line. A line
// that is not that, or whose scheme has no colours, leaves its variant out and the swatch of that
// variant stays a placeholder. No service or config dependencies, so it can be tested on its own.

function parse(text) {
    var colours = {};
    var lines = String(text === undefined || text === null ? "" : text).split("\n");

    for (var i = 0; i < lines.length; i++) {
        var tab = lines[i].indexOf("\t");
        if (tab <= 0)
            continue;

        var scheme = null;
        try {
            scheme = JSON.parse(lines[i].slice(tab + 1));
        } catch (e) {
            continue;
        }

        if (scheme && scheme.colours && typeof scheme.colours === "object")
            colours[lines[i].slice(0, tab)] = scheme.colours;
    }

    return colours;
}
