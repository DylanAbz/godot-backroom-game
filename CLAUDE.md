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

- **`scripts/game_manager.gd`** — orchestrates everything: WorldEnvironment (fog, dark ambient), level loading, player spawn, exit portal (at `level.exit_hint` if set, else random far navmesh point; locked/red on the maze level until the key is taken), flickering fluorescent lights, death/win screens, and the `--screenshot` verification flow.
- **`scripts/level.gd`** (`LevelRoot`) — base level: `_create_content()` loads a GLB and `_setup_collisions()` generates trimesh collisions (both overridable), then bakes the navmesh on a thread (`collisions_ready` → player can spawn; `nav_ready` → portal/lights placed). Level order: maze, `assets/original_backrooms.glb`, `assets/backrooms_another_level.glb`.
- **`scripts/maze_level.gd`** (`MazeLevel`, level 0) — procedural 31×31-cell (93×93 m) backrooms maze built from the Loafbrr modular pack meshes rendered via MultiMesh (a few draw calls total) with shared BoxShape3D colliders. Recursive backtracker + open rooms with pillars + braiding. Places gameplay props: yellow floor arrows along the BFS path to the exit, readable notes, wall scrawls, the key under a red light (locked exit), almond-water heals. Signals: `note_read`, `key_taken`, `water_drunk`.
- **`scripts/interactable.gd`** (`Interactable`) — Area3D on layer 8, aimed at via a player raycast and triggered with E (prompt shown in HUD).
- **`scripts/player.gd`** (`PlayerController`) — FPS controller. The full hazmat body (`escape_the_backrooms_hazmat.glb`) is attached to the body; the model has **no animations**, so everything is posed procedurally via `Skeleton3D.set_bone_pose_rotation`: head bone scaled to ~0 (camera), left arm hanging with bent elbow, right arm in weapon guard, fingers curled. The pipe is a BoneAttachment3D on the right hand; the attack tweens `_atk_pitch`/`_atk_bend` offsets so the whole arm swings. Bone poses compose in skeleton-global space over the rest pose (see `_pose_bone`); `tools/inspect_bones.gd` dumps the rig.
- **`scripts/monster.gd`** (`Monster`) — generic chaser: loads any GLB, normalizes it to a target height (source models range from 5 cm to 28 m), builds capsule + NavigationAgent3D at runtime, plays the first animation if one exists. Falls back to straight-line pursuit while the navmesh is still baking.
- **`scripts/monster_spawner.gd`** — spawns random monster types around the player (16–32 m, floor-snapped via raycast). The two hazmat models are excluded (player characters).
- **`scripts/hud.gd`**, **`scripts/ambient_audio.gd`** — code-built UI (vignette/grain shader, bars, end screens) and a procedurally generated drone (no audio files exist in the project).

### Conventions and gotchas

- **Input uses physical keycodes** (W/A/S/D positions) so ZQSD works on AZERTY. Actions: `move_*`, `jump`, `sprint`, `flashlight` (F), `restart` (R), `interact` (E), `attack` (left click — melee pipe; monsters have hp/take_hit/knockback).
- **Collision layers**: 1 = world, 2 = player, 4 = monsters, 8 = interactables. Monsters deliberately do NOT collide with the player (capsule depenetration would shove the player through walls); damage is distance-based.
- The Loafbrr pack .tscn/.tres files reference `res://Assets/...` paths that don't exist — they still load because Godot resolves the UIDs. Don't "fix" those paths.
- **glTF models face +Z**; the camera faces −Z. The player model is rotated `PI`; monsters face movement with `atan2(dir.x, dir.z)`.
- Imported GLB scenes have wildly different scales — always normalize via AABB (`Monster.combined_aabb`) rather than hardcoding sizes.
- Unused assets available: `assets/BackroomsLikeAssetRe_Godot/` (modular wall/floor/stair scenes + materials, useful for building the future maze), `backrooms_rigged_hazmat.glb` (alternative player model, has a Mixamo animation).

## Verification workflow

Visual changes should be checked with the `--screenshot` run (see Commands): it captures forward view, downward view (body/arms), a spawned monster, and level 2, then quits. Read the PNGs in `tools/screenshots/` to confirm.
