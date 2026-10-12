--!nonstrict
-- Panel entry point: composes the sound library, audio engine, and UI.
local sounds = require("./sound_library.luau")
local AudioEngine = require("./audio_engine.luau")
local engine = AudioEngine.new(sounds)
local function soundIcon(sound)
    return ui.glyph({ name = sound.icon, size = 22, color = "primary" })
end

local function soundCard(sound)
    return ui.column({ gap = 12, padding = 16, flexGrow = 1, minWidth = 240,
        fill = sound.enabled and "primary/0.14" or "surface_variant/0.25", radius = 16,
        border = sound.enabled and "primary/0.7" or "outline/0.45", borderWidth = 1.5 }, {
        ui.row({ gap = 12, align = "center" }, {
            soundIcon(sound),
            ui.column({ gap = 3, flexGrow = 1 }, {
                ui.label({ text = sound.title, fontSize = 15, fontWeight = "bold" }),
                ui.label({ text = sound.description, fontSize = 11, color = "on_surface_variant", maxLines = 2 }),
            }),
            ui.toggle({
                checked = sound.enabled,
                onChange = function(value)
                    engine:toggleSound(sound.id, value == "true")
                    render()
                end,
            }),
        }),
        ui.row({ gap = 10, align = "center" }, {
            ui.button({ glyph = "bolt", glyphSize = 14, controlSize = "sm",
                variant = sound.amplified and "primary" or "ghost",
                onClick = function()
                    engine:setAmplified(sound.id, not sound.amplified)
                    render()
                end }),
            ui.label({ text = "VOLUME", fontSize = 10, color = "on_surface_variant", width = 46 }),
            ui.slider({ min = 0, max = 100, step = 1, value = sound.level, controlSize = "sm", flexGrow = 1,
                onChange = function(value) engine:setSoundVolume(sound.id, tonumber(value) or 0); render() end }),
            ui.label({ text = sound.level .. "%", fontSize = 11, color = "primary", width = 35, textAlign = "end" }),
        }),
    })
end

function render()
    local cardRows = {}
    for index, sound in ipairs(sounds) do
        local row = cardRows[math.ceil(index / 2)]
        if not row then
            row = {}
            table.insert(cardRows, row)
        end
        table.insert(row, soundCard(sound))
    end

    local grid = {}
    for _, row in ipairs(cardRows) do
        while #row < 2 do table.insert(row, ui.spacer({ flexGrow = 1, minWidth = 240 })) end
        table.insert(grid, ui.row({ gap = 12, align = "stretch" }, row))
    end

    local playButton = ui.row({
        width = 58, height = 58, radius = 29, fill = "primary",
        align = "center", justify = "center",
        onClick = function()
            if engine.running then engine:stopAll() else engine:start() end
            render()
        end,
    }, {
        ui.glyph({ name = engine.running and "player-stop" or "player-play", size = 26, color = "on_primary" }),
    })

    panel.render(ui.column({ gap = 12, padding = 16, height = 480, fill = "surface/0.45" }, {
        ui.scroll({ gap = 12, flexGrow = 1, align = "stretch" }, grid),
        ui.row({ align = "center", justify = "center" }, {
            playButton,
        }),
    }))
end

function onOpen(_context)
    render()
end

function onExit(_signal, _reason)
    engine:cleanup()
end
