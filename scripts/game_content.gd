class_name GameContent
extends RefCounted

## Stable identifiers are shared by the save file, menus and encounter model.
const STAGE_IDS: Array[String] = ["outskirts", "corridor", "core"]
const SLOTS: Array[String] = ["weapon", "armor", "charm"]
const ITEM_IDS: Array[String] = ["training_blade", "field_coat", "pulse_charm", "cautious_blade", "shell_coat", "guard_charm", "twin_fang", "guard_shell", "chrono_charm"]
const STARTER_ITEMS: Array[String] = ["training_blade", "field_coat", "pulse_charm", "cautious_blade", "shell_coat", "guard_charm"]

static func stage(id: String) -> Dictionary:
	match id:
		"outskirts":
			return {"id": id, "name": "遗迹外围", "subtitle": "01 · 距离与破绽", "objective": "清除两组守卫，打开遗迹入口", "hint": "先观察近战前摇，再接近射手。瞬斩与跳跃可以躲开实际攻击。", "threat": "追击守卫 / 预警射手", "waves": [["drone", "drone"], ["drone", "ranged"]], "bounds": Rect2(65, 334, 1150, 145), "coins": 45, "xp": 45, "first_coins": 60, "first_xp": 60, "first_item": "twin_fang", "first_unlock": "corridor", "recommended_level": 1}
		"corridor":
			return {"id": id, "name": "机械回廊", "subtitle": "02 · 优先目标与走位", "objective": "突破三组混编守卫与周期危险", "hint": "绕到重装背后，冲锋预警后移出冲刺线。射手优先，留意地面警示。", "threat": "重装 / 射手 / 冲锋 / 地面危险", "waves": [["heavy", "drone"], ["ranged", "charger"], ["heavy", "ranged", "charger"]], "bounds": Rect2(180, 334, 920, 145), "coins": 70, "xp": 75, "first_coins": 85, "first_xp": 75, "first_item": "guard_shell", "first_unlock": "core", "recommended_level": 2}
		"core":
			return {"id": id, "name": "核心大厅", "subtitle": "03 · 裂隙守卫", "objective": "击败裂隙守卫，关闭核心", "hint": "Boss蓄力时先离开危险形状，招式结束再反击。半血后危险组合改变。", "threat": "短热身 / 两阶段Boss", "waves": [["charger", "ranged"], ["boss"]], "bounds": Rect2(110, 334, 1050, 145), "coins": 110, "xp": 105, "first_coins": 120, "first_xp": 100, "first_item": "chrono_charm", "first_unlock": "", "recommended_level": 3}
	return {}

static func item(id: String) -> Dictionary:
	var entry: Dictionary = {}
	match id:
		"training_blade":
			entry = {"name": "巡猎刃", "slot": "weapon", "description": "均衡武器，保留原有攻击与技能节奏。", "source": "初始装备", "rarity": "基础"}
		"field_coat":
			entry = {"name": "轻行外衣", "slot": "armor", "description": "轻便护具，生命与技能循环保持均衡。", "source": "初始装备", "rarity": "基础"}
		"pulse_charm":
			entry = {"name": "脉冲环", "slot": "charm", "description": "稳定资源循环，适合熟悉基础连段。", "source": "初始装备", "rarity": "基础"}
		"cautious_blade":
			entry = {"name": "护手刃", "slot": "weapon", "description": "攻击 +2，生命 +15；技能冷却延长 8%。适合等待破绽后反击。", "source": "初始构筑选择", "rarity": "基础", "attack": 2.0, "health": 15.0, "cooldown_scale": 1.08, "effect": "guard"}
		"shell_coat":
			entry = {"name": "厚壳护衣", "slot": "armor", "description": "生命 +40，攻击 -2；技能冷却延长 10%。提高容错，减少连续输出。", "source": "初始构筑选择", "rarity": "基础", "attack": -2.0, "health": 40.0, "cooldown_scale": 1.10, "effect": "guard"}
		"guard_charm":
			entry = {"name": "守势印", "slot": "charm", "description": "生命 +25；每秒能量恢复 -1。选择反击被动，利用成功躲避创造爆发窗口。", "source": "初始构筑选择", "rarity": "基础", "health": 25.0, "energy_regen": -1.0, "effect": "guard"}
		"twin_fang":
			entry = {"name": "双锋刃", "slot": "weapon", "description": "攻击 +8，生命 -20；技能冷却延长 6%。贴近敌人连击换取更高伤害。", "source": "遗迹外围首次通关", "rarity": "精制", "attack": 8.0, "health": -20.0, "cooldown_scale": 1.06, "effect": "assault"}
		"guard_shell":
			entry = {"name": "逆击甲", "slot": "armor", "description": "生命 +70，攻击 -2；技能冷却延长 8%。牺牲持续输出，增加躲避失误的容错。", "source": "机械回廊首次通关", "rarity": "精制", "health": 70.0, "attack": -2.0, "cooldown_scale": 1.08, "effect": "guard"}
		"chrono_charm":
			entry = {"name": "时序晶核", "slot": "charm", "description": "每秒能量恢复 +3，技能冷却缩短 15%；生命 -25。资源充裕，受击风险更高。", "source": "核心大厅首次通关", "rarity": "精制", "health": -25.0, "cooldown_scale": 0.85, "energy_regen": 3.0, "effect": "assault"}
	if entry.is_empty():
		return {}
	var result := {"id": id, "item_id": id, "attack": 0.0, "health": 0.0, "cooldown_scale": 1.0, "energy_regen": 0.0, "effect": ""}
	result.merge(entry, true)
	return result

static func slot_name(slot: String) -> String:
	return {"weapon": "武器", "armor": "防具", "charm": "饰品"}.get(slot, slot)

static func passive_description(id: String) -> String:
	if id == "guard":
		return "成功躲避一次实际攻击后，4秒内下一击伤害 +35%；触发有3秒间隔。受击无敌不触发。"
	return "2秒内连续3次普通攻击命中，返还6能量；返还能量有2秒间隔。需要保持近距离攻击。"
