import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Native Excalidraw-style whiteboard popup for the sidebar dock — a QML
// clone of excalidraw.com's core, not the web app itself (embedding foreign
// windows is impossible on Wayland, and quickshell has no WebEngine).
//
// One persistent infinite board, stored as a REAL .excalidraw JSON file
// (excalidraw/board.excalidraw, gitignored) so it interops with the actual
// Excalidraw app (web / desktop / VS Code extension): same element schema
// (id/type/x/y/width/height/points/seed/..., appState scroll/zoom), same
// coordinate convention (points relative to x/y, x/y the bbox min corner).
// Element types we do not implement (image, iframe, frame, ...) are skipped
// with a warning when loading a board written by the real app.
//
// Rendering is a compact roughjs-style port: every element carries a
// persisted integer `seed`; a mulberry32 PRNG derived from it jitters the
// strokes, so the hand-drawn look is stable across repaints (redrawing the
// same board always yields the same wobble). Stroke-only plus flat solid
// fill; hachure fill is deliberately not implemented yet (documented
// limitation).
//
// Board lifecycle: lazy load on first open (mkdir via Process first so the
// first save cannot race the directory), debounced autosave (~800 ms) via
// FileView, like NotesWidget's autosave.
//
// Interaction model mirrors excalidraw: select (bbox move + 4-corner
// resize), rectangle/ellipse/diamond/line/arrow/pen, click-to-type text with
// an on-canvas TextEdit overlay, click-to-delete eraser, pan with middle
// mouse or space-drag, wheel zoom at cursor, undo/redo (snapshot stack),
// Delete, PNG export of the visible viewport, open-in-app via xdg-open.
//
// Known v1 limits: no hachure fill, no images/libraries/rotation/snapping,
// the hand-drawn "Excalifont" falls back to a system font stack, PNG export
// covers the visible viewport only, no band selection.
PanelWindow {
    id: ex

    required property var shell

    property bool open: false
    property var popup: ex

    // ---- board state ----
    property var elements: []
    property var selectedEl: null
    property var draft: null
    property string tool: "selection"    // selection|rectangle|ellipse|diamond|line|arrow|freedraw|text|eraser
    property string strokeColor: "#1e1e1e"
    property string fillColor: "transparent"
    property int strokeWidth: 2
    property var view: ({ scrollX: 0, scrollY: 0, zoom: 1 })
    property string viewBg: "#ffffff"
    property string editingId: ""        // id of the text element being edited ("" = none)
    property bool textFresh: false       // text element created this editing session (never committed)
    property bool loaded: false
    property bool spaceHeld: false
    property bool panning: false
    property int undoTop: 0              // stack sizes mirrored to ints so the
    property int redoTop: 0              // button enablement bindings re-evaluate
    property var undoStack: []
    property var redoStack: []
    property string toastText: ""
    property string zoomPct: "100%"

    readonly property color toolActiveBg: Qt.rgba(0.41, 0.4, 0.86, 0.14)
    readonly property var strokePresets: ["#1e1e1e", "#e03131", "#1971c2", "#2f9e44", "#f08c00"]
    readonly property var fillPresets: ["transparent", "#ced4da", "#1e1e1e"]

    readonly property string exDir: urlToPath(Quickshell.shellDir) + "/excalidraw"
    readonly property string boardPath: exDir + "/board.excalidraw"

    anchors { left: true; top: true }
    implicitWidth: 1020
    implicitHeight: 640
    margins {
        left: shell.sidebarGap + shell.sidebarWidth + 8
        top: Math.max(8, (screen.height - implicitHeight) / 2)
    }
    exclusiveZone: 0
    visible: false
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-excalidraw"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
        open = visible
        if (visible) {
            if (!loaded) ensureDir.running = true
            focusTimer.restart()
        } else if (editingId !== "") {
            // Hidden by another popup while typing: settle the text state
            // so reopening doesn't resume a half-edited element.
            commitText()
        }
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: true
        running: false
        onTriggered: {
            if (ex.editingId !== "") {
                textEditor.forceActiveFocus()
                if (textEditor.activeFocus) stop()
            } else {
                body.forceActiveFocus()
                if (body.activeFocus) stop()
            }
        }
    }

    Process {
        id: ensureDir
        command: ["mkdir", "-p", ex.exDir]
        onExited: function(exitCode) {
            // Load only after the dir exists so the first save cannot race it.
            if (exitCode === 0 && !ex.loaded) ex.loadBoard()
        }
    }

    FileView {
        id: store
        path: ex.boardPath
        blockLoading: true
        printErrors: true
    }

    Timer {
        id: saveTimer
        interval: 800
        onTriggered: ex.saveBoard()
    }

    // ---- toolbar inline components (top-level: nested breaks lookup) ----
    component ExTool: Rectangle {
        id: toolBtn
        property string glyph: ""
        property string label: ""
        property bool active: false
        signal picked()
        width: 34
        height: 34
        radius: 8
        // NOTE: a plain Rectangle has no hovered; use the MouseArea's
        // containsMouse. Built-in `enabled` dims input for free.
        color: !toolBtn.enabled ? "transparent"
            : toolBtn.active ? toolActiveBg
            : toolArea.containsMouse ? Qt.rgba(0, 0, 0, 0.06)
            : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
            anchors.centerIn: parent
            text: toolBtn.glyph !== "" ? toolBtn.glyph : toolBtn.label
            font.family: toolBtn.glyph !== "" ? shell.iconFont : "sans-serif"
            font.pointSize: toolBtn.glyph !== "" ? 11 : 9
            font.bold: toolBtn.glyph === ""
            color: !toolBtn.enabled ? Qt.rgba(0, 0, 0, 0.25)
                : toolBtn.active ? shell.exAccentColor : shell.exFgColor
        }
        MouseArea {
            id: toolArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toolBtn.picked()
        }
    }

    component ExDivider: Rectangle {
        width: 1
        height: 20
        color: Qt.rgba(0, 0, 0, 0.12)
        anchors.verticalCenter: parent.verticalCenter
    }

    component ExSwatch: Rectangle {
        id: swatch
        property color colorValue: "#000000"
        property bool transparentStyle: false
        property bool selected: false
        signal picked()
        width: 22
        height: 22
        radius: 11
        color: swatch.transparentStyle ? "#ffffff" : swatch.colorValue
        border.width: swatch.transparentStyle ? 1 : 0
        border.color: Qt.rgba(0, 0, 0, 0.25)
        // diagonal slash marks "transparent"
        Rectangle {
            visible: swatch.transparentStyle
            width: 2
            height: 26
            rotation: 45
            color: "#e03131"
            anchors.centerIn: parent
        }
        Rectangle {
            anchors.fill: parent
            radius: 11
            color: "transparent"
            border.width: swatch.selected ? 2 : 0
            border.color: shell.exAccentColor
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: swatch.picked()
        }
    }

    component ExWidthButton: Rectangle {
        id: widthBtn
        property int widthValue: 2
        property int dotSize: 4
        property bool selected: false
        signal picked()
        width: 26
        height: 26
        radius: 13
        color: widthArea.containsMouse ? Qt.rgba(0, 0, 0, 0.06) : "transparent"
        Rectangle {
            anchors.centerIn: parent
            width: widthBtn.dotSize
            height: widthBtn.dotSize
            radius: widthBtn.dotSize / 2
            color: shell.exFgColor
        }
        Rectangle {
            anchors.fill: parent
            radius: 13
            color: "transparent"
            border.width: widthBtn.selected ? 2 : 0
            border.color: shell.exAccentColor
        }
        MouseArea {
            id: widthArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: widthBtn.picked()
        }
    }

    // ---- JS core: pure logic, extracted verbatim by tests/run.sh ----
    // JS-BEGIN
    function mulberry32(seed) {
        var a = seed >>> 0
        return function () {
            a |= 0
            a = (a + 0x6D2B79F5) | 0
            var t = Math.imul(a ^ (a >>> 15), 1 | a)
            t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296
        }
    }

    function supportedTypes() {
        return ["rectangle", "ellipse", "diamond", "line", "arrow", "freedraw", "text"]
    }

    // ---- coordinate transforms (screen = world * zoom + scroll) ----
    function toWorld(view, sx, sy) {
        return [(sx - view.scrollX) / view.zoom, (sy - view.scrollY) / view.zoom]
    }

    function toScreen(view, wx, wy) {
        return [wx * view.zoom + view.scrollX, wy * view.zoom + view.scrollY]
    }

    // Zoom keeping the world point under (sx, sy) fixed. Mutates and
    // returns view for convenience.
    function zoomAt(view, sx, sy, factor) {
        var z = Math.min(4, Math.max(0.2, view.zoom * factor))
        if (z === view.zoom) return view
        var w = toWorld(view, sx, sy)
        view.scrollX = sx - w[0] * z
        view.scrollY = sy - w[1] * z
        view.zoom = z
        return view
    }

    function centerViewport(w, h) {
        return { scrollX: w / 2, scrollY: h / 2, zoom: 1 }
    }

    // ---- roughjs-style stroke generation ----
    // Every jitter comes from the element's own PRNG, never Math.random,
    // so a redraw of the same seed reproduces the same wobble.
    function roughLinePath(rng, x1, y1, x2, y2, roughness, passes) {
        var paths = []
        var len = Math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
        var amp = roughness * (1.5 + Math.min(len, 300) * 0.012)
        for (var p = 0; p < passes; p++) {
            var sx = x1 + (rng() * 2 - 1) * amp
            var sy = y1 + (rng() * 2 - 1) * amp
            var ex = x2 + (rng() * 2 - 1) * amp
            var ey = y2 + (rng() * 2 - 1) * amp
            var pts = [[sx, sy]]
            if (len > 16) pts.push([(sx + ex) / 2 + (rng() * 2 - 1) * amp, (sy + ey) / 2 + (rng() * 2 - 1) * amp])
            pts.push([ex, ey])
            paths.push(pts)
        }
        return paths
    }

    function strokePolyline(ctx, pts) {
        ctx.moveTo(pts[0][0], pts[0][1])
        for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1])
    }

    // Jittered points on an ellipse; drawn via buildSmoothClosed.
    function ellipsePoints(rng, cx, cy, rx, ry, roughness) {
        var pts = []
        var n = 18
        for (var i = 0; i < n; i++) {
            var a = (i / n) * Math.PI * 2
            var jr = 1 + (rng() * 2 - 1) * 0.02 * roughness
            pts.push([cx + Math.cos(a) * rx * jr, cy + Math.sin(a) * ry * jr])
        }
        return pts
    }

    // Closed smooth path through the points (quadratic through midpoints).
    function buildSmoothClosed(ctx, pts) {
        var n = pts.length
        ctx.moveTo((pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2)
        for (var i = 1; i <= n; i++) {
            var c = pts[i % n]
            var nx = pts[(i + 1) % n]
            ctx.quadraticCurveTo(c[0], c[1], (c[0] + nx[0]) / 2, (c[1] + nx[1]) / 2)
        }
        ctx.closePath()
    }

    // One rough path per stroke pass per side.
    function roughPolygonPaths(rng, corners, roughness) {
        var paths = []
        for (var i = 0; i < corners.length; i++) {
            var a = corners[i]
            var b = corners[(i + 1) % corners.length]
            paths = paths.concat(roughLinePath(rng, a[0], a[1], b[0], b[1], roughness, 2))
        }
        return paths
    }

    function rectCorners(rng, x, y, w, h, roughness) {
        var o = roughness * 1.2
        return [
            [x + (rng() * 2 - 1) * o, y + (rng() * 2 - 1) * o],
            [x + w + (rng() * 2 - 1) * o, y + (rng() * 2 - 1) * o],
            [x + w + (rng() * 2 - 1) * o, y + h + (rng() * 2 - 1) * o],
            [x + (rng() * 2 - 1) * o, y + h + (rng() * 2 - 1) * o]
        ]
    }

    function diamondCorners(rng, x, y, w, h, roughness) {
        var o = roughness * 1.2
        return [
            [x + w / 2 + (rng() * 2 - 1) * o, y + (rng() * 2 - 1) * o],
            [x + w + (rng() * 2 - 1) * o, y + h / 2 + (rng() * 2 - 1) * o],
            [x + w / 2 + (rng() * 2 - 1) * o, y + h + (rng() * 2 - 1) * o],
            [x + (rng() * 2 - 1) * o, y + h / 2 + (rng() * 2 - 1) * o]
        ]
    }

    // Absolute world points of a point-based element (line/arrow/freedraw).
    function absPoints(el) {
        var out = []
        if (!el.points) return out
        for (var i = 0; i < el.points.length; i++)
            out.push([el.x + el.points[i][0], el.y + el.points[i][1]])
        return out
    }

    function arrowHeadPaths(rng, fromX, fromY, toX, toY, roughness) {
        var ang = Math.atan2(toY - fromY, toX - fromX)
        var dist = Math.sqrt((toX - fromX) * (toX - fromX) + (toY - fromY) * (toY - fromY))
        var len = Math.min(24 + roughness * 6, Math.max(12, dist * 0.35))
        var spread = 0.35 + (rng() * 2 - 1) * 0.08
        return roughLinePath(rng, toX, toY, toX - Math.cos(ang - spread) * len, toY - Math.sin(ang - spread) * len, roughness, 1)
            .concat(roughLinePath(rng, toX, toY, toX - Math.cos(ang + spread) * len, toY - Math.sin(ang + spread) * len, roughness, 1))
    }

    // Draws one element in world coordinates. Touches ctx only; no ids.
    function drawElement(ctx, el) {
        var rng = mulberry32(el.seed)
        ctx.lineWidth = el.strokeWidth
        ctx.strokeStyle = el.strokeColor
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        var filled = el.fillStyle === "solid" && el.backgroundColor !== "transparent"
        var x = el.x, y = el.y, w = el.width, h = el.height
        var paths, pts, i, p, seg

        switch (el.type) {
        case "rectangle":
            if (filled) {
                ctx.fillStyle = el.backgroundColor
                ctx.fillRect(x, y, w, h)
            }
            ctx.strokeStyle = el.strokeColor
            paths = roughPolygonPaths(rng, rectCorners(rng, x, y, w, h, el.roughness), el.roughness)
            for (i = 0; i < paths.length; i++) {
                ctx.beginPath(); strokePolyline(ctx, paths[i]); ctx.stroke()
            }
            break
        case "ellipse": {
            var cx = x + w / 2, cy = y + h / 2
            if (filled) {
                ctx.fillStyle = el.backgroundColor
                ctx.beginPath()
                buildSmoothClosed(ctx, ellipsePoints(rng, cx, cy, w / 2, h / 2, el.roughness))
                ctx.fill()
            }
            ctx.strokeStyle = el.strokeColor
            for (p = 0; p < 2; p++) {
                ctx.beginPath()
                buildSmoothClosed(ctx, ellipsePoints(rng, cx, cy, w / 2, h / 2, el.roughness))
                ctx.stroke()
            }
            break
        }
        case "diamond":
            if (filled) {
                ctx.fillStyle = el.backgroundColor
                ctx.beginPath()
                ctx.moveTo(x + w / 2, y)
                ctx.lineTo(x + w, y + h / 2)
                ctx.lineTo(x + w / 2, y + h)
                ctx.lineTo(x, y + h / 2)
                ctx.closePath()
                ctx.fill()
            }
            ctx.strokeStyle = el.strokeColor
            paths = roughPolygonPaths(rng, diamondCorners(rng, x, y, w, h, el.roughness), el.roughness)
            for (i = 0; i < paths.length; i++) {
                ctx.beginPath(); strokePolyline(ctx, paths[i]); ctx.stroke()
            }
            break
        case "line":
            pts = absPoints(el)
            for (p = 0; p < 2; p++) {
                ctx.beginPath()
                for (i = 0; i < pts.length - 1; i++) {
                    seg = roughLinePath(rng, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], el.roughness, 1)
                    strokePolyline(ctx, seg[0])
                }
                ctx.stroke()
            }
            break
        case "arrow": {
            pts = absPoints(el)
            for (p = 0; p < 2; p++) {
                ctx.beginPath()
                for (i = 0; i < pts.length - 1; i++) {
                    seg = roughLinePath(rng, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], el.roughness, 1)
                    strokePolyline(ctx, seg[0])
                }
                ctx.stroke()
            }
            // A one-point arrow (e.g. a just-created draft) has no head yet.
            if (pts.length >= 2) {
                var heads = arrowHeadPaths(rng, pts[pts.length - 2][0], pts[pts.length - 2][1], pts[pts.length - 1][0], pts[pts.length - 1][1], el.roughness)
                for (i = 0; i < heads.length; i++) {
                    ctx.beginPath(); strokePolyline(ctx, heads[i]); ctx.stroke()
                }
            }
            break
        }
        case "freedraw":
            ctx.beginPath()
            strokePolyline(ctx, smoothFreedraw(absPoints(el)))
            ctx.stroke()
            break
        case "text": {
            ctx.fillStyle = el.strokeColor
            ctx.font = el.fontSize + 'px "Excalifont", "Comic Sans MS", sans-serif'
            var lines = String(el.text || "").split("\n")
            var lh = el.fontSize * 1.25
            for (var li = 0; li < lines.length; li++)
                ctx.fillText(lines[li], el.x, el.y + el.fontSize * 0.95 + lh * li)
            break
        }
        }
    }

    // Midpoint smoothing for pen input (points are already hand-drawn, so
    // no roughjs jitter here).
    function smoothFreedraw(pts) {
        if (pts.length < 3) return pts
        var out = [pts[0]]
        for (var i = 1; i < pts.length - 1; i++)
            out.push([(pts[i][0] + pts[i + 1][0]) / 2, (pts[i][1] + pts[i + 1][1]) / 2])
        out.push(pts[pts.length - 1])
        return out
    }

    // ---- model helpers ----
    function elementBounds(el) {
        if (el.points && el.points.length) {
            var minX = el.points[0][0], minY = el.points[0][1], maxX = minX, maxY = minY
            for (var i = 1; i < el.points.length; i++) {
                minX = Math.min(minX, el.points[i][0]); minY = Math.min(minY, el.points[i][1])
                maxX = Math.max(maxX, el.points[i][0]); maxY = Math.max(maxY, el.points[i][1])
            }
            return { x: el.x + minX, y: el.y + minY, w: maxX - minX, h: maxY - minY }
        }
        return { x: el.x, y: el.y, w: el.width, h: el.height }
    }

    function distanceToSegment(px, py, ax, ay, bx, by) {
        var dx = bx - ax, dy = by - ay
        var l2 = dx * dx + dy * dy
        if (l2 === 0) return Math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay))
        var t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
        var qx = ax + t * dx, qy = ay + t * dy
        return Math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy))
    }

    function hitTestElement(el, wx, wy, tol) {
        var t = tol + (el.strokeWidth || 1)
        if (el.points && el.points.length) {
            var pts = absPoints(el)
            for (var i = 0; i < pts.length - 1; i++)
                if (distanceToSegment(wx, wy, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]) <= t)
                    return true
            return false
        }
        var b = elementBounds(el)
        return pointInBox(wx, wy, b, t)
    }

    function pointInBox(wx, wy, b, tol) {
        return wx >= b.x - tol && wx <= b.x + b.w + tol && wy >= b.y - tol && wy <= b.y + b.h + tol
    }

    function normalizeElement(raw) {
        if (!raw || typeof raw !== "object" || raw.isDeleted) return null
        if (supportedTypes().indexOf(raw.type) === -1) return null
        var el = {
            id: typeof raw.id === "string" && raw.id.length > 0 ? raw.id : "imported",
            type: raw.type,
            x: numOr(raw.x, 0),
            y: numOr(raw.y, 0),
            width: numOr(raw.width, 0),
            height: numOr(raw.height, 0),
            angle: numOr(raw.angle, 0),
            strokeColor: typeof raw.strokeColor === "string" ? raw.strokeColor : "#1e1e1e",
            backgroundColor: typeof raw.backgroundColor === "string" ? raw.backgroundColor : "transparent",
            fillStyle: raw.fillStyle === "solid" ? "solid" : "",
            strokeWidth: [1, 2, 4].indexOf(raw.strokeWidth) !== -1 ? raw.strokeWidth : 2,
            roughness: Math.max(0, Math.min(2, numOr(raw.roughness, 1))),
            opacity: numOr(raw.opacity, 100),
            seed: numOr(raw.seed, 1),
            version: numOr(raw.version, 1)
        }
        if (raw.type === "line" || raw.type === "arrow" || raw.type === "freedraw") {
            var pts = []
            if (Array.isArray(raw.points))
                for (var i = 0; i < raw.points.length; i++)
                    if (Array.isArray(raw.points[i]) && raw.points[i].length >= 2)
                        pts.push([numOr(raw.points[i][0], 0), numOr(raw.points[i][1], 0)])
            if (pts.length < 2) return null
            el.points = pts
            // excalidraw convention: x/y is the bbox min corner of the points
            var minX = pts[0][0], minY = pts[0][1]
            for (i = 1; i < pts.length; i++) {
                minX = Math.min(minX, pts[i][0]); minY = Math.min(minY, pts[i][1])
            }
            el.x += minX; el.y += minY
            for (i = 0; i < pts.length; i++) { pts[i][0] -= minX; pts[i][1] -= minY }
        }
        if (raw.type === "text") {
            el.text = typeof raw.text === "string" ? raw.text : ""
            el.fontSize = Math.max(4, Math.min(200, numOr(raw.fontSize, 20)))
        }
        return el
    }

    function numOr(v, fallback) {
        return typeof v === "number" && isFinite(v) ? v : fallback
    }

    // Tolerant .excalidraw loader: unknown element types are skipped, not
    // fatal — interop means opening boards written by the real app.
    function parseBoard(text) {
        var result = { elements: [], appState: { scrollX: 0, scrollY: 0, zoom: 1, viewBackgroundColor: "#ffffff" }, skipped: 0 }
        var parsed
        try { parsed = JSON.parse(text) } catch (e) { return result }
        if (!parsed || typeof parsed !== "object") return result
        if (!Array.isArray(parsed.elements)) return result
        for (var i = 0; i < parsed.elements.length; i++) {
            var el = normalizeElement(parsed.elements[i])
            if (el) result.elements.push(el)
            else result.skipped++
        }
        var st = parsed.appState
        if (st && typeof st === "object") {
            result.appState.scrollX = numOr(st.scrollX, result.appState.scrollX)
            result.appState.scrollY = numOr(st.scrollY, result.appState.scrollY)
            result.appState.zoom = Math.max(0.2, Math.min(4, numOr(st.zoom, 1)))
            if (typeof st.viewBackgroundColor === "string") result.appState.viewBackgroundColor = st.viewBackgroundColor
        }
        return result
    }

    function serializeBoard(elements, appState) {
        return {
            type: "excalidraw",
            version: 2,
            source: "quickshell-excalidraw-widget (sidebar)",
            elements: elements,
            appState: {
                scrollX: appState.scrollX,
                scrollY: appState.scrollY,
                zoom: appState.zoom,
                viewBackgroundColor: appState.viewBackgroundColor
            }
        }
    }

    // ---- edits ----
    function cloneElement(el) {
        var out = {}
        for (var k in el) out[k] = el[k]
        if (el.points) {
            out.points = []
            for (var i = 0; i < el.points.length; i++) out.points.push([el.points[i][0], el.points[i][1]])
        }
        return out
    }

    function applyMove(el, dx, dy) {
        var out = cloneElement(el)
        out.x += dx
        out.y += dy
        return out
    }

    // Resize to a new bbox: shapes reposition directly, point-based
    // elements rescale their relative points (and re-anchor to the new
    // min corner), text scales its font.
    function resizeToBounds(el, box) {
        var b = elementBounds(el)
        var out = cloneElement(el)
        if (el.points) {
            var sx = b.w > 0 ? box.w / b.w : 1
            var sy = b.h > 0 ? box.h / b.h : 1
            var scaled = []
            var minX = 0, minY = 0
            for (var i = 0; i < el.points.length; i++) {
                var px = el.points[i][0] * sx, py = el.points[i][1] * sy
                if (i === 0 || px < minX) minX = px
                if (i === 0 || py < minY) minY = py
                scaled.push([px, py])
            }
            out.points = []
            for (i = 0; i < scaled.length; i++)
                out.points.push([scaled[i][0] - minX, scaled[i][1] - minY])
        } else if (el.type === "text") {
            var scale = b.h > 0 ? box.h / b.h : 1
            out.fontSize = Math.max(4, Math.min(200, el.fontSize * scale))
        }
        out.x = box.x
        out.y = box.y
        out.width = box.w
        out.height = box.h
        return out
    }

    // JS-END

    // ---- widget-level helpers (need ids/state; not part of the tested core) ----
    function urlToPath(u) {
        var s = u.toString()
        if (s.indexOf("file://") === 0) return decodeURIComponent(s.substring(7))
        return s
    }

    function genId() {
        return Date.now().toString(36) + Math.random().toString(36).substring(2, 8)
    }

    function findElement(id) {
        for (var i = 0; i < elements.length; ++i)
            if (elements[i].id === id) return elements[i]
        return null
    }

    // In-place push/splice on a `property var` array fires no change
    // notification; reassigning a shallow copy re-arms bindings that depend
    // on elements (e.g. the empty-board hint) while keeping the same
    // element object references.
    function syncElements() {
        elements = elements.slice()
    }

    function newElement(type, x, y) {
        var el = {
            id: genId(),
            type: type,
            x: x, y: y,
            width: 0, height: 0,
            angle: 0,
            strokeColor: strokeColor,
            backgroundColor: fillColor,
            fillStyle: fillColor === "transparent" ? "" : "solid",
            strokeWidth: strokeWidth,
            roughness: 1,
            opacity: 100,
            seed: Math.floor(Math.random() * 2147483647),
            version: 1,
            isDeleted: false,
            boundElements: null,
            groupIds: [],
            frameId: null,
            link: null,
            locked: false,
            updated: Date.now()
        }
        if (type === "text") { el.text = ""; el.fontSize = 20 }
        // Point-based tools drag out their geometry from this seed point;
        // without it the draft is painted (and committed) without points.
        if (type === "line" || type === "arrow" || type === "freedraw") el.points = [[0, 0]]
        return el
    }

    function touch(el) {
        el.version = (el.version || 1) + 1
        el.updated = Date.now()
    }

    // Undo snapshots are always the state BEFORE a mutation; callers must
    // push before changing anything.
    function pushUndoSnapshot(snap) {
        undoStack.push(snap)
        if (undoStack.length > 50) undoStack.shift()
        redoStack = []
        redoTop = 0
        undoTop = undoStack.length
    }

    function pushUndo() {
        pushUndoSnapshot(JSON.stringify(elements))
    }

    function undo() {
        if (undoStack.length === 0) return
        redoStack.push(JSON.stringify(elements))
        redoTop = redoStack.length
        elements = JSON.parse(undoStack.pop())
        undoTop = undoStack.length
        selectedEl = selectedEl ? findElement(selectedEl.id) : null
        board.requestPaint()
        saveTimer.restart()
    }

    function redo() {
        if (redoStack.length === 0) return
        undoStack.push(JSON.stringify(elements))
        undoTop = undoStack.length
        elements = JSON.parse(redoStack.pop())
        redoTop = redoStack.length
        selectedEl = selectedEl ? findElement(selectedEl.id) : null
        board.requestPaint()
        saveTimer.restart()
    }

    function deleteSelected() {
        if (!selectedEl) return
        pushUndo()
        for (var i = 0; i < elements.length; ++i) {
            if (elements[i].id === selectedEl.id) { elements.splice(i, 1); break }
        }
        syncElements()
        selectedEl = null
        board.requestPaint()
        saveTimer.restart()
    }

    function setTool(t) {
        if (editingId !== "") commitText()
        tool = t
        if (t !== "selection") selectedEl = null
        board.requestPaint()
    }

    function loadBoard() {
        var t = store.text()
        var data = t && t.length > 0 ? parseBoard(t) : null
        if (data && data.elements.length > 0) {
            elements = data.elements
            view.scrollX = data.appState.scrollX
            view.scrollY = data.appState.scrollY
            view.zoom = data.appState.zoom
            viewBg = data.appState.viewBackgroundColor
        } else {
            var v = centerViewport(body.width, body.height)
            view.scrollX = v.scrollX
            view.scrollY = v.scrollY
            view.zoom = 1
        }
        if (data && data.skipped > 0)
            showToast("Skipped " + data.skipped + " unsupported elements")
        zoomPct = Math.round(view.zoom * 100) + "%"
        loaded = true
        board.requestPaint()
    }

    function saveBoard() {
        store.setText(JSON.stringify(serializeBoard(elements, view)))
    }

    function showToast(msg) {
        toastText = msg
        toast.opacity = 1
        toastTimer.restart()
    }

    function drawSelectionOverlay(ctx) {
        if (!selectedEl || editingId !== "") return
        var r = selectionScreenRect()
        ctx.save()
        ctx.setTransform(1, 0, 0, 1, 0, 0)
        ctx.strokeStyle = shell.exAccentColor
        ctx.lineWidth = 1
        if (ctx.setLineDash) ctx.setLineDash([4, 4])
        ctx.strokeRect(r.x, r.y, r.w, r.h)
        if (ctx.setLineDash) ctx.setLineDash([])
        ctx.fillStyle = "#ffffff"
        for (var hx = 0; hx < 2; hx++) {
            for (var hy = 0; hy < 2; hy++) {
                var hxs = r.x + hx * r.w
                var hys = r.y + hy * r.h
                ctx.fillRect(hxs - 4, hys - 4, 8, 8)
                ctx.strokeRect(hxs - 4, hys - 4, 8, 8)
            }
        }
        ctx.restore()
    }

    // Screen-space rect of the selection incl. its 4 corner handles.
    function selectionScreenRect() {
        if (!selectedEl) return null
        var b = elementBounds(selectedEl)
        return {
            x: b.x * view.zoom + view.scrollX - 4,
            y: b.y * view.zoom + view.scrollY - 4,
            w: b.w * view.zoom + 8,
            h: b.h * view.zoom + 8
        }
    }

    function handleAt(sx, sy) {
        var r = selectionScreenRect()
        if (!r) return -1
        var corners = [[r.x, r.y], [r.x + r.w, r.y], [r.x, r.y + r.h], [r.x + r.w, r.y + r.h]]
        for (var i = 0; i < 4; i++)
            if (Math.abs(sx - corners[i][0]) <= 7 && Math.abs(sy - corners[i][1]) <= 7)
                return i
        return -1
    }

    function zoomStep(factor) {
        zoomAt(view, body.width / 2, body.height / 2, factor)
        zoomPct = Math.round(view.zoom * 100) + "%"
        board.requestPaint()
    }

    function resetView() {
        var v = centerViewport(board.width, board.height)
        view.scrollX = v.scrollX
        view.scrollY = v.scrollY
        view.zoom = 1
        zoomPct = "100%"
        board.requestPaint()
    }

    function requestPaintAll() {
        board.requestPaint()
    }

    // ---- text editing overlay ----
    function startTextEditing(el) {
        editingId = el.id
        textEditor.text = el.text || ""
        positionTextEditor(el)
        textEditor.visible = true
        textEditor.forceActiveFocus()
        focusTimer.restart()
    }

    function positionTextEditor(el) {
        var s = toScreen(view, el.x, el.y)
        textEditor.x = s[0]
        textEditor.y = s[1]
        textEditor.font.pixelSize = Math.max(6, el.fontSize * view.zoom)
        textEditor.color = el.strokeColor
    }

    function commitText() {
        if (editingId === "") return
        var el = findElement(editingId)
        var t = textEditor.text
        editingId = ""
        textEditor.visible = false
        var fresh = textFresh
        textFresh = false
        if (el) {
            if (!t || t.length === 0) {
                // A never-committed fresh element leaves no undo trace:
                // removing it just restores the pre-edit state.
                if (!fresh) pushUndo()
                for (var i = 0; i < elements.length; ++i)
                    if (elements[i].id === el.id) { elements.splice(i, 1); break }
                syncElements()
                if (selectedEl && selectedEl.id === el.id) selectedEl = null
            } else {
                pushUndo()
                el.text = t
                el.width = textEditor.paintedWidth / view.zoom
                el.height = textEditor.paintedHeight / view.zoom
                touch(el)
                selectedEl = el
            }
        }
        body.forceActiveFocus()
        board.requestPaint()
        saveTimer.restart()
    }

    // ---- popup chrome ----
    function toggle() {
        if (shell.ccPopup) shell.ccPopup.visible = false
        if (shell.notesPopup) shell.notesPopup.visible = false
        if (shell.bookPopup) shell.bookPopup.visible = false
        if (shell.spotifyPopup) shell.spotifyPopup.visible = false
        open = !open
        visible = open
    }

    function close() {
        if (editingId !== "") commitText()
        open = false
        visible = false
    }

    function exportPng() {
        board.grabToImage(function(result) {
            if (result && result.saveToFile(exDir + "/board.png"))
                showToast("Exported board.png")
            else
                showToast("Export failed")
        })
    }

    Shortcut {
        sequence: "Escape"
        enabled: ex.visible
        onActivated: {
            if (ex.editingId !== "") ex.commitText()
            else if (ex.selectedEl) { ex.selectedEl = null; ex.requestPaintAll() }
            else ex.close()
        }
    }

    Shortcut { sequence: "Ctrl+Z"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.undo() }
    Shortcut { sequence: "Ctrl+Shift+Z"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.redo() }
    Shortcut { sequence: "Ctrl+Y"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.redo() }
    Shortcut { sequence: "Delete"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.deleteSelected() }
    Shortcut { sequence: "Backspace"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.deleteSelected() }

    // Excalidraw tool hotkeys. Disabled while the text editor is open —
    // shortcuts would otherwise swallow the letters being typed.
    Shortcut { sequence: "V"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.setTool("selection") }
    Shortcut { sequence: "R"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.setTool("rectangle") }
    Shortcut { sequence: "O"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.setTool("ellipse") }
    Shortcut { sequence: "D"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.setTool("diamond") }
    Shortcut { sequence: "L"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.setTool("line") }
    Shortcut { sequence: "A"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.setTool("arrow") }
    Shortcut { sequence: "P"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.setTool("freedraw") }
    Shortcut { sequence: "T"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.setTool("text") }
    Shortcut { sequence: "E"; enabled: ex.visible && ex.editingId === ""; onActivated: ex.setTool("eraser") }

    Item {
        id: body
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Space && !event.isAutoRepeat && ex.editingId === "") {
                ex.spaceHeld = true
                event.accepted = true
            }
        }
        Keys.onReleased: function(event) {
            if (event.key === Qt.Key_Space) ex.spaceHeld = false
        }

        // Open/close animation: content fades and scales in. The layer
        // surface size is static, so animating the content is safe.
        opacity: ex.visible ? 1 : 0
        scale: ex.visible ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        MultiEffect {
            source: panel
            anchors.fill: panel
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.35
            shadowBlur: 0.8
            shadowVerticalOffset: 4
            z: -1
        }

        Rectangle {
            id: panel
            x: 8
            y: 8
            width: parent.width - 16
            height: parent.height - 16
            radius: shell.cornerRadius
            color: shell.exBgColor
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.08)
            clip: true

            Canvas {
                id: board
                anchors.fill: parent
                antialiasing: true

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.setTransform(1, 0, 0, 1, 0, 0)
                    ctx.fillStyle = ex.viewBg
                    ctx.fillRect(0, 0, width, height)
                    ctx.save()
                    ctx.translate(ex.view.scrollX, ex.view.scrollY)
                    ctx.scale(ex.view.zoom, ex.view.zoom)
                    // A throw inside onPaint (one malformed element must not
                    // blank the frame — an unpainted FBO shows up BLACK on
                    // some drivers) aborts the whole paint: isolate each
                    // element and skip the broken one instead.
                    for (var i = 0; i < ex.elements.length; ++i) {
                        try {
                            ex.drawElement(ctx, ex.elements[i])
                        } catch (e) {
                            console.warn("excalidraw: skipping unrenderable element", ex.elements[i] && ex.elements[i].type, e)
                        }
                    }
                    if (ex.draft) {
                        try {
                            ex.drawElement(ctx, ex.draft)
                        } catch (e) {
                            console.warn("excalidraw: draft render failed", e)
                        }
                    }
                    ctx.restore()
                    ex.drawSelectionOverlay(ctx)
                }

                WheelHandler {
                    acceptedModifiers: Qt.NoModifier
                    onWheel: function(event) {
                        ex.zoomAt(ex.view, event.x, event.y, Math.exp(-event.angleDelta.y * 0.0012))
                        ex.zoomPct = Math.round(ex.view.zoom * 100) + "%"
                        board.requestPaint()
                    }
                }

                MouseArea {
                    id: canvasMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: ex.spaceHeld || ex.panning ? Qt.ClosedHandCursor
                        : ex.tool === "text" ? Qt.IBeamCursor
                        : ex.tool === "selection" ? Qt.ArrowCursor
                        : Qt.CrossCursor

                    // Drag state: -1 idle, 0 create, 1 move, 2 resize, 3 pan, 4 erase
                    property int mode: -1
                    property real startWx: 0
                    property real startWy: 0
                    property real startSx: 0
                    property real startSy: 0
                    property var dragOrig: null
                    property var dragAnchor: null
                    property string pendingUndo: ""
                    property int resizeCorner: -1

                    function worldAt(mouse) {
                        return toWorld(ex.view, mouse.x, mouse.y)
                    }

                    onPressed: function(mouse) {
                        if (mouse.button === Qt.MiddleButton || ex.spaceHeld) {
                            mode = 3
                            ex.panning = true
                            startSx = mouse.x; startSy = mouse.y
                            dragOrig = { scrollX: ex.view.scrollX, scrollY: ex.view.scrollY }
                            return
                        }
                        if (ex.editingId !== "") ex.commitText()
                        var w = worldAt(mouse)
                        if (ex.tool === "selection") {
                            var handle = ex.handleAt(mouse.x, mouse.y)
                            if (handle !== -1 && ex.selectedEl) {
                                mode = 2
                                resizeCorner = handle
                                dragOrig = JSON.parse(JSON.stringify(ex.selectedEl))
                                pendingUndo = JSON.stringify(ex.elements)
                                return
                            }
                            var hit = null
                            for (var i = ex.elements.length - 1; i >= 0; --i)
                                if (hitTestElement(ex.elements[i], w[0], w[1], 4 / ex.view.zoom)) { hit = ex.elements[i]; break }
                            if (hit) {
                                ex.selectedEl = hit
                                mode = 1
                                startWx = w[0]; startWy = w[1]
                                dragOrig = JSON.parse(JSON.stringify(hit))
                                pendingUndo = JSON.stringify(ex.elements)
                            } else {
                                ex.selectedEl = null
                            }
                            board.requestPaint()
                            return
                        }
                        if (ex.tool === "eraser") {
                            mode = 4
                            pendingUndo = ""
                            eraseAt(w[0], w[1])
                            return
                        }
                        if (ex.tool === "text") {
                            var el = ex.newElement("text", w[0], w[1])
                            ex.elements.push(el)
                            syncElements()
                            textFresh = true
                            ex.startTextEditing(el)
                            board.requestPaint()
                            return
                        }
                        // shape / line / arrow / pen creation
                        mode = 0
                        var d = ex.newElement(ex.tool, w[0], w[1])
                        if (d.points !== undefined) d.points = [[0, 0]]
                        dragAnchor = { x: w[0], y: w[1] }
                        ex.draft = d
                        board.requestPaint()
                    }

                    onPositionChanged: function(mouse) {
                        var w = worldAt(mouse)
                        if (mode === 3) {
                            ex.view.scrollX = dragOrig.scrollX + (mouse.x - startSx)
                            ex.view.scrollY = dragOrig.scrollY + (mouse.y - startSy)
                            board.requestPaint()
                        } else if (mode === 0 && ex.draft && dragAnchor) {
                            var d = ex.draft
                            if (d.points !== undefined) {
                                if (d.type === "freedraw") {
                                    var last = d.points[d.points.length - 1]
                                    var lx = w[0] - d.x, ly = w[1] - d.y
                                    if (Math.hypot(lx - last[0], ly - last[1]) > 1.5) d.points.push([lx, ly])
                                } else {
                                    d.points[1] = [w[0] - d.x, w[1] - d.y]
                                }
                            } else {
                                d.x = Math.min(dragAnchor.x, w[0])
                                d.y = Math.min(dragAnchor.y, w[1])
                                d.width = Math.abs(w[0] - dragAnchor.x)
                                d.height = Math.abs(w[1] - dragAnchor.y)
                            }
                            board.requestPaint()
                        } else if (mode === 1 && ex.selectedEl && dragOrig) {
                            // dragOrig is a pristine copy: the move is always
                            // recomputed from it, never compounded.
                            var moved = applyMove(dragOrig, w[0] - startWx, w[1] - startWy)
                            ex.selectedEl.x = moved.x
                            ex.selectedEl.y = moved.y
                            board.requestPaint()
                        } else if (mode === 2 && ex.selectedEl && dragOrig) {
                            var ob = elementBounds(dragOrig)
                            var fixed = [[ob.x, ob.y], [ob.x + ob.w, ob.y], [ob.x, ob.y + ob.h], [ob.x + ob.w, ob.y + ob.h]][3 - resizeCorner]
                            var box = {
                                x: Math.min(fixed[0], w[0]),
                                y: Math.min(fixed[1], w[1]),
                                w: Math.max(1, Math.abs(w[0] - fixed[0])),
                                h: Math.max(1, Math.abs(w[1] - fixed[1]))
                            }
                            for (var j = 0; j < ex.elements.length; ++j) {
                                if (ex.elements[j].id === ex.selectedEl.id) {
                                    ex.elements[j] = resizeToBounds(dragOrig, box)
                                    ex.selectedEl = ex.elements[j]
                                    break
                                }
                            }
                            board.requestPaint()
                        } else if (mode === 4) {
                            eraseAt(w[0], w[1])
                        }
                    }

                    onReleased: function(mouse) {
                        if (mode === 3) {
                            ex.panning = false
                        } else if (mode === 0 && ex.draft) {
                            var d = ex.draft
                            var keep = true
                            if (d.points !== undefined) {
                                if (d.points.length < 2) keep = false
                                else normalizePointElement(d)
                            } else if (d.width < 4 && d.height < 4) {
                                keep = false
                            }
                            if (keep) {
                                ex.pushUndo()
                                ex.elements.push(d)
                                ex.syncElements()
                                ex.touch(d)
                                ex.selectedEl = d
                            }
                            ex.draft = null
                        } else if (mode === 1 && ex.selectedEl && dragOrig && pendingUndo !== "") {
                            var b0 = elementBounds(dragOrig)
                            var b1 = elementBounds(ex.selectedEl)
                            if (Math.abs(b0.x - b1.x) > 0.01 || Math.abs(b0.y - b1.y) > 0.01) {
                                ex.touch(ex.selectedEl)
                                ex.pushUndoSnapshot(pendingUndo)
                            }
                        } else if (mode === 2 && ex.selectedEl && dragOrig && pendingUndo !== "") {
                            var rb0 = elementBounds(dragOrig)
                            var rb1 = elementBounds(ex.selectedEl)
                            if (Math.abs(rb0.x - rb1.x) > 0.01 || Math.abs(rb0.y - rb1.y) > 0.01
                                || Math.abs(rb0.w - rb1.w) > 0.01 || Math.abs(rb0.h - rb1.h) > 0.01) {
                                ex.touch(ex.selectedEl)
                                ex.pushUndoSnapshot(pendingUndo)
                            }
                        } else if (mode === 4 && pendingUndo !== "") {
                            ex.pushUndoSnapshot(pendingUndo)
                        }
                        if (mode !== -1 && mode !== 3) saveTimer.restart()
                        mode = -1
                        dragOrig = null
                        dragAnchor = null
                        pendingUndo = ""
                        board.requestPaint()
                    }

                    function eraseAt(wx, wy) {
                        for (var i = ex.elements.length - 1; i >= 0; --i) {
                            if (hitTestElement(ex.elements[i], wx, wy, 4 / ex.view.zoom)) {
                                if (pendingUndo === "") pendingUndo = JSON.stringify(ex.elements)
                                ex.elements.splice(i, 1)
                                syncElements()
                                if (ex.selectedEl && findElement(ex.selectedEl.id) === null) ex.selectedEl = null
                                board.requestPaint()
                                saveTimer.restart()
                                return
                            }
                        }
                    }

                    // Re-anchor a fresh point element so x/y is the min corner.
                    function normalizePointElement(d) {
                        var minX = d.points[0][0], minY = d.points[0][1]
                        for (var i = 1; i < d.points.length; ++i) {
                            minX = Math.min(minX, d.points[i][0])
                            minY = Math.min(minY, d.points[i][1])
                        }
                        d.x += minX
                        d.y += minY
                        for (i = 0; i < d.points.length; ++i) {
                            d.points[i][0] -= minX
                            d.points[i][1] -= minY
                        }
                        d.width = 0
                        d.height = 0
                        for (i = 0; i < d.points.length; ++i) {
                            d.width = Math.max(d.width, d.points[i][0])
                            d.height = Math.max(d.height, d.points[i][1])
                        }
                    }
                }

                // Empty-board hint.
                Text {
                    anchors.centerIn: parent
                    text: "Draw something…  (V select · R rect · P pen · T text · space-drag pan)"
                    visible: ex.elements.length === 0 && !ex.draft && ex.loaded
                    font.pointSize: 11
                    color: Qt.rgba(0, 0, 0, 0.25)
                }

                TextEdit {
                    id: textEditor
                    visible: false
                    activeFocusOnPress: true
                    selectByMouse: true
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: {
                        var el = ex.findElement(ex.editingId)
                        if (el) {
                            el.width = paintedWidth / ex.view.zoom
                            el.height = paintedHeight / ex.view.zoom
                            board.requestPaint()
                        }
                    }
                    Keys.onEscapePressed: ex.commitText()
                    Keys.onReturnPressed: ex.commitText()
                    Keys.onEnterPressed: ex.commitText()
                }

                // Keeps the overlay glued to its element while panning or
                // zooming mid-edit (crude but sufficient).
                Timer {
                    id: editorSync
                    interval: 100
                    repeat: true
                    running: ex.editingId !== ""
                    onTriggered: {
                        var el = ex.findElement(ex.editingId)
                        if (el) ex.positionTextEditor(el)
                    }
                }
            }

            // ---- main toolbar ----
            Rectangle {
                id: toolBar
                x: (parent.width - width) / 2
                y: ex.visible ? 10 : -40
                radius: 10
                color: "#ffffff"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.08)
                width: toolRow.implicitWidth + 16
                height: toolRow.implicitHeight + 12
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                MultiEffect {
                    source: toolRow
                    anchors.fill: toolRow
                    shadowEnabled: true
                    shadowColor: "#000000"
                    shadowOpacity: 0.12
                    shadowBlur: 0.4
                    shadowVerticalOffset: 2
                    z: -1
                }
                Row {
                    id: toolRow
                    anchors.centerIn: parent
                    spacing: 2

                    ExTool { glyph: "\uf245"; active: ex.tool === "selection"; onPicked: ex.setTool("selection") }
                    ExTool { glyph: "\uf096"; active: ex.tool === "rectangle"; onPicked: ex.setTool("rectangle") }
                    ExTool { glyph: "\uf111"; active: ex.tool === "ellipse"; onPicked: ex.setTool("ellipse") }
                    // FA5-only codepoints (gem \uf3a5, slash \uf713) are NOT in
                    // AtkynsonMono Nerd Font (it only ships the FA4 range, like
                    // every other working icon in this shell) — use base-font
                    // geometric glyphs instead.
                    ExTool { glyph: "\u25C6"; active: ex.tool === "diamond"; onPicked: ex.setTool("diamond") }
                    ExTool { glyph: "\u2571"; active: ex.tool === "line"; onPicked: ex.setTool("line") }
                    ExTool { glyph: "\uf062"; active: ex.tool === "arrow"; onPicked: ex.setTool("arrow") }
                    ExTool { glyph: "\uf040"; active: ex.tool === "freedraw"; onPicked: ex.setTool("freedraw") }
                    ExTool { glyph: "\uf031"; active: ex.tool === "text"; onPicked: ex.setTool("text") }
                    ExTool { glyph: "\uf12d"; active: ex.tool === "eraser"; onPicked: ex.setTool("eraser") }

                    ExDivider {}

                    ExTool { glyph: "\uf0e2"; enabled: ex.undoTop > 0; onPicked: ex.undo() }
                    ExTool { glyph: "\uf01e"; enabled: ex.redoTop > 0; onPicked: ex.redo() }
                    ExTool { glyph: "\uf014"; enabled: ex.selectedEl !== null; onPicked: ex.deleteSelected() }

                    ExDivider {}

                    ExTool { glyph: "\uf068"; onPicked: ex.zoomStep(1 / 1.2) }
                    ExTool { label: ex.zoomPct; onPicked: ex.resetView() }
                    ExTool { glyph: "\uf067"; onPicked: ex.zoomStep(1.2) }

                    ExDivider {}

                    ExTool { glyph: "\uf019"; onPicked: ex.exportPng() }
                    ExTool { glyph: "\uf08e"; onPicked: Quickshell.execDetached(["xdg-open", ex.boardPath]) }
                }
            }

            // ---- style bar (stroke colors, fill, stroke width) ----
            Rectangle {
                id: styleBar
                x: (parent.width - width) / 2
                y: ex.visible ? 56 : -40
                radius: 10
                color: "#ffffff"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.08)
                width: styleRow.implicitWidth + 16
                height: styleRow.implicitHeight + 12
                Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                MultiEffect {
                    source: styleRow
                    anchors.fill: styleRow
                    shadowEnabled: true
                    shadowColor: "#000000"
                    shadowOpacity: 0.12
                    shadowBlur: 0.4
                    shadowVerticalOffset: 2
                    z: -1
                }
                Row {
                    id: styleRow
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: ex.strokePresets
                        delegate: ExSwatch {
                            colorValue: modelData
                            selected: ex.strokeColor === modelData
                            onPicked: { ex.strokeColor = modelData; board.requestPaint() }
                        }
                    }

                    ExDivider {}

                    Repeater {
                        model: ex.fillPresets
                        delegate: ExSwatch {
                            colorValue: modelData
                            transparentStyle: modelData === "transparent"
                            selected: ex.fillColor === modelData
                            onPicked: { ex.fillColor = modelData; board.requestPaint() }
                        }
                    }

                    ExDivider {}

                    Repeater {
                        model: [
                            { w: 1, dot: 2 },
                            { w: 2, dot: 4 },
                            { w: 4, dot: 7 }
                        ]
                        delegate: ExWidthButton {
                            widthValue: modelData.w
                            dotSize: modelData.dot
                            selected: ex.strokeWidth === modelData.w
                            onPicked: { ex.strokeWidth = modelData.w; board.requestPaint() }
                        }
                    }
                }
            }

            // Toast feedback (export, skipped elements, …).
            Rectangle {
                id: toast
                x: (parent.width - width) / 2
                y: parent.height - 46
                width: toastLabel.implicitWidth + 28
                height: 32
                radius: 16
                color: Qt.rgba(0.1, 0.1, 0.12, 0.85)
                opacity: 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Text {
                    id: toastLabel
                    anchors.centerIn: parent
                    text: ex.toastText
                    color: "#ffffff"
                    font.pointSize: 9
                }
                Timer {
                    id: toastTimer
                    interval: 2200
                    onTriggered: toast.opacity = 0
                }
            }
        }
    }
}
