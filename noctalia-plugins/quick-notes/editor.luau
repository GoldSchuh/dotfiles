--!nonstrict
-- Quick Notes editor - the tall panel for writing a single note: title
-- input and a large multiline body input. Edits stay in memory while
-- typing and are flushed to disk after a short pause, on navigation and
-- on close; the tree is re-rendered per edit so the header, status line
-- and counters stay live. The note id arrives via the "quicknotes.editing"
-- state key (set by the list panel).

local MAX_NOTES = 500
local MAX_TITLE = 200
local MAX_BODY = 20000
local MAX_FILE = 12 * 1024 * 1024
local AUTOSAVE_IDLE_TICKS = 2 -- 1s panel ticks with no edits before a flush

local path = noctalia.pluginDataDir() .. "/notes.json"

local notes = {}
local editingId = nil
local confirmOpen = false
local openRev = 0 -- bumped on open to reseed the uncontrolled inputs
local bodyRev = 0 -- bumped on title submit to recreate the body input (fresh key re-applies focus)
local dirty = false
local idleTicks = 0

local function publish()
  noctalia.state.set("notes.count", #notes)
end

local function makeId()
  return string.format("%x-%s", os.time(), string.sub(tostring(math.random()), 3, 9))
end

local function titleFor(note)
  local t = noctalia.string.trim(tostring(note and note.title or ""))
  return t ~= "" and t or noctalia.tr("ui.untitled")
end

local function sanitize(raw)
  if type(raw) ~= "table" then return nil end
  return {
    id = type(raw.id) == "string" and raw.id ~= "" and raw.id or makeId(),
    title = type(raw.title) == "string" and string.sub(raw.title, 1, MAX_TITLE) or "",
    body = type(raw.body) == "string" and string.sub(raw.body, 1, MAX_BODY) or "",
    updatedAt = (type(raw.updatedAt) == "number" and raw.updatedAt) or 0,
  }
end

local function load()
  local fresh = {}
  local raw = noctalia.readFile(path)
  if raw ~= nil and #raw <= MAX_FILE then
    local decoded = noctalia.json.decode(raw)
    if type(decoded) == "table" then
      local seen = {}
      for _, rawNote in ipairs(decoded) do
        local note = sanitize(rawNote)
        if note ~= nil then
          if seen[note.id] then note.id = makeId() end
          seen[note.id] = true
          table.insert(fresh, note)
        end
      end
    end
  end
  return fresh
end

local function reload()
  notes = load()
end

local function persist()
  local payload = noctalia.json.encode(notes, true)
  if #payload > MAX_FILE then
    noctalia.log(`quick-notes refusing to write notes.json: payload is {#payload} bytes`)
    return false
  end
  noctalia.writeFile(path, payload)
  publish()
  return true
end

local function editingNote()
  if editingId == nil then return nil end
  for _, note in ipairs(notes) do
    if note.id == editingId then return note end
  end
  return nil
end

local function flush()
  if not dirty or editingId == nil then
    return
  end
  local note = editingNote()
  dirty = false
  if note ~= nil then
    -- A note left completely empty on leave is dropped instead of
    -- piling "Untitled" rows into the list.
    if note.title == "" and note.body == "" then
      for index, entry in ipairs(notes) do
        if entry.id == note.id then
          table.remove(notes, index)
          break
        end
      end
    end
  end
  persist()
  noctalia.state.set("quicknotes.dirty", noctalia.nowMs())
end

local function markEdited(field, text, maxLen)
  local note = editingNote()
  if note == nil then return end
  note[field] = string.sub(tostring(text), 1, maxLen)
  note.updatedAt = noctalia.nowMs()
  dirty = true
  idleTicks = 0
  render()
end

local function openList()
  flush()
  editingId = nil
  confirmOpen = false
  noctalia.togglePanel("roman/quick-notes:notes")
end

local function performDelete()
  local id = editingId
  if id == nil then return end
  for index, note in ipairs(notes) do
    if note.id == id then
      table.remove(notes, index)
      break
    end
  end
  dirty = false
  editingId = nil
  confirmOpen = false
  persist()
  noctalia.state.set("quicknotes.dirty", noctalia.nowMs())
  noctalia.togglePanel("roman/quick-notes:notes")
end

local function statusLine(note)
  local words = select(2, note.body:gsub("%S+", ""))
  local chars = utf8.len(note.body) or #note.body
  local status = dirty and noctalia.tr("ui.editing") or noctalia.tr("ui.saved")
  return status .. " · " .. noctalia.tr("ui.counts", { words = tostring(words), chars = tostring(chars) })
end

local function editorTree()
  local note = editingNote()
  if note == nil then
    return ui.column({ padding = 12, gap = 10, align = "center" }, {
      ui.spacer({ flexGrow = 1 }),
      ui.glyph({ name = "notes", size = 28, color = "on_surface_variant" }),
      ui.label({ text = noctalia.tr("ui.missing"), color = "on_surface_variant", fontSize = 12 }),
      ui.button({ text = noctalia.tr("ui.back_short"), variant = "outline", onClick = "onBack" }),
      ui.spacer({ flexGrow = 2 }),
    })
  end

  local titleRev = tostring(openRev)
  local bodyKeyRev = tostring(bodyRev)

  return ui.column({ flexGrow = 1, gap = 8, align = "stretch" }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.button({
        glyph = "arrow-left",
        variant = "ghost",
        onClick = "onBack",
        tooltip = noctalia.tr("ui.back_tooltip"),
      }),
      ui.input({
        key = "title-" .. editingId .. "-" .. titleRev,
        value = note.title,
        placeholder = noctalia.tr("ui.title_placeholder"),
        flexGrow = 1,
        onChange = "onTitleChanged",
        onSubmit = "onSubmitTitle",
      }),
      ui.button({
        glyph = "trash",
        variant = "ghost",
        onClick = "onDeleteClicked",
        tooltip = noctalia.tr("ui.delete_note_shortcut"),
      }),
    }),
    ui.input({
      key = "body-" .. editingId .. "-" .. bodyKeyRev,
      value = note.body,
      placeholder = noctalia.tr("ui.body_placeholder"),
      multiline = true,
      focus = true,
      flexGrow = 1,
      onChange = "onBodyChanged",
      onSubmit = "onSubmitBody",
    }),
    ui.label({
      text = statusLine(note),
      fontSize = 11,
      color = "on_surface_variant",
      maxLines = 1,
    }),
  })
