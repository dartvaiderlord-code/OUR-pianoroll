extends ScrollContainer

const DEAD_ZONE = 9.0
var touch_enabled = false
var keeps_touch: Callable
var touch_tap: Callable
var finger = -1
var drag_origin = Vector2.ZERO
var scroll_origin = 0.0
var dragging = false
var speed_y = 0.0
var scroll_position = 0.0

func _ready() -> void:
	if touch_enabled:
		# Raw touch events take precedence over the mouse events emulated for buttons.
		scroll_deadzone = 1000000
	set_process(false)
	set_process_input(touch_enabled)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION and touch_tap.is_valid():
		# The list resolves taps on touch release, after it knows whether the finger scrolled.
		if finger >= 0 or claims_touch(event.position):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if finger < 0 and claims_touch(event.position):
				finger = event.index
				drag_origin = event.position
				scroll_origin = get_v_scroll_bar().value
				speed_y = 0.0
				set_process(false)
		elif event.index == finger:
			finger = -1
			if dragging:
				dragging = false
				propagate_notification(NOTIFICATION_SCROLL_END)
				if event.canceled:
					speed_y = 0.0
				scroll_position = get_v_scroll_bar().value
				set_process(absf(speed_y) > 35.0)
				get_viewport().set_input_as_handled()
			elif touch_tap.is_valid() and not event.canceled and claims_touch(event.position) and event.position.distance_to(drag_origin) < DEAD_ZONE:
				get_viewport().set_input_as_handled()
				touch_tap.call(event.position)
	elif event is InputEventScreenDrag and event.index == finger:
		var travel = event.position - drag_origin
		if not dragging:
			if absf(travel.y) < DEAD_ZONE or absf(travel.y) < absf(travel.x) or extent() <= 0:
				return
			dragging = true
			propagate_notification(NOTIFICATION_SCROLL_BEGIN)
		scroll_vertical = roundi(clampf(scroll_origin - travel.y,0,extent()))
		speed_y = clampf(-event.velocity.y,-4200,4200)
		get_viewport().set_input_as_handled()

func claims_touch(point: Vector2) -> bool:
	return get_global_rect().has_point(point) and (not keeps_touch.is_valid() or not keeps_touch.call(point))

func extent() -> float:
	var bar = get_v_scroll_bar()
	return maxf(0,bar.max_value - bar.page)

func reset_touch() -> void:
	if dragging:
		propagate_notification(NOTIFICATION_SCROLL_END)
	finger = -1
	dragging = false
	speed_y = 0.0
	set_process(false)

func _process(delta: float) -> void:
	scroll_position = clampf(scroll_position + speed_y * delta,0,extent())
	scroll_vertical = roundi(scroll_position)
	speed_y *= exp(-7.0 * delta)
	if absf(speed_y) < 25.0 or scroll_position <= 0 or scroll_position >= extent():
		set_process(false)
