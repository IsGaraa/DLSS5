# DLSS 5 Swapper

Self-contained PowerShell installer for the **DLSS 5 Neural Rendering stack** into
games that do not ship a native DLSS implementation. Comes with an optional
Electron desktop UI. Built as a Windows-only reimplementation of the concepts in
[rakanki911/DLSS5-Swapper](https://github.com/rakanki911/DLSS5-Swapper).

![Windows](https://img.shields.io/badge/Platform-Windows%2010%2B-0078D6?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Electron UI](https://img.shields.io/badge/UI-Electron-47848F?logo=electron&logoColor=white)
![DLSS5](https://img.shields.io/badge/Stack-DLSS5%20Neural%20Rendering-9CE564)
![License](https://img.shields.io/badge/License-MIT-blue)

> **⚠️ WARNING - DO NOT USE IN MULTIPLAYER / ONLINE GAMES**
>
> This tool injects DLLs and shader layers into the game process. In any
> multiplayer, online, ranked, or anti-cheat-protected game (BattlEye, EAC,
> Vanguard, Ricochet, and the like) this is considered cheating and **can get
> your account banned** - sometimes permanently, hardware bans included. Use it
> **only** in offline / single-player titles and modes. You are responsible for
> what you inject into.

---

## Table of contents

1. Quick start
2. Requirements
3. Rendering API detection (how it works)
4. RenoDX hook mode - `EnableHooks` and Streamline
5. Providers
6. Install options & the CLI
7. The Electron UI
8. Automation & JSON output
9. Troubleshooting
10. Notes & limitations
11. Repository layout

---

## 1. Quick start

```powershell
git clone https://github.com/IsGaraa/DLSS5.git
cd DLSS5
git lfs pull        # the binary kit ships via Git LFS
```

> Updating: `git pull` (or launch the UI - it checks for updates and restarts
> itself when a newer version exists).

Launch the UI from the repo root (double-click):

```
DLSS5-UI\start.bat
```

or run it from the `DLSS5-UI` folder:

```
npm start
```

Everything the UI does also works straight from PowerShell:

```powershell
# scan a game folder
.\DLSS5-Swapper.ps1 -Scan -GamePath "C:\Games\SomeGame"

# install (API auto-detected, Deep Fried Chicken by default)
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame"

# 3 neural passes
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame" -Passes 3

# RenoDX with NeuralUplift
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame" -Provider renodx -NeuralUplift

# MFG Unlock addon (RTX 40, ReShade addon)
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame" -MFGAddon

# check the install / hook state
.\DLSS5-Swapper.ps1 -Verify -GamePath "C:\Games\SomeGame"

# repair: rewrite RenoDX EnableHooks from ReShade.log evidence
.\DLSS5-Swapper.ps1 -FixHooks -GamePath "C:\Games\SomeGame"

# uninstall / restore the originals
.\DLSS5-Swapper.ps1 -Uninstall -GamePath "C:\Games\SomeGame"

# auto-discover games from installed launchers
.\DLSS5-Swapper.ps1 -Discover -Json

# deep-scan C: (depth 6, capped at 600 game folders)
.\DLSS5-Swapper.ps1 -Discover -Root "C:\" -Depth 6 -Json
```

Add `-DryRun` to any install to preview changes without touching the disk, and
`-Launch` to start the game right after installing.

## 2. Requirements

Full requirements (hardware, NVIDIA driver versions, permissions, kit rebuild
sources) live in [Requirements.md](Requirements.md). The short version:

| Requirement | Why | Verdict |
|---|---|---|
| Windows 10+ x64 | 64-bit hooks and neural runtimes | required |
| PowerShell 5.1+ | the backend is a single `.ps1` | required |
| NVIDIA RTX 30/40/50 + recent driver | DLSS 5 Neural Rendering needs Tensor Cores; see Requirements.md | required |
| Node.js 18+ | the Electron UI | only for the UI |
| Git + Git LFS | cloning and updating the repo, pulling `kit/` | required |
| The `kit/` folder | binary DLLs and addons (already in the repo) | ships with clone |

---

## 3. Rendering API detection (how it works)

The scan walks the game folder (up to three levels deep) and reads PE headers
directly - **no per-game database**:

1. **PE / COFF parsing.** For every `.exe`, the standard import directory
   (index 1) and the delay-load directory (index 13) are parsed from the import
   tables; the first "important" module wins:
   `d3d12.dll` -> **D3D12**, `d3d11.dll` -> **D3D11**, `d3d10*.dll` -> D3D10,
   `dxgi.dll` -> DXGI, `vulkan-1.dll` -> **Vulkan**, `d3d9.dll` -> D3D9,
   `d3d8.dll` -> D3D8, `opengl32.dll` -> OpenGL.
2. **Binary strings.** If the imports are obfuscated (packers), markers such as
   `D3D12CreateDevice`, `D3D11CreateDevice`, `vkCreateInstance` are searched in
   the raw file bytes.
3. **Wrappers.** If the game links D3D but ships a **DXVK / vkd3d** wrapper DLL
   next to the exe, the render API is reported as **Vulkan** (dynamic detection
   via the wrapper modules, not just a static list).
4. **Fallbacks.** Sibling-module imports and file-name heuristics.

Both D3D11 and D3D12 map to the `dxgi.dll` payload hook in ReShade.

### Engine-level fallback (launcher stubs)

Some games are launched through a stub (a launcher, a shim, or a
multi-component launcher) whose exe has **no graphics imports at all**. The
scan then inspects the largest sibling DLLs' import tables next to the exe
(`Get-ApiFromSiblings`) - a launcher next to `Disrupt_64.dll` (Watch Dogs 2)
detects as DirectX 11 because the sibling carries `d3d11.dll` imports. Engine
markers are checked before this (`Get-ApiFromEngine`), so a Unity game whose
launcher stub is empty still resolves via `UnityPlayer.dll`.

The fallback chain per game is: `Get-DetectedApi` (exe imports/strings) →
engine DLL markers → largest sibling DLLs → *undetected*.

### Hybrid D3D + Vulkan titles

Some games ship both renderers (e.g. RDR2 with `kSettingAPI_Vulkan`). When a
D3D-detected exe also embeds `vkCreateInstance` and a ReShade Vulkan layer is
registered, the installer routes through the Vulkan layer instead of a local
`dxgi.dll` proxy - a local proxy would load a second ReShade instance into the
process and the two fight each other. The game's `ReShade.ini` gets an
`[INSTALL] BasePath` pointing at the game folder so the layer resolves the
right config, addons and shaders.

### The D3D9 rule (32-bit only)

Some titles (GTA IV, Saints Row 2) carry `d3d10`/`dxgi` imports **next to**
`d3d9.dll`. D3D9 is a 32-bit-only API, so D3D9 wins **only for 32-bit exes**.
A **64-bit** exe with a `Direct3DCreate9` string (RDR2) is always treated as
D3D10/12.

### Verified games

| Game | Detected | Notes |
|---|---|---|
| BeamNG.drive | D3D12 (imports) | vania; RTX user |
| RPCS3 | Vulkan (imports) | emulator exe |
| Red Dead Redemption 2 | Vulkan (dynamic | hybrid D3D+Vulkan, flips via layer |
| Red Dead Redemption (2025 PC) | D3D12 (imports) | Streamline host, direct-NGX |
| Watch Dogs 2 | D3D11 (via sibling) | launcher has no imports; `Disrupt_64.dll` |
| God of War Ragnarok | D3D12 (imports) | Streamline host, direct-NGX |
| GTA V Enhanced | D3D12 (imports) | Streamline host, direct-NGX |
| Spider-Man: Miles Morales | D3D12 (imports) | Streamline **routed** - needs hook fix |
| Calm Down Stalin | *(undetected)* | GDI-only: ADVAPI32/KERNEL32/SHELL32/SHLWAPI/USER32, correctly no GPU API |

---

## 4. RenoDX hook mode - `EnableHooks` and Streamline

The RenoDX DLSS5 addon ships a **hook mode** knob - `[RenoDX.DLSS5] EnableHooks`
in `ReShade.ini` - that decides how the addon patches the DLSS runtime:

| Value | Meaning | Notes |
|---|---|---|
| `0` | Hooks off | DLSS runs stock; NR disabled |
| `1` | **Streamline** - patches `sl.interposer.dll` / `sl.common.dll` | For games that route DLSS through Streamline (multi-GPU / sl.interposer titles) |
| `2` | **NGX-only** - patches the NGX modules directly | Default / safe. Correct for direct-NGX games; also the crash fallback ("if the game crashes at boot, set EnableHooks=2") |

A Streamline host that runs `EnableHooks=2` goes two **very different** ways,
and the tool tells them apart from `ReShade.log[1]` evidence:

- **Direct-NGX titles** (God of War Ragnarok, GTA V Enhanced, RDR1 PC port)
  call the DLSS runtime straight through NGX even though they also ship
  `sl.interposer.dll`. Their logs show `NGX feature create intercepted` under
  mode 2, and DLSS NR works with **no fix**. The addon's own log lines:
  `D3D12 NGX hooks installed ...`, `NGX feature create intercepted:
  feature=1 (DLSS/DLAA)`, `first NGX evaluate intercepted`.
- **Streamline-routed titles** (Spider-Man: Miles Morales) go through
  `slEvaluateFeature`. NGX-only never reaches the feature - **no** `feature
  create intercepted` line appears, the addon reports
  `Streamline: DLSS/DLSSD evaluations 0`, and the overlay shows
  *"NO NR FEATURE MATCHED"*. These need `EnableHooks=1`.

### 4.1 How the mode is auto-detected

`Get-RenoHookState` (backend) / `detectHookMode` (UI, startup) reads the most
recent `ReShade.log[1]` (including the `host64\` copy for 32-bit games) and
answers four questions:

1. **Is the game a Streamline host?** - `sl.interposer.dll` exists next to the
   exe.
2. **Did the last run patch Streamline?** - log contains
   `installing Streamline hooks into sl.*` / `Streamline hooks installed in
   sl.*` (`sl.interposer.dll` for the standard build, `sl.common.dll` for the
   Multi-GPU variant).
3. **Did the NGX layer engage?** - log contains `D3D12 NGX hooks installed` or
   `NGX module scan`.
4. **Was the game's DLSS reached directly?** - log contains
   `NGX feature create intercepted` or `first NGX evaluate intercepted`.

Feature interception only counts as direct-NGX evidence when the log has **no**
Streamline-patch lines at all - a prior `EnableHooks=1` run leaves the intercept
line in the log, so after a reinstall back to mode 2 it must not be misread as
"direct-NGX works". The *patched* state is decided by deploy authority first
(manifest `hookMode` / `ReShade.ini EnableHooks`), with log evidence as the
fallback. So the recommendation is:

```
fixApplied  = manifest.hookMode == 1 || ini EnableHooks == 1
directNgx   = logHas('NGX feature create intercepted') && !logHas(Streamline patch)
recommend   = streamlineHost && !fixApplied && ngxSeen && !directNgx
```

### 4.2 One-click fix + memory

- The library card for an install that needs it shows an amber chip
  **"RenoDX fix needed"** and a **RenoDX Fix** button.
- `-FixHooks -GamePath <folder>` (or the button) rewrites
  `[RenoDX.DLSS5] EnableHooks` in the deployed `ReShade.ini` (and the
  `host64\` variant when present) **without reinstalling**, then records the
  chosen mode as `hookMode` in `_DLSS5_Backup\manifest.json`. Later installs
  of the same game reuse the remembered mode; installing a game (or a fresh
  install) never recommits to Streamline automatically - the safe NGX-only
  default stands unless evidence says otherwise. With `-FixHooks` and no
  explicit `-RenoHooks`, the current effective mode is preserved unless a
  Streamline recommendation exists.
- **Once applied the UI says so.** The recommendation is computed from the
  *deployed* config, so after pressing **RenoDX Fix** (or `-FixHooks`) the card
  switches to a green **"RenoDX fix applied"** chip and the Fix button
  disappears immediately - no game relaunch required. The card treats an
  `EnableHooks=1` present in `ReShade.ini` or a `hookMode="1"` in the manifest
  as fix-applied, and only offers the fix again if neither is set. Note the
  manifest + ini are the source of truth here: if a game was reinstalled back
  to mode 2 after briefly running mode 1, the stale "Streamline hooks
  installed" lines in the old log do **not** mask the recommendation - the fix
  is offered again, as the game genuinely needs it.
- A green **"DLSS NR active"** chip replaces the recommendation on Streamline
  hosts that log feature interception under `EnableHooks=2` (and show no
  Streamline-patch lines) - GOW Ragnarok, GTA V Enhanced and the RDR1 PC port
  are confirmed to work this way, and the app now correctly leaves them alone
  instead of recommending a pointless fix.
- `-Verify` includes a `RenoDX fix` check item that *fails* with a `-FixHooks`
  hint when Streamline is recommended, plus an `NR upscaling` check that flags
  the `cs_5_1` proxy compile failure (see §9) and a `recommendation` /
  `hookMode` / `streamlineHost` / `featureMatched` / `nrProxyCompileFail`
  response fields for automation.

**How to use it:** play the game once with the default install, then hit
*Verify* (or let the card tell you). Three outcomes, all automatic:

- **Streamline-routed** game (no feature intercepted on NGX-only) → amber
  *RenoDX fix needed* + **RenoDX Fix** button.
- **Direct-NGX** game (feature intercepted on NGX-only) → green
  *DLSS NR active*, nothing to do.
- **Already fixed** (`EnableHooks=1` in ini or manifest) → green
  *RenoDX fix applied*, no button.

Conversely, if a Streamline-mode game freezes at boot, reinstall (or
`-FixHooks -RenoHooks ngx`) - the addon's own guidance, verbatim: *"if the game
crashes at boot, set EnableHooks=2 (NGX-only still covers Streamline calls)"*.

---

## 5. Providers

| | Deep Fried Chicken | RenoDX DLSS5 Generic |
|---|---|---|
| Passes | 1-30 sequential | 1 |
| NeuralUplift | (highest pass) | Supported |
| Frame generation coexistence | Experimental | - |
| Feeder `warmup_rebuild` | `0` (required) | `180` |
| Coexists in folder | Conflicts ignored (Chicken wins) | same |

Chicken's multi-pass is the real "DLSS 5" selling point: every layer runs its
own full neural pass, so quality scales with `-Passes`.

---

## 6. Install options & the CLI

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
| `-MFGAddon` | switch | off | Install the MFG Unlock ReShade addon (RTX 40) |
| `-RenoHooks` | auto / ngx / streamline | auto | RenoDX addon hook mode (see §4). `auto` = remembered `hookMode`, else NGX-only |
| `-FixHooks` | switch | off | Repair: rewrite `EnableHooks` from `ReShade.log` evidence (or force `-RenoHooks ngx`/`streamline`), no reinstall |
| `-KitPath` | path | `.\kit` | Override the file kit location |
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

---

## 7. The Electron UI

| Action | How |
|---|---|
| **Add games** | *Add game folder* (scans just that folder) or *Auto-scan* (launchers or deep-scan a drive) |
| **Rescan** | *Rescan all* re-scans every saved folder; the last scan is cached and loads instantly at startup |
| **Install** | Pick a game, choose a provider and options, click *Install* |
| **Verify** | One-click health check - shows only the checks that failed + a short summary line when all pass |
| **Restore** | Roll back any install from the journaled backup |
| **RenoDX Fix** | One-click `EnableHooks=1` rewrite for Streamline-routed games (see §4) |
| **Info** | *Info* tab - app version, Electron/Chromium/Node, OS, repository link, Report-a-bug |

The game cards show just the essentials: the render API badge, a green
*RenoDX/Chicken active* state, and - only when relevant - an amber fix/compile
warning. Detection details (bitness, ReShade version, native-DLSS note) ride in
the API badge tooltip instead of cluttering the tile.

---

## 8. Automation (`-Json`) and JSON shapes

Every command accepts `-Json`: all human-readable output goes to stderr, and a
single compact JSON document is emitted on stdout - designed for the Electron
UI and for scripting:

```powershell
.\DLSS5-Swapper.ps1 -Scan    -GamePath "C:\Games\SomeGame" -Json
.\DLSS5-Swapper.ps1 -Install -GamePath "C:\Games\SomeGame" -Provider renodx -Json
.\DLSS5-Swapper.ps1 -FixHooks -GamePath "C:\Games\SomeGame" -Json
.\DLSS5-Swapper.ps1 -Discover -Json
```

| Command | Response fields |
|---|---|
| `-Scan` | `gameDir`, `chosen`, `candidates[]` (each with a `Main` flag), `hasNativeDlss`, `reshade{}` |
| `-Install` | `exe`, `api`, `provider`, `passes`, `feeder`, `mfg`, `mfgProxy`, `mfgAddon`, `added[]`, `dryRun`, `manifestPath` |
| `-Verify` | `exe`, `api`, `checks[]`, `provider`, `installed` (+ `note:"not installed"`), and for RenoDX installs: `recommendation` (`null`/`streamline`), `hookMode` (`null`/`1`/`2`), `streamlineHost`, `featureMatched`, `nrProxyCompileFail` |
| `-FixHooks` | `gameDir`, `mode` (`streamline`/`ngx`), `enablehooks` (`1`/`2`), `dryRun` |
| `-Uninstall` | `removed[]`, `restored[]` |
| `-Discover` | `launchers`, `root`, `folders[]`, `scans[]` (each scan is a `-Scan` shape) |

The UI's startup library scan calls the manifest reader (`listBackups`) which
runs the same log-based diagnostic on every renodx install, so the card chips
are available before you even hit Verify.

---

## 9. Troubleshooting

### 9.1 "NO NR FEATURE MATCHED (STANDBY/FAILED)" with 0 successful NR frames

Symptom on a native-DLSS game: overlay shows *"DLSS is evaluating but the NR
feature did not bind to an output"*, `Streamline: DLSS/DLSSD evaluations 0`,
`Successful NR frames 0`.

Cause: the addon ran **NGX-only** (`EnableHooks=2`) while the game routes its
DLSS through Streamline (`sl.interposer.dll`). Fix (the addon's own guidance):

- The log shows **no** `NGX feature create intercepted` line under mode 2 - the
  app detects this and the card shows *RenoDX fix needed* - press **RenoDX Fix**
  (or `.\DLSS5-Swapper.ps1 -FixHooks`). After the game relaunches with
  `EnableHooks=1`, the log shows `installing Streamline hooks into
  sl.interposer.dll...` and `NGX feature create intercepted`, and the overlay
  binds the NR feature.

### 9.2 NR proxy compile failed - `cs_5_1` / `0x8876086c`

Symptom on a Streamline-routed game after the fix: the addon patches Streamline
and intercepts `feature=1`, but every evaluation fails with something like
`DLSS5 Generic proxy encode compilation failed with HRESULT 0x8876086c: error
X3506: unrecognized compiler target 'cs_5_1'`.

Cause: the addon's **runtime proxy shader** is compiled for a shader model the
installed runtimes/driver cannot compile in that context - an **addon/runtime
compiler issue**, **not** a config problem and not something the swapper can
change. The `NR upscaling` verify check flags it. Verify the addon version and
report to the addon author; test a known-good combo (e.g. the Streaming module
runtimes the addon lists as compatible).

### 9.3 Streamline mode freezes the game at boot

Some titles (GTA V Enhanced double-patches) freeze at the first NGX evaluate
after a loading screen when `EnableHooks=1`. Fix = back to `2`:
`.\DLSS5-Swapper.ps1 -FixHooks -RenoHooks ngx`, or reinstall with
`-RenoHooks ngx` / the UI's *NGX-only (safe)* option. This is exactly why the
install **default is NGX-only** and Streamline is only enabled when log
evidence or the user says so.

### 9.4 The classic: "nothing happened / wrong API"

Re-detect with the *Re-detect* button on the card, or `-Scan -GamePath` from
the CLI, and check the detected render API against the game. Packers can hide
imports - the string heuristic usually still catches them. Hybrid Vulkan+D3D
titles flip to the Vulkan layer automatically (see §3).

### 9.5 Vulkan requires the Feeder transport

`renodx-dlss5` is a D3D12-only addon: it detours the D3D12 `EvaluateFeature`
path, so a Vulkan process with no D3D12 device gives it nothing to hook and the
addon refuses to register (`No add-on was registered ... Unloading again`). The
fix is not to switch providers: the **DLSS5-Feeder transport** provides the
consumer's D3D12 context inside the Vulkan process, and RenoDX registers
against it. This is exactly how the DLSS 5 Swapper ships Vulkan: the Feeder
route carries the RenoDX consumer (not Deep Fried Chicken).

With the Feeder transport present:

- the DLSS5-Feeder addon creates a private in-process D3D12 device
- the neural consumer (renodx or chicken) hooks the D3D12 NGX via that device
- the Vulkan frame data is fed across the device; NR runs normally

The installer automatically enables the Feeder on Vulkan (`-Feeder off` is
ignored there). If the kit is missing `dlss5-feed.addon64`, the install aborts
with a clear message.

If `Verify` reports *Provider vs API* on a Vulkan game, the old install was
created before this fix and needs a reinstall (the installer now forces the
Feeder on Vulkan).

**Previous installs:** games installed with `-Provider renodx` and Vulkan before
this fix have `feeder=false` in the manifest and a dead addon. Reinstall them to
pick up the forced Feeder.

---

## 10. Notes & limitations

- **64-bit + 32-bit (host helper)** - the neural stack (`nvngx_dlss*`, both
  providers and the feeder add-ons) is x86-64, so a 32-bit game cannot load it
  directly. For **32-bit games** the installer puts a 64-bit **host helper**
  (`host64\`) next to the game - `dlss5-feed-host64.exe`, its own ReShade hook
  and the NVIDIA runtimes - while the game folder gets the 32-bit feeder
  (`dlss5-feed.addon32`). The helper does the NGX work over shared memory, so a
  32-bit game gets DLSS 5 the same way the community does on GTA San Andreas
  and the like. A bundled 32-bit ReShade hook (`dxgi.dll`) is deployed next to
  the exe automatically, and **DirectX 8/9** games are wrapped automatically
  with **dgVoodoo2** (D3D8/9 -> D3D11). The UI asks for confirmation before
  installing into a 32-bit game.
- **dgVoodoo2** - DirectX 8/9 translation for 32-bit games is **not bundled
  with the repo**: antivirus products flag dgVoodoo's DLLs on download (known
  false positives, 29/66 on VirusTotal), so nothing in this repository ever
  triggers that on a fresh clone. Instead the installer builds it from a local
  folder: grab the official release
  (<https://github.com/dege-diosg/dgVoodoo2/releases> - a 32-bit `D3D8.dll` /
  `D3D9.dll`, `dgVoodoo.conf` and `dgVoodooCpl.exe` from the zip), set
  `"dgvoodoo": "C:\\path\\to\\extracted"` in `sources.json`, run `-BuildKit`,
  and the 32-bit D3D8/9 path auto-deploys those files next to the game's exe.
  Without them the installer warns and copies only with `-Force`.
- **DirectX 8/9 (64-bit)** need a manual dgVoodoo2 setup (D3D9 -> D3D11
  translation) before the stack can hook them; the script warns but copies
  with `-Force`.
- **OpenGL** needs a ReShade `opengl32.dll` proxy that is not bundled.
- **Vulkan** picks the machine-wide ReShade layer
  (`C:\ProgramData\ReShade\`); if absent it falls back to a per-user implicit
  layer under `%USERPROFILE%\.dlss5vulkanlayer` (reference-counted via
  `installs.json` so uninstalling one game never breaks another).
- **Shader package** - `-BuildKit` harvests the whole ReShade shader tree from
  the local rpcs3 source (`reshade-shaders\Shaders`: `lumenite_*.fx`,
  `vort_*.fx`, `include/` and `Includes/`), and takes `DrawText.fxh` from the
  optional `"shadercore"` entry in `sources.json`. The full tree is what the
  installer deploys to `reshade-shaders\Shaders` next to the game's exe - the
  Lumenite Kernel motion-vector provider (`-MVProvider 3`, the preset default)
  includes `include/*.fxh` and `DrawText.fxh` at compile time, so without the
  complete package it fails to compile and the feed reports zero motion
  vectors.
- Games with **anti-cheat** (BattlEye etc.) may reject injected modules; use
  the offline/Story modes where available.
- **MFG Unlock addon** (`-MFGAddon`) unlocks higher DLSS **Multi Frame
  Generation** multipliers through ReShade (mavismmg/MFGAdaUnlock-RenoDx):
  loaded as `renodx-mfgunlock.addon64` and configured through the game's own
  FG selector plus the **MFG Unlock** ReShade panel. RTX 40 **only**, **x64-only**
  (it loads through the 64-bit ReShade hook). It also needs a Streamline
  DLSS-FG title and a modern `nvngx_dlssg.dll`; GTA V Enhanced's bundled 2.9.1
  wrapper caps it at 4x. First launch after install may stutter while DLSS-G
  kernels compile - restart the game once before judging quality. Its settings
  live in `ReShade.ini` under `[RenoDX.MFGUnlock]` (addon-owned); the addon file
  itself is journaled and removed on `-Uninstall`. If menu slowdowns appear when
  RenoDX DLSS5 is also installed, the MFGUnlock README reports Streamline
  2.12.129 / 310.7.129 as the known-good combined runtime set.

### 32-bit / host-helper path: known issues (future fix)

The 32-bit host-helper path is **experimental** and only partially working.
Verified on GTA IV; treat it as a known-broken area marked for a **future fix**:

- **DLSS 5 often "does nothing" visually.** ReShade loads, the feeder runs and
  the host renders DLAA frames, but the output looks unchanged. On GTA IV the
  measured cause was the neural consumer: `renodx-dlss5` v4.7 (RenoDX provider)
  faulted inside the neural evaluate (access violation in `D3D12Core.dll` via
  `nvngx_dlssnr.dll`) with current NVIDIA drivers. **Deep Fried Chicken** (the
  default `chicken` provider) works with the same driver - use `-Provider chicken`
  for 32-bit host games. Driver 616.56 also passes with either provider.
- **No RenoDX.DLSS5 tab in the game's overlay.** For a 32-bit game the provider
  add-on runs in the hidden `host64\dlss5-feed-host64.exe` helper process, not in
  the game - so the game's ReShade overlay only lists the feed add-on under
  *Addons*, and the RenoDX/Chicken panel you expect never appears there. Tuning
  is done by editing `host64\deep-fried-chicken.cfg` next to the exe.
- **Host window / focus chaos.** The helper spawns behind the game, and some
  titles (GTA IV: fullscreen -> windowed -> taskbar -> stuck at the menu) fight
  the hidden host window for focus once the game starts. Launch through the
  game's launcher/Steam; launching the raw exe may also crash the game even
  without any of this installed.
- Until these are fixed, prefer 64-bit titles - the 64-bit path (in-game hook,
  visible RenoDX/Chicken tab, no host helper) is the reliable one.

---

## 11. Repository layout

```
DLSS5-Swapper.ps1    # backend - the whole tool (single file)
Requirements.md      # hardware/driver/tooling requirements + kit rebuild sources
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
kit/                 # harvested binary kit (built by -BuildKit, tracked via Git LFS;
                     #   local-only extras like dgvoodoo/ are gitignored - see Notes)
  mfgunlock/          #   MFG Unlock ReShade addon (mavismmg/MFGAdaUnlock-RenoDx)
    renodx-mfgunlock.addon64  #     the -MFGAddon in-memory unlock
```

## Credits

- [DLSS5-Feeder](https://github.com/zeroeightysix/DLSS5-Feeder) - the DLSS5
  transport addon
- [Deep Fried Chicken](https://www.nexusmods.com/site/mods/1692) - multi-pass
  neural provider
- [RenoDX](https://www.nexusmods.com/site/mods/943) - DLSS5 Generic addon
- [MFGUnlock (MFGAdaUnlock-RenoDx)](https://github.com/mavismmg/MFGAdaUnlock-RenoDx)
  by mavismmg (fork of [ImDreamt's original](https://github.com/ImDreamt/MFGAdaUnlock-RenoDx))
  - the ReShade-addon MFG unlock with the temporal midpoint fix, integrated as
  the `-MFGAddon` option
- [DLSS 5 Swapper](https://github.com/rakanki911/DLSS5-Swapper) - original app
  concept this script reimplements