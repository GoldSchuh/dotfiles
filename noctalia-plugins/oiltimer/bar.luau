--!nonstrict
-- Oil Timer bar widget - hourglass when idle; the hourglass stays next to
-- the running time while counting (official noctalia/timer convention).
-- Click opens the desktop-widget-style panel.

local STATE = "IDLE"
local formattedTime = "00:00"
local isVertical = false
local tooltipShown = false

local function timeColor()
  if STATE == "NOTIFY" then
    return "error"
  elseif STATE == "RUNNING" then
    return "primary"
  end
  return "on_surface_variant"
end

local function showTooltip()
  barWidget.setTooltip(formattedTime)
  tooltipShown = true
end

local function hideTooltip()
  -- clearing a tooltip when there is none crashes the plugin
  if tooltipShown then
    barWidget.clearTooltip()
    tooltipShown = false
  end
end

local function render()
  if isVertical then
    barWidget.render(ui.column({ align = "center" }, {
      ui.glyph({ name = "hourglass", color = timeColor() }),
    }))
    if STATE == "RUNNING" then
      showTooltip()
    else
      hideTooltip()
    end
    return
  end

  barWidget.render(ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "hourglass", color = timeColor() }),
    ui.label({ text = formattedTime, fontWeight = "bold", color = timeColor() }),
  }))
end

function update()
  isVertical = barWidget.isVertical()
  render()
end

noctalia.state.watch("timer.state", function(value)
  STATE = value
  render()
end)

noctalia.state.watch("timer.formattedTime", function(value)
  formattedTime = value
  if STATE ~= "IDLE" then
    render()
  end
end)

function onClick()
  if STATE == "NOTIFY" then
    noctalia.state.set("timer.cmd", "RESET")
    return
  end
  noctalia.togglePanel("roman/oiltimer:panel")
end

STATE = noctalia.state.get("timer.state") or "IDLE"
formattedTime = noctalia.state.get("timer.formattedTime") or "00:00"
isVertical = barWidget.isVertical()
render()
