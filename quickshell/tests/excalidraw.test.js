// Headless tests for the excalidraw widget's pure JS core. The core is
// extracted verbatim from sidebar/ExcalidrawWidget.qml (between the
// JS-BEGIN / JS-END markers) by tests/run.sh and handed to us via
// EXCAL_CORE; eval'ing it here means we always test exactly what ships.
"use strict"
const assert = require("assert")
const fs = require("fs")

const coreSource = fs.readFileSync(process.env.EXCAL_CORE, "utf8")
// eslint-disable-next-line no-eval
;(0, eval)(coreSource)

// ---- helpers ------------------------------------------------------------

// Canvas-2D mock: records the call sequence and property writes so the
// roughjs-style renderer's logic (order of fill vs stroke, pass counts,
// arrowheads, fonts) can be pinned without Qt.
function mockCtx() {
  const ops = []
  const props = {}
  const ctx = { _ops: ops, _props: props }
  const rec = (name) => (...args) => ops.push([name, ...args])
  for (const n of ["beginPath", "closePath", "moveTo", "lineTo", "quadraticCurveTo",
    "bezierCurveTo", "stroke", "fill", "fillRect", "fillText", "save", "restore",
    "setLineDash", "clearRect", "translate", "scale"])
    ctx[n] = rec(n)
  ctx.measureText = (t) => ({ width: String(t).length * 10 })
  for (const p of ["fillStyle", "strokeStyle", "lineWidth", "font", "lineCap", "lineJoin"])
    Object.defineProperty(ctx, p, { set: (v) => { props[p] = v; ops.push([":" + p, v]) }, get: () => props[p] })
  return ctx
}

const count = (ops, name) => ops.filter((o) => o[0] === name).length

function rectEl(over) {
  return Object.assign({
    id: "t1", type: "rectangle", x: 10, y: 20, width: 100, height: 50,
    strokeColor: "#1e1e1e", backgroundColor: "transparent", fillStyle: "",
    strokeWidth: 2, roughness: 1, opacity: 100, seed: 42, version: 1
  }, over || {})
}

function lineEl(over) {
  return Object.assign({
    id: "t2", type: "line", x: 0, y: 0,
    points: [[10, 10], [60, 10], [60, 60]],
    strokeColor: "#1e1e1e", backgroundColor: "transparent", fillStyle: "",
    strokeWidth: 2, roughness: 1, opacity: 100, seed: 7, version: 1
  }, over || {})
}

let n = 0
function test(name, fn) {
  n++
  try {
    fn()
    console.log("  ok - " + name)
  } catch (e) {
    console.error("  FAIL - " + name)
    console.error(e && e.stack ? e.stack : e)
    process.exitCode = 1
  }
}

// ---- PRNG ----------------------------------------------------------------

test("mulberry32 is deterministic for the same seed", () => {
  const a = mulberry32(1234), b = mulberry32(1234)
  for (let i = 0; i < 100; i++) assert.strictEqual(a(), b())
})

test("mulberry32 differs across seeds", () => {
  const a = mulberry32(1), b = mulberry32(2)
  assert.notStrictEqual(a(), b())
})

test("mulberry32 output stays in [0,1)", () => {
  const a = mulberry32(999)
  for (let i = 0; i < 1000; i++) {
    const v = a()
    assert.ok(v >= 0 && v < 1, "out of range: " + v)
  }
})

// ---- coordinate transforms ------------------------------------------------

test("toScreen / toWorld roundtrip", () => {
  const view = { scrollX: 120, scrollY: -40, zoom: 1.7 }
  const s = toScreen(view, 33, -12)
  const w = toWorld(view, s[0], s[1])
  assert.ok(Math.abs(w[0] - 33) < 1e-9 && Math.abs(w[1] + 12) < 1e-9)
})

test("zoomAt keeps the world point under the cursor fixed", () => {
  const view = { scrollX: 300, scrollY: 200, zoom: 1 }
  const w0 = toWorld(view, 400, 250)
  zoomAt(view, 400, 250, 2)
  const w1 = toWorld(view, 400, 250)
  assert.ok(Math.abs(w0[0] - w1[0]) < 1e-9 && Math.abs(w0[1] - w1[1]) < 1e-9)
  assert.strictEqual(view.zoom, 2)
})

