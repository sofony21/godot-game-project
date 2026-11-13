@tool
extends Node2D

@export_range(1, 4, 1) var section_index := 1:
	set(value):
		section_index = clampi(value, 1, 4)
		_refresh_marker_names()
		update_configuration_warnings()
@export_enum("two_routes", "one_route") var route_type := "two_routes":
	set(value):
		route_type = value
		_refresh_marker_names()
		update_configuration_warnings()
@export_range(16, 64, 2) var length_tiles := 28:
	set(value):
		length_tiles = clampi(value, 16, 64)
		var end_marker := _find_marker("End")
		if end_marker != null:
			end_marker.position.x = float(length_tiles) * 64.0

func _ready() -> void:
	add_to_group("route_section")
	_refresh_marker_names()
	var end_marker := _find_marker("End")
	if end_marker != null:
		end_marker.position.x = float(length_tiles) * 64.0
	if Engine.is_editor_hint():
		update_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _find_marker("Start") == null or _find_marker("End") == null:
		warnings.append("Route section needs Start and End markers.")
	var sibling_sections: Array[Node] = []
	if get_parent() != null:
		for node in get_parent().get_children():
			if node.is_in_group("route_section"):
				sibling_sections.append(node)
	sibling_sections.sort_custom(func(a: Node, b: Node): return int(a.get("section_index")) < int(b.get("section_index")))
	if sibling_sections.size() != 4:
		warnings.append("Level route pattern needs exactly four sections: 2-route, 1-route, 2-route, 1-route.")
	for index in sibling_sections.size():
		var section := sibling_sections[index]
		var expected_index := index + 1
		var expected_type := "two_routes" if index % 2 == 0 else "one_route"
		if int(section.get("section_index")) != expected_index or str(section.get("route_type")) != expected_type:
			warnings.append("Sections must be numbered in the 2-route, 1-route, 2-route, 1-route order.")
			break
	return warnings

func _refresh_marker_names() -> void:
	if not is_inside_tree():
		return
	var route_label := "TwoRoutes" if route_type == "two_routes" else "OneRoute"
	var start_marker := _find_marker("Start")
	var end_marker := _find_marker("End")
	if start_marker != null:
		start_marker.name = "Section%d_%s_Start" % [section_index, route_label]
	if end_marker != null:
		end_marker.name = "Section%d_%s_End" % [section_index, route_label]

func _find_marker(marker_end: String) -> Marker2D:
	for child in get_children():
		if child is Marker2D and (child.name == marker_end or str(child.name).ends_with("_" + marker_end)):
			return child as Marker2D
	return null
