# DLSS 5 Swapper

Self-contained PowerShell installer for the **DLSS 5 Neural Rendering stack** into
games that do not ship a native DLSS implementation. Built as a Windows-only
reimplementation of the concepts in
[rakanki911/DLSS5-Swapper](https://github.com/rakanki911/DLSS5-Swapper).

![Electron UI](https://img.shields.io/badge/UI-Electron-47848F?logo=electron&logoColor=white)

## Features

- **Render API auto-detection** - PE import / delay-load / binary-string analysis
  for every `.exe` in a game folder - DirectX 8/9/10/11/12, Vulkan, OpenGL -
  no per-game database needed.
- **DLSS 5 transport** - the `DLSS5-Feeder` loadable addon plus the
  NVIDIA Neural Rendering runtimes (`nvngx_dlss.dll`, `nvngx_dlssnr.dll`).
  Games with native DLSS skip the feeder and plug straight into the native stream.
- **Neural providers** (selectable):
  - `chicken` (default) - **Deep Fried Chicken**, 1-30 sequential neural passes.
  - `renodx` - **RenoDX DLSS5 Generic**, a single NeuralUplift pass.
- **ReShade integration** - dxgi proxy for DirectX 11/12, global / per-user
  Vulkan layer, `DLSS5_Feed.fx` + `lumenite_Kernel.fx` motion-vector pipeline,
  `ReShade.ini` / `ReShadePreset.ini` wiring.
- **Journaled installs** - every original file is backed up to
  `_DLSS5_Backup\` with a manifest, and `-Uninstall` restores everything.
- **Auto game discovery** - scan installed launchers (Steam, GOG, Epic, EA,
  Origin, Ubisoft) or deep-scan any drive/folder; results are saved so a
  rescan catches newly installed games.
- **Main-executable filtering** - the scan flags the main game executable
  (DX12 preferred, then shallowest folder, then largest file) so the library
  shows one clean card per game instead of every launcher/stub/helper exe;
  alternate executables stay available via the launch picker on the install
  page.
- **Instant library** - the last scan is cached, so the UI opens directly on
  your library without re-scanning every folder at startup; hit *Rescan* to
  refresh. With no cached library and no folders yet, the UI auto-detects
  games from your installed launchers automatically.
- **Executable icons** - real icons are extracted from each game's `.exe` and
  shown on the cover-style library cards.
- **Startup auto-update** - the UI checks the GitHub remote on launch and
  fast-forwards + restarts itself when a newer version is available.

## Screenshots

![Game library - cover-style tiles with executable icons](screenshots/app-library.png)

![Install page - provider, passes, and executable picker](screenshots/app-install.png)

## Quick start

### 1. Prerequisites

- Windows 10+ (x64)
- PowerShell 5.1+
- Node.js 18+ (for the Electron UI)
- `kit/` folder with the binary kit (built by `-BuildKit`, see below)

### 2. Build the kit (first time only)

```powershell
.\DLSS5-Swapper.ps1 -BuildKit
```

This harvests the required DLLs and addons from your local vendor downloads
(harvest paths in `sources.json`, or the built-in defaults) and places them in
`kit/`. The kit already ships in the repo (Git LFS), so this is only needed
when rebuilding it from fresh downloads.

### 3. Launch the UI

```
DLSS5-UI\start.bat
```

or from the `DLSS5-UI` folder:

```
npm start
```

The Electron window opens (launched directly, so no console window stays open).
From there:

| Action | How |
|---|---|
| **Add games** | Click *Add game folder* (scans just that folder) or *Auto-scan* (launchers or deep scan a drive) |
| **Rescan** | *Rescan all* re-scans every saved folder (saved scan also loads instantly on startup) |
| **Install** | Select a game, optionally pick an alternate executable, choose a provider and options, click *Install* |
| **Verify** | Check what ended up in the folder vs. the manifest |
| **Restore** | Roll back any install from the manifest backup |

### 4. CLI (no UI)

Every command works directly from PowerShell:

```powershell
# scan
.\DLSS5-Swapper.ps1 -Scan -GamePath "C:\Games\SomeGame"

# install (auto-detect API, chicken by default)
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame"

# 3 passes, Lumenite Kernel motion vectors
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame" -Passes 3

# RenoDX with NeuralUplift
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame" -Provider renodx -NeuralUplift

# verify
.\DLSS5-Swapper.ps1 -Verify -GamePath "C:\Games\SomeGame"

# uninstall / restore
.\DLSS5-Swapper.ps1 -Uninstall -GamePath "C:\Games\SomeGame"

# auto-discover launchers
.\DLSS5-Swapper.ps1 -Discover -Json

# deep-scan C: (depth 6, capped at 600 folders)
.\DLSS5-Swapper.ps1 -Discover -Root "C:\" -Depth 6 -Json
```

Add `-DryRun` to any install to preview changes without touching the disk, and
`-Launch` to start the game after installing.

## Automation (`-Json`)

Every command accepts `-Json`: all human-readable output goes to stderr, and a
single compact JSON document is emitted on stdout - designed for the Electron
UI and for scripting:

```powershell
.\DLSS5-Swapper.ps1 -Scan    -GamePath "C:\Games\SomeGame" -Json
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame" -Provider renodx -Json
.\DLSS5-Swapper.ps1 -Discover -Json
```

### JSON shapes

| Command | Response fields |
|---|---|
| `-Scan` | `gameDir`, `chosen`, `candidates[]` (each with a `Main` flag), `hasNativeDlss`, `reshade{}` |
| `-Install` | `exe`, `api`, `provider`, `passes`, `feeder`, `added[]`, `dryRun`, `manifestPath` |
| `-Verify` | `exe`, `api`, `checks[]`, `provider`, `installed` |
| `-Uninstall` | `removed[]`, `restored[]` |
| `-Discover` | `launchers`, `root`, `folders[]`, `scans[]` (each scan is a `-Scan` shape) |

## Install options

| Option | Values | Default | Meaning |
|---|---|---|---|
| `-Provider` | `chicken` / `renodx` | `chicken` | Neural provider |
| `-Passes` | 1-30 | 1 | Chicken pass count |
| `-Api` | auto/d3d8/d3d9/d3d11/d3d12/vulkan/opengl | auto | Force the render API |
| `-Feeder` | auto/forced/off | auto | DLSS5-Feeder mode |
| `-WorkResolution` | 10-150 | 100 | Neural work resolution % |
| `-Style` | default/natural/cinematic | default | Chicken NR style |
| `-Preset` | 0+ | 0 | NR preset index |
| `-Intensity` | 1-4 | 1 | NR intensity |
| `-MVProvider` | 0-4 | 3 | Feed MV provider (3 = Lumenite Kernel) |
| `-CleanFry` | switch | off | Chicken multi-pass cleanup |
| `-TextureBoost` | switch | off | Experimental 8K path |
| `-NeuralUplift` | switch | off | RenoDX NeuralUplift |
| `-KitPath` | path | .\kit | Override the file kit location |
| `-Exe` | name.exe | auto | Pick a specific executable |
| `-DryRun` | switch | off | Do not write anything |
| `-Force` | switch | off | Proceed despite warnings |
| `-Launch` | switch | off | Start the game after install |

### Discovery options

| Option | Values | Default | Meaning |
|---|---|---|---|
| `-Discover` | switch | - | Auto-discover games |
| `-ScanRoot` | path | (launchers) | Root folder for deep scan |
| `-Depth` | 1-8 | 6 | Max sub-folder depth for deep scan |

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
   to the exe, the render API is reported as **Vulkan**.
4. **Fallbacks** - sibling-module imports and file-name heuristics.

Both D3D11 and D3D12 map to the `dxgi.dll` payload hook in ReShade.

## Provider comparison

| | Deep Fried Chicken | RenoDX DLSS5 Generic |
|---|---|---|
| Passes | 1-30 sequential | 1 |
| NeuralUplift | (highest pass) | Supported |
| Frame generation coexistence | Experimental | - |
| Feeder `warmup_rebuild` | `0` (required) | `180` |
| Coexists in folder | Conflicts ignored (Chicken wins) | same |

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

## Repository layout

```
DLSS5-Swapper.ps1    # backend - the whole tool (single file)
DLSS5-UI/            # Electron desktop app
  main.js            #   main process (IPC, swapper bridge, icon cache)
  preload.js         #   context bridge (ipcRenderer -> window.dlss5)
  icons-extract.ps1  #   batch .exe icon extraction -> www/icons (PNG)
  www/
    index.html       #   shell (titlebar + sidebar + pages)
    style.css        #   full dark theme
    app.js           #   renderer logic (library, install, verify, backups, console)
  package.json       #   electron dependency + start script
  start.bat          #   one-click launcher (no console window)
  library.json       #   saved game folders (gitignored)
  library-cache.json #   last scan, loads instantly at startup (gitignored)
kit/                 # harvested binary kit (built by -BuildKit, tracked via Git LFS)
```

## Credits

- [DLSS5-Feeder](https://github.com/zeroeightysix/DLSS5-Feeder) - the DLSS5
  transport addon
- [Deep Fried Chicken](https://www.nexusmods.com/site/mods/1692) - multi-pass
  neural provider
- [RenoDX](https://www.nexusmods.com/site/mods/943) - DLSS5 Generic addon
- [DLSS 5 Swapper](https://github.com/rakanki911/DLSS5-Swapper) - original app
  concept this script reimplements
