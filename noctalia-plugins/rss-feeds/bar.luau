--!nonstrict
-- RSS Feeds bar chip - rss glyph + newest headline of all configured feeds,
-- in the bar's declarative style (accent when fresh, muted when idle,
-- error when every feed failed). Click opens the entry panel.

local data = noctalia.state.get("rss.data") or nil
local status = noctalia.state.get("rss.status") or "loading"
local isVertical = false
local tooltipShown = false

-- newest entry across all feeds
local function headline()
  local best, bestTime = nil, -1
  if data then
    for _, feed in ipairs(data.feeds or {}) do
      for _, entry in ipairs(feed.items or {}) do
        if (entry.time or 0) >= bestTime then
          best, bestTime = entry.title, entry.time or 0
        end
      end
    end
  end
  return best
end

local function chipColor()
  if status == "error" then return "error" end
  if headline() ~= nil then return "primary" end
  return "on_surface_variant"
end

local function showTooltip()
  -- clearing a tooltip when there is none crashes the plugin
  if tooltipShown then
    barWidget.clearTooltip()
    tooltipShown = false
  end
  if headline() ~= nil then
    barWidget.setTooltip(headline())
    tooltipShown = true
  end
end

local function render()
  local color = chipColor()
  if isVertical then
    barWidget.render(ui.column({ align = "center" }, {
      ui.glyph({ name = "rss", color = color }),
    }))
    return
  end

  local text = headline()
  barWidget.render(ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "rss", color = color }),
    ui.label({
      text = text ~= nil and text or "?",
      fontWeight = "bold",
      color = color,
      maxLines = 1,
    }),
  }))
end

function update()
  isVertical = barWidget.isVertical()
  render()
end

noctalia.state.watch("rss.data", function(value)
  data = value
  render()
  showTooltip()
end)

noctalia.state.watch("rss.status", function(value)
  status = value
  render()
end)

function onClick()
  noctalia.togglePanel("roman/rss-feeds:panel")
end

isVertical = barWidget.isVertical()
render()