test("zoomAt clamps to [0.2, 4]", () => {
  const view = { scrollX: 0, scrollY: 0, zoom: 3.9 }
  zoomAt(view, 0, 0, 100)
  assert.strictEqual(view.zoom, 4)
  zoomAt(view, 0, 0, 0.0001)
  assert.strictEqual(view.zoom, 0.2)
})

test("centerViewport puts the world origin at the screen center", () => {
  const v = centerViewport(800, 600)
  assert.deepStrictEqual(toScreen(v, 0, 0), [400, 300])
})

// ---- roughjs-style stroke generation ---------------------------------------

test("roughLinePath is deterministic per seed and has 2 passes", () => {
  const p1 = roughLinePath(mulberry32(5), 0, 0, 100, 0, 1, 2)
  const p2 = roughLinePath(mulberry32(5), 0, 0, 100, 0, 1, 2)
  const p3 = roughLinePath(mulberry32(6), 0, 0, 100, 0, 1, 2)
  assert.deepStrictEqual(p1, p2)
  assert.notDeepStrictEqual(p1, p3)
  assert.strictEqual(p1.length, 2)
  assert.strictEqual(p1[0].length, 3) // endpoints + midpoint jitter for len>16
})

test("roughLinePath with roughness 0 still jitters endpoints (amp from length)", () => {
  // roughness 0 collapses amplitude entirely: endpoints must be exact.
  const p = roughLinePath(mulberry32(9), 0, 0, 100, 0, 0, 1)
  assert.deepStrictEqual(p[0][0], [0, 0])
  assert.deepStrictEqual(p[0][p[0].length - 1], [100, 0])
})

test("roughPolygonPaths on a rectangle yields 4 sides x 2 passes", () => {
  const c = rectCorners(mulberry32(3), 0, 0, 100, 60, 1)
  const paths = roughPolygonPaths(mulberry32(3), c, 1)
  assert.strictEqual(paths.length, 8)
})

test("rectCorners sit on the rect edges (jitter <= roughness*1.2)", () => {
  const c = rectCorners(mulberry32(4), 10, 10, 100, 60, 1)
  assert.ok(Math.abs(c[0][0] - 10) <= 1.2 + 1e-9 && Math.abs(c[0][1] - 10) <= 1.2 + 1e-9)
  assert.ok(Math.abs(c[1][0] - 110) <= 1.2 + 1e-9)
  assert.ok(Math.abs(c[2][1] - 70) <= 1.2 + 1e-9)
})

test("ellipsePoints stay within 2%*roughness of the radius", () => {
  const pts = ellipsePoints(mulberry32(11), 0, 0, 50, 30, 1)
  assert.strictEqual(pts.length, 18)
  for (const [x, y] of pts) {
    const r = Math.sqrt((x / 50) * (x / 50) + (y / 30) * (y / 30))
    assert.ok(Math.abs(r - 1) <= 0.02 + 1e-9, "radius drift " + r)
  }
})

test("buildSmoothClosed emits moveTo + n quadraticCurveTo + closePath", () => {
  const ctx = mockCtx()
  const pts = ellipsePoints(mulberry32(2), 0, 0, 10, 10, 1)
  ctx.beginPath()
  buildSmoothClosed(ctx, pts)
  assert.strictEqual(count(ctx._ops, "moveTo"), 1)
  assert.strictEqual(count(ctx._ops, "quadraticCurveTo"), pts.length)
  assert.strictEqual(count(ctx._ops, "closePath"), 1)
})

test("smoothFreedraw passes through short input and smooths long input", () => {
  assert.strictEqual(smoothFreedraw([[0, 0], [1, 1]]).length, 2)
  const out = smoothFreedraw([[0, 0], [10, 0], [20, 10], [30, 30]])
  assert.strictEqual(out.length, 4)
  // first and last stay fixed, interior points are midpoints
  assert.deepStrictEqual(out[0], [0, 0])
  assert.deepStrictEqual(out[out.length - 1], [30, 30])
  assert.deepStrictEqual(out[1], [15, 5])
})

test("arrowHeadPaths returns two head strokes per call", () => {
  const heads = arrowHeadPaths(mulberry32(8), 0, 0, 100, 0, 1)
  assert.strictEqual(heads.length, 2)
})

