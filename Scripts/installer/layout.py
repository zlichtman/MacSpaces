"""Finder presentation only; this never modifies the signed application."""
from pathlib import Path
app = Path(defines['app']).resolve()
files = [str(app)]
symlinks = {'Applications': '/Applications'}
background = defines['background']
icon = str(app / 'Contents/Resources/AppIcon.icns')
format = 'UDZO'
filesystem = 'HFS+'
window_rect = ((180, 160), (720, 500))
default_view = 'icon-view'
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
show_tab_view = False
arrange_by = None
icon_size = 88
text_size = 13
label_pos = 'bottom'
icon_locations = {'MacSpaces.app': (200, 267), 'Applications': (520, 267), '.background.tiff': (1000, 1000), '.VolumeIcon.icns': (1000, 1000)}
include_icon_view_settings = True
include_list_view_settings = False

# Keep support assets outside the opening canvas even when Finder shows hidden files.
scroll_position = (0, 0)
