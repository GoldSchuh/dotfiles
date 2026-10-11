--!nonstrict
-- OpenCode Usage panel - today's total, a 7-day graph, and per-model
-- breakdowns for today and all-time, fed from the shared service state.

local data = noctalia.state.get("usage.data") or nil
local status = noctalia.state.get("usage.status") or "scanning"

local function compactTokens(n)
  if not n or n <= 0 then return "0" end
  if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
  if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
  return tostring(n)
end

local function formatNumber(n)
  if not n then return "0" end
  local s = tostring(n)
  return s:reverse():gsub("(%d%d%d)", "%1."):gsub("^%.", ""):reverse()
end

local function statusColor()
  if status == "error" then return "error" end
  return "primary"
end

-- Weekday letters for the 7-day labels
local WEEK = "MTWTFSS"

-- Sort {"model": tokens} into {"model"=, "tokens"=} rows, biggest first.
local function sortedModels(byModelTokens)
  local models = {}
  if byModelTokens then
    for model, tokens in pairs(byModelTokens) do
      table.insert(models, { model = model, tokens = tokens })
    end
    table.sort(models, function(a, b) return a.tokens > b.tokens end)
  end
  return models
end

local function alltimeModels()
  local perModel = {}
  if data and data.modelUsage then
    for model, entry in pairs(data.modelUsage) do
      perModel[model] = (entry.inputTokens or 0) + (entry.outputTokens or 0)
        + (entry.cacheReadInputTokens or 0) + (entry.cacheCreationInputTokens or 0)
    end
  end
  return sortedModels(perModel)
end

local function appendAll(rows, sections)
  for _, node in ipairs(sections) do table.insert(rows, node) end
  return rows
end

local function dayLabel(iso)
  -- "2026-10-11" -> short weekday, so the week graph labels don't wrap
  if not iso or #iso ~= 10 then return "--" end
  local t = {
    year = tonumber(iso:sub(1, 4)) or 0,
    month = tonumber(iso:sub(6, 7)) or 1,
    day = tonumber(iso:sub(9, 10)) or 1,
    hour = 12,
  }
  local ok, stamp = pcall(os.time, t)
  if not ok then return iso:sub(9, 10) end
  local okDate, dateTable = pcall(os.date, "!*t", stamp)
  if not okDate or not dateTable.wday then return iso:sub(9, 10) end
  return WEEK:sub(dateTable.wday, dateTable.wday)
end

local function headerRow(color)
  return ui.row({ gap = 8, align = "center", justify = "space_between" }, {
    ui.label({ text = noctalia.tr("ui.panel_title"), fontSize = 15, fontWeight = "bold", color = color, flexGrow = 1, maxLines = 1 }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", onClick = "onRefresh" }),
    ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = "onCloseClicked" }),
  })
end

local function modelRows(title, models, biggest)
  local rows = {
    ui.label({ text = title, fontSize = 12, fontWeight = "bold", color = "on_surface_variant" }),
  }
  if #models == 0 then
    table.insert(rows, ui.label({ text = noctalia.tr("ui.no_models"), color = "outline", fontSize = 12 }))
    return rows
  end
  local shown = math.min(3, #models)
  for i = 1, shown do
    local entry = models[i]
    table.insert(rows, ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = entry.model, fontSize = 12, color = "on_surface", flexGrow = 1, maxLines = 1 }),
      ui.progress({
        progress = biggest > 0 and entry.tokens / biggest or 0,
        fill = "primary",
        width = 64,
        height = 4,
        radius = 2,
      }),
      ui.label({ text = compactTokens(entry.tokens), fontSize = 12, color = "on_surface_variant" }),
    }))
  end
  return rows
end

local function todaySection()
  local models = sortedModels(data and data.todayTokensByModel or {})
  local biggest = #models > 0 and models[1].tokens or 0
  local rows = {
    ui.row({ align = "end", gap = 8 }, {
      ui.label({ text = compactTokens(data and data.todayTotalTokens or 0), fontSize = 34, fontWeight = "bold", color = statusColor() }),
      ui.label({ text = noctalia.tr("ui.tokens_today"), color = "on_surface_variant" }),
    }),
    ui.label({
      text = noctalia.tr("ui.sessions_total", { count = formatNumber(data and data.totalSessions or 0) }),
      color = "on_surface_variant",
    }),
  }
  appendAll(rows, modelRows(noctalia.tr("ui.today_per_model"), models, biggest))
  return rows
end

local function weekSection()
  if not data or not data.recentDays then return {} end
  local values, labels = {}, {}
  local maxTokens = 0
  for _, day in ipairs(data.recentDays) do
    maxTokens = math.max(maxTokens, day.totalTokens or 0)
  end
  for _, day in ipairs(data.recentDays) do
    table.insert(values, maxTokens > 0 and (day.totalTokens or 0) / maxTokens or 0)
    table.insert(labels, dayLabel(day.date))
  end
  return {
    ui.graph({ values = values, color = "primary", width = 340, height = 44 }),
    ui.row({ justify = "space_between" }, {
      ui.label({ text = table.concat(labels, "  "), color = "on_surface_variant", fontSize = 11 }),
      ui.label({ text = noctalia.tr("ui.last_ndays", { count = #values }), color = "on_surface_variant", fontSize = 11 }),
    }),
  }
end

local function render()
  if data == nil then
    panel.render(ui.column({ padding = 14, gap = 10, align = "center" }, {
      headerRow("on_surface_variant"),
      ui.label({
        text = status == "error" and noctalia.tr("ui.error") or noctalia.tr("ui.scanning"),
        color = status == "error" and "error" or "on_surface_variant",
        fontSize = 18,
      }),
    }))
    return
  end

  local rows = {
    headerRow(statusColor()),
  }
  appendAll(rows, todaySection())
  appendAll(rows, weekSection())

  local allTime = alltimeModels()
  appendAll(rows, modelRows(noctalia.tr("ui.alltime_per_model"), allTime, #allTime > 0 and allTime[1].tokens or 0))

  panel.render(ui.column({ padding = 14, gap = 12 }, rows))
end

function onRefresh()
  noctalia.state.set("usage.cmd", "REFRESH")
end

function onCloseClicked()
  panel.close()
end

noctalia.state.watch("usage.data", function(value)
  data = value
  render()
end)

noctalia.state.watch("usage.status", function(value)
  status = value
  render()
end)

render()