// ---- geometry / hit-testing -------------------------------------------------

test("distanceToSegment measures perpendicular distance", () => {
  assert.strictEqual(distanceToSegment(5, 7, 0, 0, 10, 0), 7)
  // beyond the ends: distance to the nearest endpoint
  assert.strictEqual(distanceToSegment(-3, 0, 0, 0, 10, 0), 3)
  assert.strictEqual(distanceToSegment(13, 4, 0, 0, 10, 0), 5)
})

test("distanceToSegment handles degenerate (zero-length) segments", () => {
  assert.strictEqual(distanceToSegment(3, 4, 0, 0, 0, 0), 5)
})

test("pointInBox respects the tolerance", () => {
  const b = { x: 0, y: 0, w: 10, h: 10 }
  assert.ok(pointInBox(5, 5, b, 0))
  assert.ok(pointInBox(11.5, 5, b, 2))
  assert.ok(!pointInBox(13, 5, b, 2))
})

test("elementBounds for shapes uses x/y/width/height", () => {
  const b = elementBounds(rectEl())
  assert.deepStrictEqual(b, { x: 10, y: 20, w: 100, h: 50 })
})

test("elementBounds for point elements derives the bbox from points", () => {
  const b = elementBounds(lineEl())
  assert.deepStrictEqual(b, { x: 10, y: 10, w: 50, h: 50 })
})

test("hitTestElement hits rect interiors", () => {
  const el = rectEl()
  assert.ok(hitTestElement(el, 50, 40, 2))
  assert.ok(!hitTestElement(el, 500, 500, 2))
})

test("hitTestElement hits strokes near the path but not the bbox", () => {
  const el = lineEl() // L shape: (10,10) -> (60,10) -> (60,60)
  assert.ok(hitTestElement(el, 30, 11, 1))       // on the horizontal leg
  assert.ok(hitTestElement(el, 61, 40, 1))       // on the vertical leg
  assert.ok(!hitTestElement(el, 20, 50, 1))      // inside bbox, off path
})

test("hitTestElement tolerance adds to strokeWidth", () => {
  const el = rectEl({ strokeWidth: 4 })
  assert.ok(hitTestElement(el, 9, 40, 1))        // 1px off the left edge
  assert.ok(!hitTestElement(el, 2, 40, 1))
})

// ---- model: normalize / parse / serialize ------------------------------------

test("normalizeElement fills defaults and keeps known types", () => {
  const el = normalizeElement({ type: "rectangle", x: 1, y: 2 })
  assert.ok(el)
  assert.strictEqual(el.strokeColor, "#1e1e1e")
  assert.strictEqual(el.backgroundColor, "transparent")
  assert.strictEqual(el.fillStyle, "")
  assert.strictEqual(el.strokeWidth, 2)
  assert.strictEqual(el.roughness, 1)
  assert.strictEqual(el.seed, 1)
  assert.strictEqual(el.opacity, 100)
})

test("normalizeElement rejects unknown / deleted elements", () => {
  assert.strictEqual(normalizeElement({ type: "image" }), null)
  assert.strictEqual(normalizeElement({ type: "iframe" }), null)
  assert.strictEqual(normalizeElement({ type: "rectangle", isDeleted: true }), null)
  assert.strictEqual(normalizeElement(null), null)
  assert.strictEqual(normalizeElement("nope"), null)
})

test("normalizeElement rejects point elements with fewer than 2 points", () => {
  assert.strictEqual(normalizeElement({ type: "line", points: [[0, 0]] }), null)
})

test("normalizeElement re-anchors point elements to the min corner", () => {
  const el = normalizeElement({ type: "line", x: 100, y: 100, points: [[50, 40], [-10, 0], [0, 30]] })
  assert.strictEqual(el.x, 90)   // 100 + (-10)
  assert.strictEqual(el.y, 100)
  assert.deepStrictEqual(el.points, [[60, 40], [0, 0], [10, 30]])
})

test("normalizeElement clamps strokeWidth / roughness / fontSize", () => {
  assert.strictEqual(normalizeElement({ type: "rectangle", strokeWidth: 3 }).strokeWidth, 2)
  assert.strictEqual(normalizeElement({ type: "rectangle", strokeWidth: 1 }).strokeWidth, 1)
  assert.strictEqual(normalizeElement({ type: "rectangle", roughness: 9 }).roughness, 2)
  assert.strictEqual(normalizeElement({ type: "text", fontSize: 999 }).fontSize, 200)
})

