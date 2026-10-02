class_name CampaignUI
extends CanvasLayer

signal action_requested(action: String, payload: Dictionary)

const Catalog := preload("res://scripts/game_content.gd")
const Bindings := preload("res://scripts/input_bindings.gd")
const FONT := preload("res://assets/fonts/NotoSansSC.ttf")
const KEYART := preload("res://assets/characters/renfeng-keyart.png")
const CYAN := Color("76eee6")
const GOLD := Color("ffbd7c")
const WHITE := Color("e9eef7")
const DIM := Color("99abc4")
const VIOLET := Color("b9a1ff")
const SLOT_NAMES := {"weapon": "武器", "armor": "防具", "charm": "饰品"}
var action_controls: Dictionary = {}
var page := ""
var context: Dictionary = {}
var _store: SaveStore
var _root: Control
var _body: VBoxContainer
var _scroll: ScrollContainer
var _layout_revision := 0
var _theme: Theme
var _focus_key := ""
var _filter := "all"
var _selected_uid := ""
var _modal: Control
var _capture_action := ""
var _capture_label: Label
var _confirmation_action := ""
var _confirmation_payload: Dictionary = {}
var _focus_before_modal: Control

func _ready() -> void:
	layer = 8
	set_process_input(true)
	if _root == null:
		_build_root()
		_root.hide()

func show_page(next_page: String, store: SaveStore, extra: Dictionary = {}) -> void:
	_focus_key = _focused_action()
	var same_page := next_page == page
	page = next_page
	_store = store
	context = extra.duplicate(true)
	if not same_page:
		_focus_key = ""
		_filter = "all"
		_selected_uid = ""
	_capture_action = ""
	_confirmation_action = ""
	_confirmation_payload.clear()
	if _root == null:
		_build_root()
	var desired_focus := _focus_key
	_rebuild()
	_root.show()
	_focus_page.call_deferred(desired_focus)
	_settle_layout(_layout_revision, desired_focus)

func hide_ui() -> void:
	if _root != null:
		_root.hide()
	_capture_action = ""
	_close_modal()

func _build_root() -> void:
	_root = Control.new()
	_root.name = "CampaignInterface"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

func _make_theme() -> Theme:
	var theme := Theme.new()
	var font := FontVariation.new()
	font.base_font = FONT
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 550.0}
	theme.default_font = font
	theme.default_font_size = 20 if _store.settings.get("large_text", false) else 18
	theme.set_color("font_color", "Label", WHITE)
	theme.set_color("font_color", "Button", WHITE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color("65738c"))
	theme.set_constant("separation", "HBoxContainer", 16)
	theme.set_constant("separation", "VBoxContainer", 12)
	theme.set_constant("h_separation", "GridContainer", 14)
	theme.set_constant("v_separation", "GridContainer", 14)
	theme.set_stylebox("normal", "Button", _style(Color("142137"), Color("31415b"), 1, 10, 16, 10))
	theme.set_stylebox("hover", "Button", _style(Color("23334b"), CYAN, 1, 10, 16, 10))
	theme.set_stylebox("pressed", "Button", _style(Color("1e454c"), CYAN, 1, 10, 16, 10))
	theme.set_stylebox("disabled", "Button", _style(Color("101727"), Color("263149"), 1, 10, 16, 10))
	theme.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), GOLD, 3, 10, 4, 4))
	theme.set_stylebox("focus", "CheckButton", _style(Color(0, 0, 0, 0), GOLD, 3, 8, 4, 4))
	theme.set_stylebox("focus", "HSlider", _style(Color(0, 0, 0, 0), GOLD, 3, 8, 4, 4))
	theme.set_color("font_color", "CheckButton", WHITE)
	theme.set_color("font_disabled_color", "CheckButton", DIM)
	theme.set_stylebox("slider", "HSlider", _style(Color("293a55"), Color("293a55"), 0, 3, 0, 3))
	theme.set_stylebox("grabber_area", "HSlider", _style(CYAN, CYAN, 0, 3, 0, 3))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _style(GOLD, GOLD, 0, 3, 0, 3))
	theme.set_stylebox("background", "ProgressBar", _style(Color("293a55"), Color("293a55"), 0, 3, 0, 5))
	theme.set_stylebox("fill", "ProgressBar", _style(CYAN, CYAN, 0, 3, 0, 5))
	return theme

func _style(fill: Color, edge: Color, border: int = 1, radius: int = 12, horizontal: int = 20, vertical: int = 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(border)
	style.set_corner_radius_all(radius)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _rebuild() -> void:
	_layout_revision += 1
	_close_modal()
	_clear_children(_root)
	action_controls.clear()
	_theme = _make_theme()
	_root.theme = _theme
	var background := ColorRect.new()
	background.color = Color("091120") if page != "pause" else Color(0.025, 0.045, 0.09, 0.94)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)
	var accent := ColorRect.new()
	accent.color = CYAN
	accent.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	accent.offset_bottom = 3
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(accent)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 34)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_root.add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 16)
	margin.add_child(shell)
	_header(shell)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	shell.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16)
	scroll.add_child(_body)
	match page:
		"menu": _menu()
		"prepare": _prepare()
		"stages": _stages()
		"inventory": _inventory()
		"settings": _settings()
		"help": _help()
		"pause": _pause_page()
		"result": _result()
		_: _prepare()
	_footer(shell)
	_wire_focus.call_deferred()

