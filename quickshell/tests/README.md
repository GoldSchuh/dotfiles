# Headless tests

Run from anywhere:

```sh
tests/run.sh
```

Needs only `bash`, `node` and `python3` — no quickshell or display. The suite
re-extracts the testable cores from the QML sources on every run, so it always
tests exactly what is in the tree.

## What it covers

**`excalidraw.test.js` — the whiteboard core** (extracted verbatim from the
`JS-BEGIN`/`JS-END` block in `sidebar/ExcalidrawWidget.qml`, 47 tests):

- `mulberry32` PRNG: determinism per seed, seed divergence, output range
- coordinate transforms: `toScreen`/`toWorld` roundtrip, `zoomAt`
  (cursor-stable zoom + [0.2, 4] clamping), `centerViewport`
- roughjs-style stroke generation: `roughLinePath` (2 passes, seeded
  jitter), `roughPolygonPaths`/`rectCorners` (4 sides × 2 passes, edge
  jitter bound), `ellipsePoints` (radius drift ≤ 2%·roughness),
  `buildSmoothClosed` (emit counts), `smoothFreedraw`, `arrowHeadPaths`
- geometry / hit-testing: `distanceToSegment` (perpendicular, endpoints,
  degenerate), `pointInBox` tolerance, `elementBounds` for shape vs point
  elements, `hitTestElement` (rect interiors, strokes near path but inside
  the bbox, tolerance adds to strokeWidth)
- model/serialization: `normalizeElement` (defaults, unknown-type and
  deleted rejection, min-corner re-anchoring of point elements, clamping),
  `parseBoard` (skips unsupported types with a count, applies + clamps
  appState, survives garbage), `serializeBoard` (real `.excalidraw` shape
  and lossless roundtrip)
- edits: `cloneElement` deep-copies points, `applyMove`, `resizeToBounds`
  (point elements rescale into the new bbox, shapes keep the fixed corner,
  text scales/clamps fontSize)
- renderer against a mock Canvas-2D: solid fill painted before strokes (and
  never without), pass counts, seed determinism, arrowheads, per-line
  `fillText` with a font set, freedraw smoothing

**`qml_lint.py` — structural lint for every tracked QML file**: after
stripping comments and string literals, braces/parens/brackets must balance
and files must be non-empty. (JS regex literals inside a file would fool the
stripper; if a file ever legitimately needs one with unbalanced brackets,
pin its expected delta explicitly — today no file does.)

## Pinned bug-fix contracts

- `resizeToBounds` must re-anchor the rescaled relative points to the new
  min corner — the first implementation left them unscaled-relative, which
  moved the visible bbox to `box.x + scaledMin`.
- `normalizeElement` must re-anchor imported point elements to their min
  corner (excalidraw's own convention), otherwise hit-testing and bounds
  are offset for imported boards.
- `drawElement` must derive all jitter from the element's persisted `seed`
  (never `Math.random`) — a redraw of the same board must reproduce the
  same wobble.
