# DLSS 5 Swapper

Self-contained PowerShell installer for the **DLSS 5 Neural Rendering stack** into
games that do not ship a native DLSS implementation. Built as a Windows-only
reimplementation of the concepts in
[rakanki911/DLSS5-Swapper](https://github.com/rakanki911/DLSS5-Swapper).

## What it does

- **Detects the render API** of a game executable (DirectX 8/9/10/11/12,
  Vulkan, OpenGL) from its PE imports, delayed imports, binary strings and
  sibling wrapper modules (DXVK / vkd3d) - no per-game database needed.
- **Installs the DLSS 5 transport** - the `DLSS5-Feeder` loadable addon plus the
  NVIDIA Neural Rendering runtimes (`nvngx_dlss.dll`, `nvngx_dlssnr.dll`).
  Games that already have native DLSS (e.g. GTA V Enhanced) skip the feeder and
  plug straight into the native stream.
- **Installs one of two neural providers** (selectable):
  - `chicken` (default) - **Deep Fried Chicken**, 1 to 30 sequential neural
    passes.
  - `renodx` - **RenoDX DLSS5 Generic**, a single pass.
- **Configures ReShade**: the dxgi proxy for DirectX 11/12, a global (or
  per-user) Vulkan layer, the `DLSS5_Feed.fx` + `lumenite_Kernel.fx` motion
  vector pipeline, the `ReShade.ini` / `ReShadePreset.ini` wiring.
- **Journaled installs**: every original file is backed up to
  `_DLSS5_Backup\` with a manifest, and `-Uninstall` restores everything.

## GUI wizard

Double-click **`DLSS5-Wizard.exe`** for a Windows GUI (compiled from
`DLSS5-Wizard.cs`, rebuild with `.\Build-UI.ps1`). It drives the same script in
the background:

1. **Pick a game folder** and press *Scan folder* - it lists every executable
   found with its detected render API, bitness, native-DLSS and ReShade state,
   and remembers the best candidate.
2. **Configure** - provider (Deep Fried Chicken / RenoDX), passes, work
   resolution, style, preset, intensity, MV provider, feeder mode, force-API
   override, Clean Fry / Texture Boost / NeuralUplift, dry-run / force / launch.
3. **Install / Verify / Uninstall** - a live log streams the backend progress,
   and JSON is parsed back into the UI after each operation.

The wizard calls the script without any switches-driven UI, so the two are
always in sync.

## Automation

Every command also accepts `-Json`: everything humans would read goes to
stderr, and a single compact JSON document is emitted on stdout - designed for
the wizard and for scripting:

```powershell
.\DLSS5-Swapper.ps1 -Scan -GamePath "C:\Games\SomeGame" -Json
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame" -Passes 3 -Json    # use stderr for progress
```

## Usage

```powershell
# 0) (first time) harvest the file kit from the known sources
.\DLSS5-Swapper.ps1 -BuildKit

# 1) inspect a game folder without changing anything
.\DLSS5-Swapper.ps1 -Scan -GamePath "C:\Games\SomeGame"

# 2) install - API is auto-detected, provider defaults to chicken
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame"

#    Deep Fried Chicken, three passes, motion vectors from Lumenite Kernel:
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame" -Passes 3

#    RenoDX single-pass with NeuralUplift:
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame" -Provider renodx -NeuralUplift

# 3) check what ended up in the folder, run in rife mode:
.\DLSS5-Swapper.ps1 -Verify -GamePath "C:\Games\SomeGame"

# 4) roll back
.\DLSS5-Swapper.ps1 -Uninstall -GamePath "C:\Games\SomeGame"
```

Add `-DryRun` to any install to preview changes without touching the disk, and
`-Launch` to start the game right after installing.

## Install options

| Option | Values | Default | Meaning |
|---|---|---|---|
| `-Provider` | `chicken` / `renodx` | `chicken` | Neural provider |
| `-Passes` | 1 - 30 | 1 | Chicken pass count (`layers`) |
| `-Api` | `auto`/d3d8/d3d9/d3d10/d3d11/d3d12/vulkan/opengl | `auto` | Force the render API |
| `-Feeder` | `auto`/`forced`/`off` | `auto` | Use DLSS5-Feeder, force it, or skip it |
| `-WorkResolution` | 10 - 150 | 100 | Neural work resolution % |
| `-Style` | `default`/`natural`/`cinematic` | `default` | Chicken NR style |
| `-Preset` | 0+ | 0 | NR preset index |
| `-Intensity` | 1 - 4 | 2 | NR intensity |
| `-MVProvider` | 0 - 4 | 3 | DLSS5_Feed MV provider (3 = Lumenite Kernel) |
| `-CleanFry` | switch | off | Chicken multi-pass cleanup |
| `-TextureBoost` | switch | off | Chicken experimental 8K path |
| `-NeuralUplift` | switch | off | RenoDX NeuralUplift |
| `-KitPath` | path | `.\kit` | Override the file kit location |
| `-Exe` | `name.exe` | auto | Pick a specific executable |
| `-DryRun` | switch | off | Do not write anything |
| `-Force` | switch | off | Proceed despite warnings |
| `-Launch` | switch | off | Start the game after install |
| `-Verify` | | | Report installed state |
| `-Uninstall` | | | Remove and restore |
| `-Scan` | | | List games + detected APIs |
| `-ListKit` | | | List the kit contents |
| `-BuildKit` | | | Rebuild the kit from sources.json |

## How API detection works

The scan walks the game folder (up to three levels deep) and for each
`.exe` reads the PE headers directly:

1. **Imports** - the standard import directory (index 1) and the delay-load
   directory (index 13) are parsed; the first "important" DLL wins:
   `d3d12.dll` -> D3D12, `d3d11.dll` -> D3D11, `d3d10*.dll` -> D3D10,
   `dxgi.dll` -> DXGI, `vulkan-1.dll` -> Vulkan, `d3d9.dll` -> D3D9,
   `d3d8.dll` -> D3D8, `opengl32.dll` -> OpenGL.
2. **Strings** - if the imports are obfuscated (packers), binary markers such as
   `D3D12CreateDevice`, `D3D11CreateDevice`, `vkCreateInstance`, etc. are
   searched in the raw file bytes.
3. **Wrappers** - if the game links D3D but ships a DXVK/vkd3d wrapper DLL next
   to the exe, the render API is reported as **Vulkan** (the wrapper translates
   it, so Vulkan injection is what actually layers).
4. **Fallbacks** - sibling-module imports and file-name heuristics.

Both D3D11 and D3D12 map to the `dxgi.dll` payload hook in ReShade.

## Provider comparison

| | Deep Fried Chicken | RenoDX DLSS5 Generic |
|---|---|---|
| Passes | 1 - 30 sequential | 1 |
| NeuralUplift | (highest) | Supported |
| Frame generation coexistence | Experimental | - |
| Feeder `warmup_rebuild` | `0` (required) | `180` |
| Coexists in folder | Conflicts ignored if both present (Chicken wins) | same |

Chicken's multi-pass is the real "DLSS 5" selling point: every layer runs its
own full neural pass, so quality scales with `-Passes`.

## Notes & limitations

- **64-bit only** - the addons and the neural runtime are x86-64.
- **DirectX 8/9** need dgVoodoo2 (D3D9 -> D3D11 translation) before the stack
  can hook them; the script warns but copies with `-Force`.
- **OpenGL** needs a ReShade `opengl32.dll` proxy that is not bundled.
- **Vulkan** picks the machine-wide ReShade layer
  (`C:\ProgramData\ReShade\`); if absent it falls back to a per-user implicit
  layer under `%USERPROFILE%\.dlss5vulkanlayer`.
- Games with **anti-cheat** (BattlEye etc.) may reject injected modules; use
  the offline/Story modes where available.
- Feeder + broken APO caveat: some titles crash at startup when resuming from
  suspension; run at 100% work resolution, or disable HAGS instead of blaming
  the stack.

## Repository layout

- `DLSS5-Swapper.ps1` - the whole tool (single file)
- `kit/` - harvested binary kit (not committed; reproduced by `-BuildKit`)
- `sources.json` - override paths for the kit sources
- `README.md` - this file

## Credits

- [DLSS5-Feeder](https://github.com/zeroeightysix/DLSS5-Feeder) - the DLSS5
  transport addon
- [Deep Fried Chicken](https://www.nexusmods.com/site/mods/1692) - multi-pass
  neural provider
- [RenoDX](https://www.nexusmods.com/site/mods/943) - DLSS5 Generic addon
- [DLSS 5 Swapper](https://github.com/rakanki911/DLSS5-Swapper) - original app
  concept this script reimplements