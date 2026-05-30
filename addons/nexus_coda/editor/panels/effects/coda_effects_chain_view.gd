@tool
class_name CodaEffectsChainView
extends VBoxContainer

## Generic ordered effect chain UI.
##
## Two refresh paths so the slider under the cursor survives a drag:
##   * [method _rebuild_rows] runs only when the *structure* of the chain changes
##     (count, IDs, effect type, bypass state) — that is what tears down child widgets.
##   * [method _sync_rows_from_data] is the cheap path used after every param edit:
##     it walks the existing rows and pushes new values into sliders/spinboxes via
##     [code]set_value_no_signal[/code], leaving widget identity intact.
##
## Visual language follows the Mixer strip: each effect lives in its own
## [PanelContainer] card with a header row, accent rule, and the param grid below.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaEffectCatalogScript := preload(
	"res://addons/nexus_coda/editor/browser/effects/coda_effect_catalog.gd"
)

const _LABEL_COL_WIDTH := 140
const _SPINBOX_COL_WIDTH := 96
const _BTN_SIZE := Vector2(28, 24)
const _HEADER_HEIGHT := 30

signal effect_add_menu_opened
signal effect_add_requested(effect_type: int)
signal effect_remove_requested(effect_id: String)
signal effect_move_requested(from_index: int, to_index: int)
signal effect_param_changed(effect_id: String, param_key: String, param_value: float)
signal effect_bypass_changed(effect_id: String, on: bool)

var _title: Label
var _subtitle: Label
var _footer: Label
var _add_btn: MenuButton
var _list: VBoxContainer
var _empty_hint: Label

var _effects_ref: Array[CodaTrackEffect] = []
var _row_by_effect_id: Dictionary = {}
var _last_structure_sig: String = ""
var _suppress: bool = false
var _ready_done: bool = false
var _pending_bind: bool = false


func _ready() -> void:
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header_row)

	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override(&"separation", 0)
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_col)

	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", Tokens.FONT_HEADING_SIZE)
	_title.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	title_col.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE - 1)
	_subtitle.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_subtitle.text = ""
	title_col.add_child(_subtitle)

	_add_btn = MenuButton.new()
	_add_btn.text = "+ Effect"
	_add_btn.tooltip_text = "Add an effect to this chain"
	_add_btn.switch_on_hover = true
	_add_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	var add_popup: PopupMenu = _add_btn.get_popup()
	add_popup.transient = true
	add_popup.exclusive = true
	add_popup.unfocusable = false
	_build_add_menu(add_popup)
	if not add_popup.id_pressed.is_connected(_on_add_menu_id_pressed):
		add_popup.id_pressed.connect(_on_add_menu_id_pressed)
	if not add_popup.about_to_popup.is_connected(_on_add_menu_about_to_popup):
		add_popup.about_to_popup.connect(_on_add_menu_about_to_popup)
	header_row.add_child(_add_btn)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(_list)

	_empty_hint = Label.new()
	_empty_hint.text = "No effects yet. Use + Effect to add one."
	_empty_hint.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_empty_hint.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(_empty_hint)

	_footer = Label.new()
	_footer.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE - 1)
	_footer.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.text = ""
	add_child(_footer)
	_ready_done = true
	if _pending_bind:
		_pending_bind = false
		_apply_bind()


func set_chain_title(title: String) -> void:
	if _title != null:
		_title.text = title


func set_chain_subtitle(subtitle: String) -> void:
	if _subtitle != null:
		_subtitle.text = subtitle
		_subtitle.visible = not subtitle.is_empty()


func set_footer_text(text: String) -> void:
	if _footer != null:
		_footer.text = text


func set_footer_visible(on: bool) -> void:
	if _footer != null:
		_footer.visible = on


func bind_effects_array(effects: Array[CodaTrackEffect]) -> void:
	_last_structure_sig = ""
	_effects_ref = effects
	if not _ready_done or _list == null:
		_pending_bind = true
		return
	_apply_bind()


func get_effect_card_count() -> int:
	if _list == null:
		return 0
	var count: int = 0
	for child in _list.get_children():
		if child is PanelContainer:
			count += 1
	return count


func _apply_bind() -> void:
	if _list == null:
		return
	var sig: String = _compute_structure_sig()
	if sig == _last_structure_sig and _row_by_effect_id.size() == _effects_ref.size():
		_sync_rows_from_data()
		return
	_last_structure_sig = sig
	_rebuild_rows()