test("parseBoard skips unsupported elements and counts them", () => {
  const board = {
    type: "excalidraw", version: 2,
    elements: [
      { type: "rectangle", x: 1, y: 2 },
      { type: "image", x: 0, y: 0 },
      { type: "iframe", x: 0, y: 0 },
      { type: "rectangle", isDeleted: true }
    ],
    appState: { scrollX: 10, scrollY: -5, zoom: 2, viewBackgroundColor: "#fafafa" }
  }
  const r = parseBoard(JSON.stringify(board))
  assert.strictEqual(r.elements.length, 1)
  assert.strictEqual(r.skipped, 3)
  assert.strictEqual(r.appState.scrollX, 10)
  assert.strictEqual(r.appState.zoom, 2)
  assert.strictEqual(r.appState.viewBackgroundColor, "#fafafa")
})

test("parseBoard clamps insane zoom values", () => {
  const r = parseBoard(JSON.stringify({ elements: [], appState: { zoom: 50 } }))
  assert.strictEqual(r.appState.zoom, 4)
})

test("parseBoard survives garbage input", () => {
  for (const t of ["", "not json", "null", "42", "{\"nope\":1}"]) {
    const r = parseBoard(t)
    assert.deepStrictEqual(r.elements, [])
  }
})

test("serializeBoard writes the real .excalidraw shape and roundtrips", () => {
  const els = [rectEl(), lineEl()]
  const app = { scrollX: 5, scrollY: 6, zoom: 1.5, viewBackgroundColor: "#ffffff" }
  const text = JSON.stringify(serializeBoard(els, app))
  const parsed = JSON.parse(text)
  assert.strictEqual(parsed.type, "excalidraw")
  assert.strictEqual(parsed.version, 2)
  assert.ok(typeof parsed.source === "string" && parsed.source.length > 0)
  const r = parseBoard(text)
  assert.strictEqual(r.elements.length, 2)
  assert.deepStrictEqual(r.elements[0].points, undefined)
  assert.strictEqual(r.appState.zoom, 1.5)
})

test("serializeBoard roundtrips point elements losslessly", () => {
  const el = normalizeElement({ type: "arrow", x: 5, y: 5, points: [[0, 0], [40, 60]], seed: 3 })
  const r = parseBoard(JSON.stringify(serializeBoard([el], { scrollX: 0, scrollY: 0, zoom: 1, viewBackgroundColor: "#fff" })))
  assert.strictEqual(r.elements.length, 1)
  assert.deepStrictEqual(r.elements[0].points, [[0, 0], [40, 60]])
  assert.strictEqual(r.elements[0].x, 5)
})

// ---- edits ------------------------------------------------------------------

test("cloneElement deep-copies points", () => {
  const el = lineEl()
  const c = cloneElement(el)
  c.points[0][0] = 999
  assert.strictEqual(el.points[0][0], 10)
})

test("applyMove shifts x/y without touching relative points", () => {
  const el = lineEl()
  const m = applyMove(el, 5, -3)
  assert.strictEqual(m.x, 5)
  assert.strictEqual(m.y, -3)
  assert.deepStrictEqual(m.points, el.points)
})

test("resizeToBounds rescales point elements into the new bbox", () => {
  const el = lineEl() // bbox 10,10 50x50 (abs)
  const r = resizeToBounds(el, { x: 10, y: 10, w: 100, h: 150 })
  const b = elementBounds(r)
  assert.deepStrictEqual([b.x, b.y, b.w, b.h], [10, 10, 100, 150])
  // shape preserved: the corner point stays proportional
  assert.ok(Math.abs(r.points[2][0] - 100) < 1e-9)
  assert.ok(Math.abs(r.points[2][1] - 150) < 1e-9)
})

test("resizeToBounds keeps the fixed corner for shapes", () => {
  const el = rectEl() // 10,20 100x50
  const r = resizeToBounds(el, { x: 10, y: 20, w: 200, h: 25 })
  assert.strictEqual(r.x, 10)
  assert.strictEqual(r.y, 20)
  assert.strictEqual(r.width, 200)
  assert.strictEqual(r.height, 25)
})

