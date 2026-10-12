# ~/.config/qutebrowser/config.py — Oleo rice, matching the Noctalia bar.

import colors

config.load_autoconfig(False)

c.window.hide_decoration = True
c.window.title_format = "{perc}{audio}{current_title} — {backend}"

# ---- behavior niceties ----
c.zoom.default = 105
c.content.headers.accept_language = "de-DE,de;q=0.9,en;q=0.8"
c.scrolling.smooth = True
c.tabs.select_on_remove = "last-used"
c.tabs.new_position.stacking = False
c.editor.command = ["kitty", "-e", "nvim", "{file}"]

# ---- fonts: JetBrains Mono everywhere, like kitty ----
c.fonts.default_family = ["JetBrains Mono"]
c.fonts.web.family.standard = "Carlito"
c.fonts.web.family.sans_serif = "Carlito"
c.fonts.web.family.serif = "Tinos"
c.fonts.web.family.fixed = "JetBrains Mono"

# ---- tabs: capsule look like the Noctalia bar ----
c.tabs.position = "top"
c.tabs.show = "multiple"
c.tabs.width = "23%"
c.tabs.padding = {"top": 5, "bottom": 5, "left": 10, "right": 10}
c.tabs.favicons.show = "never"
c.tabs.title.format = "{audio}{index}: {current_title}"

c.colors.tabs.bar.bg = colors.bg
c.colors.tabs.indicator.system = "none"
c.colors.tabs.indicator.start = colors.primary
c.colors.tabs.indicator.stop = colors.primary
c.colors.tabs.indicator.error = colors.error

c.colors.tabs.selected.even.bg = colors.surface
c.colors.tabs.selected.even.fg = colors.bright_fg
c.colors.tabs.selected.odd.bg = colors.surface
c.colors.tabs.selected.odd.fg = colors.bright_fg

c.colors.tabs.even.bg = colors.bg
c.colors.tabs.even.fg = colors.dim_fg
c.colors.tabs.odd.bg = colors.bg
c.colors.tabs.odd.fg = colors.dim_fg

# ---- statusbar: low-key, only visible in modes ----
c.statusbar.show = "in-mode"
c.statusbar.position = "bottom"
c.statusbar.padding = {"top": 3, "bottom": 3, "left": 8, "right": 8}

c.colors.statusbar.normal.bg = colors.bg
c.colors.statusbar.normal.fg = colors.fg
c.colors.statusbar.private.bg = colors.bg
c.colors.statusbar.private.fg = "#c0a37f"
c.colors.statusbar.insert.bg = colors.primary
c.colors.statusbar.insert.fg = colors.bg
c.colors.statusbar.command.bg = colors.variant
c.colors.statusbar.command.fg = colors.dim_fg
c.colors.statusbar.command.private.bg = colors.variant
c.colors.statusbar.command.private.fg = colors.dim_fg
c.colors.statusbar.caret.bg = colors.bg
c.colors.statusbar.caret.fg = colors.gold
c.colors.statusbar.caret.selection.bg = colors.selection
c.colors.statusbar.caret.selection.fg = colors.selection_fg
c.colors.statusbar.progress.bg = colors.primary

c.colors.statusbar.url.success.http.fg = colors.fg
c.colors.statusbar.url.success.https.fg = colors.fg
c.colors.statusbar.url.error.fg = colors.error
c.colors.statusbar.url.warn.fg = colors.gold

# ---- completion: picklist in surface colors ----
c.completion.height = "25%"
c.completion.use_best_match = False
c.completion.open_categories = ["searchengines", "quickmarks", "bookmarks", "history"]

c.colors.completion.fg = colors.fg
c.colors.completion.category.fg = colors.dim_fg
c.colors.completion.category.bg = colors.bg
c.colors.completion.item.selected.fg = colors.bright_fg
c.colors.completion.item.selected.bg = colors.variant
c.colors.completion.item.selected.match.fg = colors.primary
c.colors.completion.match.fg = colors.gold
c.colors.completion.scrollbar.fg = colors.outline
c.colors.completion.scrollbar.bg = colors.bg

# ---- hints: rounded capsules, gold matches ----
c.hints.uppercase = False
c.colors.hints.fg = colors.bright_fg
c.colors.hints.bg = colors.surface
c.hints.border = f"1px solid {colors.outline}"
c.colors.hints.match.fg = colors.gold

# ---- messages / prompts ----
c.colors.messages.error.bg = colors.error
c.colors.messages.error.fg = colors.selection_fg
c.colors.messages.error.border = colors.error
c.colors.messages.warning.bg = colors.gold
c.colors.messages.warning.fg = colors.bg
c.colors.messages.warning.border = colors.gold
c.colors.messages.info.bg = colors.surface
c.colors.messages.info.fg = colors.bright_fg
c.colors.messages.info.border = colors.outline
c.colors.prompts.selected.bg = colors.selection
c.colors.prompts.selected.fg = colors.selection_fg
c.colors.prompts.fg = colors.fg

# ---- webpage fallback ----
c.colors.webpage.bg = colors.bg
