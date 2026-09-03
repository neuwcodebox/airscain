# AGENTS.md

This file defines repository-wide operating guidance for AI coding agents: how to approach changes, follow project conventions, organize work, and validate results. `docs/SPEC.md` defines the game requirements, while `docs/TECH.md` defines the technical design. This file contains stable working rules that apply across tasks.

## Working Rules

- Treat `SPEC.md` and `TECH.md` as authoritative.
- Implement the smallest runnable change required by the current task.
- Write code in typed GDScript.
- Work primarily through repository files and the Godot CLI, invoked with the `godot` command available on `PATH`.
- Do not leave required setup as manual Godot editor work. Persistent configuration, scene structure, values, and connections must exist in the repository.
- Do not add dependencies or technologies outside the defined stack without a concrete need.

## Planning and Commits

- For non-trivial tasks, track high-level runnable units and validation evidence in `docs/PLAN.md`; keep it aligned with the current intended result rather than conversational history.
- Complete and validate one unit at a time, then commit its implementation, tests, and plan update together as a runnable checkpoint.
- Before declaring completion, confirm the plan matches the repository and excludes broken, unverified, or unrelated work.

Typical CLI usage:

```bash
godot --headless --audio-driver Dummy --editor --path . --quit  # once after a fresh clone
godot --headless --audio-driver Dummy --path .
godot --headless --audio-driver Dummy --path . --script res://path/to/script.gd --check-only
godot --path . --scene res://path/to/scene.tscn
```

## Project Structure

- Colocate related scenes, scripts, and resources by feature.
- Use the existing top-level structure: `main/`, `world/`, `camera/`, `defense/`, `enemy/`, `ui/`, `effects/`, `tests/`, and `tools/`.
- Put unit tests in `tests/unit/` and integration tests in `tests/integration/`.
- Create a new top-level directory only when the existing structure does not fit naturally.

## Validation

- During iteration, use the cheapest relevant validation for the change.
- Run broader validation only when the scope of the change warrants it.
- Do not run a full headless import routinely after scene or resource changes.
- After adding, moving, or replacing project files, run `godot --headless --audio-driver Dummy --editor --path . --quit` to generate Godot metadata.
- Verify visual changes in an actual game window.
- Do not consider a task complete with parse errors, unhandled runtime errors, disabled tests, or placeholders replacing required behavior.
