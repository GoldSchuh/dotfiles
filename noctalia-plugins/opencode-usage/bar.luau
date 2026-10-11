--!nonstrict
-- OpenCode Usage bar chip - sparkles glyph + today's compact token count,
-- matching the bar's declarative style (accent when busy, muted when idle).
-- Click opens the usage panel.

local data = noctalia.state.get("usage.data") or nil
local status = noctalia.state.get("usage.status") or "scanning"

local function compactTokens(n)
  if not n or n <= 0 then return "0" end
  if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
  if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
  return tostring(n)
end

local function chipColor()
  if status == "error" then return "error" end
  if (data and data.todayTotalTokens or 0) > 0 then return "primary" end
  return "on_surface_variant"
end

local function render()
  if data == nil then
    barWidget.render(ui.row({ align = "center" }, {
      ui.glyph({ name = "sparkles", color = chipColor() }),
      ui.label({
        text = status == "error" and "!" or "…",
        fontWeight = "bold",
        color = chipColor(),
      }),
    }))
    return
  end

  barWidget.render(ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "sparkles", color = chipColor() }),
    ui.label({
      text = compactTokens(data.todayTotalTokens),
      fontWeight = "bold",
      color = chipColor(),
    }),
  }))
end

function update()
  render()
end

noctalia.state.watch("usage.data", function(value)
  data = value
  render()
end)

noctalia.state.watch("usage.status", function(value)
  status = value
  render()
end)

function onClick()
  noctalia.togglePanel("roman/opencode-usage:panel")
end

render()
