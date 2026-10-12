--!nonstrict
-- RSS Feeds service - runs the bundled python fetcher/parser on an interval
-- and shares the parsed feeds with bar and panel via noctalia.state.
--
--   noctalia.runAsync(...)        subprocess with output capture
--   noctalia.json decode/encode   parse fetcher JSON, write the cache copy
--   noctalia.pluginDir()          locate scripts/rss_fetcher.py
--   noctalia.pluginDataDir()      persistent last-good cache across restarts

local SCRIPT = noctalia.pluginDir() .. "/scripts/rss_fetcher.py"
local CACHE = noctalia.pluginDataDir() .. "/rss.json"

-- Slot definitions come from the plugin settings (feed_1..feed_5 + optional titles)
local urls = {}
local titles = {}

local refreshMinutes = tonumber(noctalia.getConfig("refresh_minutes")) or 30
refreshMinutes = math.max(5, math.min(1440, refreshMinutes))
local itemsPerFeed = tonumber(noctalia.getConfig("items_per_feed")) or 5
itemsPerFeed = math.max(1, math.min(15, itemsPerFeed))

local fails = 0

local function readConfig()
  urls, titles = {}, {}
  for slot = 1, 5 do
    local url = noctalia.string.trim(tostring(noctalia.getConfig("feed_" .. slot) or ""))
    if url ~= "" then
      table.insert(urls, url)
      table.insert(titles, noctalia.string.trim(tostring(noctalia.getConfig("title_" .. slot) or "")))
    end
  end
end

local function publish(data, status)
  noctalia.state.set("rss.data", data)
  noctalia.state.set("rss.status", status)
end

local function applyFetch(result)
  if result.exitCode ~= 0 then
    fails = math.min(fails + 1, 6)
  else
    local decoded, err = noctalia.json.decode(result.stdout)
    if decoded == nil then
      fails = math.min(fails + 1, 6)
      noctalia.log(`rss-feeds JSON decode failed: {err}`)
      publish(nil, "error")
    else
      fails = 0
      -- merge the human-readable slot titles onto the feed entries
      for index, feed in ipairs(decoded.feeds or {}) do
        local nice = titles[index]
        if nice ~= nil and nice ~= "" then
          feed.title = nice
        end
        if feed.title == nil or feed.title == "" then
          feed.title = feed.url
        end
      end
      publish(decoded, decoded.status or "ok")
      -- last-good copy so the cold start renders instantly with zero spawns
      noctalia.writeFile(CACHE, result.stdout)
    end
  end
  -- exponential back-off while nothing parses
  local minutes = refreshMinutes * (2 ^ fails)
  noctalia.setUpdateInterval(math.min(minutes, refreshMinutes * 64) * 60 * 1000)
end

local function fetch()
  if #urls == 0 then
    fails = 0
    noctalia.setUpdateInterval(refreshMinutes * 60 * 1000)
    publish({ feeds = {} }, "empty")
    return
  end
  local args = { "python3", SCRIPT, tostring(itemsPerFeed) }
  for _, url in ipairs(urls) do
    table.insert(args, url)
  end
  noctalia.runAsync(args, applyFetch)
end

function update()
  fetch()
end

function onConfigChanged()
  readConfig()
  refreshMinutes = tonumber(noctalia.getConfig("refresh_minutes")) or 30
  refreshMinutes = math.max(5, math.min(1440, refreshMinutes))
  itemsPerFeed = tonumber(noctalia.getConfig("items_per_feed")) or 5
  itemsPerFeed = math.max(1, math.min(15, itemsPerFeed))
  fails = 0
  fetch()
end

noctalia.state.watch("rss.cmd", function(cmd)
  if cmd == "REFRESH" then
    fails = 0
    fetch()
  end
end)

-- ---- Cold start ----

readConfig()
local cached = noctalia.readFile(CACHE)
if cached then
  local data = noctalia.json.decode(cached)
  if data ~= nil and next(urls) ~= nil then
    for index, feed in ipairs(data.feeds or {}) do
      local nice = titles[index]
      if nice ~= nil and nice ~= "" then
        feed.title = nice
      end
      if feed.title == nil or feed.title == "" then
        feed.title = feed.url
      end
    end
    publish(data, data.status or "ok")
  end
end
fetch()
