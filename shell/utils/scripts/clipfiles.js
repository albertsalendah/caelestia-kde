.pragma library

// Clips that are files, for the clipboard popout. A file manager puts a list of
// file:// URLs on the clipboard. cliphist's preview of it is one line (the
// newlines become spaces) and is cut at a fixed width, so the popout reads the
// whole clip with `cliphist decode` when it can and falls back to the preview.
// No service or config dependencies, so it can be tested on its own.

var MAX_NAMES = 500;

function isFileClip(text) {
    return typeof text === "string" && /^\s*file:\/\//.test(text);
}

// The name of one file:// URL: the last path segment, decoded; "/" for the root.
// "" when the URL is not usable (a token the preview cut in the middle ends in an
// ellipsis).
function nameOf(url) {
    if (url.charAt(url.length - 1) === "\u2026")
        return "";

    var scheme = "file://";
    var path = url.substring(scheme.length).replace(/\/+$/, "");
    if (path.length === 0)
        return url.length > scheme.length ? "/" : "";

    var last = path.substring(path.lastIndexOf("/") + 1);
    try {
        return decodeURIComponent(last);
    } catch (e) {
        return last;
    }
}

// The file names in a clip's text, in order. URLs are separated by any
// whitespace, which is what both the newline form and the preview use.
function fileNames(text) {
    var names = [];
    if (!isFileClip(text))
        return names;

    var tokens = text.split(/\s+/);
    for (var i = 0; i < tokens.length && names.length < MAX_NAMES; i++) {
        if (tokens[i].indexOf("file://") !== 0)
            continue;
        var name = nameOf(tokens[i]);
        if (name.length > 0)
            names.push(name);
    }
    return names;
}
