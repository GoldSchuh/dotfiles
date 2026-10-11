--!nonstrict
-- Quick Notes list panel - overview of the notes; rows and the + button
-- hand over to the taller editor panel. Deleting a row asks for a
-- confirmation here. Edits made in the editor arrive via the
-- "quicknotes.dirty" state key and are re-loaded.

local MAX_NOTES = 500
local MAX_TITLE = 200
local MAX_BODY = 20000
local MAX_FILE = 12 * 1024 * 1024

local path = noctalia.pluginDataDir() .. "/notes.json"

local notes = {}
local confirmId = nil
local hoveredKey = nil

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

local function previewFor(note)
  local b = tostring(note and note.body or ""):gsub("%s+", " ")
  b = noctalia.string.trim(b)
  if #b > 72 then b = string.sub(b, 1, 72) .. "…" end
  return b
end

local function relativeTime(ms)
  if ms == nil or ms <= 0 then return nil end
  local diff = math.floor((noctalia.nowMs() - ms) / 1000)
  if diff < 0 then diff = 0 end
  if diff < 60 then
    return noctalia.tr("ui.time_now")
  elseif diff < 3600 then
    return noctalia.tr("ui.time_min", { n = tostring(math.floor(diff / 60)) })
  end
  local edited = math.floor(ms / 1000)
  local day = noctalia.formatTime("%Y-%m-%d", edited)
  if day == noctalia.formatTime("%Y-%m-%d") then
    return noctalia.tr("ui.time_today", { t = noctalia.formatTime("%H:%M", edited) })
  elseif day == noctalia.formatTime("%Y-%m-%d", noctalia.nowMs() / 1000 - 86400) then
    return noctalia.tr("ui.time_yesterday")
  end
  return noctalia.formatTime("%d.%m.", edited)
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
  if raw == nil or #raw > MAX_FILE then
    publish()
    return
  end
  local decoded = noctalia.json.decode(raw)
  if type(decoded) ~= "table" then
    publish()
    return
  end
  local seen = {}
  for _, rawNote in ipairs(decoded) do
    local note = sanitize(rawNote)
    if note ~= nil then
      if seen[note.id] then note.id = makeId() end
      seen[note.id] = true
      table.insert(notes, note)
    end
  end
  table.sort(notes, function(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end)
  while #notes > MAX_NOTES do
    table.remove(notes)
  end
  publish()
end

local function save()
  local payload = noctalia.json.encode(notes, true)
  if #payload > MAX_FILE then
    noctalia.log(`quick-notes refusing to write notes.json: payload is {#payload} bytes`)
    return
  end
  noctalia.writeFile(path, payload)
  publish()
end

local function openEditor(id)
  noctalia.state.set("quicknotes.editing", id)
  noctalia.togglePanel("roman/quick-notes:editor")
end

local function createNote()
  if confirmId ~= nil or #notes >= MAX_NOTES then return end
  local note = { id = makeId(), title = "", body = "", updatedAt = noctalia.nowMs() }
  table.insert(notes, note)
  table.sort(notes, function(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end)
  save()
  openEditor(note.id)
end

local function performDelete()
  local id = confirmId
  if id == nil then return end
  for index, note in ipairs(notes) do
    if note.id == id then
      table.remove(notes, index)
      break
    end
  end
  confirmId = nil
  save()
  render()
end

local function noteRow(note)
  local isHovered = hoveredKey == note.id
  local children = {
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.row({ gap = 8, align = "center" }, {
        ui.label({
          text = titleFor(note),
          fontSize = 13,
          fontWeight = "bold",
          color = "on_surface",
          maxLines = 1,
          flexGrow = 1,
        }),
        ui.label({
          text = relativeTime(note.updatedAt) or "",
          fontSize = 10,
          color = "on_surface_variant",
          maxLines = 1,
        }),
      }),
      ui.label({
        text = previewFor(note),
        fontSize = 11,
        color = "on_surface_variant",
        maxLines = 1,
        visible = previewFor(note) ~= "",
      }),
    }),
    ui.button({
      key = "del-" .. note.id,
      glyph = "trash",
      glyphSize = 14,
      variant = "ghost",
      controlSize = "sm",
      onClick = function() confirmId = note.id; render() end,
      tooltip = noctalia.tr("ui.delete_tooltip"),
    }),
  }
  return ui.row({
    key = note.id,
    gap = 8,
    align = "center",
    padding = 6,
    paddingH = 8,
    radius = 8,
    fill = isHovered and "tertiary" or "surface",
    onHover = "onRowHover",
    onClick = function() openEditor(note.id) end,
  }, children)
end

local function listTree()
  local rows = {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "notes", color = "primary" }),
      ui.label({
        text = noctalia.tr("ui.title"),
        fontSize = 14,
        fontWeight = "bold",
        color = "primary",
        flexGrow = 1,
        maxLines = 1,
      }),
      ui.button({
        glyph = "plus",
        variant = "ghost",
        controlSize = "sm",
        enabled = #notes < MAX_NOTES,
        onClick = "onNewNote",
        tooltip = noctalia.tr("ui.new_tooltip"),
      }),
      ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = "onCloseClicked" }),
    }),
  }
  table.insert(rows, ui.separator({ color = "outline" }))

  if #notes == 0 then
    table.insert(rows, ui.spacer({ flexGrow = 1 }))
    table.insert(rows, ui.label({
      text = noctalia.tr("ui.empty"),
      color = "on_surface_variant",
      fontSize = 12,
      maxWidth = 300,
    }))
    table.insert(rows, ui.spacer({ flexGrow = 2 }))
    return ui.column({ padding = 12, gap = 10 }, rows)
  end

  local listRows = {}
  for _, note in ipairs(notes) do
    table.insert(listRows, noteRow(note))
  end
  table.insert(rows, ui.scroll({ key = "note-list", flexGrow = 1, gap = 6 }, listRows))
  return ui.column({ padding = 12, gap = 10 }, rows)
end

local function confirmTree()
  return ui.column({ padding = 12, gap = 14 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "notes", color = "primary" }),
      ui.label({
        text = noctalia.tr("ui.title"),
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
  if confirmId ~= nil then
    panel.render(confirmTree())
  else
    panel.render(listTree())
  end
end

function onNewNote()
  createNote()
end

function onRowHover(state, key)
  hoveredKey = (state == "true") and key or nil
  render()
end

function onCloseClicked()
  panel.close()
end

function onCancelDelete()
  confirmId = nil
  render()
end

function onConfirmDelete()
  performDelete()
end

function onOpen(context)
  load()
  confirmId = nil
  render()
end

noctalia.state.watch("quicknotes.dirty", function()
  load()
  render()
end)

load()
render()
