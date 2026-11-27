extends Control
func _ready() -> void:
	custom_minimum_size=Vector2(26,26)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var center:=Vector2(13,13)
	draw_circle(center,11,Color(0.45,0.25,0.04))
	draw_circle(center-Vector2(0,1),9,Color(0.92,0.65,0.16))
	draw_arc(center-Vector2(0,1),7,0,TAU,24,Color(1,0.85,0.4),1.2)
	draw_line(Vector2(13,6),Vector2(13,18),Color(0.5,0.28,0.04),2)
	draw_line(Vector2(9,10),Vector2(17,10),Color(0.5,0.28,0.04),2)