func _header(parent: Control) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var titles := {"menu": "裂隙猎人", "prepare": "出战准备", "stages": "远征 · 遗落港", "inventory": "装备背包", "settings": "设置", "help": "操作与战术", "pause": "战斗暂停", "result": "远征结算"}
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 2)
	row.add_child(block)
	_label(block, str(titles.get(page, "出战准备")), 32, WHITE)
	var subs := {"menu": "TIME HUNTER OFFLINE  /  单机横版动作", "prepare": "刃锋 · 近距离连击与时机躲避", "stages": "第一章  /  三段遭遇，逐关独立结算", "inventory": "配置在安全界面生效  /  强化与更换立即保存", "settings": "调整即时生效并保存", "help": "先看前摇，再决定接近、绕后或躲避", "pause": "战斗与本关计时已冻结", "result": "只有通关后才确认本次奖励"}
	_label(block, str(subs.get(page, "")), 16, DIM)
	var ledger := VBoxContainer.new()
	ledger.custom_minimum_size.x = 170
	ledger.size_flags_horizontal = Control.SIZE_SHRINK_END
	ledger.alignment = BoxContainer.ALIGNMENT_CENTER
	ledger.add_theme_constant_override("separation", 2)
	row.add_child(ledger)
	var balance := _label(ledger, "%d 金币" % _store.coins, 21, GOLD)
	balance.autowrap_mode = TextServer.AUTOWRAP_OFF
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var level_label := _label(ledger, "刃锋 Lv.%d" % (_store.level + 1), 16, DIM)
	level_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _footer(parent: Control) -> void:
	if page == "prepare":
		var actions := _row(parent)
		var can_edit := _store.active_run.is_empty()
		_button(actions, "选择远征关卡", "stages", func(): _open_page("stages"), true, not can_edit)
		_button(actions, "整理装备", "inventory", func(): _open_page("inventory"))
		_button(actions, "安全练习", "practice", func(): _emit("practice"), false, not can_edit)
		_button(actions, "操作说明", "help", func(): _open_page("help"))
	var message: String = context.get("message", "")
	if not message.is_empty():
		_label(parent, message, 16, GOLD)
	var line := HSeparator.new()
	line.modulate = Color("31415b")
	parent.add_child(line)
	var row := HBoxContainer.new()
	parent.add_child(row)
	var tip := _label(row, "Tab / 方向键切换焦点   Enter 确认   Esc 返回", 14, DIM)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if page != "menu":
		var pending_result: bool = page == "result" and not context.get("result", {}).get("ok", true)
		var back := _button(row, "返回战斗" if page == "pause" else "返回", "back", _back, false, pending_result, 128)
		back.size_flags_horizontal = Control.SIZE_SHRINK_END

func _label(parent: Control, text: String, font_size: int = 18, color: Color = WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size + (2 if _store.settings.get("large_text", false) and font_size >= 16 else 0))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Control, text: String, key: String, callback: Callable, primary: bool = false, disabled: bool = false, minimum_width: float = 0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(minimum_width, 50)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = disabled
	if primary:
		button.add_theme_stylebox_override("normal", _style(Color("164249"), CYAN, 1, 10, 16, 10))
		button.add_theme_color_override("font_color", CYAN)
	button.pressed.connect(callback)
	button.focus_entered.connect(func(): _focus_key = key)
	parent.add_child(button)
	action_controls[key] = button
	return button

func _emit(action: String, payload: Dictionary = {}) -> void:
	action_requested.emit(action, payload)

func _card(parent: Control, title: String, eyebrow: String = "", edge: Color = Color("2a3b54")) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color("101c30"), edge, 1, 12, 20, 18))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	if not eyebrow.is_empty():
		_label(box, eyebrow, 14, CYAN)
	if not title.is_empty():
		_label(box, title, 23)
	return box

func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	return row

func _note(parent: Control, text: String, color: Color = DIM) -> void:
	var box := _card(parent, "", "", Color("263951"))
	_label(box, text, 16, color)

