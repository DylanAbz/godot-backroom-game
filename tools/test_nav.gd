extends SceneTree

# Debug : parse le niveau 1 une fois, puis bake avec plusieurs jeux de
# paramètres pour trouver pourquoi le sol n'est pas couvert.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = load("res://assets/original_backrooms.glb").instantiate()
	root.add_child(model)

	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, model)
	print("source has data: ", src.has_data())
	var verts := src.get_vertices()
	print("source vertices: ", verts.size() / 3)
	var sminy := INF
	var smaxy := -INF
	for i in range(1, verts.size(), 3):
		sminy = minf(sminy, verts[i])
		smaxy = maxf(smaxy, verts[i])
	print("source y: ", sminy, " .. ", smaxy)

	var configs := [
		{"cell": 0.25, "radius": 0.5, "height": 1.6, "climb": 0.5, "slope": 45.0},
		{"cell": 0.25, "radius": 0.1, "height": 1.6, "climb": 0.5, "slope": 45.0},
		{"cell": 0.25, "radius": 0.5, "height": 0.5, "climb": 0.5, "slope": 45.0},
		{"cell": 0.25, "radius": 0.5, "height": 1.6, "climb": 1.0, "slope": 60.0},
		{"cell": 0.1, "radius": 0.5, "height": 1.6, "climb": 0.5, "slope": 45.0},
		{"cell": 0.5, "radius": 0.5, "height": 1.6, "climb": 0.5, "slope": 45.0},
	]
	for c in configs:
		nm.cell_size = c["cell"]
		nm.cell_height = c["cell"]
		nm.agent_radius = c["radius"]
		nm.agent_height = c["height"]
		nm.agent_max_climb = c["climb"]
		nm.agent_max_slope = c["slope"]
		nm.clear()
		NavigationServer3D.bake_from_source_geometry_data(nm, src)
		var v := nm.get_vertices()
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for p in v:
			lo = lo.min(p)
			hi = hi.max(p)
		print(c, " -> polys=", nm.get_polygon_count(), " verts=", v.size(),
				" min=", lo, " max=", hi)
	quit()
