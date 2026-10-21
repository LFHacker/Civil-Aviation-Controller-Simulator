## 往真实存档目录写几份演示存档，用于截图与手动验证 UI。
## 注意：这会写进 user://saves（真实的存档目录），不是临时目录。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/seed_demo_saves.gd
extends SceneTree


func _initialize() -> void:
	var store := SaveStore.new()
	print("存档目录: ", ProjectSettings.globalize_path(store.base_dir))

	var now := int(Time.get_unix_time_from_system())
	var px := [
		{"slot": "manual_1", "label": "演示存档 1 · 晚高峰", "seat": "tower", "airport": "DEMO",
			"sim": 23820.0, "play": 1420.0, "ago": 3600},
		{"slot": "manual_2", "label": "演示存档 2 · 地面放行", "seat": "delivery", "airport": "DEMO",
			"sim": 9450.0, "play": 640.0, "ago": 86400 * 2},
		{"slot": "auto_1", "label": "自动存档", "seat": "approach", "airport": "DEMO",
			"sim": 31200.0, "play": 2600.0, "ago": 900},
	]

	for d in px:
		var g := SaveGame.new()
		g.slot_id = str(d.slot)
		g.label = str(d.label)
		g.app_version = AtcVersion.text()
		g.created_unix = now - int(d.ago) - 3600
		g.updated_unix = now - int(d.ago)
		g.state.sim_time = float(d.sim)
		g.state.play_time = float(d.play)
		g.state.seat_id = str(d.seat)
		g.state.airport_id = str(d.airport)
		g.state.flights = [
			{"callsign": "CCA1501", "type": "B738", "phase": "final"},
			{"callsign": "CES2302", "type": "A320", "phase": "ground"},
		]
		var w := store.write(g)
		print("  ", d.slot, " -> ", "OK" if w.ok else w.error)

	# 顺便放一个损坏的存档，验证界面会把坏档标红而不是崩掉
	var bad := store.slot_path("manual_9")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	if f != null:
		f.store_string("{ 这不是合法 JSON ///")
		f.close()
		print("  manual_9 -> 已写入一份损坏存档（用于验证坏档展示）")

	quit(0)
