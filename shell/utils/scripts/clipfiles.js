.pragma library

// Clips that are files, for the clipboard popout. A file manager puts a list of
// file:// URLs on the clipboard. cliphist's preview of it is one line (the
// newlines become spaces) and is cut at a fixed width, so the popout reads the
// whole clip with `cliphist decode` when it can and falls back to the preview.
// No service or config dependencies, so it can be tested on its own.

var MAX_NAMES = 500;
var SCHEME = "file://";

var EXTENSIONS = {
    image: ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "ico", "tif", "tiff"],
    video: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg", "3gp", "ogv"],
    audio: ["mp3", "flac", "wav", "ogg", "oga", "m4a", "opus", "aac", "wma"],
    pdf: ["pdf"],
    archive: ["zip", "tar", "gz", "xz", "bz2", "7z", "rar", "zst", "tgz"],
    text: ["txt", "md", "json", "xml", "csv", "log", "ini", "conf", "yaml", "yml", "html", "css", "js", "qml", "py", "sh", "c", "cpp", "h", "hpp", "rs", "go", "ts", "java", "kt"]
};

var ICONS = {
    image: "image",
    video: "movie",
    audio: "audio_file",
    pdf: "picture_as_pdf",
    archive: "folder_zip",
    text: "description",
    file: "draft"
};

function isFileClip(text) {
    return typeof text === "string" && /^\s*file:\/\//.test(text);
}

// What a file is, from the end of its name: "image", "video", "audio", "pdf",
// "archive", "text" or "file" (anything else, and names with no extension).
function kindOf(name) {
    var dot = name.lastIndexOf(".");
    if (dot <= 0 || dot === name.length - 1)
        return "file";

    var ext = name.substring(dot + 1).toLowerCase();
    for (var kind in EXTENSIONS) {
        if (EXTENSIONS[kind].indexOf(ext) >= 0)
            return kind;
    }
    return "file";
}

// The Material icon for a kind from kindOf.
function iconFor(kind) {
    return ICONS[kind] || ICONS.file;
}

// The name of one file:// URL: the last path segment, decoded; "/" for the root.
// "" when the URL is not usable (a token the preview cut in the middle ends in an
// ellipsis).
function nameOf(url) {
    if (url.charAt(url.length - 1) === "\u2026")
        return "";

    var path = url.substring(SCHEME.length).replace(/\/+$/, "");
    if (path.length === 0)
        return url.length > SCHEME.length ? "/" : "";

    var last = path.substring(path.lastIndexOf("/") + 1);
    try {
        return decodeURIComponent(last);
    } catch (e) {
        return last;
    }
}

// The files in a clip's text, in order: { name, url, kind }. The URL is kept as
// it was copied (still percent-encoded), which is what an image source and the
// freedesktop thumbnail cache both want. URLs are separated by any whitespace,
// which is what both the newline form and the preview use.
function fileEntries(text) {
    var entries = [];
    if (!isFileClip(text))
        return entries;

    var tokens = text.split(/\s+/);
    for (var i = 0; i < tokens.length && entries.length < MAX_NAMES; i++) {
        if (tokens[i].indexOf(SCHEME) !== 0)
            continue;
        var name = nameOf(tokens[i]);
        if (name.length > 0)
            entries.push({ name: name, url: tokens[i], kind: kindOf(name) });
    }
    return entries;
}

// Just the names, in order.
function fileNames(text) {
    return fileEntries(text).map(function (entry) {
        return entry.name;
    });
}

// The sideways scroll of the file strip. A wheel step reports its distance in
// angleDelta; a touchpad swipe sideways fills x, an ordinary wheel only y. Both
// move the strip: positive towards the start, negative towards the end.
function wheelDelta(angleX, angleY) {
    return angleX !== 0 ? angleX : angleY;
}

// Where the strip goes for a wheel step of dx, when it can scroll "room" pixels
// in all. -1 means it cannot move that way (nothing to scroll, or already at the
// end the step points to), and the step belongs to the list around it instead.
function scrollStrip(contentX, room, dx) {
    if (room <= 0 || dx === 0)
        return -1;
    if ((dx > 0 && contentX <= 0) || (dx < 0 && contentX >= room))
        return -1;
    return Math.max(0, Math.min(room, contentX - dx));
}
