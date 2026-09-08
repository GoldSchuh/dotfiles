# AGENTS.md

Guidance for AI agents editing this Quickshell config.

## What this is

A Quickshell (QML) shell for the **niri** Wayland compositor. It renders a
floating red bar with a workspace label, notes widget, control center, and
clock, plus a hidden left-edge dock and a bookshelf popup. Quickshell 0.3.1,
Qt 6.

## Layout

- `shell.qml` — root `Scope`. Owns all shared theme/layout properties and the
  bar `PanelWindow`. Composes the widgets.
- `widgets/` — one QML file per widget:
  - `NotesWidget.qml` — bar button + editable notes window (autosaves to a
    daily file `~/Dokumente/Notizen/Tag/DD-MM-YYYY.md`; rolls over at midnight)
  - `ControlCenter.qml` — media controls, volume slider, power off
  - `ClockWidget.qml` — updating date/time label
  - `WorkspaceWidget.qml` — static workspace label
  - `BluetoothWidget.qml` — bluetooth toggle (click toggles the default
    adapter via `Quickshell.Bluetooth`; dim icon while disabled)
- `sidebar/` — the left sidebar dock:
  - `sidebar/SidebarWidget.qml` — dock capsule on the left screen edge,
    vertically centered, hidden behind a slim always-present trigger strip
    at the very edge; slides out (window expands + pill slides/fades in)
    when the mouse reaches the edge, tucks away when it leaves (stays out
    while the book picker is open). Quickshell has no global cursor API, so
    the strip is how "mouse near the edge" is implemented at all — and it
    must stay slim, because a surface's hover zone is also its input region
    (a wide strip swallows every click inside it). Column of colorful
    placeholder app icons; the bottom book icon toggles the book picker.
    Uses the shared theme colors (`shell.barColor` etc.)
  - `sidebar/BookPicker.qml` — popup window cloning the UI of the
    "bookshelfs" Nextcloud app (github.com/Goldschuh/bookshelfs): create
    form + "Add book from file" + Restyle/Reset nav, a shelf of book spines
    (colour/pattern/height, vertical title, drag to reorder, hover cover
    preview, double click opens the linked file) and an edit sidebar
    (update/delete). Picked covers/e-books are copied into the managed
    library dir `bookshelfs/` (gitignored — personal data, never commit)
    under generated names (`<id>-cover.<ext>` following the picked image,
    `<id>.epub` or `<id>.pdf`); `bookshelfs/shelf.json` stores only those
    names, never paths (mirrors the Nextcloud file-ID model). Epub
    title/author are extracted from OPF metadata. Legacy data in
    `~/.local/share/quickshell/bookshelfs.json` is migrated on load when
    `shelf.json` does not exist yet
  - `sidebar/BookForm.qml` — the create/edit book form (title, author,
    colour, pattern, height, cover picture, e-book file) reused by both the
    nav and the edit sidebar
  - `sidebar/FileBrowser.qml` — built-in file picker panel; the portal/Qt
    FileDialog silently fails to open when parented to a layer-shell window,
    so all picking goes through this

## Conventions

- Every widget takes `required property var shell` and reads theme/layout
  values from it (`shell.textColor`, `shell.barHeight`, `shell.iconFont`, ...).
  Do not hardcode shared values in widgets.
- Shared properties live on the root `Scope` in `shell.qml`:
  - geometry: `barHeight`, `marginSide`, `marginTop`, `cornerRadius`,
    `windowGap`, `ccWidth`, `notesWidth`, `sidebarWidth` (dock pill width),
    `edgeTriggerWidth` (edge trigger strip), `sidebarGap`, `sidebarVMargin`
  - theme: `barColor`, `textColor`, `ccBgColor`, `accentColor`, `dimColor`,
    `iconFont`; the book picker popup has its own palette (`shelfBgColor`,
    `shelfAccentColor`, `shelfAccentFgColor`, `shelfFgColor`,
    `shelfErrorColor`, `shelfErrorFgColor`) — dark green window with white
    text and white highlighted boxes, so the rest of the shell can stay red
