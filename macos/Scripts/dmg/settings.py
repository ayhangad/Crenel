# dmgbuild settings for Crenel. Run through Scripts/release-candidate.sh, which passes:
#   -D app=<path to Crenel.app> -D background=<path to background.png>
# Layout matches Scripts/dmg/background.swift: content 440×480, icon 112,
# Crenel at (220, 132), Applications at (220, 356). Finder counts the title, path and
# status bars in the window height, so the window asks for 600 to leave the content
# at least ~500 even with both bars on; the background is drawn taller than any window.
import os.path

application = defines["app"]
appname = os.path.basename(application)

format = "ULFO"
filesystem = "APFS"
files = [application]
symlinks = {"Applications": "/Applications"}
icon_locations = {appname: (220, 132), "Applications": (220, 356)}
hide_extension = [appname]

background = defines["background"]
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 120), (440, 600))
default_view = "icon-view"
show_icon_preview = False
arrange_by = None
grid_spacing = 100
label_pos = "bottom"
text_size = 13
icon_size = 112
