class_name InputBindings
extends RefCounted

const DEFAULTS := {
	"move_left": KEY_A, "move_right": KEY_D, "move_up": KEY_W, "move_down": KEY_S,
	"attack": KEY_J, "jump": KEY_SPACE, "dash": KEY_K, "burst": KEY_L,
	"ultimate": KEY_U, "pause": KEY_ESCAPE,
}
const LABELS := {
	"move_left": "向左移动", "move_right": "向右移动", "move_up": "向上移动", "move_down": "向下移动",
	"attack": "普通攻击（可按住）", "jump": "跳跃", "dash": "瞬斩 / 躲避", "burst": "裂隙连斩",
	"ultimate": "断界", "pause": "暂停 / 返回",
}
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "attack", "jump", "dash", "burst", "ultimate", "pause"]
const ARROWS := {"move_left": KEY_LEFT, "move_right": KEY_RIGHT, "move_up": KEY_UP, "move_down": KEY_DOWN}

static func key_for(settings: Dictionary, action: String) -> int:
	if action == "pause":
		return KEY_ESCAPE
	var bindings: Dictionary = settings.get("bindings", {})
	return int(bindings.get(action, DEFAULTS.get(action, 0)))

static func hint(settings: Dictionary, action: String) -> String:
	var code := key_for(settings, action)
	if code == KEY_SPACE:
		return "空格"
	if code == KEY_ESCAPE:
		return "Esc"
	return OS.get_keycode_string(code)

static func pressed(settings: Dictionary, action: String) -> bool:
	return Input.is_physical_key_pressed(key_for(settings, action)) or (ARROWS.has(action) and Input.is_physical_key_pressed(int(ARROWS[action])))

static func matches(settings: Dictionary, action: String, event: InputEventKey) -> bool:
	var code := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	return code == key_for(settings, action) or (ARROWS.has(action) and code == int(ARROWS[action]))

static func try_rebind(settings: Dictionary, action: String, code: int) -> Dictionary:
	if not DEFAULTS.has(action) or action == "pause":
		return {"ok": false, "error": "暂停键固定为 Esc。"}
	if code == 0 or code in [KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER]:
		return {"ok": false, "error": "Esc、Tab 和 Enter 保留用于界面导航。"}
	if code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		return {"ok": false, "error": "方向键保留为移动与界面导航备用键。"}
	for other in ACTIONS:
		if other != action and key_for(settings, other) == code:
			return {"ok": false, "error": "%s 已用于「%s」。" % [OS.get_keycode_string(code), LABELS[other]]}
	var bindings: Dictionary = settings.get("bindings", {}).duplicate(true)
	bindings[action] = code
	settings["bindings"] = bindings
	return {"ok": true, "error": ""}

static func restore_defaults(settings: Dictionary) -> void:
	settings["bindings"] = DEFAULTS.duplicate()