end

local function confirmTree()
  local note = editingNote()
  return ui.column({ padding = 12, gap = 14, align = "stretch" }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.button({
        glyph = "arrow-left",
        variant = "ghost",
        controlSize = "sm",
        onClick = "onCancelDelete",
        tooltip = noctalia.tr("ui.back_tooltip"),
      }),
      ui.label({
        text = note ~= nil and titleFor(note) or noctalia.tr("ui.untitled"),
        fontSize = 14,
        fontWeight = "bold",
        color = "primary",
        flexGrow = 1,
        maxLines = 1,
      }),
      ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = "onCloseClicked" }),
    }),
    ui.spacer({ flexGrow = 1 }),
    ui.label({
      text = noctalia.tr("ui.confirm_delete"),
      fontSize = 13,
      fontWeight = "bold",
      color = "on_surface",
      maxWidth = 300,
      textAlign = "center",
    }),
    ui.row({ gap = 8, justify = "end" }, {
      ui.button({ text = noctalia.tr("ui.cancel"), variant = "outline", onClick = "onCancelDelete" }),
      ui.button({ text = noctalia.tr("ui.delete"), variant = "destructive", onClick = "onConfirmDelete" }),
    }),
  })
end

function render()
  if confirmOpen then
    panel.render(confirmTree())
  else
    panel.render(editorTree())
  end
end

function onTitleChanged(text)
  markEdited("title", text, MAX_TITLE)
end

function onBodyChanged(text)
  markEdited("body", text, MAX_BODY)
end

function onSubmitTitle()
  -- Submitting the title hands the focus to the body; a fresh key recreates
  -- the body input, which re-applies its focus request.
  local note = editingNote()
  if note ~= nil then
    bodyRev += 1
    render()
  end
end

function onSubmitBody()
  flush()
  render()
end

function onBack()
  openList()
end

function onDeleteClicked()
  if editingId ~= nil then
    confirmOpen = true
    render()
  end
end

function onCancelDelete()
  confirmOpen = false
  render()
end

function onConfirmDelete()
  performDelete()
end

function onCloseClicked()
  flush()
  editingId = nil
  panel.close()
end

-- The host calls this when the panel closes any other way (Escape,
-- outside click, another panel replacing it).
function onClose()
  flush()
  editingId = nil
end

function update()
  if dirty then
    idleTicks += 1
    if idleTicks >= AUTOSAVE_IDLE_TICKS then
      flush()
      render()
    end
  end
end

function onOpen(context)
  reload()
  panel.setWantsSecondTicks(true) -- idle autosave runs from update()
  -- A context string (panel-open roman/quick-notes:editor <id>) selects the
  -- note directly, otherwise the id set by the list panel is used.
  if type(context) == "string" and context ~= "" then
    noctalia.state.set("quicknotes.editing", context)
  end
  editingId = noctalia.state.get("quicknotes.editing")
  confirmOpen = false
  dirty = false
  idleTicks = 0
  openRev += 1
  bodyRev = openRev
  render()
end

reload()
editingId = noctalia.state.get("quicknotes.editing")
render()
