Name = "wallpapers"
NamePretty = "Wallpaper"
Icon = "preferences-desktop-wallpaper"
Cache = false
Action = os.getenv("HOME") .. "/.config/scripts/set-wallpaper.sh '%VALUE%'"
HideFromProviderlist = false
Description = "Wallpaper picker mit Vorschau"
SearchName = true

function GetEntries()
    local entries = {}
    local home = os.getenv("HOME")
    local wallpaper_dir = home .. "/Dokumente/Bilder/wallpapers/"
    local cache_dir = home .. "/.cache/walker-wallpapers"
    os.execute("mkdir -p '" .. cache_dir .. "'")

    local find_cmd = "find '" .. wallpaper_dir .. "' -type f \\( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \\)"
    local handle = io.popen(find_cmd)
    local result = handle:read("*a")
    handle:close()

    for path in result:gmatch("[^\r\n]+") do
        local filename = path:match("^.+/(.+)$")
        local thumb = cache_dir .. "/" .. filename

        local f = io.open(thumb, "r")
        if f == nil then
            local magick_cmd = "magick '" .. path .. "' -thumbnail 512x288^ -gravity center -extent 512x288 '" .. thumb .. "'"
            os.execute(magick_cmd)
        else
            f:close()
        end

        table.insert(entries, {
            Text = "",
            Value = path,
            Icon = thumb,
        })
    end

    return entries
end
