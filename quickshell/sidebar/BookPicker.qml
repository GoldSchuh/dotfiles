import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Popup clone of the "bookshelfs" Nextcloud app (github.com/Goldschuh/
// bookshelfs) acting as a book picker. Everything from the repo is built in:
//   - Nav (Nav.vue/Form.vue): create form, "Add book from file",
//     "Restyle Shelf" / "Reset Shelf" settings
//   - Shelf (Shelf.vue): book spines with colour/pattern/height, vertical
//     gold title + goldenrod author, shelf planks, drag to reorder,
//     hover cover preview, click to select, double click to open the file
//   - Sidebar (Sidebar.vue): edit form with "Update book" / "Delete book"
// Data model is Book.ts (id, title, author, position, url, file, colour,
// pattern, height).
//
// Storage mirrors the Nextcloud file-ID model, but portable: picked covers
// and e-books are COPIED into the managed library dir (configDir/bookshelfs,
// gitignored) under generated names ("<id>-cover.png", "<id>.epub") and the
// shelf data (shelf.json, same dir) only stores those names — never paths.
// The portal FileDialog cannot open under a layer-shell parent, so picking
// goes through the built-in FileBrowser panel instead. Epub title/author
// are extracted from the OPF metadata like upstream's extractor.
PanelWindow {
    id: picker

    required property var shell

    property bool open: false
    property var popup: picker
    property var books: []
    property int nextId: 1
    property var selected: null

    // Drag-reorder state: the dragged book visually displaces the others
    // between its old slot and the slot under the cursor, like vuedraggable.
    property bool dragActive: false
    property int dragIndex: -1
    property int previewIndex: -1
    property bool gotFocusOnce: false

    readonly property int navWidth: 250
    readonly property int editorWidth: 272
    readonly property int headerHeight: 40
    readonly property int rowStep: 300
    readonly property int slotWidth: 55

    // Managed library: lives inside the config repo but is gitignored, so
    // the shelf data itself stays path-free and can land on GitHub.
    readonly property string libraryDir: urlToPath(Quickshell.shellDir) + "/bookshelfs"
    readonly property var imageFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
    readonly property var ebookFilters: ["*.epub", "*.pdf"]
    property var pickCallback: null
    property var _prevFocus: null

    // Test/theming aid: force every book into its lifted (hover) pose.
    property bool debugLift: false
    // Test aid: pretend this book index is the hover winner.
    property int debugHoverIndex: -1

    // Topmost-book-wins hover arbitration, like CSS :hover in the repo:
    // every book claims the cursor while its own (transform-following)
    // MouseArea contains it; the highest-priority claim wins — dragged >
    // lifted > flat, ties broken by paint order. Exactly one book is
    // hovered, it holds while the cursor rests anywhere on its visual
    // (spine or swung-out cover), and drops when the cursor leaves it.
    property var hoverClaims: ({})
    property int hoverWinner: -1

    function setHoverClaim(index, prio, on) {
        var c = hoverClaims
        if (on) {
            if (c[index] === prio) return
            c[index] = prio
        } else {
            if (c[index] === undefined) return
            delete c[index]
        }
        hoverClaims = c
        updateHoverWinner()
    }

    function updateHoverWinner() {
        var best = -1
        var bestPrio = -1
        for (var k in hoverClaims) {
            var i = parseInt(k)
            var p = hoverClaims[k]
            if (p > bestPrio || (p === bestPrio && i > best)) {
                bestPrio = p
                best = i
            }
        }
        if (hoverWinner !== best) hoverWinner = best
    }

    onBooksChanged: {
        hoverClaims = {}
        updateHoverWinner()
    }
    readonly property int rowCount: {
        var n = Math.max(picker.books.length, 1)
        return picker.slotFor(n - 1).row + 1
    }

    anchors { left: true; top: true }
    implicitWidth: 980
    implicitHeight: 540
    margins {
        left: shell.sidebarGap + shell.sidebarWidth + 8
        top: Math.max(8, (screen.height - implicitHeight) / 2)
    }
    exclusiveZone: 0
    visible: false
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bookpicker"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
        picker.open = visible
        if (visible) {
            // Re-arm the focus retry so typing works on every open.
            picker.gotFocusOnce = false
            focusTimer.start()
        } else focusTimer.stop()
    }

    Shortcut {
        sequence: "Escape"
        enabled: picker.visible
        onActivated: {
            if (fileBrowser.open) cancelBrowser()
            else if (picker.selected) picker.selected = null
            else picker.close()
        }
    }

    Timer {
        id: focusTimer
        interval: 50
        repeat: true
        onTriggered: {
            if (!picker.visible || picker.gotFocusOnce) {
                stop()
                return
            }
            if (picker._backingWindow)
                picker._backingWindow.requestActivate()
            createForm.firstField.forceActiveFocus(Qt.PopupFocusReason)
            if (createForm.firstField.activeFocus) {
                picker.gotFocusOnce = true
                stop()
            }
        }
    }

    Process {
        id: ensureDir
        command: ["mkdir", "-p", picker.libraryDir]
        running: true
        onExited: function(exitCode) {
            // Load only once the library dir exists so the first-ever
            // seed/migration save cannot race the mkdir.
            if (exitCode === 0 && !picker.loaded)
                picker.loadShelf()
        }
    }

    FileView {
        id: store
        path: picker.libraryDir + "/shelf.json"
        blockLoading: true
        printErrors: true
    }

    // Pre-library data (~/.local/share/quickshell/bookshelfs.json) used as a
    // one-time fallback when the new shelf.json does not exist yet.
    FileView {
        id: legacyStore
        path: Quickshell.env("HOME") + "/.local/share/quickshell/bookshelfs.json"
        blockLoading: true
        printErrors: false
    }

    // Single serialised worker for every library file operation (cp, rm,
    // epub/pdf extraction): quickshell Process is single-command, and rapid
    // user actions (e.g. create with cover + file, or a migration importing
    // an old cover and its book) must never run concurrently or reorder.
    property var jobQueue: []
    property bool loaded: false

    Process {
        id: jobProc
        property var onDone: null
        property string lastText: ""
        command: []
        stdout: StdioCollector {
            onStreamFinished: jobProc.lastText = text
        }
        onExited: function(exitCode) {
            // The ONLY chaining point: deliver this job's result, then start
            // the next queued job. (Chaining from the job callback as well
            // started a second job while the first was still being finished
            // off — whenever two or more jobs were queued the second call
            // overwrote onDone and swapped command, crossing callbacks and
            // dropping a job's result.)
            var cb = onDone
            onDone = null
            var out = lastText
            lastText = ""
            if (cb) cb(exitCode === 0, out)
            picker.nextJob()
        }
    }

    function runJob(argv, cb) {
        jobQueue.push({ argv: argv, cb: cb })
        if (!jobProc.running) nextJob()
    }

    function nextJob() {
        // running-guard: a job callback can enqueue work via runJob while
        // onExited is still running; starting then would clobber the
        // just-started job's onDone and cross its results.
        if (jobProc.running || jobQueue.length === 0) return
        var j = jobQueue.shift()
        jobProc.lastText = ""   // never deliver a previous job's output
        jobProc.command = j.argv
        jobProc.onDone = j.cb
        jobProc.running = true
    }

    // Copies src into the library under destName; cb receives the stored
    // name on success or "" on failure.
    function importFile(srcPath, destName, cb) {
        runJob(["cp", "--", srcPath, libraryDir + "/" + destName], function(ok) {
            if (cb) cb(ok ? destName : "")
        })
    }

    // Deletes library entries by stored name (ignores paths and empties).
    function removeLib(names) {
        var args = ["rm", "-f", "--"]
        for (var i = 0; i < names.length; i++) {
            var n = names[i]
            if (n && n !== "" && n !== "-1" && !n.startsWith("/"))
                args.push(libraryDir + "/" + n)
        }
        if (args.length > 3) runJob(args, null)
    }

    // EbookFileService.php pipeline for an imported book file: extracts
    // metadata (title/author) and the cover image, writes the cover to the
    // library and applies the results to the book. mode: "overwrite" fills
    // title/author from the file (add-from-file), "fillEmpty" only fills
    // blanks (create with file), "coverOnly" only sets a cover when the
    // book has none (file replaced on update).
    function processBookFile(book, srcPath, mode) {
        var dest = libraryDir + "/" + book.id + "-cover"
        runJob(["sh", "-c", extractScript, "sh", srcPath, dest, extOf(srcPath)], function(ok, text) {
            var lines = (text || "").split("\n")
            var title = (lines[0] || "").trim()
            var author = (lines[1] || "").trim()
            var covext = (lines[2] || "").trim()
            var changed = false
            if (covext !== "" && (mode !== "coverOnly" || !book.url || book.url === "")) {
                var newName = dest.substring(libraryDir.length + 1) + "." + covext
                // Drop the superseded cover (e.g. the previously imported
                // cover or picked image had a different extension, or this
                // extraction supersedes a picked cover) so the library never
                // accumulates orphaned <id>-cover.* files.
                if (book.url && book.url !== newName && !book.url.startsWith("/"))
                    removeLib([book.url])
                book.url = newName
                changed = true
            }
            if (mode === "overwrite") {
                if (title !== "") { book.title = unescapeXml(title); changed = true }
                if (author !== "") { book.author = unescapeXml(author); changed = true }
            } else if (mode === "fillEmpty") {
                if (title !== "" && book.title === "") { book.title = unescapeXml(title); changed = true }
                if (author !== "" && book.author === "") { book.author = unescapeXml(author); changed = true }
            }
            if (changed) {
                picker.books = picker.books.slice()
                save()
                if (picker.selected === book && covext !== "") editForm.setCover(book.url)
            }
        })
    }

    // "$1" = book file, "$2" = cover destination base (extensionless),
    // "$3" = lowercase file extension. Prints: line 1 title, line 2 author,
    // line 3 cover extension ("" when no cover was found); writes the cover
    // image to "$2.$ext" when one was found.
    property string extractScript:
        "book=\"$1\"; dest=\"$2\"; ext=\"$3\"\n" +
        "title=\"\"; author=\"\"; covext=\"\"\n" +
        "if [ \"$ext\" = \"epub\" ]; then\n" +
        "  opfpath=$(unzip -p \"$book\" META-INF/container.xml 2>/dev/null | sed -n 's/.*full-path=\"\\([^\"]*\\)\".*/\\1/p' | head -n 1)\n" +
        "  if [ -n \"$opfpath\" ]; then\n" +
        "    opf=$(unzip -p \"$book\" \"$opfpath\" 2>/dev/null | tr -d '\\n')\n" +
        "    title=$(printf '%s' \"$opf\" | grep -o '<dc:title[^>]*>[^<]*' | head -n 1 | sed 's/<[^>]*>//')\n" +
        "    author=$(printf '%s' \"$opf\" | grep -o '<dc:creator[^>]*>[^<]*' | head -n 1 | sed 's/<[^>]*>//')\n" +
        "    metatag=$(printf '%s' \"$opf\" | grep -o '<meta[^>]*>' | head -n 1)\n" +
        "    case \"$metatag\" in *name=\"cover\"*|*property=\"cover-image\"*) coverid=$(printf '%s' \"$metatag\" | sed 's/.*content=\"//;s/\".*//') ;; esac\n" +
        "    coverhref=\"\"\n" +
        "    if [ -n \"$coverid\" ]; then\n" +
        "      coverhref=$(printf '%s' \"$opf\" | grep -o \"<item[^>]*id=\\\"$coverid\\\"[^>]*\" | head -n 1 | sed 's/.*href=\"//;s/\".*//')\n" +
        "    fi\n" +
        "    if [ -z \"$coverhref\" ]; then\n" +
        "      coverhref=$(printf '%s' \"$opf\" | grep -o '<item[^>]*properties=\"[^\"]*cover-image[^\"]*\"[^>]*' | head -n 1 | sed 's/.*href=\"//;s/\".*//')\n" +
        "    fi\n" +
        "    if [ -z \"$coverhref\" ]; then\n" +
        "      coverhref=$(printf '%s' \"$opf\" | grep -o '<item[^>]*media-type=\"image/[^s][^\"]*\"[^>]*' | head -n 1 | sed 's/.*href=\"//;s/\".*//')\n" +
        "    fi\n" +
        "    if [ -n \"$coverhref\" ]; then\n" +
        "      dir=${opfpath%/*}\n" +
        "      if [ \"$dir\" = \"$opfpath\" ]; then\n" +
        "        zippath=\"$coverhref\"\n" +
        "      else\n" +
        "        zippath=\"$dir/$coverhref\"\n" +
        "      fi\n" +
        "      unzip -p \"$book\" \"$zippath\" > \"$dest.raw\" 2>/dev/null\n" +
        "    fi\n" +
        "  fi\n" +
        "elif [ \"$ext\" = \"pdf\" ]; then\n" +
        "  if command -v pdfinfo >/dev/null 2>&1; then\n" +
        "    title=$(pdfinfo \"$book\" 2>/dev/null | sed -n 's/^Title:[[:space:]]*//p' | head -n 1)\n" +
        "    author=$(pdfinfo \"$book\" 2>/dev/null | sed -n 's/^Author:[[:space:]]*//p' | head -n 1)\n" +
        "  fi\n" +
        "  if command -v pdftoppm >/dev/null 2>&1; then\n" +
        "    pdftoppm -png -singlefile -f 1 -l 1 -scale-to 280 \"$book\" \"$dest\" 2>/dev/null\n" +
        "  fi\n" +
        "  # pdftoppm writes \"$dest.png\" directly (no .raw detour like the\n" +
        "  # epub branch); without reporting covext the cover was written but\n" +
        "  # never linked into book.url.\n" +
        "  if [ -s \"$dest.png\" ]; then covext=png; fi\n" +
        "fi\n" +
        "if [ -s \"$dest.raw\" ]; then\n" +
        "  sig=$(head -c 4 \"$dest.raw\" | od -An -tx1 | tr -d ' \\n')\n" +
        "  case \"$sig\" in\n" +
        "    89504e47) covext=png ;;\n" +
        "    ffd8*) covext=jpg ;;\n" +
        "    47494638) covext=gif ;;\n" +
        "    52494646) covext=webp ;;\n" +
        "    3c3f786d|3c737667) covext=svg ;;\n" +
        "  esac\n" +
              "  if [ -n \"$covext\" ]; then\n" +
        "    mv \"$dest.raw\" \"$dest.$covext\"\n" +
        "  else\n" +
        "    rm -f \"$dest.raw\"\n" +
        "  fi\n" +
        "else\n" +
        "  rm -f \"$dest.raw\"\n" +
        "fi\n" +
        "printf '%s\\n%s\\n%s' \"$title\" \"$author\" \"$covext\""

    function unescapeXml(s) {
        return s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
                .replace(/&quot;/g, "\"").replace(/&apos;/g, "'")
    }

    // Runs the EbookFileService.php-style extraction for an imported book
    // file. mode: "overwrite" fills title/author from the file (add-from-
    // file), "fillEmpty" only fills blanks (create with file), "coverOnly"
    // only sets a cover when the book has none (file replaced on update).
    function extOf(p) {
        var s = p.toString()
        var d = s.lastIndexOf(".")
        var e = d > -1 ? s.substring(d + 1).toLowerCase() : ""
        return /^[a-z0-9]{1,5}$/.test(e) ? e : ""
    }

    // Resolves a stored library name to a real path (legacy absolute paths
    // from before the library existed pass through untouched).
    function resolveLib(name) {
        if (!name || name === "" || name === "-1") return ""
        if (name.startsWith("/")) return name
        return libraryDir + "/" + name
    }

    // Percent-encodes a local path into a file URL while keeping the path
    // separators; unlike string concatenation this survives "#", "?" and
    // malformed "%"-sequences in file names.
    function pathToUrl(p) {
        return "file://" + encodeURIComponent(p).replace(/%2F/gi, "/")
    }

    function importCover(book, src) {
        var old = (book.url && !book.url.startsWith("/")) ? book.url : ""
        importFile(src, book.id + "-cover." + (extOf(src) || "png"), function(name) {
            if (name !== "") {
                // Replace: the previous stored cover may have a different
                // extension (same <id> base) — remove it, or it is orphaned.
                if (old !== "" && old !== name) removeLib([old])
                book.url = name
                picker.books = picker.books.slice()
                save()
                if (picker.selected === book) editForm.setCover(name)
            }
        })
    }

    function importBookFile(book, src, mode) {
        var old = (book.file && !book.file.startsWith("/")) ? book.file : ""
        importFile(src, book.id + "." + (extOf(src) || "epub"), function(name) {
            if (name !== "") {
                if (old !== "" && old !== name) removeLib([old])
                book.file = name
                picker.books = picker.books.slice()
                save()
                if (picker.selected === book) editForm.setFile(name)
                if (extOf(name) === "epub" || extOf(name) === "pdf")
                    processBookFile(book, src, mode)
            }
        })
    }

    // Translucent spine decoration, approximating the CSS gradients in
    // Shelf.vue: 0 pyramid, 1 stairs, 2 argyle, 3 tartan.
    component PatternCanvas: Canvas {
        id: pat
        property int pattern: 0
        onPatternChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.save()
            if (pattern === 0) {
                ctx.fillStyle = "rgba(255,255,255,0.10)"
                for (var y = 0; y < height; y += 20)
                    for (var x = 0; x < width; x += 20) {
                        ctx.beginPath()
                        if (((x + y) / 20) % 2 === 0) {
                            ctx.moveTo(x, y + 20); ctx.lineTo(x + 10, y); ctx.lineTo(x + 20, y + 20)
                        } else {
                            ctx.moveTo(x, y); ctx.lineTo(x + 20, y); ctx.lineTo(x + 10, y + 20)
                        }
                        ctx.closePath()
                        ctx.fill()
                    }
            } else if (pattern === 1) {
                ctx.strokeStyle = "rgba(255,255,255,0.12)"
                ctx.lineWidth = 1
                for (var i = -height; i < width + height; i += 6) {
                    ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i + height * 0.5, height); ctx.stroke()
                }
            } else if (pattern === 2) {
                ctx.strokeStyle = "rgba(255,255,255,0.10)"
                ctx.lineWidth = 1
                for (var j = -height; j < width + height; j += 30) {
                    ctx.beginPath(); ctx.moveTo(j, 0); ctx.lineTo(j + height * 0.6, height); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(j + height * 0.6, 0); ctx.lineTo(j, height); ctx.stroke()
                }
            } else {
                ctx.fillStyle = "rgba(0,0,0,0.22)"
                for (var yy = 0; yy < height; yy += 50) ctx.fillRect(0, yy, width, 3)
                for (var xx = 0; xx < width; xx += 50) ctx.fillRect(xx, 0, 3, height)
                ctx.strokeStyle = "rgba(0,0,0,0.15)"
                for (var k = -height; k < width + height; k += 8) {
                    ctx.beginPath(); ctx.moveTo(k, 0); ctx.lineTo(k + height * 0.5, height); ctx.stroke()
                }
            }
            ctx.restore()
        }
    }

    // The 190x280 book cover from Shelf.vue/Sidebar.vue: colour block with
    // the linked cover image on top (local path stands in for the NC file id).
    component CoverView: Rectangle {
        property var book: null
        width: 190
        height: 280
        radius: 3
        color: picker.safeColor(book ? book.colour : "")
        border.width: 2
        border.color: Qt.darker(shell.shelfBgColor, 2.2)
        clip: true

        readonly property bool hasCover: book ? (book.url !== undefined && book.url !== null && book.url !== "" && book.url !== "-1") : false

        Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            source: parent.hasCover ? picker.pathToUrl(picker.resolveLib(parent.book.url)) : ""
        }
        Text {
            anchors.centerIn: parent
            text: "\uf02d"
            font.family: picker.shell.iconFont
            font.pointSize: 34
            color: Qt.rgba(0, 0, 0, 0.25)
            visible: !parent.hasCover
        }
    }

    component PickerButton: Rectangle {
        id: pickBtn
        property string label: ""
        property string glyph: ""
        property bool primary: false
        property bool danger: false
        signal clicked()
        width: parent.width
        height: 32
        radius: 8
        readonly property color base: danger ? picker.shell.shelfErrorColor
            : primary ? picker.shell.shelfAccentColor
            : Qt.rgba(1, 1, 1, 0.08)
        color: pma.pressed ? Qt.darker(base, 1.25)
            : pma.containsMouse ? (pickBtn.primary ? Qt.darker(base, 1.07) : Qt.lighter(base, 1.2))
            : base

        Text {
            anchors.centerIn: parent
            text: (pickBtn.glyph !== "" ? pickBtn.glyph + "  " : "") + pickBtn.label
            color: pickBtn.primary ? picker.shell.shelfAccentFgColor : picker.shell.shelfFgColor
            font.pointSize: 9
            font.bold: pickBtn.primary || pickBtn.danger
        }
        MouseArea {
            id: pma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pickBtn.clicked()
        }
    }

    // --- bookshelfs logic (App.vue + utils.ts) -----------------------------

    function safeColor(c) {
        if (!c) return "#5a4030"
        try { return Qt.color(c).toString() } catch (e) { return "#5a4030" }
    }
    function randomColour() {
        var availableColours = ["maroon", "darkgreen", "darkolivegreen", "brown", "saddlebrown", "sienna", "midnightblue"]
        return availableColours[Math.floor(Math.random() * availableColours.length)] || "darkolivegreen"
    }
    function randomPattern() { return Math.floor(Math.random() * 4) }
    function randomHeight() { return 220 + Math.floor(Math.random() * 71) }
    // Normalises a pattern/height arriving from stored data or form input:
    // blanks or garbage fall back to a random value, numbers are wrapped/
    // clamped into the valid range. (Raw `Number(v) % 4` / clamping on a
    // NaN produced NaN heights — a book that painted nothing at all.)
    function normPattern(v) {
        if (v === undefined || v === null || v === "") return randomPattern()
        var n = Number(v)
        return isNaN(n) ? randomPattern() : ((n % 4) + 4) % 4
    }
    function normHeight(v) {
        if (v === undefined || v === null || v === "") return randomHeight()
        var n = Number(v)
        return isNaN(n) ? randomHeight() : Math.min(290, Math.max(160, Math.round(n)))
    }
    function baseName(p) {
        var s = p.toString()
        var i = s.lastIndexOf("/")
        if (i >= 0) s = s.substring(i + 1)
        var d = s.lastIndexOf(".")
        // d > 0 keeps dotfiles like ".hidden" intact (d === 0 is the
        // leading dot).
        return d > 0 ? s.substring(0, d) : s
    }
    function urlToPath(u) {
        var s = u.toString()
        if (s.indexOf("file://") === 0) return decodeURIComponent(s.substring(7))
        return s
    }
    function getPath(book) {
        if (book.url === undefined || book.url === null || book.url === "" || book.url === "-1") return null
        return book.url
    }

    function save() {
        store.setText(JSON.stringify(picker.books))
    }

    function loadShelf() {
        var t = store.text()
        if ((!t || t.length === 0) && legacyStore.text() && legacyStore.text().length > 0)
            t = legacyStore.text()   // one-time migration from the old path
        var arr = null
        if (t && t.length > 0) {
            try {
                var parsed = JSON.parse(t)
                if (Array.isArray(parsed)) arr = parsed
            } catch (e) { arr = null }
        }
        // An existing empty shelf (after Reset Shelf) must stay empty:
        // seeding whenever the parsed array was empty resurrected the demo
        // books on every restart following a reset.
        if (arr) {
            for (var i = 0; i < arr.length; i++) {
                var b = arr[i]
                if (!b || typeof b !== "object") { arr.splice(i, 1); i--; continue }
                b.title = b.title || ""
                b.author = b.author || ""
                b.position = i
                b.url = (b.url === undefined || b.url === null || b.url === -1 || b.url === "-1") ? "" : String(b.url)
                b.file = (b.file === undefined || b.file === null || b.file === -1 || b.file === "-1") ? "" : String(b.file)
                b.colour = b.colour || randomColour()
                b.pattern = normPattern(b.pattern)
                b.height = normHeight(b.height)
                if (b.id === undefined || b.id === null) b.id = picker.nextId++
                else {
                    // Coerce: a string id ("5") made `b.id >= nextId`
                    // compare fine but `nextId = b.id + 1` concatenate ("51").
                    b.id = Number(b.id)
                    if (isNaN(b.id)) b.id = picker.nextId++
                    else if (b.id >= picker.nextId) picker.nextId = b.id + 1
                }
            }
            arr.sort(function(a, b) { return a.position - b.position })
            picker.books = arr
            // Migrate pre-library books that still carry absolute paths.
            for (var j = 0; j < picker.books.length; j++) {
                var mb = picker.books[j]
                if (mb.url.startsWith("/")) importCover(mb, mb.url)
                if (mb.file.startsWith("/")) importBookFile(mb, mb.file, "overwrite")
            }
        } else {
            seedShelf()
        }
        picker.loaded = true
    }

    function seedShelf() {
        picker.books = [
            { id: 1, title: "The Hobbit", author: "Tolkien", position: 0, url: "", file: "", colour: "maroon", pattern: 0, height: 250 },
            { id: 2, title: "Dune", author: "Herbert", position: 1, url: "", file: "", colour: "midnightblue", pattern: 2, height: 280 },
            { id: 3, title: "1984", author: "Orwell", position: 2, url: "", file: "", colour: "darkgreen", pattern: 1, height: 230 }
        ]
        picker.nextId = 4
        save()
    }

    function createBook(v) {
        var b = {
            id: picker.nextId++,
            title: v.title || "",
            author: v.author || "",
            position: picker.books.length,
            url: "",
            file: "",
            colour: v.colour ? v.colour : randomColour(),
            pattern: normPattern(v.pattern),
            height: normHeight(v.height)
        }
        picker.books = picker.books.concat([b])
        save()
        // Freshly picked files arrive as transient absolute source paths in
        // the form; import them into the library and store only the names.
        if (v.url && v.url.startsWith("/")) importCover(b, v.url)
        if (v.file && v.file.startsWith("/")) importBookFile(b, v.file, "fillEmpty")
    }

    function addFromFile(src) {
        var b = {
            id: picker.nextId++,
            title: baseName(src),
            author: "",
            position: picker.books.length,
            url: "",
            file: "",
            colour: randomColour(),
            pattern: randomPattern(),
            height: randomHeight()
        }
        picker.books = picker.books.concat([b])
        save()
        importBookFile(b, src, "overwrite")
    }

    function updateBook(book, v) {
        if (!book) return
        book.title = v.title || ""
        book.author = v.author || ""
        if (v.colour) book.colour = v.colour
        if (v.pattern !== "") book.pattern = normPattern(v.pattern)
        if (v.height !== "") book.height = normHeight(v.height)
        // Cover: cleared / replaced (import new, drop old only on success)
        // / name untouched.
        if (v.url === "") {
            removeLib([book.url])
            book.url = ""
        } else if (v.url.startsWith("/")) {
            var oldCover = (book.url && !book.url.startsWith("/")) ? book.url : ""
            importFile(v.url, book.id + "-cover." + (extOf(v.url) || "png"), function(name) {
                if (name !== "") {
                    if (oldCover !== "" && oldCover !== name) removeLib([oldCover])
                    book.url = name
                    picker.books = picker.books.slice()
                    save()
                    if (picker.selected === book) editForm.setCover(name)
                }
            })
        } else {
            book.url = v.url
        }
        // Book file: same pattern.
        if (v.file === "") {
            removeLib([book.file])
            book.file = ""
        } else if (v.file.startsWith("/")) {
            var oldFile = (book.file && !book.file.startsWith("/")) ? book.file : ""
            importFile(v.file, book.id + "." + (extOf(v.file) || "epub"), function(name) {
                if (name !== "") {
                    if (oldFile !== "" && oldFile !== name) removeLib([oldFile])
                    book.file = name
                    picker.books = picker.books.slice()
                    save()
                    if (picker.selected === book) editForm.setFile(name)
                    if (extOf(name) === "epub" || extOf(name) === "pdf")
                        processBookFile(book, v.file, "coverOnly")
                }
            })
        } else {
            book.file = v.file
        }
        picker.books = picker.books.slice()
        save()
    }

    function deleteBookById(id) {
        var victim = null
        var arr = []
        for (var i = 0; i < picker.books.length; i++) {
            if (picker.books[i].id === id) victim = picker.books[i]
            else arr.push(picker.books[i])
        }
        for (var j = 0; j < arr.length; j++) arr[j].position = j
        picker.books = arr
        if (picker.selected && picker.selected.id === id) picker.selected = null
        if (victim) removeLib([victim.url, victim.file])
        save()
    }

    function reStyle() {
        for (var i = 0; i < picker.books.length; i++) {
            picker.books[i].colour = randomColour()
            picker.books[i].pattern = randomPattern()
            picker.books[i].height = randomHeight()
        }
        picker.books = picker.books.slice()
        save()
    }

    function resetShelf() {
        var names = []
        for (var i = 0; i < picker.books.length; i++)
            names.push(picker.books[i].url, picker.books[i].file)
        removeLib(names)
        picker.books = []
        picker.selected = null
        save()
    }

    function moveBook(from, to) {
        if (from === to || from < 0 || to < 0 || from >= picker.books.length) return
        var arr = picker.books.slice()
        var b = arr.splice(from, 1)[0]
        arr.splice(to, 0, b)
        for (var i = 0; i < arr.length; i++) arr[i].position = i
        picker.books = arr
        save()
    }

    // --- shelf layout -------------------------------------------------------

    function slotFor(visualIndex) {
        var per = Math.max(1, Math.floor((shelfArea.width - 60) / slotWidth))
        var row = Math.floor(visualIndex / per)
        return {
            x: 30 + (visualIndex % per) * slotWidth,
            y: 24 + row * rowStep,
            row: row
        }
    }

    function visualIndexOf(modelIndex) {
        if (!dragActive || dragIndex < 0 || previewIndex < 0 || dragIndex === previewIndex)
            return modelIndex
        if (modelIndex === dragIndex) return previewIndex
        if (dragIndex < previewIndex && modelIndex > dragIndex && modelIndex <= previewIndex)
            return modelIndex - 1
        if (dragIndex > previewIndex && modelIndex >= previewIndex && modelIndex < dragIndex)
            return modelIndex + 1
        return modelIndex
    }

    function slotAtPoint(px, py) {
        for (var i = 0; i < picker.books.length; i++) {
            var s = slotFor(i)
            if (px >= s.x - 3 && px <= s.x + slotWidth - 2 && py >= s.y && py <= s.y + 280)
                return i
        }
        return -1
    }

    function select(book) {
        if (picker.selected === book) return
        picker.selected = book
        if (book) editForm.setFrom(book)
    }

    function toggle() {
        if (shell.ccPopup) shell.ccPopup.visible = false
        if (shell.notesPopup) shell.notesPopup.visible = false
        if (picker.open) cancelBrowser()   // don't leak browser state/callback
        picker.open = !open
        picker.visible = open
    }

    function close() {
        cancelBrowser()
        picker.open = false
        picker.visible = false
    }

    // Initial load happens in ensureDir.onExited so shelf.json can be
    // written safely.

    // --- window chrome ------------------------------------------------------

    Rectangle {
        id: body
        anchors.fill: parent
        radius: shell.cornerRadius
        color: shell.shelfBgColor
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.04)
        // Fade the whole window in on every open (the window geometry itself
        // cannot animate here; hiding stays instant).
        opacity: picker.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Item {
            id: header
            x: 10
            y: 8
            width: parent.width - 20
            height: picker.headerHeight - 16

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf02d"
                font.family: picker.shell.iconFont
                font.pointSize: 12
                color: picker.shell.shelfFgColor
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: "Bookshelfs"
                font.pointSize: 10
                font.bold: true
                color: picker.shell.shelfFgColor
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 100
                anchors.verticalCenter: parent.verticalCenter
                text: "book picker"
                font.pointSize: 8
                color: Qt.rgba(1, 1, 1, 0.35)
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                text: "Esc to close"
                font.pointSize: 8
                color: Qt.rgba(1, 1, 1, 0.35)
            }
            Text {
                id: closeButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf00d"
                font.family: picker.shell.iconFont
                font.pointSize: 11
                color: closeArea.containsMouse ? picker.shell.shelfFgColor : Qt.rgba(1, 1, 1, 0.5)
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: picker.close()
                }
            }
        }

        // --- Nav (Nav.vue): create form + add-from-file + settings -----------

        Rectangle {
            id: nav
            x: 0
            y: picker.headerHeight
            width: picker.navWidth
            height: parent.height - picker.headerHeight
            color: Qt.lighter(shell.shelfBgColor, 2.0)

            Flickable {
                id: navScroll
                anchors.fill: parent
                anchors.margins: 10
                contentHeight: navCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: navCol
                    width: navScroll.width
                    spacing: 6

                    Text {
                        text: "New book"
                        font.pointSize: 8
                        font.bold: true
                        color: picker.shell.shelfFgColor
                        bottomPadding: 2
                    }
                    BookForm {
                        id: createForm
                        shell: picker.shell
                        width: parent.width
                        onSubmitted: {
                            var v = createForm.values()
                            if (v.title.trim() === "" && v.file.trim() === "") {
                                createForm.firstField.forceActiveFocus(Qt.PopupFocusReason)
                                return
                            }
                            picker.createBook(v)
                            createForm.clear()
                        }
                        onCoverRequested: picker.openBrowser(picker.imageFilters, function(p) { createForm.setCover(p) })
                        onFileRequested: picker.openBrowser(picker.ebookFilters, function(p) { createForm.setFile(p) })
                    }
                    function createFromForm() {
                        var v = createForm.values()
                        if (v.title.trim() === "" && v.file.trim() === "") {
                            createForm.firstField.forceActiveFocus(Qt.PopupFocusReason)
                            return
                        }
                        picker.createBook(v)
                        createForm.clear()
                    }
                    PickerButton {
                        label: "Create book"
                        glyph: "\uf067"
                        primary: true
                        onClicked: createFromForm()
                    }
                    PickerButton {
                        label: "Add book from file"
                        glyph: "\uf093"
                        onClicked: picker.openBrowser(picker.ebookFilters, function(p) { picker.addFromFile(p) })
                    }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }
                    Text {
                        text: "Settings"
                        font.pointSize: 8
                        font.bold: true
                        color: picker.shell.shelfFgColor
                        topPadding: 4
                    }
                    PickerButton {
                        label: "Restyle Shelf"
                        glyph: "\uf021"
                        onClicked: picker.reStyle()
                    }
                    PickerButton {
                        label: "Reset Shelf"
                        glyph: "\uf014"
                        danger: true
                        onClicked: picker.resetShelf()
                    }
                }
            }
        }

        // --- Shelf (Shelf.vue) -----------------------------------------------

        Item {
            id: shelfArea
            x: picker.navWidth
            y: picker.headerHeight
            width: parent.width - picker.navWidth
            height: parent.height - picker.headerHeight
            clip: true

            Rectangle {
                anchors.fill: parent
                color: Qt.darker(shell.shelfBgColor, 1.55)
            }

            // Clicking the shelf background deselects the book.
            MouseArea {
                anchors.fill: parent
                onClicked: picker.selected = null
            }

            // The shelf scrolls once books overflow the first row (the
            // window is fixed-size). Wheel scrolls everywhere — child
            // MouseAreas don't take wheel events; drag-panning from the
            // background is ceded to the deselect area, book dragging keeps
            // precedence over flicking (MouseArea drag sets keepMouseGrab).
            Flickable {
                id: shelfScroll
                anchors.fill: parent
                contentWidth: shelfArea.width
                contentHeight: Math.max(height, 24 + picker.rowCount * picker.rowStep + 24)
                boundsBehavior: Flickable.StopAtBounds
                clip: true

            Repeater {
                model: picker.rowCount
                delegate: Rectangle {
                    required property int index
                    x: 20
                    width: shelfArea.width - 40
                    // 2 px under the book bottoms (bottoms at row y + 280;
                    // books stand on the plank with a 2 px overlap).
                    y: 24 + index * picker.rowStep + 278
                    height: 8
                    radius: 4
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.darker(shell.shelfBgColor, 1.2) }
                        GradientStop { position: 1.0; color: Qt.darker(shell.shelfBgColor, 1.7) }
                    }
                    border.width: 1
                    border.color: Qt.darker(shell.shelfBgColor, 2.0)
                }
            }

            Repeater {
                model: picker.books
                delegate: Item {
                    id: bookRoot
                    required property var modelData
                    required property int index

                    width: 50
                    height: 280
                    x: picker.slotFor(picker.visualIndexOf(index)).x
                    y: picker.slotFor(picker.visualIndexOf(index)).y + (280 - modelData.height)
                    // Slot changes slide instead of jumping (vuedraggable
                    // feel). Disabled for the dragged book, whose x/y the
                    // drag itself is writing; delegates are recreated on
                    // reorder, so fresh items never animate from 0,0.
                    Behavior on x {
                        enabled: !dragMa.drag.active
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        enabled: !dragMa.drag.active
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                    // Hit area and stacking stay enlarged through the unlift
                    // grace so the pose cannot flicker while the swing-back
                    // is still settling.
                    readonly property bool poseHold: lift || liftHold.running
                    z: dragMa.drag.active ? 20 : (poseHold ? 10 : 0)

                    // Repo hover (Shelf.vue .book:hover), toned down: Qt's
                    // root projection is perspective, so big tilt angles
                    // magnify the spine over its own cover. The hit area
                    // follows the tilt (transformed hit testing): while
                    // lifted it grows so the book holds the pose for as long
                    // as the cursor rests anywhere on it; winning the claim
                    // arbitration (topmost under cursor) is what lifts it.
                    readonly property int claimPrio: dragMa.drag.active || dragMa.pressed ? 200 : lift ? 100 : 0
                    readonly property bool hovered: picker.hoverWinner === index || picker.debugHoverIndex === index
                    property bool lifted: false
                    readonly property bool lift: lifted || picker.debugLift
                    onHoveredChanged: {
                        if (hovered) {
                            liftHold.stop()
                            lifted = true
                        } else {
                            liftHold.restart()
                        }
                    }
                    onLiftedChanged: picker.setHoverClaim(index, claimPrio, dragMa.containsMouse)
                    onClaimPrioChanged: picker.setHoverClaim(index, claimPrio, dragMa.containsMouse)

                    Timer {
                        id: liftHold
                        interval: 250
                        onTriggered: if (!bookRoot.hovered) bookRoot.lifted = false
                    }

                    transform: [
                        Translate {
                            x: bookRoot.lift * -18
                            y: bookRoot.lift * 26
                            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        },
                        Rotation {
                            angle: bookRoot.lift * -8
                            axis { x: 0; y: 0; z: 1 }
                            origin { x: 25; y: modelData.height / 2 }
                            Behavior on angle { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        },
                        Rotation {
                            angle: bookRoot.lift * -16
                            axis { x: 0; y: 1; z: 0 }
                            origin { x: 0; y: 140 }
                            Behavior on angle { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        },
                        Rotation {
                            angle: bookRoot.lift * -10
                            axis { x: 1; y: 0; z: 0 }
                            // Tilt about the book's base, not a hardcoded
                            // 280: the stale pivot floated below the plank
                            // on shorter books.
                            origin { x: 25; y: modelData.height }
                            Behavior on angle { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    ]

                    MouseArea {
                        id: dragMa
                        anchors {
                            fill: parent
                            topMargin: poseHold ? -40 : 0
                            leftMargin: poseHold ? -30 : 0
                            rightMargin: 6
                            // Stop 10px above the spine base: a fixed
                            // bottomMargin made the hit area of short books
                            // reach into/below the plank and the next row's
                            // hover band.
                            bottomMargin: 290 - modelData.height
                        }
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        drag.target: bookRoot
                        drag.axis: Drag.XAndYAxis
                        drag.minimumX: 0
                        drag.maximumX: shelfArea.width - 50
                        drag.minimumY: 0
                        drag.maximumY: Math.max(0, shelfScroll.contentHeight - 120)

                        onContainsMouseChanged: picker.setHoverClaim(index, claimPrio, containsMouse)

                        property real pressX: 0
                        property real pressY: 0
                        onPressed: function(mouse) {
                            pressX = mouse.x
                            pressY = mouse.y
                            picker.dragActive = true
                            picker.dragIndex = index
                            picker.previewIndex = index
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed) return
                            // Slot coords live in the scrollable content, so
                            // map through the Flickable's contentItem (this
                            // accounts for contentY while scrolled).
                            var p = mapToItem(shelfScroll.contentItem, mouse.x, mouse.y)
                            var s = picker.slotAtPoint(p.x, p.y)
                            if (s >= 0) picker.previewIndex = s
                        }
                        onReleased: {
                            var from = picker.dragIndex
                            var to = picker.previewIndex >= 0 ? picker.previewIndex : from
                            picker.dragActive = false
                            picker.dragIndex = -1
                            picker.previewIndex = -1
                            // Dragging wrote x/y directly, destroying the
                            // declarative slot bindings — restore them so the
                            // book springs back (a moveBook reorder rebuilds
                            // the delegates with fresh bindings anyway).
                            restoreSlot()
                            if (from !== to) {
                                // Deferred: reordering rebuilds every shelf
                                // delegate, which must not happen inside the
                                // mouse-release handler (scene graph crash).
                                Qt.callLater(function() { picker.moveBook(from, to) })
                            }
                        }
                        onCanceled: {
                            picker.dragActive = false
                            picker.dragIndex = -1
                            picker.previewIndex = -1
                            restoreSlot()
                        }
                        function restoreSlot() {
                            bookRoot.x = Qt.binding(function() {
                                return picker.slotFor(picker.visualIndexOf(bookRoot.index)).x
                            })
                            bookRoot.y = Qt.binding(function() {
                                return picker.slotFor(picker.visualIndexOf(bookRoot.index)).y
                                    + (280 - bookRoot.modelData.height)
                            })
                        }
                        onClicked: function(mouse) {
                            if (Math.abs(mouse.x - pressX) > 4 || Math.abs(mouse.y - pressY) > 4)
                                return  // that was a drag, not a pick
                            picker.select(modelData)
                        }
                        onDoubleClicked: {
                            var p = picker.resolveLib(modelData.file)
                            if (p !== "") Qt.openUrlExternally(picker.pathToUrl(p))
                        }
                    }

                    // Spine with colour, pattern, vertical title and author.
                    // y defaults to 0: bookRoot is already bottom-aligned, so
                    // the spine must not offset again (that double-offset
                    // pushed short books below the plank).
                    Rectangle {
                        id: spine
                        width: 50
                        height: modelData.height
                        radius: 3
                        color: picker.safeColor(modelData.colour)
                        border.width: 2
                        border.color: "#200404"

                        PatternCanvas {
                            anchors.fill: parent
                            pattern: modelData.pattern
                        }
                        // Spine roundness: darker edges, lighter centre.
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.28) }
                                GradientStop { position: 0.3; color: Qt.rgba(0, 0, 0, 0) }
                                GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0) }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.28) }
                            }
                        }
                        // Rotated coordinate frame: its top edge is the
                        // spine's right edge, so the title reads top-to-
                        // bottom along the right like the repo's
                        // writing-mode: vertical-rl title.
                        Item {
                            width: spine.height
                            height: spine.width
                            anchors.centerIn: parent
                            rotation: 90
                            Text {
                                anchors.top: parent.top
                                anchors.topMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                // Clamped to the spine length: longer titles
                                // used to overflow past the spine bottom and
                                // vanish under the swung-out cover.
                                width: parent.width - 8
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.title || "Untitled"
                                color: "gold"
                                font.pointSize: 11
                                font.bold: true
                            }
                        }
                        Text {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            // Elide inside the spine: the overflow used to be
                            // chopped mid-letter by the cover painted above.
                            width: parent.width - 12
                            elide: Text.ElideRight
                            visible: modelData.author !== ""
                            text: modelData.author
                            color: "goldenrod"
                            font.pointSize: 8
                            font.bold: true
                        }
                    }

                    // Top pages face (the repo's .top): edge-on while flat,
                    // shows as a white block above the spine on lift. It
                    // hangs above the spine and hinges at its bottom edge
                    // (y=-2, the spine top): it used to sit 190px lower,
                    // which painted a detached white slab over the middle of
                    // every book shorter than 280px.
                    Rectangle {
                        x: 0
                        y: -192
                        width: 50
                        height: 190
                        radius: 2
                        color: "#f3efe6"
                        border.width: 1
                        border.color: "#b9b2a4"
                        transform: Rotation {
                            angle: bookRoot.lift ? 78 : 90
                            axis { x: 1; y: 0; z: 0 }
                            origin { x: 25; y: 190 }
                            Behavior on angle { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    }

                    // Cover face, hinged at the spine's right edge like the
                    // repo's .cover: 90 deg is edge-on (hidden while flat);
                    // on lift it swings to 40 deg and faces the viewer.
                    // Hinges beyond ~70 deg vanish under the composed tilt.
                    CoverView {
                        book: modelData
                        x: 50
                        width: 190
                        // Match the book height so top and bottom edges line
                        // up with the spine; the fixed 280 made the cover
                        // hang below the plank on shorter books.
                        height: modelData.height
                        transform: Rotation {
                            angle: bookRoot.lift ? 40 : 90
                            axis { x: 0; y: 1; z: 0 }
                            origin { x: 0; y: 140 }
                            Behavior on angle { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
            } // Flickable shelfScroll
        }

        // --- Sidebar (Sidebar.vue): update / delete the selected book --------

        Rectangle {
            id: editorPanel
            width: picker.editorWidth
            height: parent.height
            x: picker.selected ? parent.width - width : parent.width
            visible: x < parent.width - 1
            color: Qt.lighter(shell.shelfBgColor, 2.0)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)
            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            Flickable {
                anchors.fill: parent
                anchors.margins: 10
                contentHeight: editCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: editCol
                    width: editorPanel.width - 20
                    spacing: 8

                    Item {
                        width: parent.width
                        height: 20
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Edit book"
                            font.pointSize: 9
                            font.bold: true
                            color: picker.shell.shelfFgColor
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf00d"
                            font.family: picker.shell.iconFont
                            font.pointSize: 10
                            color: editorCloseArea.containsMouse ? picker.shell.shelfFgColor : Qt.rgba(1, 1, 1, 0.5)
                            MouseArea {
                                id: editorCloseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.selected = null
                            }
                        }
                    }
                    BookForm {
                        id: editForm
                        shell: picker.shell
                        width: parent.width
                        onSubmitted: if (picker.selected) picker.updateBook(picker.selected, editForm.values())
                        onCoverRequested: picker.openBrowser(picker.imageFilters, function(p) { editForm.setCover(p) })
                        onFileRequested: picker.openBrowser(picker.ebookFilters, function(p) { editForm.setFile(p) })
                    }
                    Item {
                        width: parent.width
                        height: 200
                        // Shows the stored cover — or, the moment a new image
                        // is picked, that image (its path sits in the form
                        // until "Update book" imports it into the library).
                        CoverView {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 130
                            height: 192
                            book: {
                                var b = picker.selected
                                if (!b) return null
                                var pending = editForm.values().url
                                return {
                                    colour: b.colour,
                                    url: pending.startsWith("/") ? pending : b.url
                                }
                            }
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: 6
                        PickerButton {
                            width: (parent.width - 6) / 2
                            label: "Update book"
                            primary: true
                            enabled: picker.selected !== null
                            onClicked: picker.updateBook(picker.selected, editForm.values())
                        }
                        PickerButton {
                            width: (parent.width - 6) / 2
                            label: "Delete book"
                            danger: true
                            enabled: picker.selected !== null
                            onClicked: picker.deleteBookById(picker.selected.id)
                        }
                    }
                }
            }
        }
    }

    // Sibling of body, never a child of it: an effect inside its own source
    // item is a self-referential layer and corrupted the scene graph here.
    MultiEffect {
        source: body
        anchors.fill: body
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.45
        shadowBlur: 0.8
        shadowVerticalOffset: 6
        z: -1
    }

    // Built-in file browser (the portal FileDialog cannot open under a
    // layer-shell parent).
    FileBrowser {
        id: fileBrowser
        shell: picker.shell
        width: 460
        height: 440
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        z: 100
        onPicked: function(p) {
            open = false
            var cb = picker.pickCallback
            var pf = picker._prevFocus
            picker.pickCallback = null
            picker._prevFocus = null
            if (cb) cb(p)
            // Hand keyboard focus back to the field that opened the
            // browser so typing continues where it left off.
            if (pf) pf.forceActiveFocus()
        }
        onCancelled: {
            picker.pickCallback = null
            if (picker._prevFocus) {
                picker._prevFocus.forceActiveFocus()
                picker._prevFocus = null
            }
        }
    }

    function openBrowser(filters, cb) {
        // Blur the form field while the browser is open: otherwise typed
        // keys and Enter keep editing/submitting behind the dialog.
        _prevFocus = picker._backingWindow ? picker._backingWindow.activeFocusItem : null
        pickCallback = cb
        fileBrowser.show(filters)
        fileBrowser.forceActiveFocus()
    }

    function cancelBrowser() {
        fileBrowser.hide()
        pickCallback = null
    }
}
