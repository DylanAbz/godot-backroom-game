# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Backroom** is a first-person horror game set in the Backrooms, built with **Godot 4.6.3** (Forward+ renderer). The player (hazmat suit, visible body/arms) explores maze-like levels while randomly spawned monsters chase them. Planned features: weapons, key items to unlock exits, giant randomized maze.

## Commands

Godot executable: `C:/Users/frabb/Downloads/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe` (the `_console` variant prints output to the terminal — always use it from scripts).

```powershell
# Run the game
& "$env:USERPROFILE\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe" --path .

# Re-import assets / re-register script classes after structural changes (headless)
& "...Godot_v4.6.3-stable_win64_console.exe" --headless --path . --import

# Automated visual verification: runs the game, saves screenshots to tools/screenshots/, quits
& "...Godot_v4.6.3-stable_win64_console.exe" --path . --resolution 1280x720 -- --screenshot

# Inspect a GLB's node tree / animations / AABB
& "...Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s tools/inspect_glb.gd
```

After adding/renaming scripts with `class_name`, run `--import` so cross-script class references resolve.

## Architecture

Everything is built in code from `scenes/main.tscn` (root: `GameManager`). Only `main.tscn` and `player.tscn` exist as scene files; levels, monsters, HUD, portal and lights are constructed at runtime.

- **`scripts/game_manager.gd`** — orchestrates everything: WorldEnvironment (fog, dark ambient), level loading, player spawn, exit portal placed at a random far navmesh point, flickering fluorescent lights, death/win screens, and the `--screenshot` verification flow.
- **`scripts/level.gd`** (`LevelRoot`) — loads a level GLB, generates trimesh collisions on every MeshInstance3D, then bakes the navmesh on a thread (`collisions_ready` → player can spawn; `nav_ready` → portal/lights placed). Levels: `assets/original_backrooms.glb` then `assets/backrooms_another_level.glb`.
- **`scripts/player.gd`** (`PlayerController`) — FPS controller. The full hazmat body (`escape_the_backrooms_hazmat.glb`) is attached to the body; the model has **no animations**, so arms are posed and swung procedurally via `Skeleton3D.set_bone_pose_rotation` and the head bone is scaled to ~0 to not block the camera.
- **`scripts/monster.gd`** (`Monster`) — generic chaser: loads any GLB, normalizes it to a target height (source models range from 5 cm to 28 m), builds capsule + NavigationAgent3D at runtime, plays the first animation if one exists. Falls back to straight-line pursuit while the navmesh is still baking.
- **`scripts/monster_spawner.gd`** — spawns random monster types around the player (16–32 m, floor-snapped via raycast). The two hazmat models are excluded (player characters).
- **`scripts/hud.gd`**, **`scripts/ambient_audio.gd`** — code-built UI (vignette/grain shader, bars, end screens) and a procedurally generated drone (no audio files exist in the project).

### Conventions and gotchas

- **Input uses physical keycodes** (W/A/S/D positions) so ZQSD works on AZERTY. Actions: `move_*`, `jump`, `sprint`, `flashlight` (F), `restart` (R).
- **Collision layers**: 1 = world, 2 = player, 4 = monsters. Monsters deliberately do NOT collide with the player (capsule depenetration would shove the player through walls); damage is distance-based.
- **glTF models face +Z**; the camera faces −Z. The player model is rotated `PI`; monsters face movement with `atan2(dir.x, dir.z)`.
- Imported GLB scenes have wildly different scales — always normalize via AABB (`Monster.combined_aabb`) rather than hardcoding sizes.
- Unused assets available: `assets/BackroomsLikeAssetRe_Godot/` (modular wall/floor/stair scenes + materials, useful for building the future maze), `backrooms_rigged_hazmat.glb` (alternative player model, has a Mixamo animation).

## Verification workflow

Visual changes should be checked with the `--screenshot` run (see Commands): it captures forward view, downward view (body/arms), a spawned monster, and level 2, then quits. Read the PNGs in `tools/screenshots/` to confirm.
