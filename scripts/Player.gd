extends CharacterBody3D

# ---------- Node refs ----------
@onready var head: Node3D                    = $Head
@onready var head_x: Node3D                  = $Head/HeadXRotation
@onready var camera: Camera3D                = $Head/HeadXRotation/Camera3D
@onready var flashlight: Node3D              = $Flashlight
@onready var flashlight_light: SpotLight3D   = $Flashlight/FlashLightMesh/SpotLight3D
@onready var flashlight_sound: AudioStreamPlayer3D = $Flashlight/FlashLightMesh/FlashlightSound

@onready var body_model: Node3D              = $character_q2
@onready var anim_tree: AnimationTree        = body_model.get_node_or_null("AnimationTree")
@onready var anim_player: AnimationPlayer    = body_model.get_node_or_null("AnimationPlayer")

# ---------- Menu scene ----------
@export var menu_scene: PackedScene = preload("res://menu.tscn")
var menu: CanvasLayer = null
var _menu_open := false

# ---------- Config ----------
const MOUSE_SENS := 0.003
const SPEED := 3.0
const FLASHLIGHT_FOLLOW_SPEED := 15.0
const ANIM_SMOOTHING_SPEED := 8.0
const MAX_HEAD_PITCH := deg_to_rad(89.0)

# หน่วงตัวหันตามหัว ~0.2 วินาที
const BODY_DELAY := 0.2
const BODY_TURN_SPEED := 1.0 / BODY_DELAY   # ≈ 5.0

# AnimationTree (BlendSpace1D ชื่อ locomotion)
const AT_BLEND_PARAM := "parameters/locomotion/blend_position"
# AnimationPlayer fallback
const AP_IDLE := "idle"
const AP_WALK := "walk"

# โมเดลหันหลัง → ชดเชยด้วยการหมุน 180°
const MODEL_YAW_OFFSET := PI

# ---------- State ----------
var yaw := 0.0
var pitch := 0.0
var anim_blend := 0.0
var _mouse_dx := 0.0
var _mouse_dy := 0.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	head.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	head_x.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	body_model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON

	if anim_tree:
		anim_tree.active = true
		if anim_player and anim_tree.anim_player == NodePath():
			anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	if anim_player:
		anim_player.playback_default_blend_time = 0.1

	# ถ้ามีเมนูถูกวางไว้ในฉากอยู่แล้ว ให้หาแล้วซ่อนมันไว้ก่อน
	_ensure_menu_ref()
	if menu:
		menu.visible = false

	# ชดเชยทิศเริ่มต้นของโมเดล
	body_model.rotation.y += MODEL_YAW_OFFSET

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not _menu_open:
		_mouse_dx += event.relative.x
		_mouse_dy += event.relative.y
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F and not _menu_open:
		flashlight_light.visible = !flashlight_light.visible
		flashlight_sound.play()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_menu()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	# ---- อัปเดตหัว/คอในฟิสิกส์ (กันสั่น) ----
	
	if not _menu_open and (_mouse_dx != 0.0 or _mouse_dy != 0.0):
		yaw   -= _mouse_dx * MOUSE_SENS
		pitch -= _mouse_dy * MOUSE_SENS
		pitch = clamp(pitch, -MAX_HEAD_PITCH, MAX_HEAD_PITCH)
		_mouse_dx = 0.0
		_mouse_dy = 0.0
	head.rotation.y = yaw
	head_x.rotation.x = pitch

	if _menu_open:
		return  # หยุดเกมเพลย์เมื่อเปิดเมนู

	# ---- อินพุตเดิน (ตามหัว/เมาส์) ----
	var iv := Vector2.ZERO
	if Input.is_action_pressed("up"):    iv.y -= 1.0   # W = ไปทางหัว
	if Input.is_action_pressed("down"):  iv.y += 1.0
	if Input.is_action_pressed("left"):  iv.x -= 1.0
	if Input.is_action_pressed("right"): iv.x += 1.0
	iv = iv.normalized()

	var head_basis := Basis(Vector3.UP, head.rotation.y)
	var dir := (head_basis.x * iv.x) + (head_basis.z * iv.y)
	dir = dir.normalized()

	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y = 0.0
	move_and_slide()

	# ---- ลำตัวค่อย ๆ หันตามหัว (ดีเลย์ ~0.2s) ----
	var target_yaw := head.rotation.y + MODEL_YAW_OFFSET
	body_model.rotation.y = lerp_angle(body_model.rotation.y, target_yaw, delta * BODY_TURN_SPEED)

	# ---- อนิเมชัน ----
	var move_amount := dir.length()
	anim_blend = lerp(anim_blend, move_amount, delta * ANIM_SMOOTHING_SPEED)

	if anim_tree:
		anim_tree.set(AT_BLEND_PARAM, anim_blend)
	elif anim_player:
		var target := (AP_WALK if move_amount > 0.1 else AP_IDLE)
		if anim_player.current_animation != target:
			anim_player.play(target)
			
	for index in range(get_slide_collision_count()):
		# We get one of the collisions with the player
		var collision = get_slide_collision(index)

		# If the collision is with ground
		if collision.get_collider() == null:
			continue
			
	move_and_slide()

	# ---- ไฟฉายตามหัว ----
	_flashlight_follow(delta)

# ---------- Helpers ----------
func _flashlight_follow(delta: float) -> void:
	flashlight.rotation.y = lerp_angle(flashlight.rotation.y, head.rotation.y, delta * FLASHLIGHT_FOLLOW_SPEED)
	flashlight.rotation.x = lerp_angle(flashlight.rotation.x, head_x.rotation.x, delta * FLASHLIGHT_FOLLOW_SPEED)

func _toggle_menu() -> void:
	if _menu_open:
		_close_menu()
	else:
		_open_menu()

func _open_menu() -> void:
	_ensure_menu_ref()
	if menu == null and menu_scene:
		var root := get_tree().current_scene
		menu = menu_scene.instantiate() as CanvasLayer
		menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		root.add_child(menu)

	if menu:
		if menu.has_signal("resume_requested") and not menu.is_connected("resume_requested", Callable(self, "_close_menu")):
			menu.connect("resume_requested", Callable(self, "_close_menu"))
		if menu.has_signal("quit_requested") and not menu.is_connected("quit_requested", Callable(self, "_on_quit_game")):
			menu.connect("quit_requested", Callable(self, "_on_quit_game"))

		menu.visible = true
		_menu_open = true
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _close_menu() -> void:
	if menu:
		menu.visible = false
	_menu_open = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_quit_game() -> void:
	get_tree().quit()

func _ensure_menu_ref() -> void:
	if menu: return
	var root := get_tree().current_scene
	if root:
		var found := root.find_child("Menu", true, false)
		if found is CanvasLayer:
			menu = found