func _menu() -> void:
	var row := _row(_body)
	var intro := _card(row, "刃锋", "第一章 · 遗落港", Color("385167"))
	intro.get_parent().size_flags_stretch_ratio = 1.15
	_label(intro, "追踪裂隙，夺回时间。", 29, CYAN)
	_label(intro, "一名猎人，三段远征。观察敌人的前摇，穿过危险，在破绽中完成连击。", 19, DIM)
	var portrait := TextureRect.new()
	portrait.texture = KEYART
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(0, 295)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro.add_child(portrait)
	var actions := _card(row, "开始远征", "离线存档 · 自动保存")
	if _store.has_progress:
		var checkpoint := not _store.active_run.is_empty()
		_button(actions, "继续游戏", "continue", func(): _emit("continue"), true)
		var resume_text := "继续进入出战准备，保留装备、等级与关卡解锁。"
		if checkpoint:
			resume_text = "恢复最近安全节点：%s。该遭遇重新开始，已入账进度保留。" % Catalog.stage(str(_store.active_run.get("stage", "outskirts"))).get("name", "遗迹外围")
		_label(actions, resume_text, 16, DIM)
		_button(actions, "新游戏", "new_game", func(): _confirm("开始新游戏？", "当前角色等级、金币、装备、关卡记录与检查点将被替换，设置恢复默认。", "new_game", {}, "确认新游戏"))
	else:
		var protected_save := _store.load_status in ["corrupt", "unsupported"]
		_button(actions, "覆盖存档并开始新游戏" if protected_save else "开始游戏", "begin", func(): _confirm("覆盖现有存档？", "现有存档无法读取。继续会替换主存档与备份，重新开始角色进度，并恢复默认设置。", "new_game", {}, "确认覆盖") if protected_save else _emit("begin"), true)
		_label(actions, "从刃锋的初始装备开始，首通奖励会确定性解锁下一关。", 17, DIM)
	_button(actions, "设置", "settings", func(): _open_page("settings"))
	_button(actions, "操作说明", "help", func(): _open_page("help"))
	if not _store.load_message.is_empty():
		_label(actions, _store.load_message, 16, GOLD)
	_label(actions, "通关后奖励到账。失败或返回准备不会损失已有装备与金币。", 16, DIM)

func _prepare() -> void:
	var can_edit := _store.active_run.is_empty()
	if not can_edit:
		var resume := _card(_body, "还有一场未完成的远征", "检查点已保存", GOLD)
		_label(resume, "继续恢复最近安全节点。若要调整配装，请先放弃本次未结算收益；已有进度全部保留。", 17, DIM)
		var resume_row := _row(resume)
		_button(resume_row, "继续远征", "continue", func(): _emit("continue"), true)
		_button(resume_row, "放弃本次远征并调整配装", "abandon", func(): _confirm("放弃本次远征？", "仅放弃本次未结算收益与检查点。已入账的装备、金币、经验和关卡解锁保留。", "abandon", {}, "确认放弃"))
	var config := _store.combat_config()
	var hero := _card(_body, "刃锋  Lv.%d" % (_store.level + 1), "角色状态", Color("355569"))
	var metrics := _row(hero)
	_metric(metrics, "最大生命", "%d" % config.get("health", 220), CYAN)
	_metric(metrics, "攻击", "%d" % config.get("attack", 22), WHITE)
	_metric(metrics, "技能冷却", "%d%%" % roundi(float(config.get("cooldown_scale", 1.0)) * 100), VIOLET)
	_metric(metrics, "能量恢复", "%.1f / 秒" % config.get("energy_regen", 7), GOLD)
	var xp_row := _row(hero)
	var max_level := _store.level >= SaveStore.MAX_LEVEL
	_label(xp_row, "已达当前等级上限" if max_level else "经验 %d / %d" % [_store.xp, _store.xp_needed()], 16, DIM)
	var bar := ProgressBar.new()
	bar.max_value = maxi(1, _store.xp_needed())
	bar.value = bar.max_value if max_level else _store.xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(430, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_row.add_child(bar)
	var gear_row := _row(_body)
	for slot in Catalog.SLOTS:
		var item := _store.equipped_item(slot)
		var box := _card(gear_row, str(item.get("name", "未装备")), SLOT_NAMES[slot])
		_label(box, str(item.get("description", "可从背包装备一个%s。" % SLOT_NAMES[slot])), 16, DIM)
		var tier := int(_store.enhancements.get(slot, 0))
		var cost := _store.enhancement_cost(slot)
		var increase := "+2 攻击 / 级" if slot == "weapon" else ("+10 生命 / 级" if slot == "armor" else "+0.5 能量恢复 / 级")
		_label(box, "槽位强化 +%d / 3  ·  %s" % [tier, increase], 15, GOLD)
		_button(box, "已达强化上限" if tier >= 3 else "强化 · %d 金币" % cost, "enhance_" + slot, func(): _emit("enhance", {"slot": slot}), false, not can_edit or tier >= 3 or _store.coins < cost)
	var build_row := _row(_body)
	var passive := _card(build_row, "战斗被动", "出战前免费切换")
	var passive_row := _row(passive)
	for id in ["assault", "guard"]:
		var selected: bool = _store.passive == id
		_button(passive_row, ("✓ " if selected else "") + ("连击输出" if id == "assault" else "反击生存"), "passive_" + id, func(): _emit("passive", {"passive": id}), selected, not can_edit)
	_label(passive, Catalog.passive_description(_store.passive), 16, DIM)
	var skills := _card(build_row, "技能选择", "范围与伤害之间的取舍")
	var burst_row := _row(skills)
	_label(burst_row, "裂隙连斩", 17, VIOLET)
	for id in ["wide", "focused"]:
		var selected: bool = _store.variants.get("burst", "wide") == id
		_button(burst_row, ("✓ " if selected else "") + ("广域" if id == "wide" else "聚焦"), "burst_" + id, func(): _emit("variant", {"skill": "burst", "variant": id}), selected, not can_edit)
	_label(skills, "广域：范围120% / 伤害80%。聚焦：范围80% / 伤害120%。", 15, DIM)
	var ultimate_row := _row(skills)
	_label(ultimate_row, "断界", 17, GOLD)
	var unlocked: bool = config.get("skills", []).has("ultimate")
	for id in ["normal", "precision"]:
		var selected: bool = _store.variants.get("ultimate", "normal") == id
		_button(ultimate_row, ("✓ " if selected else "") + ("标准" if id == "normal" else "精准"), "ultimate_" + id, func(): _emit("variant", {"skill": "ultimate", "variant": id}), selected, not unlocked or not can_edit)
	_label(skills, "精准：范围70% / 伤害130%，需要更贴近目标。" if unlocked else "首通遗迹外围解锁断界。", 15, DIM)

func _metric(parent: Control, caption: String, value: String, color: Color) -> void:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 2)
	parent.add_child(block)
	_label(block, value, 25, color)
	_label(block, caption, 15, DIM)

