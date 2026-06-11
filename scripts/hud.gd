class_name HUD
extends CanvasLayer

## Interface : barres de vie/stamina, viseur, vignette + grain (shader),
## flash de dégâts, écrans de mort et de victoire. Tout est construit en code.

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv);
	float breath = 0.03 * sin(TIME * 1.2);
	float vig = smoothstep(0.30, 0.78 + breath, d);
	float grain = fract(sin(dot(UV * (mod(TIME, 10.0) + 1.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 col = mix(vec3(0.0), vec3(0.45, 0.0, 0.0), damage);
	float alpha = clamp(vig * 0.9 + damage * 0.45 + 0.05, 0.0, 1.0);
	COLOR = vec4(col + grain * 0.07, alpha);
}
"""

var _vignette_mat: ShaderMaterial
var _damage := 0.0
var _health_fill: ColorRect
var _stamina_fill: ColorRect
var _level_label: Label
var _death_panel: Control
var _win_panel: Control

const BAR_W := 220.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Vignette plein écran.
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = shader
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.material = _vignette_mat
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	# Viseur.
	var crosshair := ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.35)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -1.5
	crosshair.offset_top = -1.5
	crosshair.offset_right = 1.5
	crosshair.offset_bottom = 1.5
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	# Barres de vie et stamina en bas à gauche.
	var bars := Control.new()
	bars.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bars.offset_left = 24
	bars.offset_top = -70
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bars)
	_health_fill = _make_bar(bars, 0, Color(0.7, 0.12, 0.1))
	_stamina_fill = _make_bar(bars, 22, Color(0.75, 0.65, 0.3))

	# Nom du niveau en haut.
	_level_label = Label.new()
	_level_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_level_label.offset_top = 28
	_level_label.add_theme_font_size_override("font_size", 26)
	_level_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_level_label)

	# Rappel des contrôles en bas à droite.
	var controls := Label.new()
	controls.text = "ZQSD se déplacer · Maj courir · Espace sauter · F lampe"
	controls.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	controls.offset_left = -520
	controls.offset_top = -40
	controls.add_theme_font_size_override("font_size", 14)
	controls.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(controls)

	_death_panel = _make_end_panel(root, "VOUS ÊTES MORT", Color(0.6, 0.05, 0.05))
	_win_panel = _make_end_panel(root, "VOUS VOUS ÊTES ÉCHAPPÉ", Color(0.7, 0.65, 0.4))


func _make_bar(parent: Control, y: float, color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.position = Vector2(0, y)
	bg.size = Vector2(BAR_W, 14)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2(2, 2)
	fill.size = Vector2(BAR_W - 4, 10)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	return fill


func _make_end_panel(parent: Control, title: String, color: Color) -> Control:
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.8)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var hint := Label.new()
	hint.text = "Appuyez sur R pour recommencer"
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	return panel


func _process(delta: float) -> void:
	_damage = maxf(_damage - delta * 1.4, 0.0)
	_vignette_mat.set_shader_parameter("damage", _damage)


func set_health(value: float) -> void:
	_health_fill.size.x = (BAR_W - 4) * clampf(value / 100.0, 0.0, 1.0)


func set_stamina(value: float) -> void:
	_stamina_fill.size.x = (BAR_W - 4) * clampf(value / 100.0, 0.0, 1.0)


func flash_damage() -> void:
	_damage = 1.0


func show_level_name(text: String) -> void:
	_level_label.text = text
	_level_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(3.5)
	tween.tween_property(_level_label, "modulate:a", 0.0, 2.0)


func show_death() -> void:
	_death_panel.visible = true


func show_win() -> void:
	_win_panel.visible = true
