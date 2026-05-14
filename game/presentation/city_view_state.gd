# Presentation-only city hub submode (**NORMAL** vs **PLANNING**). No domain reads, no **`GameState`** apply bridge, no log.
# Phase **5.1.17i** — toggled from **City Hub** only; selection changes reset planning via **SelectionController**.
# See **[CITY_UX.md](../../docs/CITY_UX.md)**.
class_name CityViewState
extends RefCounted

enum Submode { NORMAL, PLANNING }

var _submode: int = Submode.NORMAL


func enter_planning() -> void:
	_submode = Submode.PLANNING


func exit_planning() -> void:
	_submode = Submode.NORMAL


func reset_to_normal() -> void:
	_submode = Submode.NORMAL


func is_planning() -> bool:
	return _submode == Submode.PLANNING
