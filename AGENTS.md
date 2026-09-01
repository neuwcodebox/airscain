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

- For any non-trivial task, maintain `docs/PLAN.md` as a concise checklist of high-level, runnable work units.
- Keep the plan aligned with the current intended result. Record completed outcomes and their validation evidence; do not use it as a transcript of abandoned approaches or conversational revisions.
- Complete and validate one high-level unit at a time. Keep the project runnable between units.
- When a unit is complete, update `docs/PLAN.md` and commit the implementation, tests, and plan entry together.
- Make each commit a coherent, verified checkpoint with a descriptive message. Do not commit broken intermediate states, unrelated user changes, or work that has not actually satisfied its checklist item.
- Before declaring the task complete, ensure the plan reflects the current repository state and that all required items are checked off with appropriate evidence.

Typical CLI usage:

```bash
godot --headless --path .
godot --headless --path . --script res://path/to/script.gd --check-only
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
- Verify visual changes in an actual game window.
- Do not consider a task complete with parse errors, unhandled runtime errors, disabled tests, or placeholders replacing required behavior.