- `windowGap` is niri's gap around tiled windows. A top-anchored layer
  surface is arranged in the usable area, i.e. it already starts *below* the
  bar's exclusive zone — to align with normal windows, offset its content by
  `windowGap` only. Adding `barHeight + marginTop` again double-counts the
  bar and pushes the content too low.
- Widgets close each other's popups through the `shell.ccPopup` /
  `shell.notesPopup` / `shell.bookPopup` aliases rather than reaching into
  each other.
- Resizing a layer surface can transiently drop `containsMouse` — collapsing
  a hover surface immediately on hover loss made the sidebar dock flicker.
  Keep the sidebar's `hideTimer` debounce; don't react to a single hover loss.
- A surface's hover zone is its input region: every px of the sidebar
  surface that can catch hover also swallows clicks aimed at the window
  underneath. Keep `edgeTriggerWidth` slim (8px); wide hover + free clicks
  are mutually exclusive on Wayland. While expanded, the sidebar clips its
  input region to the edge corridor + dock band with `QsWindow.mask`
  (sidebar/SidebarWidget.qml) so clicks above/below the open dock pass
  through — don't drop that mask.
- Icons are glyphs from `AtkynsonMono Nerd Font` (referenced as `shell.iconFont`).

## Critical: keyboard focus / text input

Getting text input to work in a popup was the hardest part of this project.
Rules learned the hard way:

- **Do not use `TextArea`/`TextInput` inside a `PopupWindow`** for editable
  text — it would not receive keyboard input here.
- The working pattern is a dedicated **`PanelWindow`** on `WlrLayer.Top` with
  `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` while visible, and
  `WlrKeyboardFocus.None` while hidden. See `NotesWidget.qml`.
- Inside that window, use a plain **`TextEdit`** (not `TextArea`), with
  `focus: <window>.visible` and `activeFocusOnPress: true`.
- A retry `Timer` calls `forceActiveFocus()` (and
  `_backingWindow.requestActivate()`) until the editor actually has
  `activeFocus`; focus handoff on show is async.
- `PopupWindow.grabFocus: true` alone is not enough for text input on niri.
- The bar `PanelWindow` itself uses `WlrKeyboardFocus.OnDemand` so its
  anchored popup windows can take keyboard focus when requested.

## IPC

`shell.qml` declares an `IpcHandler` (import `Quickshell.Io`) exposing widget
actions to the outside, e.g. for global shortcuts:

```qml
IpcHandler {
    target: "notes"
    function toggle() { notesWidget.toggle() }
}
```

Invoke a handler from the shell with:

```sh
quickshell ipc call notes toggle    # notes editor
quickshell ipc call bookshelfs toggle  # book picker popup
```

- List available targets with `quickshell ipc show`.
- The matching global keybind is **not** part of this repo; it is a niri
  `spawn "quickshell" "ipc" "call" <target> <fn>` keybind in the user's
  `~/.config/niri/config.kdl`.
- Keep handler functions side-effect-only (return nothing) unless a caller
  needs a result; add new actions as new functions on the relevant target.

## Validation

Always type-check a change by loading the config headlessly:

```sh
timeout 5s quickshell -p shell.qml
```

Success = it prints `Configuration Loaded` and exits only via the timeout.
Any `ERROR: Failed to load configuration` means the edit is broken.

To inspect a running instance:

```sh
quickshell list            # find instance id
quickshell log -i <id>     # read its log
quickshell kill -i <id>    # stop it
quickshell -d -p shell.qml # start detached
```

Note: `timeout 5s quickshell -p shell.qml` spawns a throwaway instance; the
user's live instance is separate and hot-reloads on file save.

## Tests (headless environments)

On machines without quickshell or a display, the bookshelf plugin has a
headless test suite in `tests/` that extracts and runs the real JS logic from
the QML sources, executes the epub/pdf extraction script with bash against
real EPUB fixtures, and lints every QML file structurally:

```sh
tests/run.sh
```

Run it after every change to `sidebar/BookPicker.qml` & friends; it
re-extracts the sources on each run, so it always tests what is in the tree.
`tests/README.md` documents what is covered and which bug-fix contracts are
pinned.
