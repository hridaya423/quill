import os.path

app = defines.get("app", "build/Quill.app")
appname = os.path.basename(app)

format = "UDZO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "assets/Quill.icns"
background = "assets/dmg/background.tiff"
window_rect = ((200, 120), (660, 448))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {appname: (180, 212), "Applications": (480, 212)}
hide_extensions = [appname]