func _stages() -> void:
	_label(_body, "每关独立结算 · 首通额外奖励仅一次 · 失败与退出只放弃本次未结算收益", 16, CYAN)
	var row := _row(_body)
	for id in Catalog.STAGE_IDS:
		var stage := Catalog.stage(id)
		var unlocked := _store.unlocked_stages.has(id)
		var cleared := _store.first_clears.has(id)
		var box := _card(row, stage.name, stage.subtitle, Color("365467") if unlocked else Color("27354b"))
		box.add_theme_constant_override("separation", 8)
		box.get_parent().add_theme_stylebox_override("panel", _style(Color("101c30"), Color("365467") if unlocked else Color("27354b"), 1, 12, 18, 14))
		_label(box, "目标  " + stage.objective, 16, WHITE)
		_label(box, "威胁  " + stage.threat, 15, VIOLET)
		_label(box, stage.hint, 15, DIM)
		var divider := HSeparator.new()
		divider.modulate = Color("31415b")
		box.add_child(divider)
		_label(box, "每次通关  %d 金币 / %d 经验" % [stage.coins, stage.xp], 16, GOLD)
		_label(box, "额外首通  %d 金币 / %d 经验" % [stage.first_coins, stage.first_xp], 15, DIM)
		_label(box, Catalog.item(stage.first_item).get("name", "") + ("  ·  已获得" if cleared else "  ·  首通必得"), 16, CYAN)
		var record: Dictionary = _store.records.get(id, {})
		var fastest := _format_time(float(record.get("best_time", 0))) if int(record.get("clears", 0)) > 0 else "—"
		_label(box, "已通关 %d 次  ·  最快 %s" % [record.get("clears", 0), fastest], 14, DIM)
		_label(box, "建议 Lv.%d · 非强制门槛" % stage.recommended_level, 14, DIM)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(spacer)
		var reason := "首通%s后解锁" % Catalog.stage("outskirts" if id == "corridor" else "corridor").name
		_button(box, "开始挑战" if unlocked else reason, "stage_" + id, func(): _emit("start_stage", {"stage": id}), unlocked, not unlocked or not _store.active_run.is_empty())
	var actions := _row(_body)
	_button(actions, "返回准备 · 调整配装", "prepare", func(): _open_page("prepare"))

