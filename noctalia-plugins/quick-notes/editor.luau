--!nonstrict
-- Quick Notes editor - the tall panel for writing a single note: title
-- input and a large multiline body input, autosaves on every change.
-- Back/Delete hand control back to the list panel; the note id arrives
-- via the "quicknotes.editing" state key (set by the list).

local MAX_NOTES = 500
local MAX_TITLE = 200
local MAX_BODY = 20000
local MAX_FILE = 12 * 1024 * 1024

local path = noctalia.pluginDataDir() .. "/notes.json"

local notes = {}
local editingId = nil
local confirmOpen = false

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
  notes = {}
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
          table.insert(notes, note)
        end
      end
    end
  end
end

local function save()
  local payload = noctalia.json.encode(notes, true)
  if #payload > MAX_FILE then
    noctalia.log(`quick-notes refusing to write notes.json: payload is {#payload} bytes`)
    return
  end
  noctalia.writeFile(path, payload)
  publish()
  noctalia.state.set("quicknotes.dirty", noctalia.nowMs())
end

local function editingNote()
  if editingId == nil then return nil end
  for _, note in ipairs(notes) do
    if note.id == editingId then return note end
  end
  return nil
end

local function setField(field, text, maxLen)
  local note = editingNote()
  if note == nil then return end
  note[field] = string.sub(tostring(text), 1, maxLen)
  note.updatedAt = noctalia.nowMs()
  save()
end

local function openList()
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
  editingId = nil
  confirmOpen = false
  save()
  openList()
end

local function editorTree()
  local note = editingNote()
  if note == nil then
    return ui.column({ padding = 12, gap = 10, align = "center" }, {
      ui.label({ text = noctalia.tr("ui.missing"), color = "on_surface_variant", fontSize = 12 }),
      ui.button({ text = noctalia.tr("ui.back_short"), variant = "outline", onClick = "onBack" }),
    })
  end

  return ui.column({ padding = 12, gap = 10 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.button({
        glyph = "arrow-left",
        variant = "ghost",
        controlSize = "sm",
        onClick = "onBack",
        tooltip = noctalia.tr("ui.back_tooltip"),
      }),
      ui.label({
        text = titleFor(note),
        fontSize = 14,
        fontWeight = "bold",
        color = "primary",
        flexGrow = 1,
        maxLines = 1,
      }),
      ui.label({
        text = noctalia.tr("ui.autosaves"),
        fontSize = 9,
        color = "on_surface_variant",
      }),
      ui.button({
        glyph = "trash",
        glyphSize = 14,
        variant = "ghost",
        controlSize = "sm",
        onClick = "onDeleteClicked",
        tooltip = noctalia.tr("ui.delete_note_shortcut"),
      }),
    }),
    ui.input({
      key = "title-" .. editingId,
      value = note.title or "",
      placeholder = noctalia.tr("ui.title_placeholder"),
      fontSize = 13,
      controlSize = "sm",
      focus = true,
      onChange = function(text) setField("title", text, MAX_TITLE) end,
    }),
    ui.input({
      key = "body-" .. editingId,
      value = note.body or "",
      placeholder = noctalia.tr("ui.body_placeholder"),
      fontSize = 13,
      multiline = true,
      height = 370,
      onChange = function(text) setField("body", text, MAX_BODY) end,
    }),
  })
end

local function confirmTree()
  local note = editingNote()
  return ui.column({ padding = 12, gap = 14, align = "center" }, {
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
    ui.spacer({ flexGrow = 1 }),
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
  panel.close()
end

function onOpen(context)
  load()
  editingId = noctalia.state.get("quicknotes.editing")
  confirmOpen = false
  render()
end

load()
editingId = noctalia.state.get("quicknotes.editing")
render()
