# dmgbuild settings for Crenel. Run through Scripts/release-candidate.sh, which passes:
#   -D app=<path to Crenel.app> -D background=<path to background.png>
# Layout matches Scripts/dmg/background.swift: window 440×520, icon 128,
# Crenel at (220, 150), Applications at (220, 398).
import os.path

application = defines["app"]
appname = os.path.basename(application)

format = "ULFO"
filesystem = "APFS"
files = [application]
symlinks = {"Applications": "/Applications"}
icon_locations = {appname: (220, 150), "Applications": (220, 398)}
hide_extension = [appname]

background = defines["background"]
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 120), (440, 520))
default_view = "icon-view"
show_icon_preview = False
arrange_by = None
grid_spacing = 100
label_pos = "bottom"
text_size = 13
icon_size = 112