func _inventory() -> void:
	var can_edit := _store.active_run.is_empty()
	if not can_edit:
		_note(_body, "远征检查点仍在。装备配置暂时锁定；返回准备后可继续远征，或确认放弃本次收益再配装。", GOLD)
	var filters := _row(_body)
	for id in ["all", "weapon", "armor", "charm", "new"]:
		_button(filters, {"all": "全部装备", "weapon": "武器", "armor": "防具", "charm": "饰品", "new": "新获得"}[id], "filter_" + id, func(): _select_filter(id), _filter == id)
	var layout := _row(_body)
	var list_panel := _card(layout, "装备 · %d 件" % _store.inventory.size(), "按获取顺序 · 最近获得在前")
	list_panel.get_parent().size_flags_stretch_ratio = 1.1
	var matching: Array[Dictionary] = []
	for instance in _store.inventory:
		var data := Catalog.item(str(instance.item_id))
		if _filter == "all" or (_filter == "new" and instance.get("new", false)) or data.get("slot", "") == _filter:
			matching.append(instance)
	matching.reverse()
	if matching.is_empty():
		_label(list_panel, "当前筛选没有装备。通关首通可获得新的构筑部件。", 18, DIM)
		_selected_uid = ""
	elif _selected_uid.is_empty() or not matching.any(func(item): return item.uid == _selected_uid):
		_selected_uid = matching[0].uid
	for instance in matching:
		var uid: String = instance.uid
		var item := Catalog.item(str(instance.item_id))
		var state := " · 装备中" if _store.equipped.values().has(uid) else ""
		if instance.get("locked", false):
			state += " · 锁定"
		if instance.get("new", false):
			state += " · 新"
		var text := "%s  /  %s%s" % [item.name, SLOT_NAMES.get(item.slot, item.slot), state]
		_button(list_panel, text, "item_" + uid, func(): _select_item(uid), uid == _selected_uid)
	var detail := _card(layout, "装备详情", "对比当前装备", Color("3b5269"))
	if _selected_uid.is_empty():
		_label(detail, "选择一件装备以查看属性与来源。", 18, DIM)
		return
	var instance := _store.item_instance(_selected_uid)
	var item := Catalog.item(str(instance.item_id))
	var slot: String = item.slot
	var current := _store.equipped_item(slot)
	_label(detail, item.name, 25, CYAN)
	_label(detail, "%s · %s" % [item.rarity, SLOT_NAMES[slot]], 16, VIOLET)
	_label(detail, item.description, 18, WHITE)
	_label(detail, "来源  " + item.source, 16, DIM)
	var compare := _card(detail, "", "当前 → 选中  /  基础装备属性")
	for property in ["attack", "health", "cooldown_scale", "energy_regen"]:
		var caption: String = {"attack": "攻击", "health": "生命", "cooldown_scale": "冷却倍率", "energy_regen": "能量 / 秒"}[property]
		var previous := float(current.get(property, 1 if property == "cooldown_scale" else 0))
		var selected := float(item.get(property, 1 if property == "cooldown_scale" else 0))
		var change := selected - previous
		var improved: bool = change > 0 and property != "cooldown_scale" or change < 0 and property == "cooldown_scale"
		_label(compare, "%s   %s → %s   (%s%s)" % [caption, _stat_value(property, previous), _stat_value(property, selected), "+" if change > 0 else "", _stat_value(property, change)], 16, CYAN if improved else DIM)
	var equipped: bool = _store.equipped.get(slot, "") == _selected_uid
	var uid := _selected_uid
	_button(detail, "卸下" if equipped else "装备到" + SLOT_NAMES[slot], "equip_selected", func(): _emit("unequip", {"slot": slot}) if equipped else _emit("equip", {"uid": uid}), true, not can_edit)
	_button(detail, "解除锁定" if instance.get("locked", false) else "锁定装备", "lock_selected", func(): _emit("lock", {"uid": uid}), false, not can_edit)
	var slot_count := 0
	for owned in _store.inventory:
		if Catalog.item(str(owned.item_id)).get("slot", "") == slot:
			slot_count += 1
	var protected := equipped or bool(instance.get("locked", false)) or slot_count <= 1
	_button(detail, "处置装备", "discard_selected", func(): _confirm("处置「%s」？" % item.name, "这件装备将永久从背包移除，不会返还金币。", "discard", {"uid": uid}, "确认处置"), false, protected or not can_edit)
	var protection_note := "处置需要再次确认。没有背包容量限制。"
	if equipped or bool(instance.get("locked", false)):
		protection_note = "先卸下并解除锁定，才能处置装备。"
	elif slot_count <= 1:
		protection_note = "这是本部位最后一件装备，保留它以确保还能配置角色。"
	_label(detail, protection_note, 15, DIM)

func _select_filter(id: String) -> void:
	_filter = id
	_focus_key = "filter_" + id
	_rebuild()
	_focus_page.call_deferred("filter_" + id)
	_settle_layout(_layout_revision, "filter_" + id)

func _select_item(uid: String) -> void:
	_selected_uid = uid
	_focus_key = "item_" + uid
	_rebuild()
	_focus_page.call_deferred("item_" + uid)
	_settle_layout(_layout_revision, "item_" + uid)

func _stat_value(property: String, value: float) -> String:
	return "%d%%" % roundi(value * 100) if property == "cooldown_scale" else ("%.1f" % value if property == "energy_regen" else "%d" % roundi(value))

func _settings() -> void:
	var row := _row(_body)
	var options := _card(row, "音量与反馈", "辅助与显示")
	var sliders := [["master_volume", "总音量"], ["sfx_volume", "音效音量"], ["shake", "震屏强度"], ["flash", "闪白强度"], ["particles", "粒子密度"]]
	for entry in sliders:
		_slider(options, entry[0], entry[1])
	for entry in [["muted", "静音"], ["damage_numbers", "显示伤害数字"], ["large_text", "较大字号"], ["fullscreen", "全屏显示"]]:
		_toggle(options, entry[0], entry[1])
	_label(options, "降低粒子仍保留危险范围、起手与命中反馈。", 15, DIM)
	var controls := _card(row, "按键设置", "方向键始终可用于移动")
	for action in Bindings.ACTIONS:
		var action_row := _row(controls)
		var caption := _label(action_row, Bindings.LABELS[action], 16, DIM)
		caption.size_flags_stretch_ratio = 1.7
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_button(action_row, Bindings.hint(_store.settings, action) + (" · 固定" if action == "pause" else ""), "binding_" + action, func(): _capture_binding(action), false, action == "pause", 110)
	_button(controls, "恢复默认按键", "reset_bindings", func(): _emit("reset_bindings"))

