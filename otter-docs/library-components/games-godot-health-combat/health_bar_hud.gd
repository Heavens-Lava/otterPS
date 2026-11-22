class_name HealthBarHUD
extends ProgressBar

@export var health_component: HealthComponent
@export var label_node: Label


func _ready() -> void:
	if health_component == null:
		return
	health_component.health_changed.connect(_on_health_changed)
	_on_health_changed(health_component.current_health, health_component.max_health)


func _on_health_changed(current: int, maximum: int) -> void:
	max_value = maximum
	value = current
	if label_node != null:
		label_node.text = "%d / %d HP" % [current, maximum]
