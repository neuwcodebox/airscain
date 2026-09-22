# Airscain

[한국어](README.md)

> A 3D real-time strategy game about building an air-defense network under incomplete information and protecting an island city from relentless combined air attacks.

![Missile contrails and crossing gunfire above an outer battery, with the coastal city behind it](docs/images/demo.png)

In Airscain, you do not control individual weapons directly. Instead, you connect sensors, command-and-control assets, interceptors, and support facilities into a single air-defense network. Radars observe real threats and build tracks, while suitable defenses respond automatically according to shared information and rules of engagement.

Every operation generates new terrain, coastlines, and urban areas. The enemy does more than increase its numbers: it combines reconnaissance, deception, saturation attacks, suppression of enemy air defenses, and facility strikes while adapting to your deployments and previous engagements. There is no final victory state. Your objective is to expand and sustain the defense network for as long as the city remains operational.

## Core Gameplay

- Procedurally generated island terrain and dense low-poly cities
- An incomplete-information model that separates physical objects from player-observed tracks
- Automatic engagements driven by detection, tracking, classification, IFF, and the command-and-control network
- Layered defenses built from long-, medium-, and short-range missiles, guns, lasers, HPM systems, and interceptor drones
- Long-term operations shaped by ammunition, power, heat, damage, resupply, and repair
- Combined attack packages using reconnaissance, electronic warfare, deception, SEAD, cruise missiles, and ballistic threats
- Tactical decision-making through overlays, track relationships, and an altitude profile
- A sustained attack flow that adapts to battlefield conditions and defensive performance
- Korean and English interfaces with system-language detection and immediate switching in Settings

## Operation Flow

```text
Assess the battlefield and deploy assets
→ Detect contacts and establish tracks
→ Share information through the command-and-control network
→ Conduct layered interceptions under the rules of engagement
→ Repair damage, resupply, and relocate assets
→ Expand the defense network and prepare for the next attack
```

Budget is used to purchase new air-defense assets or restore city function. Repeating one powerful system is not enough: you must connect equipment with different detection ceilings, engagement ranges, target profiles, ammunition limits, and power requirements so each layer covers the others' weaknesses.

## Game Modes

| Mode | Description |
|---|---|
| Sustained Operation | Manage your budget and defense network while surviving increasingly complex air attacks. Supports saving and loading. |
| Training | Learn deployment, detection, automatic engagement, automatic resupply, repair, and city restoration through a 13-step guided exercise. |
| Sandbox | Freely deploy assets and threats to test defensive combinations and engagement outcomes. |

## Running the Game

This repository currently targets running the game from source. It requires [Godot 4.7.2](https://godotengine.org/) with the `godot` command available on your `PATH`.

After a fresh clone or pull that adds or moves project files, generate the Godot metadata first:

```bash
godot --headless --audio-driver Dummy --editor --path . --quit
```

Then launch the game:

```bash
godot --path .
```

## Controls

| Input | Action |
|---|---|
| `W` `A` `S` `D` | Move the camera relative to the screen direction |
| Mouse wheel | Zoom in and out |
| Middle-mouse drag | Orbit the camera horizontally and vertically, up to a 90-degree top-down view |
| `Q` `E` | Rotate the camera |
| `Backspace` | Reset camera position, zoom, and angle |
| Left mouse button | Select an asset or track, or confirm placement |
| Right mouse button / `Esc` | Cancel the current placement |
| Right mouse button | Clear the selection when not placing an asset |
| `Esc` | Open the operation menu |

Pause and the 1×, 2×, and 4× simulation speeds are available in the upper-right corner. Sustained Operation saves are available from the operation menu, while saves can be loaded from both the main menu and the operation menu.

## Development and Validation

The project uses Godot 4.7.2 and typed GDScript. Native and web builds share the same Compatibility renderer configuration. The GUT test framework is included in the repository.

```bash
godot --headless --audio-driver Dummy --path . \
  -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit
```

## Documentation

- [Game requirements](docs/SPEC.md)
- [Technical design](docs/TECH.md)
- [Implementation plan and validation log](docs/PLAN.md)
- [Agent instructions](AGENTS.md)
