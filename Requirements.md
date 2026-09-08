# Requirements

Everything needed to run the **DLSS 5 Swapper** backend and its Electron UI.

## Hardware

| Requirement | Why | Verdict |
|---|---|---|
| NVIDIA GPU with **Tensor cores** | DLSS 5 Neural Rendering runs on the `nvngx_dlssnr` model, which needs Tensor Cores | required |
| GeForce RTX 30 / 40 / 50 series | The community builds used here are tested on RTX 30/40/50 | recommended |
| ~300 MB free disk per game | `nvngx_dlss.dll` (~59 MB) + `nvngx_dlssnr.dll` (~158 MB) + shaders are copied next to every game exe | required |
| Enough VRAM | Neural Rendering evaluates at (or above) your render resolution on top of the game itself | recommended |

> The off-the-shelf NVIDIA signed `nvngx_dlssnr.dll` is hard-locked to RTX 50
> (feature-18 create fails with `0xBAD00001` elsewhere). On RTX 30/40 you need
> the community-patched DLL (RenoDX Discord). A non-NVIDIA or pre-RTX card
> cannot run the neural pass at all.

### Driver

- **Windows**: NVIDIA Game Ready driver, current.
- **NeuralUplift** officially needs **616.56 or newer**.
- On the 32-bit host-helper path, `renodx-dlss5` v4.7 is **measured to fail**
  on recent drivers (such as 620.02) - it faults inside `D3D12Core` during the
  neural evaluate. Use the **Deep Fried Chicken** provider (good on 620.02) or
  driver **616.56**, or a compatible RenoDX build. See README *32-bit /
  host-helper path*.

## OS & permissions

| Requirement | Why | Verdict |
|---|---|---|
| Windows 10+ **x64** (or Windows 11) | 64-bit hooks, ReShade layers and the neural runtimes | required |
| Administrator rights | Installing into `C:\Program Files (x86)\...` and writing the machine-wide Vulkan layer under `C:\ProgramData\ReShade` | required for those paths |

Games under the user's own folders (e.g. `C:\Games\...`) do not need elevation.
Games under `Program Files` do.

## Backend

| Requirement | Why | Verdict |
|---|---|---|
| PowerShell 5.1+ | the backend is a single `DLSS5-Swapper.ps1` | required |
| ExecutionPolicy -Bypass (or a signed policy) | the script and UI launch PowerShell with `-ExecutionPolicy Bypass` | required |

## UI (optional)

| Requirement | Why | Verdict |
|---|---|---|
| Node.js 18+ | to install the Electron runtime | only for the UI |
| `DLSS5-UI\` folder | run `start.bat` (auto-`npm install`) or `npm start` from `DLSS5-UI` | only for the UI |

## Repository

| Requirement | Why | Verdict |
|---|---|---|
| Git | cloning/updating; the UI auto-updates via `git fetch origin main` | required |
| Git LFS | the binary kit (`kit/`) ships through Git LFS | required - `git lfs pull` |

## Kit / rebuild (`-BuildKit`)

The `kit/` folder ships with the clone, but if you rebuild it you need the
sources configured in `sources.json`:

- **ReShade 6.8.0 add-on build** (`dxgi.dll`, `reshade-vulkan\ReShade*`) - full
  add-on support is mandatory, the standard build silently loads no add-ons.
- **Deep Fried Chicken** (`chicken\deep-fried-chicken.addon64`,
  `deep-fried-chicken-nvngx.dll`) - from its Discord/Nexus.
- **RenoDX DLSS5 Generic** (`renodx\renodx-dlss5.addon64`) - from the RenoDX
  Discord (`#dlss5`), same `nvngx_dlssnr.dll` runtime.
- **NVIDIA runtimes** (`runtime\nvngx_dlss.dll`, `nvngx_dlssnr.dll`).
- **dgVoodoo2** for 32-bit DirectX 8/9 games (`dgvoodoo\D3D8.dll`,
  `D3D9.dll`, `dgVoodoo.conf`, `dgVoodooCpl.exe`) - antivirus products flag it
  as a false positive, so it is built locally, not committed.

## Verification

```powershell
.\DLSS5-Swapper.ps1 -Verify -GamePath "C:\Path\To\Game"
```

Logs the swapper writes next to the game exe: `ReShade.log`,
`dlss5-feed.log`, `deep-fried-chicken.log`, and `host64\dlss5-feed-host.log`
for 32-bit games.

## Warnings

- **Anti-cheat / multiplayer**: injecting DLLs and shader layers into an online,
  ranked or anti-cheat-protected game is considered cheating and can get you
  banned (hardware bans included). Use **only** in offline / single-player.
- **32-bit games**: the host-helper path is experimental. Prefer 64-bit titles.
  See README *32-bit / host-helper path: known issues (future fix)*.
- **RTX on / alternatives**: DLSS 5 replaces nothing; the game must meet the
  NVIDIA runtime and driver conditions above or the neural pass stays inert.