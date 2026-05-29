@tool
extends RefCounted
class_name CodaDesignTokens

## Central design tokens for the Coda editor.
## Keeping these in code (not just a .tres) means runtime-built UI can stay consistent.

const ACCENT := Color(0.42, 0.74, 1.00, 1.0)
const ACCENT_DIM := Color(0.30, 0.55, 0.78, 1.0)
const SURFACE_BG := Color(0.105, 0.115, 0.135, 1.0)
const SURFACE_RAISED := Color(0.135, 0.150, 0.175, 1.0)
const SURFACE_SUNKEN := Color(0.085, 0.095, 0.115, 1.0)
const SURFACE_BORDER := Color(0.235, 0.255, 0.295, 1.0)
const TEXT_PRIMARY := Color(0.92, 0.94, 0.97, 1.0)
const TEXT_SECONDARY := Color(0.66, 0.71, 0.78, 1.0)
const TEXT_MUTED := Color(0.50, 0.55, 0.62, 1.0)
const DANGER := Color(0.95, 0.40, 0.40, 1.0)
const WARN := Color(0.95, 0.70, 0.30, 1.0)
const SUCCESS := Color(0.50, 0.85, 0.55, 1.0)

const CLIP_FILL := Color(0.88, 0.52, 0.44, 0.82)
const CLIP_FILL_SELECTED := Color(0.94, 0.60, 0.50, 0.92)
const CLIP_BORDER := Color(0.68, 0.38, 0.32, 1.0)
const CLIP_BORDER_SELECTED := Color(0.98, 0.94, 0.90, 1.0)
const FADE_LINE := Color(0.96, 0.97, 0.99, 0.95)
const FADE_SHADE := Color(0.04, 0.05, 0.08, 0.42)
const HANDLE_DIAMOND_FILL := Color(0.97, 0.98, 1.0, 1.0)
const HANDLE_DIAMOND_BORDER := Color(0.22, 0.26, 0.32, 1.0)
const TRIM_HANDLE := Color(0.98, 0.98, 1.0, 0.82)
const TRIM_HANDLE_HOT := Color(1.0, 1.0, 1.0, 1.0)
const CROSSFADE_HIGHLIGHT := Color(0.95, 0.95, 0.98, 0.12)

const SPACING_XS := 4
const SPACING_SM := 8
const SPACING_MD := 12
const SPACING_LG := 16
const SPACING_XL := 24
const RADIUS_SM := 4
const RADIUS_MD := 6
const RADIUS_LG := 10

const FONT_TITLE_SIZE := 18
const FONT_HEADING_SIZE := 14
const FONT_BODY_SIZE := 13
const FONT_LABEL_SIZE := 12


static func make_panel_stylebox(
	bg: Color = SURFACE_RAISED,
	border: Color = SURFACE_BORDER,
	radius: int = RADIUS_MD,
	border_width: int = 1
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = SPACING_MD
	sb.content_margin_right = SPACING_MD
	sb.content_margin_top = SPACING_SM
	sb.content_margin_bottom = SPACING_SM
	return sb


static func make_section_separator() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE_BORDER
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


## Project-wide theme variant. The editor window builds a Theme that overrides the
## `accent` color and the dark/light surface palette, then applies it to its root.
static func make_project_theme(theme_mode: String, accent: Color) -> Theme:
	var theme := Theme.new()
	var bg: Color = SURFACE_BG
	var raised: Color = SURFACE_RAISED
	var border: Color = SURFACE_BORDER
	var text: Color = TEXT_PRIMARY
	var text_dim: Color = TEXT_SECONDARY
	if theme_mode.to_lower() == "light":
		bg = Color(0.96, 0.96, 0.97, 1.0)
		raised = Color(1.0, 1.0, 1.0, 1.0)
		border = Color(0.84, 0.86, 0.90, 1.0)
		text = Color(0.10, 0.12, 0.16, 1.0)
		text_dim = Color(0.32, 0.36, 0.42, 1.0)

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = raised
	panel_sb.border_color = border
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(RADIUS_MD)
	panel_sb.content_margin_left = SPACING_SM
	panel_sb.content_margin_right = SPACING_SM
	panel_sb.content_margin_top = SPACING_XS
	panel_sb.content_margin_bottom = SPACING_XS
	theme.set_stylebox("panel", "PanelContainer", panel_sb)

	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = bg
	theme.set_stylebox("panel", "Panel", bg_sb)

	theme.set_color("font_color", "Label", text)
	theme.set_color("font_color", "Button", text)
	theme.set_color("font_color", "CheckBox", text)
	theme.set_color("font_color", "OptionButton", text)
	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("font_color_disabled", "Label", text_dim)

	# Accent goes on highlight elements that read accent in their built-in styles.
	theme.set_color("font_focus_color", "Button", accent)
	theme.set_color("caret_color", "LineEdit", accent)
	theme.set_color("selection_color", "LineEdit", Color(accent.r, accent.g, accent.b, 0.35))
	return theme
