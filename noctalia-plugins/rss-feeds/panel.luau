--!nonstrict
-- RSS Feeds panel - one section per configured feed with the newest N
-- entries, fed from the shared service state. Clicking an entry opens it
-- via xdg-open; refresh asks the service for an immediate re-fetch.

local data = noctalia.state.get("rss.data") or nil
local status = noctalia.state.get("rss.status") or "loading"

local function openLink(link)
  if link ~= nil and string.sub(link, 1, 4) == "http" then
    noctalia.runAsync({ "xdg-open", link }, function() end)
  end
end

local function statusColor()
  if status == "error" then return "error" end
  return "primary"
end

local function relativeTime(ms)
  if ms == nil or ms <= 0 then return nil end
  local diff = math.floor((noctalia.nowMs() - ms) / 1000)
  if diff < 0 then diff = 0 end
  if diff < 60 then
    return noctalia.tr("ui.time_now")
  elseif diff < 3600 then
    return noctalia.tr("ui.time_min", { n = tostring(math.floor(diff / 60)) })
  elseif diff < 86400 then
    return noctalia.tr("ui.time_hour", { n = tostring(math.floor(diff / 3600)) })
  elseif diff < 172800 then
    return noctalia.tr("ui.time_yesterday")
  end
  return noctalia.formatTime("%d.%m.", math.floor(ms / 1000))
end

local function headerRow(color)
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = "rss", color = color }),
    ui.label({
      text = noctalia.tr("ui.panel_title"),
      fontSize = 14,
      fontWeight = "bold",
      color = color,
      flexGrow = 1,
      maxLines = 1,
    }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", onClick = "onRefresh" }),
    ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = "onCloseClicked" }),
  })
end

local function entryRow(feedTitle, entry)
  local rel = relativeTime(entry.time) or ""
  local children = {
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({
        text = entry.title,
        fontSize = 12,
        fontWeight = "bold",
        color = "on_surface",
        maxLines = 2,
        flexGrow = 1,
      }),
      ui.label({
        text = rel,
        fontSize = 10,
        color = "on_surface_variant",
        maxLines = 1,
        visible = rel ~= "",
      }),
    }),
    ui.glyph({ name = "external-link", color = "on_surface_variant" }),
  }
  return ui.row({
    gap = 8,
    align = "center",
    padding = 6,
    paddingH = 8,
    radius = 8,
    fill = "surface",
    onClick = function() openLink(entry.link) end,
    tooltip = feedTitle,
  }, children)
end

local function feedSection(feed)
  local rows = {
    ui.label({
      text = feed.title,
      fontSize = 12,
      fontWeight = "bold",
      color = "primary",
      maxLines = 1,
    }),
  }
  if #feed.items == 0 then
    table.insert(rows, ui.label({
      text = feed.error ~= nil and feed.error or noctalia.tr("ui.no_items"),
      color = "on_surface_variant",
      fontSize = 12,
    }))
  else
    for _, entry in ipairs(feed.items) do
      table.insert(rows, entryRow(feed.title, entry))
    end
  end
  return rows
end

local function renderList()
  local rows = { headerRow(statusColor()) }
  table.insert(rows, ui.separator({ color = "outline" }))

  if status == "loading" or data == nil then
    table.insert(rows, ui.label({
      text = status == "error" and noctalia.tr("ui.error") or noctalia.tr("ui.loading"),
      color = statusColor(),
    }))
  elseif status == "empty" then
    table.insert(rows, ui.label({
      text = noctalia.tr("ui.no_feeds"),
      color = "on_surface_variant",
      maxWidth = 360,
    }))
  else
    for _, feed in ipairs(data.feeds or {}) do
      for _, row in ipairs(feedSection(feed)) do
        table.insert(rows, row)
      end
      table.insert(rows, ui.spacer({ height = 6 }))
    end
  end

  local columnChildren = {}
  for i = 1, 2 do table.insert(columnChildren, rows[i]) end
  local scrolled = {}
  for i = 3, #rows do table.insert(scrolled, rows[i]) end
  table.insert(columnChildren, ui.scroll({ key = "rss-list", flexGrow = 1, gap = 6 }, scrolled))
  panel.render(ui.column({ padding = 12, gap = 10 }, columnChildren))
end

function render()
  renderList()
end

function onRefresh()
  noctalia.state.set("rss.cmd", "REFRESH")
end

function onCloseClicked()
  panel.close()
end

noctalia.state.watch("rss.data", function(value)
  data = value
  render()
end)

noctalia.state.watch("rss.status", function(value)
  status = value
  render()
end)

function onOpen(context)
  render()
end

render()
