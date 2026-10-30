.pragma library

// A hex color as a person types it: with or without the #, in either case, and in the short form of
// three digits too (#abc is #aabbcc). normalise gives "#rrggbb" for what is a color and "" for what
// is not, so one call both checks and cleans. No service or config dependencies, so it can be
// tested on its own.

function normalise(text) {
    var hex = String(text === undefined || text === null ? "" : text).trim().replace(/^#/, "").toLowerCase();
    if (!/^([0-9a-f]{3}|[0-9a-f]{6})$/.test(hex))
        return "";
    if (hex.length === 3)
        hex = hex.charAt(0) + hex.charAt(0) + hex.charAt(1) + hex.charAt(1) + hex.charAt(2) + hex.charAt(2);
    return "#" + hex;
}