func _slider(parent: Control, key: String, caption: String) -> void:
	var row := _row(parent)
	var name_label := _label(row, caption, 16, DIM)
	name_label.custom_minimum_size.x = 96
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = float(_store.settings.get(key, 1.0))
	slider.custom_minimum_size = Vector2(150, 48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)
	action_controls["setting_" + key] = slider
	var amount := _label(row, "%d%%" % roundi(slider.value * 100), 16, CYAN)
	amount.custom_minimum_size.x = 58
	amount.size_flags_horizontal = Control.SIZE_SHRINK_END
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_entered.connect(func(): _focus_key = "setting_" + key)
	slider.value_changed.connect(func(value): amount.text = "%d%%" % roundi(value * 100); _emit("setting", {"key": key, "value": value}))

func _toggle(parent: Control, key: String, caption: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = caption
	toggle.button_pressed = _store.muted if key == "muted" else bool(_store.settings.get(key, false))
	toggle.custom_minimum_size.y = 48
	toggle.focus_mode = Control.FOCUS_ALL
	parent.add_child(toggle)
	action_controls["setting_" + key] = toggle
	toggle.focus_entered.connect(func(): _focus_key = "setting_" + key)
	toggle.toggled.connect(func(value): _emit("setting", {"key": key, "value": value}))

func _help() -> void:
	var row := _row(_body)
	var controls := _card(row, "刃锋的基础动作", "实际按键")
	_label(controls, "%s %s %s %s  移动（方向键也可用）" % [Bindings.hint(_store.settings, "move_up"), Bindings.hint(_store.settings, "move_left"), Bindings.hint(_store.settings, "move_down"), Bindings.hint(_store.settings, "move_right")], 18, CYAN)
	for action in ["attack", "jump", "dash", "burst", "ultimate", "pause"]:
		_label(controls, "%s   %s" % [Bindings.hint(_store.settings, action), Bindings.LABELS[action]], 18, WHITE)
	_label(controls, "瞬斩：22能量 / 基础冷却3.5秒\n裂隙连斩：48能量 / 基础冷却7秒\n断界：75能量 / 基础冷却15秒", 16, DIM)
	var tactics := _card(row, "先读危险，再抓破绽", "四种敌人与首领")
	for tip in ["追击守卫：短前摇后出招。拉开一点距离，等攻击落空再回击。", "预警射手：瞄准线出现后改变位置，利用发射间隔接近。", "重装守卫：正面减伤。绕到背后，慢重击结束后再进攻。", "冲锋守卫：蓄力时确定方向，侧移离开冲刺线，撞空后反击。", "裂隙守卫：观察地面形状；半血后调整招式组合，别在蓄力中贪刀。"]:
		_label(tactics, tip, 17, DIM)
	_note(_body, "通关后金币、经验与装备一次性到账；失败只失去未结算收益。安全练习不发奖，也不会消耗长期进度。", GOLD)
	if context.get("source_page", context.get("back_page", "")) != "pause" and not context.get("practice", false):
		_button(_body, "进入安全练习", "practice", func(): _emit("practice"), true, not _store.active_run.is_empty())

func _pause_page() -> void:
	var row := _row(_body)
	var state := _card(row, "安全暂停", "本关")
	var stage := Catalog.stage(str(context.get("stage_id", "outskirts")))
	_label(state, "安全练习" if context.get("practice", false) else str(stage.get("name", "遗迹外围")), 27, CYAN)
	_label(state, "计时、敌人、冷却与能量恢复都已暂停。恢复时请重新按下操作键。", 19, DIM)
	_label(state, "返回准备会放弃本次未结算收益与本关检查点；已入账的金币、经验和装备全部保留。", 18, GOLD)
	var actions := _card(row, "继续行动", "操作")
	_button(actions, "继续战斗", "resume", func(): _emit("resume"), true)
	_button(actions, "操作说明", "help", func(): _open_page("help"))
	_button(actions, "设置", "settings", func(): _open_page("settings"))
	if not context.get("practice", false):
		_button(actions, "从检查点重试", "retry_checkpoint", func(): _emit("retry_checkpoint"), false, not context.get("has_checkpoint", false))
		_button(actions, "重新开始本关", "restart_stage", func(): _confirm("重新开始本关？", "本次尚未结算的收益会放弃。本关从入口开始，已入账进度保留。", "restart_stage", {}, "确认重开"))
	_button(actions, "返回准备", "abandon", func(): _confirm("返回出战准备？", "放弃本次未结算收益与本关检查点。已入账的金币、经验、装备和关卡解锁保留。", "abandon", {}, "确认返回"))

func _result() -> void:
	var result: Dictionary = context.get("result", {})
	var stats: Dictionary = context.get("stats", {})
	var won: bool = result.get("won", false)
	var saved: bool = result.get("ok", true)
	var stage_id: String = result.get("stage", context.get("stage_id", "outskirts"))
	var stage := Catalog.stage(stage_id)
	var headline := "核心已关闭 · 第一章完成" if won and stage_id == "core" else ("远征成功" if won else "本次远征未完成")
	var main := _card(_body, headline, str(stage.get("name", "遗迹外围")), CYAN if won else VIOLET)
	var metrics := _row(main)
	_metric(metrics, "通关时间" if won else "本次用时", _format_time(float(result.get("time", stats.get("elapsed", stats.get("time", 0))))), CYAN)
	_metric(metrics, "击败敌人", str(result.get("kills", stats.get("kills", 0))), WHITE)
	_metric(metrics, "受到伤害", "%d" % roundi(float(result.get("damage_taken", stats.get("damage", stats.get("damage_taken", 0))))), VIOLET)
	if not saved:
		_label(main, "奖励尚未保存，重试后才到账" if won else "本次结果尚未保存，请重试后继续", 25, GOLD)
		_label(main, str(result.get("error", "存档写入失败。请检查可用存储空间后重试。")), 17, DIM)
	elif won:
		if saved:
			_label(main, "已确认到账  ·  %d 金币  /  %d 经验" % [result.get("coins", 0), result.get("xp", 0)], 25, GOLD)
			_label(main, "首次通关奖励已包含在内。" if result.get("first_clear", false) else "本次为重复通关，发放常规奖励。", 16, DIM)
			if int(result.get("bonus_coins", 0)) > 0:
				_label(main, "宝箱奖励  +%d 金币（已计入总额）" % result.bonus_coins, 17, CYAN)
			if int(result.get("level_after", _store.level)) > int(result.get("level_before", _store.level)):
				_label(main, "等级提升  Lv.%d → Lv.%d" % [int(result.level_before) + 1, int(result.level_after) + 1], 21, CYAN)
			for item_id in result.get("items", []):
				var item := Catalog.item(str(item_id))
				_label(main, "获得装备  「%s」  ·  %s" % [item.get("name", item_id), item.get("description", "")], 18, WHITE)
			for unlock in result.get("unlocks", []):
				_label(main, "新解锁  " + ("断界 · 可在准备页选择变体" if unlock == "ultimate" else str(Catalog.stage(str(unlock)).get("name", unlock))), 18, VIOLET)
	else:
		_label(main, str(result.get("reason", context.get("reason", "生命耗尽。观察敌人前摇与危险区域，在出招后再反击。"))), 20, GOLD)
		_label(main, "本次未发放奖励。已有等级、金币、装备与解锁均已保留。", 18, DIM)
	var actions := _row(_body)
	if not saved:
		_button(actions, "重试保存奖励" if won else "重试保存结果", "retry_settlement", func(): _emit("retry_settlement"), true)
		_button(actions, "再次挑战", "restart_stage", func(): _emit("restart_stage"), false, true)
		_button(actions, "整理装备", "inventory", func(): _open_page("inventory"), false, true)
		_button(actions, "返回准备", "prepare", func(): _open_page("prepare"), false, true)
		if won and stage_id != "core":
			_button(actions, "挑战下一关", "next_stage", func(): _emit("next_stage"), false, true)
	elif won:
		var next_index := Catalog.STAGE_IDS.find(stage_id) + 1
		if next_index > 0 and next_index < Catalog.STAGE_IDS.size():
			_button(actions, "挑战下一关", "next_stage", func(): _emit("next_stage"), true, not saved)
		_button(actions, "再次挑战", "restart_stage", func(): _emit("restart_stage"), false, not saved)
		_button(actions, "整理装备", "inventory", func(): _open_page("inventory"), false, not saved)
		_button(actions, "返回准备", "prepare", func(): _open_page("prepare"), false, not saved)
	else:
		_button(actions, "从检查点重试", "retry_checkpoint", func(): _emit("retry_checkpoint"), true, not context.get("has_checkpoint", false))
		_button(actions, "重新开始本关", "restart_stage", func(): _emit("restart_stage"))
		_button(actions, "返回准备", "abandon", func(): _emit("abandon"))

func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]