func _compute_structure_sig() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for eff in _effects_ref:
		parts.append("%s:%d:%d" % [eff.id, int(eff.type), int(eff.bypass)])
	return "%d|%s" % [_effects_ref.size(), "|".join(parts)]


func _build_add_menu(menu: PopupMenu) -> void:
	menu.clear()
	# Group entries by category for a quicker scan; PopupMenu shows them in insertion order.
	var by_cat: Dictionary = {}
	var types: Array[CodaTrackEffect.Type] = CodaEffectCatalogScript.all_types_sorted()
	for t in types:
		var cat: String = CodaEffectCatalogScript.category_for_type(t)
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(t)
	var first: bool = true
	for cat in by_cat.keys():
		if not first:
			menu.add_separator(str(cat))
		else:
			menu.add_separator(str(cat))
			first = false
		for t in by_cat[cat]:
			# Menu IDs start at 1 — Godot treats 0 as "unset" for some PopupMenu paths.
			menu.add_item(CodaEffectCatalogScript.display_name_for_type(t), int(t) + 1)


func _on_add_menu_about_to_popup() -> void:
	effect_add_menu_opened.emit()


func _on_add_menu_id_pressed(id: int) -> void:
	_submit_menu_pick(id)


func _submit_menu_pick(raw_id: int) -> void:
	if raw_id <= 0:
		return
	var effect_type: int = raw_id - 1
	if effect_type < 0 or effect_type > int(CodaTrackEffect.Type.STEREO_ENHANCE):
		return
	effect_add_requested.emit(effect_type)


# ---------- Rendering ----------

func _rebuild_rows() -> void:
	_row_by_effect_id.clear()
	for c in _list.get_children():
		_list.remove_child(c)
		if c == _empty_hint:
			continue
		c.queue_free()

	if _effects_ref.is_empty():
		_empty_hint.visible = true
		_list.add_child(_empty_hint)
		return
	_empty_hint.visible = false

	for i in _effects_ref.size():
		var eff: CodaTrackEffect = _effects_ref[i]
		var card: PanelContainer = _make_effect_card(eff, i)
		_list.add_child(card)
	_list.update_minimum_size()


func _sync_rows_from_data() -> void:
	for i in _effects_ref.size():
		var eff: CodaTrackEffect = _effects_ref[i]
		var row_meta: Variant = _row_by_effect_id.get(eff.id, null)
		if row_meta == null:
			continue
		var meta: Dictionary = row_meta as Dictionary
		if meta.has("bypass_btn"):
			var btn: CheckBox = meta["bypass_btn"] as CheckBox
			if btn != null and btn.button_pressed != eff.bypass:
				btn.set_pressed_no_signal(eff.bypass)
		var widgets: Dictionary = meta.get("param_widgets", {}) as Dictionary
		var params: Dictionary = eff.params
		for k in widgets.keys():
			var pair: Dictionary = widgets[k] as Dictionary
			var sl: HSlider = pair.get("slider") as HSlider
			var spb: SpinBox = pair.get("spinbox") as SpinBox
			var cur: float = float(params.get(k, sl.value if sl != null else 0.0))
			if sl != null and not sl.has_focus() and not is_equal_approx(sl.value, cur):
				sl.set_value_no_signal(cur)
			if spb != null and not spb.get_line_edit().has_focus() \
					and not is_equal_approx(spb.value, cur):
				spb.set_value_no_signal(cur)


# ---------- Effect card ----------

