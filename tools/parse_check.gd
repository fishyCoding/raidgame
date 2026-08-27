extends SceneTree

## Loads every script in the project and reports the ones that will not compile.
##
## Worth its own tool because the obvious checks do not do this. `--check-only`
## compiles a file without the autoloads, so every script that touches Net fails
## with "Identifier not found" whether or not anything is wrong; `--import` only
## reports scripts something else pulls in. A parse error in a script that is
## only loaded when a gadget is used will sail past both and then show up as a
## body in the level behaving like a bare CharacterBody2D.


func _initialize() -> void:
	var bad: Array = []
	var seen := 0
	for path in _scripts("res://scripts"):
		seen += 1
		var script := ResourceLoader.load(path, "GDScript")
		if script == null or not (script as GDScript).can_instantiate():
			bad.append(path)
	print("-- checked %d scripts --" % seen)
	for path in bad:
		print("  BROKEN  %s" % path)
	print("\n%s" % ("PASS" if bad.is_empty() else "FAIL"))
	quit(0 if bad.is_empty() else 1)


func _scripts(dir: String) -> Array:
	var found: Array = []
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".gd"):
			found.append("%s/%s" % [dir, name])
	for sub in DirAccess.get_directories_at(dir):
		found += _scripts("%s/%s" % [dir, sub])
	return found