func _open_page(target: String) -> void:
	_emit("page", {"page": target, "source_page": page, "back_page": page})

func _back() -> void:
	if _modal != null:
		_close_modal()
		return
	if page == "pause":
		_emit("resume")
	elif page == "prepare":
		_emit("page", {"page": "menu"})
	elif page == "result":
		var result: Dictionary = context.get("result", {})
		if not result.get("ok", true):
			return
		_emit("page", {"page": "prepare"}) if result.get("won", false) else _emit("abandon")
	else:
		_emit("page", {"page": context.get("back_page", "prepare" if page in ["stages", "inventory"] else "menu")})

func _modal_shell(title: String, text: String) -> VBoxContainer:
	_close_modal()
	_focus_before_modal = _root.get_viewport().gui_get_focus_owner()
	_modal = Control.new()
	_modal.name = "Confirmation"
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_modal)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(shade)
	var centered := CenterContainer.new()
	centered.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(centered)
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size.x = 620
	centered.add_child(wrapper)
	var box := _card(wrapper, title, "请确认", GOLD)
	_label(box, text, 19, DIM)
	return box

func _confirm(title: String, text: String, action: String, payload: Dictionary, confirm_label: String) -> void:
	var box := _modal_shell(title, text)
	_confirmation_action = action
	_confirmation_payload = payload.duplicate(true)
	var row := _row(box)
	var cancel := _button(row, "取消", "modal_cancel", _close_modal, true)
	_button(row, confirm_label, "modal_confirm", _confirm_accept)
	cancel.grab_focus()
	_wire_focus()