func _make_effect_card(eff: CodaTrackEffect, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border: Color = Tokens.ACCENT_DIM if not eff.bypass else Tokens.SURFACE_BORDER
	card.add_theme_stylebox_override(
		&"panel", Tokens.make_panel_stylebox(Tokens.SURFACE_RAISED, border, Tokens.RADIUS_MD)
	)

	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	card.add_child(body)

	var header: HBoxContainer = _make_card_header(eff, index)
	body.add_child(header)

	body.add_child(_make_hairline_separator())

	var params_box := VBoxContainer.new()
	params_box.add_theme_constant_override(&"separation", 2)
	body.add_child(params_box)

	var widgets: Dictionary = {}
	var specs: Array[Dictionary] = CodaEffectCatalogScript.param_specs(eff.type)
	for sp in specs:
		var pair: Dictionary = {}
		var row: HBoxContainer = _make_param_row(eff, sp, pair)
		params_box.add_child(row)
		widgets[str(sp.get("name", ""))] = pair

	_row_by_effect_id[eff.id] = {
		"card": card,
		"bypass_btn": header.get_meta(&"bypass_btn"),
		"param_widgets": widgets,
	}
	return card


func _make_card_header(eff: CodaTrackEffect, index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	row.custom_minimum_size = Vector2(0, _HEADER_HEIGHT)

	var bypass := CheckBox.new()
	bypass.text = ""
	bypass.focus_mode = Control.FOCUS_NONE
	bypass.button_pressed = eff.bypass
	bypass.tooltip_text = "Bypass this effect"
	bypass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bypass.toggled.connect(
		func(on: bool) -> void:
			effect_bypass_changed.emit(eff.id, on)
	)
	row.add_child(bypass)
	row.set_meta(&"bypass_btn", bypass)

	var title := Label.new()
	title.text = CodaEffectCatalogScript.display_name_for_type(eff.type)
	title.add_theme_font_size_override(&"font_size", Tokens.FONT_HEADING_SIZE)
	title.add_theme_color_override(
		&"font_color", Tokens.TEXT_MUTED if eff.bypass else Tokens.TEXT_PRIMARY
	)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	var category := Label.new()
	category.text = CodaEffectCatalogScript.category_for_type(eff.type)
	category.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE - 1)
	category.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	category.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(category)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(_make_icon_button("↑", "Move effect up", index <= 0, func() -> void:
		effect_move_requested.emit(index, index - 1)
	))
	row.add_child(_make_icon_button("↓", "Move effect down", index >= _effects_ref.size() - 1,
		func() -> void:
			effect_move_requested.emit(index, index + 1)
	))
	row.add_child(_make_icon_button("✕", "Remove effect", false, func() -> void:
		effect_remove_requested.emit(eff.id)
	))
	return row


func _make_icon_button(text: String, tip: String, p_disabled: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = _BTN_SIZE
	b.disabled = p_disabled
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_press)
	return b


func _make_hairline_separator() -> Panel:
	var sep := Panel.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.SURFACE_BORDER
	sep.add_theme_stylebox_override(&"panel", sb)
	return sep


# ---------- Param row ----------

func _make_param_row(eff: CodaTrackEffect, spec: Dictionary, out_widgets: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", Tokens.SPACING_MD)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pkey: String = str(spec.get("name", ""))
	var unit: String = str(spec.get("unit", ""))
	var lbl_text: String = _humanize_param_key(pkey)
	if not unit.is_empty():
		lbl_text = "%s (%s)" % [lbl_text, unit]

	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.custom_minimum_size = Vector2(_LABEL_COL_WIDTH, 0)
	lbl.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	lbl.add_theme_color_override(&"font_color", Tokens.TEXT_SECONDARY)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.tooltip_text = str(spec.get("tooltip", ""))
	row.add_child(lbl)

	var sl := HSlider.new()
	sl.min_value = float(spec.get("min", 0.0))
	sl.max_value = float(spec.get("max", 1.0))
	sl.step = float(spec.get("step", 0.01))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(0, 22)
	sl.focus_mode = Control.FOCUS_NONE
	sl.mouse_filter = Control.MOUSE_FILTER_STOP
	var cur: float = float(eff.params.get(pkey, sl.min_value))
	sl.value = cur
	sl.tooltip_text = str(spec.get("tooltip", ""))
	row.add_child(sl)

	var spb := SpinBox.new()
	spb.min_value = sl.min_value
	spb.max_value = sl.max_value
	spb.step = sl.step
	spb.value = cur
	spb.custom_minimum_size = Vector2(_SPINBOX_COL_WIDTH, 0)
	spb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(spb)

	sl.value_changed.connect(
		func(v: float) -> void:
			if _suppress:
				return
			_suppress = true
			spb.set_value_no_signal(v)
			_suppress = false
			effect_param_changed.emit(eff.id, pkey, v)
	)
	spb.value_changed.connect(
		func(v: float) -> void:
			if _suppress:
				return
			_suppress = true
			sl.set_value_no_signal(v)
			_suppress = false
			effect_param_changed.emit(eff.id, pkey, float(v))
	)

	out_widgets["slider"] = sl
	out_widgets["spinbox"] = spb
	return row


static func _humanize_param_key(key: String) -> String:
	if key.is_empty():
		return key
	var parts: PackedStringArray = key.replace("_", " ").split(" ")
	var out: PackedStringArray = PackedStringArray()
	for p in parts:
		if p.is_empty():
			continue
		out.append(p.substr(0, 1).to_upper() + p.substr(1))
	return " ".join(out)
