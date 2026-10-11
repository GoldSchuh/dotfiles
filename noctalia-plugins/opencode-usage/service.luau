--!nonstrict
-- OpenCode usage service - runs the bundled sqlite scanner on an interval
-- and shares the parsed summary with bar and panel via noctalia.state.
--
--   noctalia.runAsync(...)        subprocess with output capture
--   noctalia.json decode/encode   parse scanner JSON, write the cache copy
--   noctalia.pluginDir()          locate scripts/opencode_usage_scanner.py
--   noctalia.pluginDataDir()      persistent last-good cache across restarts

-- Scanner script and cache path
local SCRIPT = noctalia.pluginDir() .. "/scripts/opencode_usage_scanner.py"
local CACHE = noctalia.pluginDataDir() .. "/usage.json"

-- Commands from bar/panel via noctalia.state.watch("usage.cmd", ...)

local refreshSec = tonumber(noctalia.getConfig("refresh_interval_sec")) or 300
if refreshSec < 30 then refreshSec = 30 end
if refreshSec > 3600 then refreshSec = 3600 end

local dbPath = tostring(noctalia.getConfig("db_path") or "~/.local/share/opencode/opencode.db")

noctalia.setUpdateInterval(refreshSec * 1000)

-- ---- Scanner ----

local function publish(data, status)
  noctalia.state.set("usage.data", data)
  noctalia.state.set("usage.status", status)
end

local function applyScan(result)
  if result.exitCode ~= 0 then
    publish(nil, "error")
    noctalia.log(`opencode-usage scanner failed ({result.exitCode}): {result.stderr}`)
    return
  end
  local data, err = noctalia.json.decode(result.stdout)
  if data == nil then
    publish(nil, "error")
    noctalia.log(`opencode-usage JSON decode failed: {err}`)
    return
  end
  publish(data, "ready")
  -- last-good copy so the cold start renders instantly with zero spawns
  noctalia.writeFile(CACHE, result.stdout)
end

local function scan()
  noctalia.state.set("usage.status", "scanning")
  noctalia.runAsync({ "python3", SCRIPT, dbPath }, applyScan)
end

function update()
  scan()
end

function onConfigChanged()
  refreshSec = tonumber(noctalia.getConfig("refresh_interval_sec")) or 300
  if refreshSec < 30 then refreshSec = 30 end
  if refreshSec > 3600 then refreshSec = 3600 end
  dbPath = tostring(noctalia.getConfig("db_path") or "~/.local/share/opencode/opencode.db")
  noctalia.setUpdateInterval(refreshSec * 1000)
  scan()
end

noctalia.state.watch("usage.cmd", function(cmd)
  if cmd == "REFRESH" then
    scan()
  end
end)

-- ---- Cold start ----

-- Last-good cache first so bar/panel never wait on the first scan roundtrip.
local cached = noctalia.readFile(CACHE)
if cached then
  local data = noctalia.json.decode(cached)
  if data then
    publish(data, "ready")
  end
end

noctalia.state.set("usage.status", "scanning")
scan()
