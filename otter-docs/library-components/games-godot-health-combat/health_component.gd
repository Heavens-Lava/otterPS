class_name HealthComponent
extends Node

signal health_changed(current_health: int, max_health: int)
signal damaged(amount: int, remaining_health: int)
signal healed(amount: int, current_health: int)
signal defeated

@export var max_health: int = 100
@export var armor_reduction: int = 0
@export var invulnerability_seconds: float = 0.25

var current_health: int
var is_alive: bool = true
var _invulnerable_until_ms: int = 0


func _ready() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)


func apply_damage(raw_amount: int) -> int:
	if not is_alive or raw_amount <= 0:
		return 0

	var now_ms := Time.get_ticks_msec()
	if now_ms < _invulnerable_until_ms:
		return 0

	var mitigated := maxi(1, raw_amount - armor_reduction)
	current_health = maxi(0, current_health - mitigated)
	_invulnerable_until_ms = now_ms + int(invulnerability_seconds * 1000.0)

	damaged.emit(mitigated, current_health)
	health_changed.emit(current_health, max_health)

	if current_health == 0:
		is_alive = false
		defeated.emit()

	return mitigated


func heal(amount: int) -> int:
	if not is_alive or amount <= 0:
		return 0
	var before := current_health
	current_health = mini(max_health, current_health + amount)
	var restored := current_health - before
	if restored > 0:
		healed.emit(restored, current_health)
		health_changed.emit(current_health, max_health)
	return restored
