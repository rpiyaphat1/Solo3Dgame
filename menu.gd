extends CanvasLayer

signal resume_requested
signal quit_requested

@onready var resume_btn = $ResumeButton
@onready var quit_btn  = $QuitButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false

	resume_btn.connect("pressed", Callable(self, "_emit_resume"))
	quit_btn.connect("pressed", Callable(self, "_emit_quit"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_emit_resume()
		get_viewport().set_input_as_handled()

func _emit_resume() -> void:
	print("resume clicked")
	emit_signal("resume_requested")

func _emit_quit() -> void:
	get_tree().quit()