test("resizeToBounds scales text fontSize and clamps it", () => {
  const el = rectEl({ type: "text", text: "hi", fontSize: 20, width: 40, height: 25 })
  const up = resizeToBounds(el, { x: 10, y: 20, w: 80, h: 50 })
  assert.strictEqual(up.fontSize, 40)
  const cap = resizeToBounds(el, { x: 10, y: 20, w: 4000, h: 2500 })
  assert.strictEqual(cap.fontSize, 200)
})

// ---- renderer (mock ctx) ------------------------------------------------------

test("drawElement rectangle: solid fill is painted before the strokes", () => {
  const ctx = mockCtx()
  drawElement(ctx, rectEl({ fillStyle: "solid", backgroundColor: "#ced4da" }))
  const fillIdx = ctx._ops.findIndex((o) => o[0] === "fillRect")
  assert.ok(fillIdx !== -1, "no fillRect")
  const firstStroke = ctx._ops.findIndex((o) => o[0] === "stroke")
  assert.ok(firstStroke > fillIdx, "fill must come before stroke")
  assert.strictEqual(ctx._props.fillStyle, "#ced4da")
})

test("drawElement rectangle without fill never fills", () => {
  const ctx = mockCtx()
  drawElement(ctx, rectEl())
  assert.strictEqual(count(ctx._ops, "fillRect"), 0)
})

test("drawElement rectangle emits 8 stroke passes (4 sides x 2)", () => {
  const ctx = mockCtx()
  drawElement(ctx, rectEl())
  assert.strictEqual(count(ctx._ops, "stroke"), 8)
})

test("drawElement is deterministic for the same seed", () => {
  const ctx1 = mockCtx(), ctx2 = mockCtx()
  drawElement(ctx1, rectEl({ seed: 123 }))
  drawElement(ctx2, rectEl({ seed: 123 }))
  assert.deepStrictEqual(ctx1._ops, ctx2._ops)
  drawElement(ctx1, rectEl({ seed: 124 }))
  assert.notDeepStrictEqual(ctx1._ops, ctx2._ops)
})

test("drawElement arrow emits body passes plus arrowhead strokes", () => {
  const ctx = mockCtx()
  drawElement(ctx, lineEl({ type: "arrow", points: [[0, 0], [120, 0]] }))
  // 2 body passes + 2 head strokes
  assert.strictEqual(count(ctx._ops, "stroke"), 4)
})

test("drawElement ellipse fills under strokes when solid", () => {
  const ctx = mockCtx()
  drawElement(ctx, rectEl({ type: "ellipse", fillStyle: "solid", backgroundColor: "#ffc9c9" }))
  assert.strictEqual(count(ctx._ops, "fill"), 1)
  assert.strictEqual(count(ctx._ops, "stroke"), 2)
  const fillIdx = ctx._ops.findIndex((o) => o[0] === "fill")
  assert.ok(fillIdx < ctx._ops.findIndex((o) => o[0] === "stroke"))
})

test("drawElement text draws one fillText per line with a font set", () => {
  const ctx = mockCtx()
  drawElement(ctx, rectEl({ type: "text", text: "one\ntwo", fontSize: 20 }))
  const texts = ctx._ops.filter((o) => o[0] === "fillText")
  assert.strictEqual(texts.length, 2)
  assert.strictEqual(texts[0][1], "one")
  assert.strictEqual(texts[1][1], "two")
  assert.ok(/20px/.test(ctx._props.font), ctx._props.font)
})

test("drawElement freedraw strokes a smoothed polyline", () => {
  const ctx = mockCtx()
  drawElement(ctx, lineEl({ type: "freedraw", points: [[0, 0], [10, 2], [20, 5], [30, 9]] }))
  assert.strictEqual(count(ctx._ops, "stroke"), 1)
  assert.strictEqual(count(ctx._ops, "moveTo"), 1)
  // 4 input points -> 3 lineTo after midpoint smoothing
  assert.strictEqual(count(ctx._ops, "lineTo"), 3)
})

test("drawElement line is drawn with two jittered passes", () => {
  const ctx = mockCtx()
  drawElement(ctx, lineEl())
  assert.strictEqual(count(ctx._ops, "stroke"), 2)
})

console.log("excalidraw core: " + n + " tests")
