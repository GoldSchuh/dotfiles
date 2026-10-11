--!nonstrict
-- Quick Notes bar chip - notes glyph + note count (muted when empty).
-- Click toggles the panel. Cold-loads the count from notes.json so the chip
-- is correct before the panel has ever been opened.

local count = nil

local function render()
  if count == nil or count <= 0 then
    barWidget.render(ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "notes", color = "on_surface_variant" }),
    }))
    return
  end
  barWidget.render(ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "notes", color = "on_surface" }),
    ui.label({
      text = tostring(count),
      fontWeight = "bold",
      color = "on_surface_variant",
    }),
  }))
end

function update()
  render()
end

noctalia.state.watch("notes.count", function(value)
  count = value
  render()
end)

function onClick()
  noctalia.togglePanel("roman/quick-notes:notes")
end

local raw = noctalia.readFile(noctalia.pluginDataDir() .. "/notes.json")
if raw ~= nil then
  local decoded = noctalia.json.decode(raw)
  if type(decoded) == "table" then
    count = #decoded
  end
end

render()
