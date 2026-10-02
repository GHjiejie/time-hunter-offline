extends SceneTree

const Interface := preload("res://scripts/campaign_ui.gd")
const Store := preload("res://scripts/save_store.gd")
const Bindings := preload("res://scripts/input_bindings.gd")
var checks := 0
var failures := 0
var events: Array[Dictionary] = []
var ui: CampaignUI
var store: SaveStore

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = code
	ui._input(event)

func show(next_page: String, context: Dictionary = {}) -> void:
	ui.show_page(next_page, store, context)
	await process_frame
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	store = Store.new()
	store.storage_path = "user://campaign-ui-test.json"
	ui = Interface.new()
	root.add_child(ui)
	ui.action_requested.connect(func(action, payload): events.append({"action": action, "payload": payload}))
	await show("menu")
	check(ui.action_controls.has("begin") and not ui.action_controls.has("continue"), "new save has start, no invalid continue")
	check(ui._body.global_position.y < 150, "short header keeps content near the top")
	check(root.gui_get_focus_owner() == ui.action_controls.begin, "initial page owns native keyboard focus")
	var tab_event := InputEventKey.new()
	tab_event.pressed = true
	tab_event.keycode = KEY_TAB
	tab_event.physical_keycode = KEY_TAB
	Input.parse_input_event(tab_event)
	await process_frame
	check(root.gui_get_focus_owner() == ui.action_controls.settings, "native Tab moves focus through menu")
	ui.action_controls.begin.grab_focus()
	key(KEY_ENTER)
	check(events[-1].action == "begin", "Enter activates focused start once")
	key(KEY_DOWN)
	check(root.gui_get_focus_owner() == ui.action_controls.settings, "arrows reach next native action")
	store.has_progress = true
	await show("menu")
	check(ui.action_controls.has("continue"), "existing save provides continue")
	var before := events.size()
	ui.action_controls.new_game.pressed.emit()
	check(events.size() == before and ui._modal != null, "new game requires confirmation")
	check(root.gui_get_focus_owner() == ui.action_controls.modal_cancel, "destructive confirmation defaults to cancel")
	key(KEY_ESCAPE)
	check(events.size() == before and ui._modal == null, "Esc cancels replacement without data action")
	ui.action_controls.new_game.pressed.emit()
	ui.action_controls.modal_confirm.pressed.emit()
	check(events[-1].action == "new_game", "confirmed replacement emits explicit action")
	store.has_progress = false
	store.load_status = "corrupt"
	await show("menu")
	before = events.size()
	ui.action_controls.begin.pressed.emit()
	check(ui._modal != null and events.size() == before, "unreadable save is protected by confirmation")
	key(KEY_ESCAPE)
	store.has_progress = true
	store.load_status = "loaded"
	await show("stages", {"back_page": "prepare"})
	check(not ui.action_controls.stage_outskirts.disabled, "first stage is playable")
	check(ui.action_controls.stage_corridor.disabled and ui.action_controls.stage_core.disabled, "locked stages are disabled")
	ui.action_controls.stage_outskirts.pressed.emit()
	check(events[-1].action == "start_stage" and events[-1].payload.stage == "outskirts", "stage action carries stable stage id")
	key(KEY_ESCAPE)
	check(events[-1].payload.page == "prepare", "stage Esc returns to preparation")
	await show("inventory")
	ui._select_item(str(store.equipped.weapon))
	await process_frame
	check(ui.action_controls.discard_selected.disabled, "equipped item cannot be discarded")
	var candidate := "starter_cautious_blade"
	ui._select_item(candidate)
	await process_frame
	check(not ui.action_controls.discard_selected.disabled, "spare equipment can be considered for discard")
	before = events.size()
	ui.action_controls.discard_selected.pressed.emit()
	check(ui._modal != null and events.size() == before, "discard requires explicit second action")
	key(KEY_ESCAPE)
	check(events.size() == before and store.item_instance(candidate).uid == candidate, "cancel keeps item and emits no mutation")
	for instance in store.inventory:
		if instance.uid == candidate:
			instance.locked = true
	await show("inventory")
	ui._select_item(candidate)
	await process_frame
	check(ui.action_controls.discard_selected.disabled, "locked equipment cannot be discarded")
	await show("settings", {"back_page": "pause"})
	await process_frame
	check(root.gui_get_focus_owner() == ui.action_controls.setting_master_volume, "settings start on volume, keeping top controls visible")
	check(ui._scroll.scroll_vertical == 0 and ui._scroll.get_global_rect().encloses(ui.action_controls.setting_master_volume.get_global_rect()), "fresh settings show volume inside the visible clip after layout: scroll=%d slider=%s clip=%s" % [ui._scroll.scroll_vertical, ui.action_controls.setting_master_volume.get_global_rect(), ui._scroll.get_global_rect()])
	ui.action_controls.binding_ultimate.grab_focus()
	await show("settings", {"back_page": "pause"})
	check(root.gui_get_focus_owner() == ui.action_controls.binding_ultimate and ui._scroll.get_global_rect().encloses(ui.action_controls.binding_ultimate.get_global_rect()), "settings rebuild keeps focused lower binding visible")
	key(KEY_ESCAPE)
	check(events[-1].payload.page == "pause", "settings opened while paused return to pause")
	await show("settings", {"back_page": "menu"})
	before = events.size()
	ui.action_controls.binding_attack.pressed.emit()
	key(KEY_K)
	check(ui._modal != null and events.size() == before and ui._capture_label.text.contains("已用于"), "rebind conflict remains open with readable error")
	key(KEY_F)
	check(ui._modal == null and events[-1].action == "binding" and events[-1].payload.code == KEY_F, "valid key emits a binding change")
	ui.action_controls.binding_dash.pressed.emit()
	before = events.size()
	key(KEY_ESCAPE)
	check(ui._modal == null and events.size() == before, "binding Esc cancels without changing settings")
	var settings := store.settings.duplicate(true)
	check(Bindings.try_rebind(settings, "attack", KEY_F).ok, "valid rebind is accepted")
	check(Bindings.hint(settings, "attack") == "F", "help hints use current binding")
	check(not Bindings.try_rebind(settings, "burst", KEY_F).ok, "duplicate binding is rejected")
	check(not Bindings.try_rebind(settings, "attack", KEY_ESCAPE).ok and not Bindings.try_rebind(settings, "pause", KEY_F).ok, "reserved cancel key is protected")
	Bindings.restore_defaults(settings)
	check(Bindings.hint(settings, "attack") == "J", "restore defaults resets actual map")
	await show("pause", {"has_checkpoint": false})
	check(ui.action_controls.retry_checkpoint.disabled, "missing checkpoint action is disabled")
	before = events.size()
	ui.action_controls.abandon.pressed.emit()
	check(ui._modal != null and events.size() == before, "pause abandon confirms unbanked loss")
	key(KEY_ESCAPE)
	await show("result", {"result": {"won": true, "ok": false, "stage": "outskirts", "error": "写入失败"}})
	check(ui.action_controls.has("retry_settlement") and ui.action_controls.next_stage.disabled and ui.action_controls.inventory.disabled, "pending payout can only retry saving")
	before = events.size()
	key(KEY_ESCAPE)
	check(events.size() == before, "pending payout cannot be skipped through Esc")
	ui.action_controls.retry_settlement.pressed.emit()
	check(events[-1].action == "retry_settlement", "pending payout retries explicit transaction")
	await show("result", {"result": {"won": false, "ok": false, "stage": "outskirts"}})
	before = events.size()
	key(KEY_ESCAPE)
	check(ui.action_controls.has("retry_settlement") and ui.action_controls.back.disabled and events.size() == before, "failed run also waits for durable settlement")
	await show("result", {"result": {"won": true, "ok": true, "stage": "core", "coins": 110, "xp": 105}, "stats": {"time": 63, "kills": 3, "damage": 22}})
	check(not ui.action_controls.has("next_stage"), "final chapter does not promise nonexistent unlock")
	await show("prepare")
	check(ui.action_controls.stages.global_position.y > ui._body.global_position.y and not ui._body.is_ancestor_of(ui.action_controls.stages), "expedition action stays available outside scrolling content")
	check(ui.action_controls.ultimate_precision.disabled, "locked ultimate variant is disabled")
	store.active_run = {"stage": "outskirts"}
	await show("prepare")
	check(ui.action_controls.has("continue") and ui.action_controls.passive_guard.disabled and ui.action_controls.burst_focused.disabled, "unfinished run offers resume and prevents loadout changes")
	store.active_run = {}
	await show("prepare")
	ui.action_controls.passive_guard.grab_focus()
	await show("prepare", {"message": "已保存"})
	check(root.gui_get_focus_owner() == ui.action_controls.passive_guard, "rebuilding preserves meaningful keyboard focus")
	ui.queue_free()
	await process_frame
	print("UI CHECKS: %d / FAILED: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
