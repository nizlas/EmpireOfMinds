# Native GDExtension (`eom_native`)

Native C++ GDExtension for Empire of Minds. Registers `EomTerrainNative`:

- float64/`PackedFloat64Array` boundary probes (N3b.1a);
- `solve_cg_plain_global` (N3b.1b) — an exact port of the rank-3/plain-PCG
  hot path of `Ts08HeightSolver` (one GDScript/C++ crossing per solve, all
  PCG iterations native, bit-identical results, ~86× faster on the
  reference map).

`game/domain/world/ts08_height_solver.gd` (GDScript) remains the verified
reference implementation and the default backend; the native path is
explicit opt-in (`Ts08HeightSolver.BACKEND_NATIVE`) and fails loudly when
this extension is not built. Component census/routing and the analytic /
deflated gauge routes always run in GDScript.

## Toolchain

- CMake ≥ 3.22 with the Ninja generator (verified: CMake 4.3.1, Ninja 1.13.2)
- MSVC x64 (Visual Studio with the C++ workload; located via `vswhere`)
- Python 3 on PATH (godot-cpp binding generation)
- Godot 4.6.2-stable Windows x86_64 editor binary (headless-capable)

## Dependency pinning

`godot-cpp` is fetched by CMake (`FetchContent`) from the immutable commit of
tag **`godot-4.5-stable`** (`e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`) with a
SHA-256–verified tarball. godot-cpp has no 4.6 release (v10/master is beta and
versioned independently); per upstream, extensions targeting Godot 4.5 load in
4.6.x, so the descriptor sets `compatibility_minimum = "4.5"`. The binding is
built with `GODOTCPP_TARGET=editor` (the only current consumer is the dev
editor/headless binary) and `GODOTCPP_PRECISION=single` (matching the engine
build; `PackedFloat64Array` elements stay float64 regardless).

## Build and test

From the repo root in plain PowerShell (no VS developer shell needed):

```powershell
# Configure + build (Release; first build compiles godot-cpp, ~2 min)
.\scripts\build-native.ps1

# Headless smoke test (load, registration, exact float64 probe results)
& "C:\Users\nicla\tools\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe" `
    --headless --path game -s res://domain/tests/test_native_extension_smoke.gd

# N3b.1b native solver tests (require the built extension; fail loudly otherwise):
#   focused synthetic kernel + route-proof tests
#     -s res://domain/tests/test_native_cg_kernel.gd
#   full reference-map parity, determinism, and benchmark (includes one
#   ~56 s GDScript reference solve)
#     -s res://domain/tests/test_ts08_height_solver_n3b_native.gd
```

`.\scripts\build-native.ps1 windows-ninja-debug` selects the Debug preset.
Benchmark numbers in the docs come from the Release preset.

## Outputs (all gitignored)

- `native/build/<preset>/` — CMake/Ninja build tree
- `game/bin/eom_native.gdextension` — descriptor, generated at configure time
- `game/bin/eom_terrain_native.windows.editor.x86_64.dll` — deployed post-build

Nothing under `game/bin/` is committed, so a checkout without a local build
has no descriptor and Godot loads nothing; the smoke test then fails with a
message pointing at `scripts/build-native.ps1`.