func _confirm_accept() -> void:
	var pending := _confirmation_action
	var data := _confirmation_payload.duplicate(true)
	_close_modal()
	_emit(pending, data)

func _close_modal() -> void:
	if _modal != null:
		_root.remove_child(_modal)
		_modal.queue_free()
		_modal = null
	action_controls.erase("modal_cancel")
	action_controls.erase("modal_confirm")
	_capture_action = ""
	_capture_label = null
	_confirmation_action = ""
	_confirmation_payload.clear()
	if is_instance_valid(_focus_before_modal) and _focus_before_modal.is_inside_tree():
		_focus_before_modal.grab_focus()
	_focus_before_modal = null
	_wire_focus.call_deferred()

func _capture_binding(action: String) -> void:
	var box := _modal_shell("设置「%s」按键" % Bindings.LABELS[action], "按下一个新按键。Esc 取消；Tab、Enter 和方向键保留用于界面导航。")
	_capture_action = action
	_capture_label = _label(box, "等待按键…", 23, CYAN)
	var cancel := _button(box, "取消", "modal_cancel", _close_modal, true)
	cancel.grab_focus()
	_wire_focus()

func _input(event: InputEvent) -> void:
	if _root == null or not _root.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if not _capture_action.is_empty():
		if code == KEY_ESCAPE:
			_close_modal()
		else:
			var candidate: Dictionary = _store.settings.duplicate(true)
			var validation := Bindings.try_rebind(candidate, _capture_action, code)
			if validation.ok:
				var action := _capture_action
				_close_modal()
				_emit("binding", {"action": action, "code": code})
			else:
				_capture_label.text = validation.error
		get_viewport().set_input_as_handled()
		return
	if code == KEY_ESCAPE:
		_back()
		get_viewport().set_input_as_handled()
	elif code in [KEY_ENTER, KEY_KP_ENTER]:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button and not focused.disabled:
			focused.pressed.emit()
			get_viewport().set_input_as_handled()
	elif code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and not get_viewport().gui_get_focus_owner() is HSlider:
		_navigate(-1 if code in [KEY_UP, KEY_LEFT] else 1)
		get_viewport().set_input_as_handled()

func _focusable_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for key in action_controls:
		var control: Control = action_controls[key]
		if not is_instance_valid(control) or not control.is_inside_tree() or not control.is_visible_in_tree():
			continue
		if _modal != null and not _modal.is_ancestor_of(control):
			continue
		if control is BaseButton and control.disabled:
			continue
		controls.append(control)
	return controls

func _wire_focus() -> void:
	if _root == null or not is_inside_tree():
		return
	var controls := _focusable_controls()
	for index in range(controls.size()):
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = control.get_path_to(controls[(index - 1 + controls.size()) % controls.size()])

func _focus_page(desired_key: String = "") -> void:
	if _root == null or not _root.visible:
		return
	var controls := _focusable_controls()
	if controls.is_empty():
		return
	var desired: Control = action_controls.get(desired_key)
	if desired != null and controls.has(desired):
		desired.grab_focus()
	else:
		var preferred := {"menu": "continue" if _store.has_progress else "begin", "prepare": "stages" if _store.active_run.is_empty() else "continue", "stages": "stage_outskirts", "inventory": "filter_all", "settings": "setting_master_volume", "help": "back", "pause": "resume", "result": "retry_settlement" if not context.get("result", {}).get("ok", true) else "restart_stage"}
		var first: Control = action_controls.get(preferred.get(page, ""))
		(first if first != null and controls.has(first) else controls[0]).grab_focus()

func _settle_layout(revision: int, desired_key: String) -> void:
	# Containers sort over successive frames. A focus event on an unfinished
	# tree can otherwise leave the correct control above the visible clip.
	await get_tree().process_frame
	await get_tree().process_frame
	if revision != _layout_revision or not is_instance_valid(_scroll) or not _root.visible:
		return
	if desired_key.is_empty():
		_scroll.scroll_vertical = 0
		# Changing the range queues one final child sort. Wait for that before
		# comparing the focused control against the clip.
		await get_tree().process_frame
		if revision != _layout_revision or not _root.visible:
			return
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and _scroll.is_ancestor_of(focused):
		_scroll.ensure_control_visible(focused)

func _focused_action() -> String:
	if _root == null or not is_inside_tree():
		return ""
	var focused := get_viewport().gui_get_focus_owner()
	for key in action_controls:
		if action_controls[key] == focused:
			return key
	return ""

func _navigate(direction: int) -> void:
	var controls := _focusable_controls()
	if controls.is_empty():
		return
	var index := controls.find(get_viewport().gui_get_focus_owner())
	controls[(index + direction + controls.size()) % controls.size()].grab_focus()
