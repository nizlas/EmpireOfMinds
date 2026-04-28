# Immutable turn order snapshot: player ids, whose turn it is, and turn counter for UI/rules.
# See docs/TURNS.md
class_name TurnState
extends RefCounted

const _TURN_STATE_SCRIPT = preload("res://domain/turn_state.gd")

var players: Array
var current_index: int
var turn_number: int

func _init(p_players: Array, p_current_index: int = 0, p_turn_number: int = 1) -> void:
	assert(p_players.size() > 0, "TurnState requires at least one player id")
	assert(
		p_current_index >= 0 and p_current_index < p_players.size(),
		"current_index must index into players"
	)
	assert(p_turn_number >= 1, "turn_number must be >= 1")
	var pi = 0
	while pi < p_players.size():
		assert(typeof(p_players[pi]) == TYPE_INT, "player ids must be int")
		pi = pi + 1
	players = p_players.duplicate()
	current_index = p_current_index
	turn_number = p_turn_number

func current_player_id() -> int:
	return players[current_index]

func advance():
	var n = players.size()
	var next_i = (current_index + 1) % n
	var next_n = turn_number
	if next_i == 0:
		next_n = turn_number + 1
	return _TURN_STATE_SCRIPT.new(players.duplicate(), next_i, next_n)

func equals(other) -> bool:
	if other == null:
		return false
	if not (other is TurnState):
		return false
	if turn_number != other.turn_number:
		return false
	if current_index != other.current_index:
		return false
	if players.size() != other.players.size():
		return false
	var i = 0
	while i < players.size():
		if players[i] != other.players[i]:
			return false
		i = i + 1
	return true
