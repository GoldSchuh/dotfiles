--!nonstrict
-- Oil Timer panel - exactly the official timer desktop-widget layout:
-- big countdown, progress bar, +/- minute buttons, Reset/Start-Pause.
-- Drives the same shared service state.

local STATE = "IDLE"
local remaining = 0
local formattedTime = "0"
local duration = 0

local function timeColor()
  if STATE == "NOTIFY" then
    return "error"
  elseif remaining > 0 then
    return "primary"
  end
  return "outline"
end

local function render()
  local remainingText = remaining > 0 and formattedTime or "--:--"

  local rows = {
    ui.label({
      text = remainingText,
      fontSize = 40,
      fontWeight = "bold",
      color = timeColor(),
    }),
  }

  table.insert(rows, ui.progress({
    progress = duration > 0 and remaining / duration or 0,
    fill = "primary",
    width = 180,
    height = 6,
    radius = 3,
  }))

  if STATE == "IDLE" then
    table.insert(rows, ui.row({ gap = 4, justify = "center" }, {
      ui.button({ text = "-1m", variant = "ghost", controlSize = "sm", onClick = "onMinus1" }),
      ui.button({ text = "+1m", variant = "ghost", controlSize = "sm", onClick = "onPlus1" }),
      ui.button({ text = "+5m", variant = "ghost", controlSize = "sm", onClick = "onPlus5" }),
    }))
  end

  local btnText = STATE == "RUNNING" and "Pause" or "Start"
  local btnVariant = STATE == "RUNNING" and "secondary" or "primary"

  table.insert(rows, ui.row({ gap = 8, justify = "center" }, {
    ui.button({
      text = "Zurücksetzen",
      variant = "destructive",
      onClick = "onReset",
    }),
    ui.button({
      text = btnText,
      variant = btnVariant,
      onClick = "onToggle",
      enabled = remaining > 0,
    }),
  }))

  panel.render(ui.column({ gap = 10, align = "center" }, rows))
end

local function adjust(deltaSeconds)
  if STATE ~= "IDLE" then
    return
  end
  noctalia.state.set("timer.remaining", math.max(0, remaining + deltaSeconds))
end

noctalia.state.watch("timer.state", function(value)
  STATE = value
  render()
end)

noctalia.state.watch("timer.formattedTime", function(value)
  formattedTime = value
  render()
end)

noctalia.state.watch("timer.remaining", function(value)
  remaining = value
  render()
end)

noctalia.state.watch("timer.duration", function(value)
  duration = value
  render()
end)

function onMinus1()
  adjust(-60)
end

function onPlus1()
  adjust(60)
end

function onPlus5()
  adjust(300)
end

function onReset()
  noctalia.state.set("timer.cmd", "RESET")
end

function onToggle()
  if STATE == "RUNNING" then
    noctalia.state.set("timer.cmd", "PAUSE")
  else
    noctalia.state.set("timer.cmd", "START")
  end
end

STATE = noctalia.state.get("timer.state") or "IDLE"
remaining = noctalia.state.get("timer.remaining") or 0
formattedTime = noctalia.state.get("timer.formattedTime") or "0"
duration = noctalia.state.get("timer.duration") or 0
render()
