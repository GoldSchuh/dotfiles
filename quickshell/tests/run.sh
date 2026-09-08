#!/usr/bin/env bash
# Headless test suite (no quickshell / display needed): re-extracts the
# testable JS cores from the QML sources on every run, so it always tests
# what is in the tree.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== excalidraw: extract core =="
awk '/JS-BEGIN/{f=1;next} /JS-END/{f=0} f' "$ROOT/sidebar/ExcalidrawWidget.qml" > "$TMP/excalidraw-core.js"
[ -s "$TMP/excalidraw-core.js" ] || { echo "FAIL: core extraction came out empty"; exit 1; }

echo "== excalidraw: core syntax (node --check) =="
node --check "$TMP/excalidraw-core.js"

echo "== excalidraw: core tests =="
EXCAL_CORE="$TMP/excalidraw-core.js" node "$ROOT/tests/excalidraw.test.js"

echo "== qml structural lint =="
python3 "$ROOT/tests/qml_lint.py" "$ROOT"

echo ""
echo "ALL PASSED"
