#requires -Version 5.1
<#
  DLSS 5 Swapper - a self-contained installer for the DLSS 5 Neural Rendering
  stack (DLSS5-Feeder + a neural provider) into non-DLSS games, modelled on the
  DLSS5-Swapper app (rakanki911/DLSS5-Swapper).

  Two neural provider routes are supported:
    - Provider 'chicken' (default): Deep Fried Chicken - one to thirty sequential
      DLSS Neural Rendering passes (deep-fried-chicken.addon64).
    - Provider 'renodx':            RenoDX DLSS5 Generic v4.7 - a single pass.

  Rendering API is auto-detected from the game executable PE (imports, delayed
  imports, binary markers, sibling modules and filename), including DXVK/vkd3d
  wrappers: DirectX 11/12 (dxgi hook), Vulkan (global/user Vulkan layer),
  DirectX 8/9 (dgVoodoo2 auto-deployed for 32-bit games), OpenGL.

  USAGE
    .\DLSS5-Swapper.ps1 -BuildKit                     build the file kit from
                                                      verified local sources
    .\DLSS5-Swapper.ps1 -Scan -GamePath <folder>      detect games + APIs
    .\DLSS5-Swapper.ps1 -Install -GamePath <folder> [options]
    .\DLSS5-Swapper.ps1 -Verify -GamePath <folder>
    .\DLSS5-Swapper.ps1 -Uninstall -GamePath <folder>
    .\DLSS5-Swapper.ps1 -ListKit

  INSTALL OPTIONS
    -Api d3d8|d3d9|d3d10|d3d11|d3d12|vulkan|opengl|auto   (default auto)
    -Provider chicken|renodx                             (default chicken)
    -Passes 1..30                                        chicken passes (default 1)
    -WorkResolution 10..150                              (default 100)
    -Style default|natural|cinematic                     (default default)
    -Preset 0..N                                         NR preset index (default 0)
    -Intensity 1..4                                      NR intensity (default 1)
    -MVProvider 0..4                                     DLSS5_Feed MV provider
                                                         (default 3 = Lumenite Kernel)
    -CleanFry                                            enable multi-pass cleanup
    -TextureBoost                                        enable experimental 8K path
    -NeuralUplift                                        renodx NeuralUplift
    -RenoHooks auto|ngx|streamline                       renodx addon hook mode
                                                          (auto=remembered or NGX-only,
                                                          streamline=patch Streamline
                                                          sl.interposer/sl.common for
                                                          Streamline-routed titles)
    -FixHooks                                            rewrite the addon's EnableHooks
                                                          per -RenoHooks (auto-detects
                                                          from ReShade.log evidence)
    -Feeder auto|forced|off                              DLSS5-Feeder transport
    -MFGAddon                                            install the MFG Unlock ReShade
                                                          addon (mavismmg/MFGAdaUnlock-
                                                          RenoDx) alongside the stack for
                                                          Streamline DLSS-FG titles on RTX 40
    -Exe <name.exe>                                      pick a specific executable
    -KitPath <folder>                                    kit location override
    -DryRun                                              do not write anything
    -Force                                               proceed despite warnings
    -Launch                                              start the game after install
#>

param(
    [switch]$BuildKit,
    [switch]$Scan,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Verify,
    [switch]$ListKit,
    [switch]$Help,
    [string]$GamePath,
    [string]$Exe,
    [ValidateSet('auto','d3d8','d3d9','d3d10','d3d11','d3d12','vulkan','opengl')]
    [string]$Api = 'auto',
    [ValidateSet('chicken','renodx')]
    [string]$Provider = 'chicken',
    [ValidateRange(1,30)]
    [int]$Passes = 1,
    [ValidateRange(10,150)]
    [int]$WorkResolution = 100,
    [ValidateSet('default','natural','cinematic')]
    [string]$Style = 'default',
    [int]$Preset = 0,
    [double]$Intensity = 1.0,
    [ValidateRange(0,4)]
    [int]$MVProvider = 3,
    [switch]$CleanFry,
    [switch]$TextureBoost,
[switch]$NeuralUplift,
    [ValidateSet('auto','ngx','streamline')]
    [string]$RenoHooks = 'auto',
    [ValidateSet('auto','forced','off')]
    [string]$Feeder = 'auto',
    [switch]$MFGAddon,
    [switch]$LoadFromDllMain,
    [string]$KitPath = '',
    [string]$ExeFilter = '',
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Launch,
    [switch]$FixHooks,
    [switch]$Discover,
    [string]$ScanRoot = '',
    [int]$Depth = 6,
    [switch]$Json,
    [switch]$NoColor
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:Kit  = if ($KitPath) { $KitPath } else { Join-Path $Script:Root 'kit' }

if ($Json) {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
}

# Default verified local sources (edit the path in sources.json to change them).
$Script:SourceDefaults = @{
    chicken   = 'C:\Users\drago\Downloads\Compressed\Deep-Fried-Chicken-v1.4.8-alpha'
    rpcs3     = 'C:\Users\drago\Downloads\Compressed\rpcs3-v0.0.42-19930-33a723af_win64_msvc'
    gta       = 'C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V Enhanced'
    reshadeVk = 'C:\ProgramData\ReShade'
    reshade32 = 'C:\Users\drago\Downloads\Compressed\ReShade_6.8.0_Addon'
    shadercore = 'C:\Users\drago\Downloads\Compressed\reshade-shaders-official\Shaders'
    dgvoodoo  = 'C:\Users\drago\Downloads\Compressed\dgVoodoo2-2.87.4'
    mfgunlock = 'C:\Users\drago\Downloads\Compressed\MFGAdaUnlock'
}

$Script:NOT_A_GAME = '^(unins|setup|install|vcredist|vc_redist|dxsetup|dxwebsetup|oalinst|uninstall|crashreport|crashhandler|unitycrashhandler|easyanticheat|eac|battleye|be_service|launcher|activation|patch|update|dotnetfx|touchup|rapidcrc|autorun|autoplay|quicksfv|readme|config|benchmark|report|helper|service|cleanup|modorganizer|redlauncher|skse\d*_loader|hlds\b|srcds\b|steamerrorreporter|dgvoodoocpl|reshade_setup)'

$Script:SKIP_DIRS = @('_dlss5_backup','reshade-shaders','host64','node_modules','.git','paks','movies','screenshots','saved','logs','mods','downloads','overwrite','profiles','_redist','prerequisites','directx','redist','redistributables','_commonredist','dotnet','installer_resources','installer','installers','support','vcredist','_support','directx_redist','eaanticheat','easyanticheat','battleye','backup','backups','_backup','bak','old','original','originals')

# ---------------------------------------------------------------------------
# logging helpers (when -Json, humans go to stderr, JSON goes to stdout)
# ---------------------------------------------------------------------------
function Write-Step { param([string]$T) if ($Json) { [Console]::Error.WriteLine("[DLSS5] $T") } else { Write-Host "[DLSS5] $T" -ForegroundColor Cyan } }
function Write-Ok   { param([string]$T) if ($Json) { [Console]::Error.WriteLine("[DLSS5] $T") } else { Write-Host "[DLSS5] $T" -ForegroundColor Green } }
function Write-Warn { param([string]$T) if ($Json) { [Console]::Error.WriteLine("[DLSS5] $T") } else { Write-Host "[DLSS5] $T" -ForegroundColor Yellow } }
function Write-Err  { param([string]$T) if ($Json) { [Console]::Error.WriteLine("[DLSS5] $T") } else { Write-Host "[DLSS5] $T" -ForegroundColor Red } }

function Fail { param([string]$T) Write-Err $T; exit 1 }

# ---------------------------------------------------------------------------
# small IO helpers
# ---------------------------------------------------------------------------
function Get-AsciiImports {
    # parse the import (dir 1) and delay-load (dir 13) tables of a PE file
    param([string]$Path)
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0
        if ($br.ReadUInt16() -ne 0x5A4D) { return @() }            # 'MZ'
        $fs.Position = 0x3C
        $peOff = $br.ReadInt32()
        $fs.Position = $peOff
        if ($br.ReadUInt32() -ne 0x00004550) { return @() }        # 'PE\0\0'
        $null = $br.ReadUInt16()                                    # Machine
        $numSections = $br.ReadUInt16()
        $null = $br.ReadUInt32(); $null = $br.ReadUInt32(); $null = $br.ReadUInt32()
        $optSize = $br.ReadUInt16()                                 #SizeOfOptionalHeader
        $null = $br.ReadUInt16()                                    #Characteristics
        $optOff = $peOff + 24
        $fs.Position = $optOff
        $magic = $br.ReadUInt16()
        $is64 = ($magic -eq 0x20B)
        $ddOff = if ($is64) { 112 } else { 96 }

        $secOff = $optOff + $optSize
        $sections = @()
        $fs.Position = $secOff
        for ($i = 0; $i -lt $numSections; $i++) {
            $fs.Position = $secOff + $i * 40
            $buf = $br.ReadBytes(40)
            if ($buf.Length -lt 40) { break }
            $sections += [pscustomobject]@{
                VirtualSize = [BitConverter]::ToUInt32($buf, 8)
                VirtualAddr = [BitConverter]::ToUInt32($buf, 12)
                RawSize     = [BitConverter]::ToUInt32($buf, 16)
                RawOffset   = [BitConverter]::ToUInt32($buf, 20)
            }
        }
        function RvaToOff([uint32]$rva) {
            foreach ($s in $sections) {
                $span = [Math]::Max($s.VirtualSize, $s.RawSize)
                if ($rva -ge $s.VirtualAddr -and $rva -lt ($s.VirtualAddr + $span)) {
                    return ($s.RawOffset + ($rva - $s.VirtualAddr))
                }
            }
            return $null
        }
        function ReadCStr([long]$pos, [int]$cap = 260) {
            $b = $br.ReadBytes($cap)
            $sb = New-Object System.Text.StringBuilder
            for ($j = 0; $j -lt $b.Length; $j++) {
                if ($b[$j] -eq 0) { break }
                [void]$sb.Append([char]$b[$j])
            }
            return $sb.ToString().ToLower()
        }
        $names = New-Object System.Collections.Generic.HashSet[string]
        function Read-Table([int]$dirIndex, [int]$stride, [int]$nameField) {
            $fs.Position = $optOff + $ddOff + $dirIndex * 8
            $dirRva = $br.ReadUInt32()
            if ($dirRva -eq 0) { return }
            $dirOff = RvaToOff $dirRva
            if ($null -eq $dirOff) { return }
            $fs.Position = [int64]$dirOff
            for ($d = 0; $d -lt 512; $d++) {
                $fs.Position = [int64]$dirOff + $d * $stride
                $desc = $br.ReadBytes($stride)
                if ($desc.Length -lt $stride) { break }
                $nameRva = [BitConverter]::ToUInt32($desc, $nameField)
                if ($nameRva -eq 0) { break }
                $nameOff = RvaToOff $nameRva
                if ($null -eq $nameOff) { continue }
                $fs.Position = [int64]$nameOff
                $nm = ReadCStr $nameOff
                if ($nm) { [void]$names.Add($nm) }
            }
        }
        Read-Table 1 20 12
        Read-Table 13 32 4
        return @($names)
    } catch {
        return @()
    } finally {
        if ($br) { $br.Dispose() }
        if ($fs) { $fs.Dispose() }
    }
}

function Get-PeBitness {
    param([string]$Path)
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0
        if ($br.ReadUInt16() -ne 0x5A4D) { return $null }
        $fs.Position = 0x3C
        $peOff = $br.ReadInt32()
        $fs.Position = $peOff
        if ($br.ReadUInt32() -ne 0x00004550) { return $null }
        $fs.Position = $peOff + 24
        $magic = $br.ReadUInt16()
        $br.Dispose(); $fs.Dispose()
        if ($magic -eq 0x20B) { return 64 }
        if ($magic -eq 0x10B) { return 32 }
        return $null
    } catch { return $null }
}

function Find-BinaryMarkers {
    # true if ALL markers exist as ASCII OR UTF-16LE text inside the file (single fast pass)
    param([string]$Path, [string[]]$Markers, [bool]$Any = $false)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $l1 = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
        $found = 0
        $hit = $false
        foreach ($m in $Markers) {
            $hit = $false
            if ($l1.IndexOf($m, [System.StringComparison]::Ordinal) -ge 0) { $hit = $true }
            if (-not $hit) {
                $pat16 = ($m.ToCharArray() -join "`0") + "`0"
                if ($l1.IndexOf($pat16, [System.StringComparison]::Ordinal) -ge 0) { $hit = $true }
            }
            if ($hit) { $found++ }
            if ($Any -and $hit) { return $true }
        }
        return ($found -eq $Markers.Count)
    } catch { return $false }
}

function Get-FileProductVersion {
    param([string]$Path)
    try {
        $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Resolve-Path -LiteralPath $Path))
        if ($v.ProductVersion) { return $v.ProductVersion }
        if ($v.FileVersion) { return $v.FileVersion }
        return '?'
    } catch { return '?' }
}

# ---------------------------------------------------------------------------
# rendering API detection (mirrors DLSS5-Swapper)
# ---------------------------------------------------------------------------
function Get-ApiFromNames {
    param([string[]]$Imports, [int]$Bitness = 0)
    $has = { param($n) $Imports -contains $n }
    if (& $has 'd3d12.dll')   { return @{ api = 'dxgi';    label = 'DirectX 12'; via = 'imports' } }
    if (& $has 'd3d11.dll')   { return @{ api = 'dxgi';    label = 'DirectX 11'; via = 'imports' } }
    if ((& $has 'd3d10.dll') -or (& $has 'd3d10_1.dll')) { return @{ api = 'd3d10'; label = 'DirectX 10'; via = 'imports' } }
    if (& $has 'dxgi.dll')    { return @{ api = 'dxgi';    label = 'DirectX (DXGI)'; via = 'imports' } }
    if (& $has 'vulkan-1.dll'){ return @{ api = 'vulkan';  label = 'Vulkan'; via = 'imports' } }
    # D3D9/D3D8 are 32-bit-only APIs. A 64-bit exe that imports them (e.g. RDR2
    # statically links d3d9.dll for its legacy pipeline) is never a D3D9/8 renderer.
    if ($Bitness -ne 64) {
        if (& $has 'd3d9.dll')    { return @{ api = 'd3d9';    label = 'DirectX 9'; via = 'imports' } }
        if (& $has 'd3d8.dll')    { return @{ api = 'd3d8';    label = 'DirectX 8'; via = 'imports' } }
    }
    if (& $has 'opengl32.dll'){ return @{ api = 'opengl';  label = 'OpenGL'; via = 'imports' } }
    return $null
}

function Get-ApiFromMarkers {
    param([string]$Path, [int]$Bitness = 0)
    $markers = @('D3D12CreateDevice','D3D12SDKPath','D3D12SDKVersion','D3D11CreateDevice','D3D10CreateDevice','CreateDXGIFactory','Direct3DCreate9','Direct3DCreate8','vkCreateInstance','wglCreateContext')
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $l1 = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
$TestMarker = {
        param($m)
        if ($l1.IndexOf($m, [System.StringComparison]::Ordinal) -ge 0) { return $true }
        $pat16 = ($m.ToCharArray() -join "`0") + "`0"
        return ($l1.IndexOf($pat16, [System.StringComparison]::Ordinal) -ge 0)
    }
    $has = @{}
    foreach ($m in $markers) { $has[$m] = [bool](& $TestMarker $m) }
# D3D9 wins over D3D10/11 when both are present BUT only for 32-bit exes:
    # the late-D3D9 era games (GTA IV, Saints Row 2) import d3d10/dxgi as
    # auxiliary entry points while presenting through D3D9. D3D9 is a 32-bit-only
    # API, so a 64-bit exe carrying a Direct3DCreate9 marker (e.g. RDR2) is never
    # a D3D9 renderer - treat it as D3D10/12 (i.e. dxgi) as before.
    if (($Bitness -eq 32) -and $has['Direct3DCreate9'] -and ($has['D3D10CreateDevice'] -or $has['D3D11CreateDevice'])) { return @{ api='d3d9'; label='DirectX 9'; via='strings' } }
    if ($has['D3D12CreateDevice'] -or $has['D3D12SDKPath'] -or $has['D3D12SDKVersion']) { return @{ api='dxgi'; label='DirectX 12'; via='strings' } }
    if ($has['D3D11CreateDevice']) { return @{ api='dxgi'; label='DirectX 11'; via='strings' } }
    if ($has['D3D10CreateDevice']) { return @{ api='d3d10'; label='DirectX 10'; via='strings' } }
    if ($has['CreateDXGIFactory']) { return @{ api='dxgi'; label='DirectX (DXGI)'; via='strings' } }
    if ($has['Direct3DCreate9'])   { return @{ api='d3d9'; label='DirectX 9'; via='strings' } }
    if ($has['Direct3DCreate8'])   { return @{ api='d3d8'; label='DirectX 8'; via='strings' } }
    if ($has['vkCreateInstance'])  { return @{ api='vulkan'; label='Vulkan'; via='strings' } }
    if ($has['wglCreateContext'])  { return @{ api='opengl'; label='OpenGL'; via='strings' } }
    return $null
}

function Get-ApiFromDynamic {
    # 64-bit engines that load their renderer at runtime (e.g. RDR2) statically
    # bind no modern graphics DLL - only a legacy d3d9.dll - while carrying both
    # D3D12 and Vulkan entry points. BeamNG-like games are immune because they
    # statically import d3d12/d3d11/dxgi, so they never reach this path. When the
    # exe ships D3D12 + vkCreateInstance markers and a ReShade Vulkan layer is
    # registered, the game's actual presenter is Vulkan (RDR2 journal:
    # kSettingAPI_Vulkan).
    param([string]$Path, [string[]]$Imports, [int]$Bitness = 0)
    if ($Bitness -ne 64) { return $null }
    if (($Imports -contains 'd3d11.dll') -or ($Imports -contains 'd3d12.dll') -or
        ($Imports -contains 'dxgi.dll')  -or ($Imports -contains 'vulkan-1.dll')) { return $null }
    $hasD3D = Find-BinaryMarkers -Path $Path -Markers @('D3D12CreateDevice') -Any $true
    $hasVk  = Find-BinaryMarkers -Path $Path -Markers @('vkCreateInstance') -Any $true
    if (-not ($hasD3D -and $hasVk)) { return $null }
    $hasLayer = (Test-Path -LiteralPath (Join-Path 'C:\ProgramData\ReShade' 'ReShade64.dll')) -or
                (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.dlss5vulkanlayer\ReShade64.dll'))
    if (-not $hasLayer) { return $null }
    return @{ api = 'vulkan'; label = 'Vulkan'; via = 'dynamic' }
}

function Test-VulkanWrapper {
    # a Direct3D DLL sitting beside the exe that is really DXVK / vkd3d
    param([string]$Dir, [string]$Api, [int]$Bitness)
    $candidates = switch ($Api) {
        'dxgi'   { @('d3d12.dll','d3d11.dll','dxgi.dll') }
        'd3d10'  { @('d3d10.dll','d3d10_1.dll') }
        'd3d9'   { @('d3d9.dll') }
        'd3d8'   { @('d3d8.dll') }
        default  { @() }
    }
    foreach ($c in $candidates) {
        $p = Join-Path $Dir $c
        if (-not (Test-Path -LiteralPath $p)) { continue }
        if ((Get-PeBitness $p) -ne $Bitness) { continue }
        if (Find-BinaryMarkers -Path $p -Markers @('ReShade')) { continue }
        if ((Find-BinaryMarkers -Path $p -Markers @('DXVK','vkd3d')) -and
            (Find-BinaryMarkers -Path $p -Markers @('vkGetInstanceProcAddr'))) { return $true }
    }
    return $false
}

function Get-DetectedApi {
    param([string]$ExePath, [int]$Bitness = 0)
    $imports = Get-AsciiImports -Path $ExePath
    $d = Get-ApiFromNames -Imports $imports -Bitness $Bitness
    if ($d) { return $d }
    $d = Get-ApiFromDynamic -Path $ExePath -Imports $imports -Bitness $Bitness
    if ($d) { return $d }
    $d = Get-ApiFromMarkers -Path $ExePath -Bitness $Bitness
    if ($d) { return $d }
    return $null
}

function Get-IsReShadeProxy {
    param([string]$Path)
    try { return (Find-BinaryMarkers -Path $Path -Markers @('ReShade')) } catch { return $false }
}

function Get-ApiFromEngine {
    # catch games whose .exe is a launcher/stub; the render API lives in an engine DLL
    param([string]$Dir, [int]$Bitness)
    if (-not (Test-Path -LiteralPath (Join-Path $Dir 'UnityPlayer.dll'))) { return $null }
    $player = Join-Path $Dir 'UnityPlayer.dll'
    try {
        if ((Get-PeBitness $player) -ne $Bitness) { return $null }
    } catch { return $null }
    $blocked = @('d3d12.dll','d3d11.dll','dxgi.dll','d3d9.dll','d3d8.dll','opengl32.dll','vulkan-1.dll')
    foreach ($b in $blocked) {
        if ((Test-Path -LiteralPath (Join-Path $Dir $b)) -and (Get-IsReShadeProxy (Join-Path $Dir $b))) {
            return $null
        }
    }
    # Unity bundles every backend (D3D11/D3D12/Vulkan/OpenGL); the default Windows
    # player is D3D11, and the folder already carries no third-party proxy, so the
    # DXGI hook route is the right default. users can force another API.
    return [pscustomobject]@{ Item = 'UnityPlayer.dll'; Api = 'dxgi'; Label = 'Unity (DirectX 11/12)'; Via = 'engine' }
}

function Get-ApiFromSiblings {
    # games whose .exe is a launcher/stub (zero graphics imports) keep the real
    # renderer in a sibling engine DLL (e.g. Watch Dogs 2: WatchDogs2.exe is a
    # stub; Disrupt_64.dll imports d3d11.dll). As the very last fallback, scan the
    # import tables of the largest DLLs beside the exe and report the first hit.
    param([string]$Dir, [int]$Bitness)
    try { $dlls = @(Get-ChildItem -LiteralPath $Dir -Filter '*.dll' -File -ErrorAction SilentlyContinue) } catch { $dlls = @() }
    if ($dlls.Count -eq 0) { return $null }
    $blocked = @('dxgi.dll','d3d12.dll','d3d11.dll','d3d10.dll','d3d10_1.dll','d3d9.dll','d3d8.dll','opengl32.dll','vulkan-1.dll','dinput8.dll','nvngx_dlss.dll','nvngx_dlssnr.dll','nvngx_dlssg.dll','nvngx_dlssd.dll','sl.interposer.dll','sl.common.dll')
    $cands = $dlls | Where-Object {
        $_.Length -ge 262144 -and
        $blocked -notcontains $_.Name.ToLower() -and
        $_.Name -notmatch '^(sl\.|nvngx|sl\.)' -and
        -not (Get-IsReShadeProxy $_.FullName)
    } | Sort-Object Length -Descending | Select-Object -First 12
    foreach ($d in $cands) {
        if ((Get-PeBitness $d.FullName) -ne $Bitness) { continue }
        $imports = Get-AsciiImports -Path $d.FullName
        if (-not $imports -or $imports.Count -eq 0) { continue }
        $r = Get-ApiFromNames -Imports $imports -Bitness $Bitness
        if ($r) { $r.via = 'sibling:' + $d.Name; return $r }
    }
    return $null
}

function Get-ReShadeInfo {
    param([string]$Dir)
    $hooks = @('dxgi.dll','d3d12.dll','d3d11.dll','d3d9.dll','opengl32.dll','dinput8.dll')
    foreach ($h in $hooks) {
        $p = Join-Path $Dir $h
        if ((Test-Path -LiteralPath $p) -and (Get-IsReShadeProxy $p)) {
            return [pscustomobject]@{ Installed = $true; File = $h; Kind = 'proxy'; Version = (Get-FileProductVersion $p) }
        }
    }
    return [pscustomobject]@{ Installed = $false; File = $null; Kind = $null; Version = $null }
}

function Get-GameScan {
    param([string]$GameDir)
    $candidates = New-Object System.Collections.Generic.List[object]
    $undetected = New-Object System.Collections.Generic.List[object]
    $exeRoot = $GameDir
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($GameDir)
    $depth = 0
    while ($queue.Count -gt 0 -and $depth -lt 4) {
        $cur = $queue.Dequeue()
        try { $items = Get-ChildItem -LiteralPath $cur -File -Force -ErrorAction SilentlyContinue } catch { $items = @() }
        if ($items -eq $null) { $items = @() }
        foreach ($it in $items) {
            if ($it.Extension -ne '.exe') { continue }
            if ($it.Name -match $Script:NOT_A_GAME) { continue }
            if ($it.Name -match '\.(log|cfg)$') { continue }
            $bitness = Get-PeBitness $it.FullName
            if (-not $bitness) { continue }
$detected = Get-DetectedApi $it.FullName $bitness
            if (-not $detected) {
                $detected = Get-ApiFromEngine -Dir $cur -Bitness $bitness
            }
            if (-not $detected) {
                $detected = Get-ApiFromSiblings -Dir $cur -Bitness $bitness
            }
            if (-not $detected) {
                $undetected.Add([pscustomobject]@{ Path=$it.FullName; Name=$it.Name; Size=$it.Length; Depth=$depth; Bitness=$bitness; Api=$null; Label='undetected'; Via='undetected' })
                continue
            }
            $wrapped = Test-VulkanWrapper -Dir $cur -Api $detected.api -Bitness $bitness
            $api    = if ($wrapped) { 'vulkan' } else { $detected.api }
            $label  = if ($wrapped) { 'Vulkan' } else { $detected.label }
            $via    = if ($wrapped) { 'vulkan-wrapper' } else { $detected.via }
            $candidates.Add([pscustomobject]@{ Path=$it.FullName; Name=$it.Name; Size=$it.Length; Depth=$depth; Bitness=$bitness; Api=$api; Label=$label; Via=$via; Dx12=($label -eq 'DirectX 12') })
        }
        $subDirs = @()
        try { $subDirs = Get-ChildItem -LiteralPath $cur -Directory -Force -ErrorAction SilentlyContinue } catch {}
        if ($subDirs -eq $null) { $subDirs = @() }
        foreach ($d in $subDirs) {
            if ($Script:SKIP_DIRS -contains $d.Name.ToLower()) { continue }
            if ($depth -lt 2) { $queue.Enqueue($d.FullName) }
        }
        $depth++
    }

$sorted = @($candidates.ToArray()) | Sort-Object -Property @{ Expression = { if ($_.Dx12) {0} else {1} } },
                                      @{ Expression = 'Depth' }, 
                                      @{ Expression = { -$_.Size } }
    $chosen = $null
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $combined = @($sorted) + @($undetected.ToArray())
    # If this folder already has a DLSS5 install, trust the exe recorded in its
    # manifest: a launcher/helper sitting next to the real game exe (e.g. a mod
    # manager) must not win the size heuristic and get verified/patched instead.
    $manExe = Get-ManifestProp (Get-OldManifest $GameDir) 'exe'
    if ($manExe) {
        foreach ($c in $combined) {
            if ($c.Name -ieq $manExe) { $chosen = $c; break }
        }
    }
    if (-not $chosen) {
        foreach ($c in $combined) {
            if ($seen.Add($c.Name.ToLower())) { $chosen = $c; break }
        }
    }
    if ($chosen) {
        foreach ($c in $combined) {
            $c | Add-Member -NotePropertyName Main -NotePropertyValue ([bool]($c.Path -eq $chosen.Path)) -Force
        }
    }
    $reshade = $null
    if ($chosen) { $reshade = Get-ReShadeInfo (Split-Path -Parent $chosen.Path) }
    return [pscustomobject]@{
        GameDir = $GameDir
        Chosen  = $chosen
        Candidates = $combined
        ReShade = $reshade
HasNativeDlss = ((Test-Path (Join-Path $GameDir 'sl.interposer.dll')) -or
                         (Test-Path (Join-Path $GameDir 'sl.dlss.dll')))
    }
}

# ---------------------------------------------------------------------------
# kit
# ---------------------------------------------------------------------------
function Get-Sources {
    # merged sources.json over defaults
    $src = @{} 
    $Script:SourceDefaults.GetEnumerator() | ForEach-Object { $src[$_.Key] = $_.Value }
    $cfg = Join-Path $Script:Root 'sources.json'
    if (Test-Path -LiteralPath $cfg) {
        try {
            $j = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { if ($p.Value) { $src[$p.Name] = $p.Value } }
        } catch { Write-Warn "sources.json ignored: $_" }
    }
    return $src
}

function New-Kit {
    Write-Step "Building kit in $Script:Kit"
    $src = Get-Sources
    $require = @{
        chicken = (Join-Path $src.chicken 'deep-fried-chicken.addon64')
        feed    = (Join-Path $src.rpcs3 'dlss5-feed.addon64')
        renodx  = (Join-Path $src.rpcs3 'renodx-dlss5.addon64')
        dlssdll = (Join-Path $src.rpcs3 'nvngx_dlss.dll')
        dlssnr  = (Join-Path $src.rpcs3 'nvngx_dlssnr.dll')
        dxgi    = (Join-Path $src.gta 'dxgi.dll')
        feedfx  = (Join-Path $src.rpcs3 'reshade-shaders\Shaders\DLSS5_Feed.fx')
        kernel  = (Join-Path $src.rpcs3 'reshade-shaders\Shaders\lumenite_Kernel.fx')
    }
    foreach ($k in $require.Keys) {
        if (-not (Test-Path -LiteralPath $require[$k])) { Fail "Missing source for '$k': $($require[$k]). Put the paths into sources.json or place the file at the known location." }
    }

$dirs = @('addons','chicken','renodx','runtime','plugins','reshade','reshade-vulkan','host64','shaders','dgvoodoo','mfgunlock')
    foreach ($d in $dirs) { New-Item -ItemType Directory -Path (Join-Path $Script:Kit $d) -Force | Out-Null }

    $manifest = [ordered]@{}
    $copy = @{}
    $copy['addons\dlss5-feed.addon64'] = $require.feed
    foreach ($n in @('dlss5-feed.addon32','host64\dlss5-feed-host64.exe')) {
        $src32 = Join-Path $src.rpcs3 $n
        if (Test-Path -LiteralPath $src32) { $copy[$n] = $src32 }
        else {
            $existing = Join-Path $Script:Kit $n
            if (Test-Path -LiteralPath $existing) { $copy[$n] = $existing }
            else { Write-Warn "no source for optional '$n' and no prior kit copy - skipped" }
        }
    }
    $copy['chicken\deep-fried-chicken.addon64'] = $require.chicken
    $copy['chicken\deep-fried-chicken-nvngx.dll'] = (Join-Path $src.chicken 'deep-fried-chicken-nvngx.dll')
    $copy['renodx\renodx-dlss5.addon64'] = $require.renodx
    $copy['runtime\nvngx_dlss.dll'] = $require.dlssdll
    $copy['runtime\nvngx_dlssnr.dll'] = $require.dlssnr
    $copy['plugins\deep-fried-chicken-nvngx.dll'] = (Join-Path $src.chicken 'deep-fried-chicken-nvngx.dll')
    $copy['reshade\dxgi.dll'] = $require.dxgi
$copy['shaders\DLSS5_Feed.fx'] = $require.feedfx
    $copy['shaders\lumenite_Kernel.fx'] = $require.kernel
    # shaders - ship the whole feeder shader package (LumeniteFX/vort providers,
    # include/ + Includes/ + DrawText.fxh) so every MV provider actually compiles
    $shRoot = Join-Path $src.rpcs3 'reshade-shaders\Shaders'
    if (Test-Path -LiteralPath $shRoot) {
        foreach ($f in @(Get-ChildItem -LiteralPath $shRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.fx','.fxh' })) {
            $copy["shaders\$($f.Name)"] = $f.FullName
        }
        foreach ($sub in @('include','Includes')) {
            $s = Join-Path $shRoot $sub
            if (Test-Path -LiteralPath $s) {
                Get-ChildItem -LiteralPath $s -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $copy["shaders\$($_.FullName.Substring($shRoot.Length).TrimStart('\'))"] = $_.FullName
                }
            }
        }
    }
    $dt = Join-Path $src.shadercore 'DrawText.fxh'
    if (Test-Path -LiteralPath $dt) { $copy['shaders\DrawText.fxh'] = $dt }
    else { Write-Warn "no source for optional 'shaders\DrawText.fxh' (set shadercore) - lumenite_Kernel.fx will not compile" }
if (Test-Path -LiteralPath (Join-Path $src.reshadeVk 'ReShade64.dll')) {
        foreach ($n in @('ReShade64.dll','ReShade64.json','ReShade32.dll','ReShade32.json')) {
            $p = Join-Path $src.reshadeVk $n
            if (Test-Path -LiteralPath $p) { $copy["reshade-vulkan\$n"] = $p }
        }
    }

    $dv32 = Join-Path $src.dgvoodoo 'MS\x86\D3D9.dll'
    if (Test-Path -LiteralPath $dv32) {
        foreach ($n in @('D3D8.dll','D3D9.dll')) {
            $p = Join-Path $src.dgvoodoo "MS\x86\$n"
            if (Test-Path -LiteralPath $p) { $copy["dgvoodoo\$n"] = $p }
        }
        foreach ($n in @('dgVoodoo.conf','dgVoodooCpl.exe')) {
            $p = Join-Path $src.dgvoodoo $n
            if (Test-Path -LiteralPath $p) { $copy["dgvoodoo\$n"] = $p }
        }
    }

    # 32-bit ReShade hook (deployed as dxgi.dll for 32-bit D3D games)
    $rs32 = Join-Path $src.reshade32 'ReShade32.dll'
    if (Test-Path -LiteralPath $rs32) { $copy['reshade\dxgi-x86.dll'] = $rs32 }
    else {
        $existing = Join-Path $Script:Kit 'reshade\dxgi-x86.dll'
        if (Test-Path -LiteralPath $existing) { $copy['reshade\dxgi-x86.dll'] = $existing }
        else { Write-Warn "no source for optional 'reshade\dxgi-x86.dll' and no prior kit copy - 32-bit ReShade hook skipped" }
    }

    # MFG Unlock (mavismmg/MFGAdaUnlock-RenoDx) - ReShade addon that unlocks 3x/4x/6x on
    # RTX 40 with the temporal midpoint correction, in-memory (no proxy rename needed).
    $mfgAddonSrc = Join-Path $src.mfgunlock 'renodx-mfgunlock.addon64'
    if (Test-Path -LiteralPath $mfgAddonSrc) { $copy['mfgunlock\renodx-mfgunlock.addon64'] = $mfgAddonSrc }
    else {
        $existingAddon = Join-Path $Script:Kit 'mfgunlock\renodx-mfgunlock.addon64'
        if (Test-Path -LiteralPath $existingAddon) { $copy['mfgunlock\renodx-mfgunlock.addon64'] = $existingAddon }
        else { Write-Warn "no source for optional 'mfgunlock\renodx-mfgunlock.addon64' and no prior kit copy - the -MFGAddon unlock is unavailable" }
    }

foreach ($rel in $copy.Keys) {
        $dest = Join-Path $Script:Kit $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath $copy[$rel] -Destination $dest -Force
        $hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
        $manifest[($rel -replace '\\','/')] = [ordered]@{ hash = $hash; version = (Get-FileProductVersion $dest); size = (Get-Item -LiteralPath $dest).Length }
    }
    $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $Script:Kit 'kit.json') -Encoding UTF8
    Write-Ok "Kit ready: $($manifest.Count) files"
}

function Test-Kit {
    $json = Join-Path $Script:Kit 'kit.json'
    if (-not (Test-Path -LiteralPath $json)) { return $false }
    $manifest = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
    foreach ($prop in $manifest.PSObject.Properties) {
        $p = Join-Path $Script:Kit ($prop.Name -replace '/','\')
        if (-not (Test-Path -LiteralPath $p)) { Write-Err "kit missing: $($prop.Name)"; return $false }
    }
    return $true
}

function Invoke-ListKit {
    $json = Join-Path $Script:Kit 'kit.json'
    if (-not (Test-Path -LiteralPath $json)) { Fail "No kit found. Run -BuildKit first." }
    $manifest = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
    Write-Step "Kit contents:"
    foreach ($prop in $manifest.PSObject.Properties) {
        $h = [string]$prop.Value.hash
        Write-Host ("  {0,-34} v={1,-16} sha256={2}" -f $prop.Name, $prop.Value.version, $h.Substring(0,12))
    }
}

# ---------------------------------------------------------------------------
# INI merging (preserve existing content, upsert keys)
# ---------------------------------------------------------------------------
function Set-IniValues {
    param([string]$Path, [hashtable]$Sections)
    $enc = New-Object System.Text.UTF8Encoding($false)
    if (-not (Test-Path -LiteralPath $Path)) {
        $sb = New-Object System.Text.StringBuilder
        foreach ($sec in $Sections.Keys) {
            [void]$sb.AppendLine('[' + $sec + ']')
            foreach ($k in $Sections[$sec].Keys) { [void]$sb.AppendLine($k + '=' + $Sections[$sec][$k]) }
            [void]$sb.AppendLine('')
        }
        [System.IO.File]::WriteAllText($Path, $sb.ToString(), $enc)
        return
    }
    $lines = New-Object System.Collections.Generic.List[string]
    ([System.IO.File]::ReadAllLines($Path) | ForEach-Object { $lines.Add($_) }) | Out-Null
    foreach ($sec in $Sections.Keys) {
        $header = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*\[([^\]]+)\]\s*$' -and $matches[1] -ieq $sec) { $header = $i; break }
        }
        $keys = $Sections[$sec]
        if ($header -ge 0) {
            $next = $lines.Count
            for ($i = $header + 1; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*\[[^\]]+\]\s*$' -and $lines[$i] -ne $lines[$header]) { $next = [Math]::Min($next, $i) }
            }
            $insertAfter = $header
            foreach ($k in $keys.Keys) {
                $idx = -1
                for ($i = $header + 1; $i -lt $next; $i++) {
                    if ($lines[$i] -match ('^\s*' + [regex]::Escape($k) + '\s*=')) { $idx = $i; break }
                }
                if ($idx -ge 0) {
                    $lines[$idx] = $k + '=' + $keys[$k]
                } else {
                    $lines.Insert($insertAfter + 1, $k + '=' + $keys[$k])
                    $next++
                    $insertAfter++
                }
            }
        } else {
            $lines.Add('[' + $sec + ']')
            foreach ($k in $keys.Keys) { $lines.Add($k + '=' + $keys[$k]) }
            $lines.Add('')
        }
    }
[System.IO.File]::WriteAllLines($Path, $lines, $enc)
}

function Remove-IniSection {
    param([string]$Path, [string]$Section)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lines = New-Object System.Collections.Generic.List[string]
    $removing = $false
    foreach ($ln in [System.IO.File]::ReadAllLines($Path)) {
        if ($ln -match '^\s*\[([^\]]+)\]\s*$') {
            $removing = ($matches[1] -ieq $Section)
            if ($removing) { continue }
        }
        if (-not $removing) { $lines.Add($ln) }
    }
    [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------------------
# provider config generation
# ---------------------------------------------------------------------------
function Get-DfcConfig {
    param([int]$Layers, [int]$WorkPercent, [int]$StyleIndex, [int]$NrxPreset, [double]$NrxIntensity, [bool]$CleanFry, [bool]$TextureBoost)
    $style = switch ($StyleIndex) { 1 { 1 } 2 { 2 } default { 0 } }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('config_schema=11')
    [void]$sb.AppendLine('arm=1')
    [void]$sb.AppendLine('hook_mode=3')
    [void]$sb.AppendLine('early_load_policy=0')
    [void]$sb.AppendLine('safe_neutral_start=0')
    [void]$sb.AppendLine('menu_accent_rgb=4364026')
    [void]$sb.AppendLine('ui_correction_mode=0')
    [void]$sb.AppendLine('toggle_hotkey_vk=0')
    [void]$sb.AppendLine('toggle_hotkey_modifiers=0')
    [void]$sb.AppendLine('enabled=1')
    [void]$sb.AppendLine("layers=$Layers")
    [void]$sb.AppendLine("neural_work_percent=$WorkPercent")
    [void]$sb.AppendLine('neural_work_divisor=1')
    [void]$sb.AppendLine('neural_placement_mode=0')
    [void]$sb.AppendLine('frame_generation_coexistence=1')
    [void]$sb.AppendLine('preserve_native_tone_color=0')
    [void]$sb.AppendLine('preserve_native_tone_color_strength=0.000')
    [void]$sb.AppendLine('creative_lut=0')
    [void]$sb.AppendLine('creative_lut_strength=1.000')
    [void]$sb.AppendLine("clean_fry_enabled=$([int]$CleanFry)")
    [void]$sb.AppendLine('clean_fry_cleanup_strength=0.650')
    [void]$sb.AppendLine('clean_fry_detail_retention=0.850')
    [void]$sb.AppendLine('motion_stability_enabled=1')
    [void]$sb.AppendLine('motion_stability_strength=0.200')
    [void]$sb.AppendLine('motion_stability_detail_retention=1.000')
    [void]$sb.AppendLine("texture_boost=$([int]$TextureBoost)")
    [void]$sb.AppendLine('texture_boost_strength=1.000')
    [void]$sb.AppendLine('adaptive_scene_white=1')
    [void]$sb.AppendLine('adaptive_cascade_style=0')
    [void]$sb.AppendLine('adaptive_cascade_quality=3')
    [void]$sb.AppendLine('adaptive_cascade_maximum_depth=4')
    [void]$sb.AppendLine('adaptive_cascade_novelty=0.8500')
    [void]$sb.AppendLine('adaptive_cascade_reinforcement=0.5500')
    [void]$sb.AppendLine('adaptive_cascade_detail_budget=0.8000')
    [void]$sb.AppendLine('adaptive_cascade_temporal=0.5500')
    [void]$sb.AppendLine('adaptive_cascade_motion_rejection=0.7500')
    [void]$sb.AppendLine('adaptive_cascade_depth_rejection=0.8000')
    [void]$sb.AppendLine('adaptive_cascade_disocclusion_rejection=0.9000')
    [void]$sb.AppendLine('adaptive_cascade_residual_energy_threshold=0.001500')
    [void]$sb.AppendLine('adaptive_cascade_debug_view=0')
    [void]$sb.AppendLine('adaptive_cascade_debug_stage=3')
    [void]$sb.AppendLine('adaptive_cascade_foundation_structure=1.2000')
    [void]$sb.AppendLine('adaptive_cascade_foundation_tone=0.3500')
    [void]$sb.AppendLine('adaptive_cascade_foundation_gain=1.0000')
    [void]$sb.AppendLine('adaptive_cascade_foundation_excitation=0.0000')
    [void]$sb.AppendLine('adaptive_cascade_foundation_renderer_anchor=0.0000')
    [void]$sb.AppendLine('adaptive_cascade_foundation_intensity=1.1000')
    [void]$sb.AppendLine('adaptive_cascade_foundation_response_weight=0.0000')
    [void]$sb.AppendLine('adaptive_cascade_foundation_excitation_limit=0.0000')
    [void]$sb.AppendLine('adaptive_cascade_foundation_neural_feedback=0.0000')
    [void]$sb.AppendLine('adaptive_cascade_foundation_contribution_headroom=1.0000')
    [void]$sb.AppendLine('adaptive_cascade_meso_structure=1.4000')
    [void]$sb.AppendLine('adaptive_cascade_meso_tone=0.1000')
    [void]$sb.AppendLine('adaptive_cascade_meso_gain=1.0000')
    [void]$sb.AppendLine('adaptive_cascade_meso_excitation=0.7000')
    [void]$sb.AppendLine('adaptive_cascade_meso_renderer_anchor=0.1000')
    [void]$sb.AppendLine('adaptive_cascade_meso_intensity=1.3500')
    [void]$sb.AppendLine('adaptive_cascade_meso_response_weight=0.9000')
    [void]$sb.AppendLine('adaptive_cascade_meso_excitation_limit=0.1000')
    [void]$sb.AppendLine('adaptive_cascade_meso_neural_feedback=0.2000')
    [void]$sb.AppendLine('adaptive_cascade_meso_contribution_headroom=1.8000')
    [void]$sb.AppendLine('adaptive_cascade_fine_structure=1.6500')
    [void]$sb.AppendLine('adaptive_cascade_fine_tone=0.0500')
    [void]$sb.AppendLine('adaptive_cascade_fine_gain=0.8000')
    [void]$sb.AppendLine('adaptive_cascade_fine_excitation=0.6500')
    [void]$sb.AppendLine('adaptive_cascade_fine_renderer_anchor=0.1500')
    [void]$sb.AppendLine('adaptive_cascade_fine_intensity=1.5500')
    [void]$sb.AppendLine('adaptive_cascade_fine_response_weight=1.0000')
    [void]$sb.AppendLine('adaptive_cascade_fine_excitation_limit=0.0800')
    [void]$sb.AppendLine('adaptive_cascade_fine_neural_feedback=0.4000')
    [void]$sb.AppendLine('adaptive_cascade_fine_contribution_headroom=2.0000')
    [void]$sb.AppendLine('adaptive_cascade_micro_structure=1.9000')
    [void]$sb.AppendLine('adaptive_cascade_micro_tone=0.0000')
    [void]$sb.AppendLine('adaptive_cascade_micro_gain=0.6000')
    [void]$sb.AppendLine('adaptive_cascade_micro_excitation=0.5500')
    [void]$sb.AppendLine('adaptive_cascade_micro_renderer_anchor=0.2000')
    [void]$sb.AppendLine('adaptive_cascade_micro_intensity=1.8000')
    [void]$sb.AppendLine('adaptive_cascade_micro_response_weight=1.0000')
    [void]$sb.AppendLine('adaptive_cascade_micro_excitation_limit=0.0600')
    [void]$sb.AppendLine('adaptive_cascade_micro_neural_feedback=0.5500')
    [void]$sb.AppendLine('adaptive_cascade_micro_contribution_headroom=2.0000')
    [void]$sb.AppendLine('scene_paper_white_scale=1.765')
    [void]$sb.AppendLine('hdr_transfer_strength=1.000')
    [void]$sb.AppendLine('color_strength=1.000')
    [void]$sb.AppendLine('detail_color_coupling=0.000')
    for ($i = 1; $i -le 30; $i++) {
        [void]$sb.AppendLine("layer_${i}_nr_preset=$NrxPreset")
        [void]$sb.AppendLine("layer_${i}_nr_style=$style")
        [void]$sb.AppendLine("layer_${i}_intensity={0:F3}" -f $NrxIntensity)
        [void]$sb.AppendLine("layer_${i}_local_tone=1.000")
        [void]$sb.AppendLine("layer_${i}_local_structure=1.000")
        [void]$sb.AppendLine("layer_${i}_skin_structure=0.500")
        [void]$sb.AppendLine("layer_${i}_auto_mask=1")
        [void]$sb.AppendLine("layer_${i}_ui_correction=1")
        [void]$sb.AppendLine("layer_${i}_depth_convention=0")
        [void]$sb.AppendLine("layer_${i}_mvec_scale_x_multiplier=1.000")
        [void]$sb.AppendLine("layer_${i}_mvec_scale_y_multiplier=1.000")
    }
    for ($i = 1; $i -le 29; $i++) {
        [void]$sb.AppendLine("depth_bridge_${i}_enabled=0")
        [void]$sb.AppendLine("depth_bridge_${i}_mode=0")
        [void]$sb.AppendLine("depth_bridge_${i}_strength=0.500")
        [void]$sb.AppendLine("depth_bridge_${i}_start=0.650")
        [void]$sb.AppendLine("depth_bridge_${i}_far_limit=1.000")
        [void]$sb.AppendLine("depth_bridge_${i}_curve=2.000")
        [void]$sb.AppendLine("depth_bridge_${i}_edge_protection=1.000")
    }
    [void]$sb.AppendLine('residual_shadow_multiplier=1.000')
    [void]$sb.AppendLine('residual_light_multiplier=1.000')
    [void]$sb.AppendLine('glow_suppression=0.000')
    return $sb.ToString()
}

function Get-FeedConfig {
    param([int]$WorkPercent, [int]$Warmup)
    return @"
enabled=1
mode=2
hdr=-1
depth_inverted=-1
flags=-1
reset_every=0
warmup_rebuild=$Warmup
rebuild=0
log_frames=3
create_delay=60
preset=0
work_resolution=$WorkPercent
mv_scale_x=1.000
mv_scale_y=1.000
host_window=0
async_home=1
"@
}

function Get-PresetContent {
    $presetPath = $null
    return @'
Techniques=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx
TechniqueSorting=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx,DLSS5_Feed_Debug@DLSS5_Feed.fx,Lumenite_AnamorphicBloom@lumenite_AnamorphicBloom.fx,Lumenite_LSAO@lumenite_LSAO.fx,Lumenite_QuantAO@lumenite_QuantAO.fx,Lumenite_QuantMotion@lumenite_QuantMotion.fx,Lumenite_RTAO@lumenite_RTAO.fx,LUMENITE_SSSR@lumenite_SSSR.fx,Lumenite_TRAA@lumenite_TRAA.fx,vort_MotionEffects@vort_Motion.fx

[DLSS5_Feed.fx]
DEBUG_VIEW=0
DEPTH_TOLERANCE=0.100000
GEOM_AGREE_PX=1.500000
GEOM_DYNAMIC_MARGIN=0.250000
GEOM_ENABLE=0
GEOM_MASK_REJECTED=0.350000
GEOM_OUTLIER_PX=4.000000
GEOM_PARALLAX=0.020000
LUMA_TOLERANCE=0.250000
MASK_STRENGTH=1.000000
MV_CONSISTENCY=1.400000
MV_LOWRES_FILTER=0
MV_PROVIDER_INFO=0
MV_SCALE=1.000000
MV_SIGN=1.000000,1.000000
MV_VALIDATE=1
STATIC_BIAS=0.150000
STATIC_MIN_CONTRAST=0.012000
VALIDATE_DEPTH=1
VALIDATE_LUMA=0
VALIDATE_MV=1
VALIDATE_STATIC=1
'@
}

# ---------------------------------------------------------------------------
# journal / backup
# ---------------------------------------------------------------------------
function Get-ManifestPath { param($GameDir) Join-Path $GameDir '_DLSS5_Backup\manifest.json' }

function Get-OldManifest { param($GameDir)
    $p = Get-ManifestPath $GameDir
    if (Test-Path -LiteralPath $p) { try { return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) } catch {} }
    return $null
}

# Read a manifest field tolerantly. Older tool generations stored identity
# fields ('exe','api','apiLabel','bit') under 'game' and never wrote
# 'provider'/'host64'/'bit'/'feeder', so plain property access throws under
# strict mode. Returns $null when the field is absent.
function Get-ManifestProp {
    param([object]$Manifest, [string]$Name)
    if ($null -eq $Manifest) { return $null }
    $p = $Manifest.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    if ($Name -eq 'bit') {
        $b = $Manifest.PSObject.Properties['bitness']
        if ($b) { return $b.Value }
    }
    $g = $Manifest.PSObject.Properties['game']
    if ($g -and $g.Value) {
        $gp = $g.Value.PSObject.Properties[$Name]
        if ($gp) { return $gp.Value }
        if ($Name -eq 'bit') {
            $gb = $g.Value.PSObject.Properties['bitness']
            if ($gb) { return $gb.Value }
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
function Install-Stack {
    param($GameDir, $ApiOverride, $Provider, $Passes, $WorkPercent, $StyleIndex, $NrxPreset, $NrxIntensity, $SymMv, $SymCleanFry, $SymTexBoost, $SymUplift, $FeederMode, $ExeName, $MfgAddon = $false, $LoadFromDllMain = $false)
    if (-not (Test-Path -LiteralPath $Script:Kit)) { Fail "No kit folder. Run: .\DLSS5-Swapper.ps1 -BuildKit" }
    if (-not (Test-Kit)) { Fail "Kit incomplete. Rebuild with: .\DLSS5-Swapper.ps1 -BuildKit" }

    $scan = Get-GameScan $GameDir
    $exe = $null
    if ($ExeName) {
        $exe = $scan.Candidates | Where-Object { $_.Name -ieq $ExeName } | Select-Object -First 1
        if (-not $exe) { Fail "Executable '$ExeName' not found in $GameDir" }
    } else {
        $exe = $scan.Chosen
        if (-not $exe) { Fail "No game executable detected in '$GameDir'." }
    }
    $exeDir = Split-Path -Parent $exe.Path
    Write-Step "Game: $($exe.Name) | bitness $($exe.Bitness) | detected: $($exe.Label) ($($exe.Via))"

$api = $ApiOverride
    if ($api -eq 'auto') {
        if (-not $exe.Api) {
            Fail "API could not be detected for $($exe.Name). Pass -Api (e.g. -Api d3d12 or -Api vulkan)."
        }
        $api = $exe.Api
        # Hybrid games: some ship both D3D11/12 and a Vulkan renderer (e.g. RDR2,
        # GTA V, Hitman). If D3D was detected but the exe also imports vulkan-1.dll
        # and a ReShade Vulkan layer is registered, the game's actual presenting
        # renderer is usually Vulkan - route through the layer, NOT a local dxgi
        # proxy. A local dxgi.dll would load a second ReShade into the process and
        # the two instances fight ("Another ReShade instance was already loaded...");
        # the D3D12/Vulkan journal also shows RDR2 runs with <API>kSettingAPI_Vulkan</API>.
        #
        # Only a REAL import (import or delay-load table) triggers the flip. A bare
        # vkCreateInstance string elsewhere in the file is not enough - e.g.
        # BeamNG.drive.x64.exe embeds CEF/ANGLE Vulkan blobs but presents via D3D12.
        if ($api -eq 'dxgi') {
            $importsVulkan = (Get-AsciiImports -Path $exe.Path) -contains 'vulkan-1.dll'
            if ($importsVulkan) {
                $hasVkLayer = (Test-Path -LiteralPath (Join-Path 'C:\ProgramData\ReShade' 'ReShade64.dll')) -or
                              (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.dlss5vulkanlayer\ReShade64.dll'))
                if ($hasVkLayer) {
                    Write-Step "Detected a Vulkan-capable hybrid (Dxgi + vulkan-1.dll import) and a registered ReShade Vulkan layer; routing through the Vulkan layer for $($exe.Name)."
                    $api = 'vulkan'
                }
            }
        }
    }
    switch ($api) {
        'd3d10' { $api = 'dxgi'; $label = 'DirectX 10' }
        'd3d11' { $api = 'dxgi'; $label = 'DirectX 11' }
        'd3d12' { $api = 'dxgi'; $label = 'DirectX 12' }
        'dxgi'  { $label = 'DirectX 11/12' }
        'd3d9'  { $label = 'DirectX 9' }
        'd3d8'  { $label = 'DirectX 8' }
        'vulkan' { $label = 'Vulkan' }
        'opengl' { $label = 'OpenGL' }
        default  { $label = $api }
    }
    Write-Step "Render API: $label"

if ($api -eq 'opengl') {
        Write-Warn "OpenGL needs an opengl32.dll ReShade proxy; none is bundled."
        if (-not $Force) { Fail "Aborting (use -Force to copy files anyway)." }
    }
    if ($Provider -eq 'renodx' -and $api -eq 'vulkan') {
        # RenoDX DLSS5 Generic detours the D3D12 NGX evaluate. On Vulkan the
        # D3D12 device that feeds it is manufactured in-process by the DLSS5-
        # Feeder addon (the consumer registers when the Feeder is present).
        # Without the Feeder, the addon has nothing to hook ('No add-on was
        # registered ... Unloading again' on No Man's Sky). This is exactly the
        # supported config the DLSS 5 Swapper ships on Vulkan (Feeder + RenoDX).
        $feedAddon64 = Join-Path $Script:Kit 'addons\dlss5-feed.addon64'
        if (-not (Test-Path -LiteralPath $feedAddon64)) {
            if (-not $Force) {
                Fail "renodx on a Vulkan game needs the DLSS5-Feeder transport, but kit\addons\dlss5-feed.addon64 is missing. Rebuild the kit (-BuildKit), or use -Provider chicken, or -Force to copy files anyway."
            }
        } else {
            Write-Step "RenoDX on Vulkan: DLSS5-Feeder will be enabled (provides the D3D12 context the consumer needs to register)."
        }
    }
# 32-bit games run the neural stack in a 64-bit host helper (feeder host64)
    $is32Bit = ($exe.Bitness -ne 64)
    $host64 = $false
    if ($is32Bit) {
        $has32 = (Test-Path -LiteralPath (Join-Path $Script:Kit 'addons\dlss5-feed.addon32')) -and
                 (Test-Path -LiteralPath (Join-Path $Script:Kit 'host64\dlss5-feed-host64.exe'))
        if ($has32) {
            Write-Step "32-bit game: neural stack runs in the 64-bit host helper (host64\)"
            $host64 = $true
        } else {
            Write-Warn "32-bit game ($($exe.Name)) but the 32-bit kit pieces are missing (addons\dlss5-feed.addon32, host64\dlss5-feed-host64.exe). Rebuild the kit."
            if (-not $Force) {
                Fail "This build targets 64-bit games only ($($exe.Name) is $($exe.Bitness)-bit)."
            }
        }
    }

    if ($api -eq 'd3d8' -or $api -eq 'd3d9') {
        $hasDg = (Test-Path -LiteralPath (Join-Path $Script:Kit 'dgvoodoo\D3D9.dll'))
        if ($is32Bit -and $hasDg) {
            Write-Step "DirectX $($api.Substring(3)) game: dgVoodoo2 (D3D8/9 -> D3D11) will be deployed next to the exe so the stack can hook it."
        } else {
            Write-Warn "DirectX 8/9 needs dgVoodoo2 -> D3D11 translation before the DLSS5 stack can hook it."
            if (-not $Force) { Fail "Aborting (use -Force to copy files anyway)." }
        }
    }

    # Feeder decision. The DLSS5-Feeder addon manufactures the DLSS 5 NGX
    # contract and provides the consumer's private D3D12 device. On Vulkan,
    # ReShade runs through the machine/user-wide layer with no D3D12 context of
    # its own; the Feeder is what lets the consumer (renodx or chicken) register
    # at all in a Vulkan process. This matches the DLSS 5 Swapper app, which
    # always routes Vulkan through the Feeder regardless of native DLSS.
    $vulkanApi = ($api -eq 'vulkan')
    $native = (Test-Path -LiteralPath (Join-Path $exeDir 'sl.interposer.dll')) -or
              (Test-Path -LiteralPath (Join-Path $exeDir 'sl.dlss.dll'))
    $useFeeder = $false
    if ($vulkanApi) {
        if ($FeederMode -eq 'off') {
            Write-Warn "-Feeder off ignored: on a Vulkan game the Feeder transport is required (without it the neural addon cannot register in the Vulkan process - see README 9.5)."
        }
        $useFeeder = $true
    }
    elseif ($FeederMode -eq 'forced') { $useFeeder = $true }
    elseif ($FeederMode -eq 'off') { $useFeeder = $false }
    else { $useFeeder = -not $native }
    if ($useFeeder) { Write-Step "Transport: DLSS5-Feeder $(if ($vulkanApi) { '(mandatory on Vulkan - provides the consumer D3D12 context)' } else { '(non-DLSS game)' })" }
    else { Write-Step "Transport: game native DLSS (Feeder skipped)" }

    # MFG Unlock addon (optional): ReShade addon build of the same in-memory approach
    # (mavismmg/MFGAdaUnlock-RenoDx). Dropped into the addon path beside the exe; it drives
    # the multiplier through the game's own FG selector plus its ReShade panel (and can go to
    # 3x/4x/6x). It is x64-only because ReShade's 64-bit hook is the only addon host we ship.
    if ($MfgAddon) {
        if (-not (Test-Path -LiteralPath (Join-Path $Script:Kit 'mfgunlock\renodx-mfgunlock.addon64'))) {
            Fail "The -MFGAddon unlock was requested but kit\mfgunlock\renodx-mfgunlock.addon64 is missing. Rebuild the kit (-BuildKit) or add the MFG Unlock release to sources.json ('mfgunlock')."
        }
        if ($exe.Bitness -ne 64) {
            Write-Warn "$($exe.Name) is a $($exe.Bitness)-bit executable but the MFG addon is x64-only - it cannot load in a 32-bit process."
            if (-not $Force) { Fail "Aborting the MFG addon install for a 32-bit game (use -Force to place it anyway)." }
        }
        Write-Step "MFG Unlock addon: renodx-mfgunlock.addon64 (ReShade panel, game menu multiplier)"
    }

    # backup journal + helpers (before touching the disk)
    $backDir = Join-Path $GameDir '_DLSS5_Backup'
    if (-not $DryRun) {
        if (Test-Path -LiteralPath $backDir) {
            if (-not $Force) { Fail "A DLSS5 backup already exists in $GameDir (use -Uninstall first, or -Force to start over)." }
            $old = Get-OldManifest $GameDir
            if ($old) {
                $oldAdded = @(Get-ManifestProp $old 'added')
                Write-Step "Reinstall (-Force): removing $($oldAdded.Count) previously-added files"
                foreach ($a in $oldAdded) {
                    if (-not $a) { continue }
                    $p = Join-Path $GameDir $a
                    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
                }
            }
        }
        New-Item -ItemType Directory -Path $backDir -Force | Out-Null
    }
    $renoHookMode = if ($RenoHooks -eq 'streamline') { '1' } else { '2' }
    $manifest = [ordered]@{
        tool = 'DLSS5-Swapper'
        date = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        game = $GameDir
        exe  = $exe.Name
        bit  = $exe.Bitness
        api  = $api
        apiLabel = $label
        provider = $Provider
        hookMode = $(if ($Provider -eq 'renodx') { $renoHookMode } else { $null })
        feeder = [bool]$useFeeder
        mfgAddon = [bool]$MfgAddon
        host64 = [bool]$host64
        added = (New-Object System.Collections.ArrayList)
        replaced = (New-Object System.Collections.ArrayList)
    }

    function Add-Replace {
        param([string]$Dest)
        if ((Test-Path -LiteralPath $Dest) -and -not $DryRun) {
            $rel = $Dest.Substring($GameDir.Length).TrimStart('\')
            $backName = (Get-Date -Format 'yyyyMMddHHmmss') + '__' + ($rel -replace '[\\/]', '_')
            Copy-Item -LiteralPath $Dest -Destination (Join-Path $backDir $backName) -Force
            [void]$manifest.replaced.Add([pscustomobject]@{ file = $rel; backup = $backName })
        }
    }

    function Install-OneFile {
        param([string]$KitRel, [string]$DestRel)
        $src = Join-Path $Script:Kit $KitRel
        if (-not (Test-Path -LiteralPath $src)) { Write-Warn "kit missing: $KitRel"; return }
        $dest = Join-Path $exeDir $DestRel
        if ($DryRun) { Write-Step "[dry] would install $DestRel"; return }
        Add-Replace $dest
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force -ErrorAction SilentlyContinue | Out-Null
        Copy-Item -LiteralPath $src -Destination $dest -Force
        [void]$manifest.added.Add($dest.Substring($GameDir.Length).TrimStart('\'))
    }

# ReShade injection (recorded so -Uninstall reverts it)
    $reshade = Get-ReShadeInfo $exeDir
    $reshadeRoute = $reshade.Installed -or ($api -eq 'vulkan')
    if (($api -eq 'd3d8' -or $api -eq 'd3d9') -and $is32Bit) {
        if ($Force) { $reshadeRoute = $true }
        elseif ($hasDg -and ($reshade.Installed -or (Test-Path -LiteralPath (Join-Path $Script:Kit 'reshade\dxgi-x86.dll')))) { $reshadeRoute = $true }
    }
    if ($api -eq 'vulkan') {
        # Vulkan does not load a proxy DLL from the executable directory. ReShade
        # runs as a machine-wide (ProgramData) or per-user (%USERPROFILE%)
        # implicit Vulkan layer registered in the HKCU registry. The per-user
        # layer is reference-counted (installs.json) so restoring one game does
        # not break another - the same contract as the DLSS 5 Swapper's
        # vulkan-layer.js.
        $vkHub = if ($is32Bit) { 'ReShade32' } else { 'ReShade64' }
        $layer = Test-Path -LiteralPath (Join-Path 'C:\ProgramData\ReShade' ($vkHub + '.dll'))
        if ($layer) {
            $reshadeRoute = $true
        } else {
            $user = Join-Path $env:USERPROFILE '.dlss5vulkanlayer'
            $userJson = Join-Path $user ($vkHub + '.json')
            $uInstalls = Join-Path $user 'installs.json'
            if (-not (Test-Path -LiteralPath (Join-Path $user ($vkHub + '.dll')))) {
                if ($DryRun) { Write-Step "[dry] would install user Vulkan layer ($vkHub)" }
                else {
                    New-Item -ItemType Directory -Path $user -Force | Out-Null
                    if (Test-Path -LiteralPath (Join-Path $Script:Kit "reshade-vulkan\$vkHub.dll")) {
                        foreach ($n in @($vkHub + '.dll', $vkHub + '.json')) {
                            Copy-Item -LiteralPath (Join-Path $Script:Kit "reshade-vulkan\$n") -Destination (Join-Path $user $n) -Force
                        }
                        New-Item -Path 'HKCU:\Software\Khronos\Vulkan\ImplicitLayers' -Force | Out-Null
                        New-ItemProperty -Path 'HKCU:\Software\Khronos\Vulkan\ImplicitLayers' -Name $userJson -Value 0 -PropertyType DWord -Force | Out-Null
                    }
                }
            }
            $reshadeRoute = $true
            if (-not $DryRun) {
                $gameKey = $GameDir.TrimEnd('\')
                $games = @()
                if (Test-Path -LiteralPath $uInstalls) {
                    try {
                        $data = Get-Content -LiteralPath $uInstalls -Raw | ConvertFrom-Json
                        $games = @($data.games | Where-Object { $_ -and ($_.TrimEnd('\') -ne $gameKey) })
                    } catch { $games = @() }
                }
                if (@($games) -notcontains $gameKey) { $games += $gameKey }
                [System.IO.File]::WriteAllText($uInstalls, (@{ version = 1; games = $games } | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }
    if ($api -eq 'dxgi') {
        $needsProxy = -not $reshade.Installed
        if ($needsProxy -and -not (Test-Path -LiteralPath (Join-Path $exeDir 'dxgi.dll'))) {
            if ($is32Bit) {
                if (Test-Path -LiteralPath (Join-Path $Script:Kit 'reshade\dxgi-x86.dll')) {
                    if ($DryRun) { Write-Step "[dry] would copy 32-bit ReShade dxgi.dll" }
                    else { Install-OneFile 'reshade\dxgi-x86.dll' 'dxgi.dll' }
                    $reshadeRoute = $true
                } else {
                    Write-Warn "32-bit D3D game: a 32-bit ReShade dxgi hook must be installed first (run the ReShade installer against $($exe.Name) - it detects 32-bit itself and enables add-on loading)."
                    if ($Force) { $reshadeRoute = $true }
                    else { Fail "No 32-bit ReShade dxgi hook present and none is bundled (rebuild the kit to get kit\reshade\dxgi-x86.dll). Install ReShade 32-bit into the game folder, then retry (or use -Force to copy the files anyway)." }
                }
            } else {
                if ($DryRun) { Write-Step "[dry] would copy ReShade dxgi.dll" }
                else { Install-OneFile 'reshade\dxgi.dll' 'dxgi.dll' }
                $reshadeRoute = $true
            }
        } elseif (-not $needsProxy) {
            Write-Step "ReShade already present: $($reshade.File) v$($reshade.Version)"
        }
    }

    if (-not $reshadeRoute -and -not $DryRun) { Fail "No ReShade injection route available. Install ReShade manually, then retry." }

    if ($DryRun) {
        Write-Step "[dry] provider=$Provider passes=$Passes work=$WorkPercent% style=$StyleIndex mvProvider=$MVProvider feeder=$useFeeder route=$reshadeRoute host64=$host64 mfgAddon=$MfgAddon"
        return
    }

# runtimes + 32-bit host helper + feeder + neural consumer
    $hostRel = if ($host64) { 'host64\' } else { '' }
    $earlyLoadAddon = $null
    $hostLoadAddon = $null

    if ($host64) {
        Install-OneFile 'host64\dlss5-feed-host64.exe' 'host64\dlss5-feed-host64.exe'
        Install-OneFile 'reshade\dxgi.dll'             'host64\dxgi.dll'
    }
    Install-OneFile 'runtime\nvngx_dlss.dll'   ($hostRel + 'nvngx_dlss.dll')
    Install-OneFile 'runtime\nvngx_dlssnr.dll' ($hostRel + 'nvngx_dlssnr.dll')
    if ($MfgAddon) { Install-OneFile 'mfgunlock\renodx-mfgunlock.addon64' 'renodx-mfgunlock.addon64' }

    if ($useFeeder) {
        if ($host64) { Install-OneFile 'addons\dlss5-feed.addon32' 'dlss5-feed.addon32' }
        else { Install-OneFile 'addons\dlss5-feed.addon64' 'dlss5-feed.addon64' }
    }

    if ($Provider -eq 'chicken') {
        Install-OneFile 'chicken\deep-fried-chicken.addon64'   ($hostRel + 'deep-fried-chicken.addon64')
        Install-OneFile 'chicken\deep-fried-chicken-nvngx.dll' ($hostRel + 'deep-fried-chicken-nvngx.dll')
        $hostLoadAddon = 'deep-fried-chicken.addon64'
        # generate chicken cfg (next to the consumer: game dir for 64-bit, host64\ for 32-bit)
        $cfgDest = Join-Path $exeDir ($hostRel + 'deep-fried-chicken.cfg')
        New-Item -ItemType Directory -Path (Split-Path -Parent $cfgDest) -Force | Out-Null
        Add-Replace $cfgDest
        $cfgText = Get-DfcConfig -Layers $Passes -WorkPercent $WorkPercent -StyleIndex $StyleIndex -NrxPreset $NrxPreset -NrxIntensity $NrxIntensity -CleanFry $SymCleanFry -TextureBoost $SymTexBoost
        [System.IO.File]::WriteAllText($cfgDest, $cfgText, (New-Object System.Text.UTF8Encoding($false)))
        [void]$manifest.added.Add($cfgDest.Substring($GameDir.Length).TrimStart('\'))
    } else {
        Install-OneFile 'renodx\renodx-dlss5.addon64' ($hostRel + 'renodx-dlss5.addon64')
        $hostLoadAddon = 'renodx-dlss5.addon64'
    }
    # A provider switch never removed the OTHER provider's add-on: ReShade loads every
    # *.addon64 found in AddonPath=.\ at startup, so a stale renodx/chicken consumer
    # kept loading (and showing its overlay tab) even after switching. Drop the disabled
    # provider's files from the game folder (and host64\ for 32-bit games) unless the
    # user originally had that file there (i.e. it is backed up in this manifest).
    $staleFiles = if ($Provider -eq 'chicken') { @('renodx-dlss5.addon64') } else { @('deep-fried-chicken.addon64','deep-fried-chicken-nvngx.dll','deep-fried-chicken.cfg') }
    foreach ($rel in $staleFiles) {
        foreach ($pfx in @('', 'host64\')) {
            $sp = Join-Path $exeDir ($pfx + $rel)
            if (-not (Test-Path -LiteralPath $sp)) { continue }
            if ($manifest.replaced | Where-Object { $_.file -ieq ($pfx + $rel) }) { continue }
            Write-Step "Removing stale $($pfx)$rel left behind by the previous provider..."
            Remove-Item -LiteralPath $sp -Force
        }
    }
    if ($LoadFromDllMain -and -not $host64) { $earlyLoadAddon = $hostLoadAddon }

    if ($useFeeder) {
        $feedDest = Join-Path $exeDir 'dlss5-feed.cfg'
        Add-Replace $feedDest
        $warmup = if ($Provider -eq 'chicken') { 0 } else { 180 }
[System.IO.File]::WriteAllText($feedDest, (Get-FeedConfig -WorkPercent $WorkPercent -Warmup $warmup), (New-Object System.Text.UTF8Encoding($false)))
        [void]$manifest.added.Add($feedDest.Substring($GameDir.Length).TrimStart('\'))
    }

    # dgVoodoo2 (DirectX 8/9 -> D3D11) for 32-bit D3D8/D3D9 games
    if (($api -eq 'd3d8' -or $api -eq 'd3d9') -and $is32Bit) {
        $dgFiles = @('D3D9.dll','dgVoodoo.conf','dgVoodooCpl.exe')
        if ($api -eq 'd3d8') { $dgFiles = @('D3D8.dll','D3D9.dll','dgVoodoo.conf','dgVoodooCpl.exe') }
        foreach ($n in $dgFiles) { Install-OneFile "dgvoodoo\$n" $n }
        # 32-bit ReShade dxgi hook behind the D3D11 translation (unless one is already there)
        if ($reshadeRoute -and -not $reshade.Installed -and -not (Test-Path -LiteralPath (Join-Path $exeDir 'dxgi.dll'))) {
            Install-OneFile 'reshade\dxgi-x86.dll' 'dxgi.dll'
        }
    }

    # shaders
# shaders - whole package (root effects + include/ + Includes/) so every MV provider compiles
    $shaderDestDir = Join-Path $exeDir 'reshade-shaders\Shaders'
    foreach ($sf in @(Get-ChildItem -LiteralPath (Join-Path $Script:Kit 'shaders') -Recurse -File -ErrorAction SilentlyContinue)) {
        $rel = $sf.FullName.Substring((Join-Path $Script:Kit 'shaders').Length).TrimStart('\')
        $dest = Join-Path $shaderDestDir $rel
        Add-Replace $dest
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath $sf.FullName -Destination $dest -Force
        [void]$manifest.added.Add($dest.Substring($GameDir.Length).TrimStart('\'))
    }

# ReShade.ini (game side)
    $iniPath = Join-Path $exeDir 'ReShade.ini'
    Add-Replace $iniPath
    $sections = @{
        'ADDON'   = @{ 'AddonPath' = '.\' }
        'GENERAL' = @{
            'EffectSearchPaths' = '.\reshade-shaders\Shaders\**'
            'PresetPath'        = '.\ReShadePreset.ini'
            'PreprocessorDefinitions' = "DLSS5_MV_PROVIDER=$MVProvider"
        }
        'INPUT'   = @{ 'KeyOverlay' = '33,0,0,0' }
    }
    if ($api -eq 'vulkan') {
        # The Vulkan layer is registered machine-wide (ProgramData) or per-user.
        # Its injection DLL sits elsewhere, so point ReShade's base path at the game
        # folder: ReShade otherwise defaults the layer base to the DLL directory and
        # would (a) abort the load-check for lack of a ReShade.ini next to the layer
        # DLL and (b) ignore the game-folder ReShade.ini/addons/shaders entirely.
        $sections['INSTALL'] = @{ 'BasePath' = $exeDir }
    }
    if ($earlyLoadAddon) { $sections['ADDON']['LoadFromDllMain'] = $earlyLoadAddon }
    $styleNum = switch ($StyleIndex) { 1 { 1 } 2 { 2 } default { 0 } }
    if ($Provider -eq 'renodx' -and -not $host64) {
        $sections['RenoDX.DLSS5'] = @{
            'EnableHooks'        = "$renoHookMode"
            'NeuralUplift'       = ([int]$SymUplift.IsPresent)
            'NRAutoMask'         = '0'
            'NRDiffuseWhiteNits' = '203'
            'NREnableUpscaling'  = '1'
            'NRIntensity'        = ('{0:0}' -f $NrxIntensity)
            'NRMVecScaleX'       = '1'
            'NRMVecScaleY'       = '1'
            'NRPreset'           = "$NrxPreset"
            'NRStyle'            = "$styleNum"
            'NRUICorrection'     = '1'
        }
    }
    Set-IniValues -Path $iniPath -Sections $sections
    if ($Provider -eq 'chicken') { Remove-IniSection -Path $iniPath -Section 'RenoDX.DLSS5' }
    [void]$manifest.added.Add($iniPath.Substring($GameDir.Length).TrimStart('\'))

    # host64\ReShade.ini - the 64-bit helper's own ReShade hosts the neural consumer
    if ($host64) {
        $hostIni = Join-Path $exeDir 'host64\ReShade.ini'
        Add-Replace $hostIni
        $hsections = @{ 'ADDON' = @{ 'AddonPath' = '.\' }; 'INPUT' = @{ 'KeyOverlay' = '33,0,0,0' } }
        if ($LoadFromDllMain -and $hostLoadAddon) { $hsections['ADDON']['LoadFromDllMain'] = $hostLoadAddon }
        if ($Provider -eq 'renodx') {
            $hsections['RenoDX.DLSS5'] = @{
                'EnableHooks'        = "$renoHookMode"
                'NeuralUplift'       = ([int]$SymUplift.IsPresent)
                'NRAutoMask'         = '0'
                'NRDiffuseWhiteNits' = '203'
                'NREnableUpscaling'  = '1'
                'NRIntensity'        = ('{0:0}' -f $NrxIntensity)
                'NRMVecScaleX'       = '1'
                'NRMVecScaleY'       = '1'
                'NRPreset'           = "$NrxPreset"
                'NRStyle'            = "$styleNum"
                'NRUICorrection'     = '1'
            }
        }
        Set-IniValues -Path $hostIni -Sections $hsections
        if ($Provider -eq 'chicken') { Remove-IniSection -Path $hostIni -Section 'RenoDX.DLSS5' }
        [void]$manifest.added.Add($hostIni.Substring($GameDir.Length).TrimStart('\'))
    }

    # preset
    $presetPath = Join-Path $exeDir 'ReShadePreset.ini'
    Add-Replace $presetPath
    if (Test-Path -LiteralPath $presetPath) {
        $sb = New-Object System.Collections.Generic.List[string]
        ([System.IO.File]::ReadAllLines($presetPath) | ForEach-Object { $sb.Add($_) }) | Out-Null
        $found = $false
        for ($i = 0; $i -lt $sb.Count; $i++) {
            if ($sb[$i] -match '^\s*Techniques\s*=') {
                if ($sb[$i] -notmatch 'DLSS5_Feed' -or $sb[$i] -notmatch 'Lumenite_Kernel') {
                    $sb[$i] = 'Techniques=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx'
                }
                $found = $true
            }
        }
        if (-not $found) { $sb.Insert(0, 'Techniques=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx') }
        $hasSection = [bool]($sb -match '^\s*\[DLSS5_Feed\.fx\]\s*$')
        if (-not $hasSection) {
            $sb.Add('')
            $sb.Add('[DLSS5_Feed.fx]')
            foreach ($raw in ((Get-PresetContent) -split "`n")) {
                $t = $raw.Trim("`r")
                if ($t -and $t -notmatch '^\s*Techniques\s*=' -and $t -notmatch '^\s*\[') { $sb.Add($t) }
            }
        }
        [System.IO.File]::WriteAllLines($presetPath, $sb, (New-Object System.Text.UTF8Encoding($false)))
    } else {
        [System.IO.File]::WriteAllText($presetPath, (Get-PresetContent), (New-Object System.Text.UTF8Encoding($false)))
    }
    [void]$manifest.added.Add($presetPath.Substring($GameDir.Length).TrimStart('\'))

if (-not $DryRun) { $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Get-ManifestPath $GameDir) -Encoding UTF8 }

    if (-not $DryRun) {
        Write-Ok "Installed into $exeDir"
        Write-Step "Provider : $Provider"
        if ($Provider -eq 'chicken') { Write-Step "Passes   : $Passes (deep-fried-chicken.cfg layers)" }
        Write-Step "Feeder   : $([bool]$useFeeder)"
        if ($MfgAddon) { Write-Step "MFGUnlock: ReShade addon renodx-mfgunlock.addon64 (open ReShade > Add-ons > MFG Unlock)" }
        $archNote = ''
        if ($host64) { $archNote = '  (neural stack in host64\)' }
        Write-Step ("Arch     : {0}-bit{1}" -f $exe.Bitness, $archNote)
        Write-Step "Logs     : $exeDir\dlss5-feed.log"
        Write-Step "Verify   : .\DLSS5-Swapper.ps1 -Verify -GamePath `"$GameDir`""
    }

    if ($Launch) { Start-Process -FilePath $exe.Path -WorkingDirectory $exeDir }

    return [pscustomobject]@{
        action = 'install'
        gameDir = $GameDir
        exe = $exe.Name
        api = $label
        provider = $Provider
        passes = $Passes
        feeder = [bool]$useFeeder
        mfgAddon = [bool]$MfgAddon
        bitness = $exe.Bitness
        host64 = [bool]$host64
        added = @($manifest.added)
        dryRun = [bool]$DryRun
        manifestPath = (Get-ManifestPath $GameDir)
    }
}

# ---------------------------------------------------------------------------
# renodx hook-mode diagnostics (ReShade.log evidence based)
# ---------------------------------------------------------------------------
function Get-RenoHookState {
    # Reads the addon's ReShade.log* to learn how the last run patched the stack.
    # The addon does not log its overlay status ('NO NR FEATURE MATCHED'), but it
    # does log its Streamline patch activity: mode 1 prints 'installing/hooks
    # installed in sl.interposer.dll' (or sl.common.dll on Multi-GPU builds),
    # mode 2 leaves Streamline untouched.
    # recommend = 'streamline' when a Streamline-routed game ran NGX-only
    # (addon guidance: 'set EnableHooks=1 ... and restart the game').
    param($GameDir, $ExeDir)
    $oid = Get-OldManifest $GameDir
    $hosted = [bool](Get-ManifestProp $oid 'host64')
    $streamlineHost = $false
    $streamlinePatched = $false
    $ngxSeen = $false
    $featureMatched = $false
    $proxyCompileFail = $false
    $logDirs = @($ExeDir)
    if ($hosted) { $logDirs += (Join-Path $ExeDir 'host64') }
    foreach ($ld in $logDirs) {
        if (Test-Path -LiteralPath (Join-Path $ld 'sl.interposer.dll')) { $streamlineHost = $true; break }
    }
    foreach ($ld in $logDirs) {
        foreach ($name in @('ReShade.log', 'ReShade.log1')) {
            $p = Join-Path $ld $name
            if (-not (Test-Path -LiteralPath $p)) { continue }
            try { $t = [System.IO.File]::ReadAllText($p) } catch { continue }
            $ci = [System.StringComparison]::OrdinalIgnoreCase
            if ($t.IndexOf('installing Streamline hooks into sl.', $ci) -ge 0 -or
                $t.IndexOf('Streamline hooks installed in sl.', $ci) -ge 0) { $streamlinePatched = $true }
            if ($t.IndexOf('D3D12 NGX hooks installed', $ci) -ge 0 -or
                $t.IndexOf('NGX module scan', $ci) -ge 0) { $ngxSeen = $true }
            if ($t.IndexOf('NGX feature create intercepted', $ci) -ge 0 -or
                $t.IndexOf('first NGX evaluate intercepted', $ci) -ge 0) { $featureMatched = $true }
            if ($t.IndexOf('proxy encode compilation failed', $ci) -ge 0) { $proxyCompileFail = $true }
        }
    }
    # effective mode: manifest hookMode + deployed ReShade.ini EnableHooks are
    # authoritative for what the next run uses; fall back to log evidence when
    # neither is set (a reinstall can leave a stale patched log behind).
    $iniHooks = $null
    foreach ($ld in $logDirs) {
        $ip = Join-Path $ld 'ReShade.ini'
        if (Test-Path -LiteralPath $ip) {
            $m = [regex]::Match([System.IO.File]::ReadAllText($ip), '(?mi)^\[RenoDX\.DLSS5\][\s\S]*?^EnableHooks\s*=\s*(\d)')
            if ($m.Success) { $iniHooks = $m.Groups[1].Value; break }
        }
    }
    $manifestMode = Get-ManifestProp $oid 'hookMode'
    if ($manifestMode -eq '1' -or $iniHooks -eq '1') { $patchedEffective = $true }
    elseif ($manifestMode -eq '2' -or $iniHooks -eq '2') { $patchedEffective = $false }
    else { $patchedEffective = $streamlinePatched }
    $curMode = if ($manifestMode -eq '1' -or $manifestMode -eq '2') { [int]$manifestMode }
    elseif ($iniHooks -eq '1') { 1 } elseif ($iniHooks -eq '2') { 2 }
    elseif ($streamlinePatched) { 1 } elseif (-not $streamlineHost) { $null } else { 2 }
    # 'feature create intercepted' only proves the direct-NGX path works when the
    # log shows no Streamline patch at all - a prior EnableHooks=1 run (stale log
    # after a reinstall) also prints the intercept line but proves nothing about
    # NGX-only. So direct-NGX evidence = feature matched AND Streamline untouched.
    $directNgx = $featureMatched -and -not $streamlinePatched
    $recommend = $null
    # Only recommend when the game is Streamline-routed AND the addon was never
    # actually reached: a direct-NGX title (GOW Ragnarok, GTA V Enhanced, RDR1)
    # logs 'NGX feature create intercepted' and works fine on EnableHooks=2.
    if ($streamlineHost -and -not $patchedEffective -and $ngxSeen -and -not $directNgx) { $recommend = 'streamline' }
    [pscustomobject]@{
        streamlineHost = [bool]$streamlineHost
        streamlinePatched = [bool]$streamlinePatched
        ngxSeen = [bool]$ngxSeen
        featureMatched = [bool]$directNgx
        proxyCompileFail = [bool]$proxyCompileFail
        enablehooks = $curMode
        recommend = $recommend
    }
}

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------
function Invoke-VerifyStack {
    param($GameDir)
    $scan = Get-GameScan $GameDir
    $exe = $scan.Chosen
    if (-not $exe) { Fail "No game executable found." }
    $exeDir = Split-Path -Parent $exe.Path
$manifest = Get-OldManifest $GameDir
    Write-Step "Verifying $($exe.Name) ($($exe.Label))"
    if (-not $manifest) {
        Write-Step "No DLSS5 install found in $($exe.Name) - nothing to verify."
        if (-not $Json) { Write-Warn "Nothing was installed here yet. Run -Install first." }
        return [pscustomobject]@{
            action = 'verify'
            gameDir = $GameDir
            exe = $exe.Name
            api = $exe.Label
            checks = @()
            provider = $null
            installed = $false
            note = 'not installed'
        }
    }

    $pfx = if ($exe.Bitness -ne 64) { 'host64\' } else { '' }
    $checks = @()
    foreach ($n in @('nvngx_dlss.dll','nvngx_dlssnr.dll')) {
        $p = Join-Path $exeDir ($pfx + $n)
        $checks += [pscustomobject]@{ Item = ($pfx + $n); Ok = (Test-Path -LiteralPath $p); Note = if (Test-Path -LiteralPath $p) { 'v' + (Get-FileProductVersion $p) } else { 'MISSING' } }
    }
    if ($exe.Bitness -ne 64) {
        foreach ($n in @('dlss5-feed.addon32','host64\dlss5-feed-host64.exe','host64\dxgi.dll','dxgi.dll')) {
            $p = Join-Path $exeDir $n
            $checks += [pscustomobject]@{ Item = $n; Ok = (Test-Path -LiteralPath $p); Note = if (Test-Path -LiteralPath $p) { 'present' } else { 'MISSING' } }
        }
    }
    $manBit = Get-ManifestProp $manifest 'bit'
    $manApi = Get-ManifestProp $manifest 'api'
    if ($manifest -and ($manApi -eq 'd3d8' -or $manApi -eq 'd3d9') -and $manBit -ne 64) {
        $dgChecks = @('D3D9.dll','dgVoodoo.conf')
        if ($manApi -eq 'd3d8') { $dgChecks = @('D3D8.dll','D3D9.dll','dgVoodoo.conf') }
        foreach ($n in $dgChecks) {
            $p = Join-Path $exeDir $n
            $checks += [pscustomobject]@{ Item = $n; Ok = (Test-Path -LiteralPath $p); Note = if (Test-Path -LiteralPath $p) { 'present' } else { 'MISSING' } }
        }
    }
    foreach ($n in @('dlss5-feed.addon64','deep-fried-chicken.addon64','deep-fried-chicken-nvngx.dll','deep-fried-chicken.cfg','renodx-dlss5.addon64','dxgi.dll')) {
        $p = Join-Path $exeDir ($pfx + $n)
        if (Test-Path -LiteralPath $p) {
            $checks += [pscustomobject]@{ Item = ($pfx + $n); Ok = $true; Note = 'present' }
        }
    }
    $feedCfg = Join-Path $exeDir 'dlss5-feed.cfg'
    if (Test-Path -LiteralPath $feedCfg) {
        $text = Get-Content -LiteralPath $feedCfg -Raw
        $checks += [pscustomobject]@{ Item = 'dlss5-feed.cfg mode/warmup'; Ok = ($text -match 'mode=2'); Note = ($text -match 'warmup_rebuild=\d+') }
    }
    $dfcCfg = Join-Path $exeDir ($pfx + 'deep-fried-chicken.cfg')
    if (Test-Path -LiteralPath $dfcCfg) {
        $text = Get-Content -LiteralPath $dfcCfg -Raw
        $layers = if ($text -match 'layers=(\d+)') { $matches[1] } else { '?' }
        $checks += [pscustomobject]@{ Item = ($pfx + 'deep-fried-chicken.cfg'); Ok = ($text -match 'arm=1'); Note = "layers=$layers" }
    }
    if (Test-Path -LiteralPath (Join-Path $exeDir 'ReShade.ini')) {
        $ini = Get-Content -LiteralPath (Join-Path $exeDir 'ReShade.ini') -Raw
        if ($exe.Bitness -eq 64) {
            # LoadFromDllMain makes ReShade initialize the add-on from inside its own
            # DllMain; that preload is racy and can silently drop the neural consumer
            # at startup (observed on rpcs3/Vulkan - registers only some launches).
            # The deterministic route is the post-init add-on scan (AddonPath=\.\),
            # which installs now use by default (README 9.8).
            $lfdm = ($ini -match 'LoadFromDllMain=.+addon64')
            $checks += [pscustomobject]@{ Item = 'ReShade.ini add-on load'; Ok = (-not $lfdm); Note = $(if ($lfdm) { 'LoadFromDllMain (flaky DllMain preload) present' } else { 'scan load (deterministic)' }) }
        } else {
            $checks += [pscustomobject]@{ Item = 'ReShade.ini AddonPath'; Ok = ($ini -match 'AddonPath=.\\\s*$' -or $ini -match 'AddonPath'); Note = ($ini -match 'DLSS5_MV_PROVIDER=3') }
            $hostIniP = Join-Path $exeDir 'host64\ReShade.ini'
            if (Test-Path -LiteralPath $hostIniP) {
                $hini = Get-Content -LiteralPath $hostIniP -Raw
                $hlfdm = ($hini -match 'LoadFromDllMain=.+addon64')
                $checks += [pscustomobject]@{ Item = 'host64\ReShade.ini add-on load'; Ok = (-not $hlfdm); Note = $(if ($hlfdm) { 'LoadFromDllMain (flaky DllMain preload) present' } else { 'scan load (deterministic)' }) }
            }
        }
    }
    # d3dcompiler_47.dll trap: a Windows 8.1-era copy (6.3.x) sitting beside the
    # exe wins the DLL search order over System32's modern copy and cannot
    # compile the neural proxy shader (cs_5_1), so the NR pass silently fails
    # every frame (README 9.2).
    $dcLocal = $false
    $dcTrap = $false
    $dcDirs = @(@{ Dir = $exeDir; Label = 'game folder' })
    if ($pfx) { $dcDirs += @{ Dir = (Join-Path $exeDir 'host64'); Label = 'host64\' } }
    foreach ($dce in $dcDirs) {
        $dcp = Join-Path $dce.Dir 'd3dcompiler_47.dll'
        if (-not (Test-Path -LiteralPath $dcp)) { continue }
        $dcLocal = $true
        $dcv = Get-FileProductVersion $dcp
        if ($dcv -match '^6\.3\.') {
            $dcTrap = $true
            $checks += [pscustomobject]@{ Item = ($pfx + 'd3dcompiler_47.dll'); Ok = $false; Note = "Windows 8.1-era build $dcv in the $($dce.Label) shadows System32 and cannot compile cs_5_1 - the NR pass silently fails every frame. Rename/delete it (README 9.2)." }
        } elseif ($dcv -eq '?') {
            $dcTrap = $true
            $checks += [pscustomobject]@{ Item = ($pfx + 'd3dcompiler_47.dll'); Ok = $false; Note = "a copy sits in the $($dce.Label) but its version is unreadable - if it predates SM 5.1 the NR pass fails every frame. Rename/delete it (README 9.2)." }
        } else {
            $checks += [pscustomobject]@{ Item = ($pfx + 'd3dcompiler_47.dll'); Ok = $true; Note = "v$dcv in the $($dce.Label) - new enough for cs_5_1" }
        }
    }
    # MFG Unlock addon - must still sit in the addon path
    $manMfgAddon = Get-ManifestProp $manifest 'mfgAddon'
    if ($manMfgAddon) {
        $pa = Join-Path $exeDir 'renodx-mfgunlock.addon64'
        if (Test-Path -LiteralPath $pa) {
            $checks += [pscustomobject]@{ Item = 'MFG Unlock addon'; Ok = $true; Note = 'v' + (Get-FileProductVersion $pa) }
        } else {
            $checks += [pscustomobject]@{ Item = 'MFG Unlock addon'; Ok = $false; Note = 'MISSING' }
        }
    }

if (-not $Json) {
        foreach ($c in $checks) {
            $color = if ($c.Ok) { 'Green' } else { 'Red' }
            Write-Host ("  {0,-30} {1}  {2}" -f $c.Item, ($(if ($c.Ok) { 'OK ' } else { 'FAIL' })), $c.Note) -ForegroundColor $color
        }
    }

    # conflict detection
    $activeAddons = @(Get-ChildItem -LiteralPath $exeDir -Filter '*.addon64' -File -ErrorAction SilentlyContinue)
    $host64Dir = Join-Path $exeDir 'host64'
    if (Test-Path -LiteralPath $host64Dir) {
        $activeAddons += @(Get-ChildItem -LiteralPath $host64Dir -Filter '*.addon64' -File -ErrorAction SilentlyContinue)
    }
    $neural = @($activeAddons | Where-Object { $_.Name -match 'chicken|renodx' })
    if ($neural.Count -gt 1) { Write-Err "!! Multiple neural providers active: $($neural.Name -join ', ') - only one may be present. Chicken stays inert beside RenoDX." }
    elseif ($neural.Count -eq 1) { Write-Ok "Neural provider: $($neural[0].FullName.Substring($GameDir.Length))" }

$prov2 = Get-ManifestProp $manifest 'provider'
    $hookRec = $null
    $hookMode = $null
    $hostSL = $false
    $proxyFail = $false
    $featureMatched = $false
    if ($prov2 -eq 'renodx') {
        $hs = Get-RenoHookState $GameDir $exeDir
        $hostSL = [bool]$hs.streamlineHost
        $hookMode = $hs.enablehooks
        $featureMatched = [bool]$hs.featureMatched
        $modeNote = if ($hs.enablehooks -eq 1) { 'Streamline' } elseif ($hs.enablehooks -eq 2) { 'NGX-only' } else { 'n/a' }
        # RenoDX DLSS5 detours the D3D12 NGX evaluate. On Vulkan it only
        # registers when the DLSS5-Feeder transport is present: the Feeder
        # addon creates a private in-process D3D12 device so the consumer has
        # something to hook. Without it the addon declines to register and the
        # neural pass never runs. This is the same Feeder + RenoDX config the
        # DLSS 5 Swapper ships on Vulkan; flag only when the feeder is absent.
        $isVulkan = ($exe.Label -eq 'Vulkan') -or
                    ((Get-ManifestProp $manifest 'api') -eq 'vulkan')
        $manFeeder = Get-ManifestProp $manifest 'feeder'
        $feedAddon64 = Join-Path $exeDir 'dlss5-feed.addon64'
        $feedAddon32 = Join-Path $exeDir 'dlss5-feed.addon32'
        $feederPresent = [bool]$manFeeder -or (Test-Path -LiteralPath $feedAddon64) -or (Test-Path -LiteralPath $feedAddon32)
        if ($isVulkan -and -not $feederPresent) {
            $checks += [pscustomobject]@{ Item = 'Provider vs API'; Ok = $false; Note = "renodx on Vulkan needs the DLSS5-Feeder transport (manifest.feeder=$manFeeder; no dlss5-feed.addon64 next to the exe) - reinstall (the installer auto-enables the Feeder on Vulkan)" }
        } elseif ($isVulkan -and $feederPresent) {
            $checks += [pscustomobject]@{ Item = 'Provider vs API'; Ok = $true; Note = "renodx on Vulkan via the Feeder transport (the consumer registers against the Feeder's private D3D12 device)" }
        } elseif ($hs.recommend -eq 'streamline') {
            $hookRec = 'streamline'
            $checks += [pscustomobject]@{ Item = 'RenoDX fix'; Ok = $false; Note = 'set EnableHooks=1 in ReShade.ini (.\DLSS5-Swapper.ps1 -FixHooks does this) for Streamline-routed games' }
        } else {
            $hookNote = $modeNote
            if ($hs.featureMatched -and $hs.enablehooks -eq 2) { $hookNote = 'NGX-only, direct-NGX feature matched (DLSS NR active, no fix needed)' }
            $checks += [pscustomobject]@{ Item = 'RenoDX hook mode'; Ok = $true; Note = $hookNote }
        }
        if ($hs.proxyCompileFail) {
            $proxyFail = $true
            $note = if ($dcTrap) { "addon couldn't compile its proxy shader (cs_5_1) - a Windows 8.1-era d3dcompiler_47.dll in the game folder is shadowing System32. Rename/delete it (README 9.2)." }
                    else { "addon couldn't compile its proxy shader (cs_5_1) - no local d3dcompiler_47.dll found, so this is an addon/runtime/driver issue: see README 9.2, report to the addon author" }
            $checks += [pscustomobject]@{ Item = 'NR upscaling'; Ok = $false; Note = $note }
        }
    }

    # Foreign injector / overlay: the Feeder's NGX session is per-process. Some
    # games load a mod injector or overlay that makes NGX refuse the whole
    # process (0xBAD00002 PlatformError on a pure capability query, before any
    # device exists). Detect the signature in the Feeder log and name the
    # injector files sitting beside the exe (README 9.6).
    $ngxBlock = $false
    $vLogDirs = @($exeDir)
    if ($pfx) { $vLogDirs += (Join-Path $exeDir 'host64') }
    foreach ($ld in $vLogDirs) {
        $fp = Join-Path $ld 'dlss5-feed.log'
        if (-not (Test-Path -LiteralPath $fp)) { continue }
        try { $ft = [System.IO.File]::ReadAllText($fp) } catch { continue }
        if ($ft.IndexOf('it is refusing this PROCESS', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $ft.IndexOf('NGX refused even the capability query', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $ngxBlock = $true; break }
    }
    $injectors = @(Get-ChildItem -LiteralPath $exeDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(dinput8|dsound|winmm|version|uext64|lol)\.dll$' -or $_.Extension -in '.asi','.ipe' } |
        ForEach-Object { $_.Name })
    $injList = @($injectors | Sort-Object -Unique)
    if ($ngxBlock) {
        $what = if ($injList.Count) { 'possible source(s): ' + ($injList -join ', ') + ' beside the game exe; also check Uplay/Steam or other overlays' }
                else { 'no known injector files found beside the exe - look for Uplay/Steam/other overlays or anti-cheat loaded into the game' }
        $checks += [pscustomobject]@{ Item = 'NGX process refused'; Ok = $false; Note = "the Feeder's NGX session was refused for the whole process (0xBAD00002 PlatformError / 0xBAD00001 FeatureNotSupported before any device). Another injector or overlay is blocking NGX - $what. Temporarily disable it, relaunch, and re-verify (README 9.6)." }
    } elseif ($injList.Count) {
        $checks += [pscustomobject]@{ Item = 'Injectors present'; Ok = $true; Note = ($injList -join ', ') + ' beside the exe - harmless unless the Feeder log shows an NGX process refusal' }
    }

if (-not $Json) {
        foreach ($logName in @('dlss5-feed.log','deep-fried-chicken.log')) {
            $log = Join-Path $exeDir $logName
            if (Test-Path -LiteralPath $log) {
                Write-Step "--- $logName (tail) ---"
                Get-Content -LiteralPath $log -Tail 8 | ForEach-Object { Write-Host ("  " + $_) }
            }
        }
    }
if ($manifest) {
        $mvals = foreach ($p in @('provider','api','bit','host64','feeder')) {
            $v = Get-ManifestProp $manifest $p
            "$p=" + $(if ($null -ne $v -and $v -ne '') { $v } else { '?' })
        }
        $mAdded = Get-ManifestProp $manifest 'added'
        $mCount = if ($mAdded) { @($mAdded).Count } else { 0 }
        Write-Step ("Manifest: " + (($mvals + "files=$mCount") -join ' '))
    }

    return [pscustomobject]@{
        action = 'verify'
        gameDir = $GameDir
        exe = $exe.Name
        api = $exe.Label
        checks = @($checks)
        provider = Get-ManifestProp $manifest 'provider'
        installed = [bool]$manifest
        recommendation = $hookRec
        hookMode = $hookMode
        streamlineHost = $hostSL
        featureMatched = $featureMatched
        nrProxyCompileFail = $proxyFail
        d3dcompilerLocal = [bool]$dcLocal
        d3dcompilerTrap = [bool]$dcTrap
        ngxProcessRefused = [bool]$ngxBlock
    }
}

# ---------------------------------------------------------------------------
# renodx hook-mode repair
# ---------------------------------------------------------------------------
function Invoke-FixHooks {
    # Rewrites [RenoDX.DLSS5] EnableHooks in the deployed ReShade.ini (and the
    # host64 variant) without reinstalling, and records the chosen mode in the
    # manifest so later installs remember it. -RenoHooks 'auto' decides from
    # Get-RenoHookState log evidence (streamline when a Streamline host ran
    # NGX-only, else ngx).
    param($GameDir)
    $manifest = Get-OldManifest $GameDir
    if (-not $manifest) { Fail "No DLSS5 manifest found in $GameDir (nothing to fix)." }
    if ((Get-ManifestProp $manifest 'provider') -ne 'renodx') { Fail "Hook mode only applies to RenoDX installs." }
    $scan = Get-GameScan $GameDir
    $exe = $scan.Chosen
    if (-not $exe) { Fail "No game executable found in $GameDir." }
    $exeDir = Split-Path -Parent $exe.Path
    $hs = Get-RenoHookState $GameDir $exeDir
    $target = if ($RenoHooks -eq 'streamline') { '1' } elseif ($RenoHooks -eq 'ngx') { '2' } else {
        if ($hs.recommend -eq 'streamline') { '1' }
        elseif ($hs.enablehooks -eq 1 -or $hs.enablehooks -eq 2) { [string]$hs.enablehooks }
        else { '2' }
    }
    $iniPaths = @(Join-Path $exeDir 'ReShade.ini')
    $hi = Join-Path $exeDir 'host64\ReShade.ini'
    if (Test-Path -LiteralPath $hi) { $iniPaths += $hi }
    foreach ($ip in $iniPaths) {
        if ($DryRun) {
            Write-Step "[dry] would set $ip [RenoDX.DLSS5] EnableHooks=$target"
        } elseif (Test-Path -LiteralPath $ip) {
            Set-IniValues -Path $ip -Sections @{ 'RenoDX.DLSS5' = @{ 'EnableHooks' = $target } }
        }
    }
    if (-not $DryRun) {
        $om = @{}
        foreach ($prop in $manifest.PSObject.Properties) { $om[$prop.Name] = $prop.Value }
        $om['hookMode'] = $target
        ConvertTo-Json ([pscustomobject]$om) -Depth 5 | Set-Content -LiteralPath (Get-ManifestPath $GameDir) -Encoding UTF8
    }
    $modeLabel = if ($target -eq '1') { 'Streamline' } else { 'NGX-only' }
    if (-not $DryRun) { Write-Ok "RenoDX hook mode set to EnableHooks=$target ($modeLabel)" }
    return [pscustomobject]@{
        action = 'fixhooks'
        gameDir = $GameDir
        mode = $(if ($target -eq '1') { 'streamline' } else { 'ngx' })
        enablehooks = $target
        dryRun = [bool]$DryRun
    }
}

# ---------------------------------------------------------------------------
# uninstall
# ---------------------------------------------------------------------------
function Invoke-UninstallStack {
    param($GameDir)
    $manifest = Get-OldManifest $GameDir
    if (-not $manifest) { Fail "No DLSS5 manifest found in $GameDir (nothing to uninstall)." }
    $backDir = Join-Path $GameDir '_DLSS5_Backup'
    Write-Step "Removing DLSS5 files and restoring originals..."
$addedArr = @(Get-ManifestProp $manifest 'added')
    $replArr = @(Get-ManifestProp $manifest 'replaced')
    foreach ($a in $addedArr) {
        if (-not $a) { continue }
        $p = Join-Path $GameDir $a
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    foreach ($r in $replArr) {
        $bak = Join-Path $backDir $r.backup
        $dst = Join-Path $GameDir $r.file
        New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
        if (Test-Path -LiteralPath $bak) { Copy-Item -LiteralPath $bak -Destination $dst -Force }
    }
Remove-Item -LiteralPath $backDir -Recurse -Force
    if (Get-ManifestProp $manifest 'host64') {
        $host64Dir = Join-Path $GameDir 'host64'
        if (Test-Path -LiteralPath $host64Dir) { Remove-Item -LiteralPath $host64Dir -Recurse -Force }
    }
    Write-Ok "Uninstalled. Original files restored."
    # Drop this game from the per-user Vulkan layer reference list and, only when
    # no other game remains, unregister the HKCU ImplicitLayers entry and delete
    # the layer DLLs - mirroring vulkan-layer.js detach() in the reference app.
    if ((Get-ManifestProp $manifest 'api') -eq 'vulkan') {
        $user = Join-Path $env:USERPROFILE '.dlss5vulkanlayer'
        $uInstalls = Join-Path $user 'installs.json'
        if (Test-Path -LiteralPath $uInstalls) {
            $remaining = @()
            try {
                $data = Get-Content -LiteralPath $uInstalls -Raw | ConvertFrom-Json
                $remaining = @($data.games | Where-Object { $_ -and ($_.TrimEnd('\') -ne $GameDir.TrimEnd('\')) })
            } catch { $remaining = @() }
            if (@($remaining).Count -gt 0) {
                [System.IO.File]::WriteAllText($uInstalls, (@{ version = 1; games = $remaining } | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
                Write-Step "Vulkan user layer kept (still used by $(@($remaining).Count) other game$(if (@($remaining).Count -ne 1) { 's' }))."
            } else {
                foreach ($name in @('ReShade64.json','ReShade32.json')) {
                    $jp = Join-Path $user $name
                    if (Test-Path -LiteralPath $jp) {
                        Remove-ItemProperty -Path 'HKCU:\Software\Khronos\Vulkan\ImplicitLayers' -Name $jp -ErrorAction SilentlyContinue
                    }
                }
                if (Test-Path -LiteralPath $user) { Remove-Item -LiteralPath $user -Recurse -Force -ErrorAction SilentlyContinue }
                Write-Step "Vulkan user layer removed (no more games reference it)."
            }
        }
    }
    return [pscustomobject]@{ action = 'uninstall'; gameDir = $GameDir; removed = @($addedArr); restored = @($replArr); host64 = [bool](Get-ManifestProp $manifest 'host64') }
}

# ---------------------------------------------------------------------------
# discovery - launcher roots and/or full disk scan for game folders
# ---------------------------------------------------------------------------
function Get-SteamLibs {
    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($vdf in @(
            'C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf',
            'C:\Program Files\Steam\steamapps\libraryfolders.vdf')) {
        if (-not (Test-Path -LiteralPath $vdf)) { continue }
        try {
            $txt = Get-Content -LiteralPath $vdf -Raw
            foreach ($m in [regex]::Matches($txt, '"path"\s*"([^"]+)"')) {
                $libs.Add(($m.Groups[1].Value -replace '\\\\', '\'))
            }
        } catch { Write-Warn "Steam library list unreadable: $vdf" }
    }
    if ($libs.Count -eq 0) {
        foreach ($p in @(
                'C:\Program Files (x86)\Steam\steamapps\common',
                'C:\Program Files\Steam\steamapps\common')) {
            if (Test-Path -LiteralPath $p) { $libs.Add($p) }
        }
    }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $libs) {
        $common = if ([System.IO.Path]::GetFileName($l) -eq 'common') { $l } else { Join-Path $l 'steamapps\common' }
        if (Test-Path -LiteralPath $common) { $out.Add($common) }
    }
    return $out
}

function Get-LauncherRoots {
    return @(
        'C:\Program Files (x86)\GOG Galaxy\Games',
        'C:\Program Files\GOG Galaxy\Games',
        'C:\Program Files\Epic Games',
        'C:\Program Files\EA Games',
        'C:\Program Files (x86)\Origin Games',
        'C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games',
        'C:\Program Files\Ubisoft\Ubisoft Game Launcher\games'
    )
}

$Script:DEEP_SKIP = @('windows','winnt','programdata','$recycle.bin','recovery','system volume information','perflogs','msocache','temp','tmp','windowsapps','appdata','packages','node_modules','.git','dotnet','partial','common files','windows kits','intel','nvidia','amd','dell','hp','nahimic','msi','asus','gigabyte','python','visual studio','clr','.nuget')

function Invoke-Discover {
    param([string]$Root = '', [int]$Depth = 6)
    $launcherMode = [string]::IsNullOrEmpty($Root)
    $found = New-Object System.Collections.Generic.List[object]
    $scans = New-Object System.Collections.Generic.List[object]
    $processed = New-Object System.Collections.Generic.HashSet[string]
    $fail = ''

    function Add-GameDir {
        param([string]$Dir)
        $key = $Dir.TrimEnd('\').ToLower()
        if (-not $processed.Add($key)) { return }
        Write-Step "Scanning $Dir"
        try {
            $s = Get-GameScan $Dir
            if ($s -and $s.Chosen) {
                $found.Add($key)
                $scans.Add([pscustomobject]@{
                    gameDir = $Dir
                    chosen = $s.Chosen
                    candidates = @($s.Candidates)
                    hasNativeDlss = [bool]$s.HasNativeDlss
                    reshade = [pscustomobject]@{ present = [bool]($s.ReShade.Installed); file = $s.ReShade.File; version = $s.ReShade.Version }
                })
                Write-Ok "Discovered $($s.Chosen.Name)  ($Dir)"
            }
        } catch { Write-Warn "No scan for $Dir : $_" }
    }

    if ($launcherMode) {
        $roots = @()
        $roots += Get-SteamLibs
        foreach ($r in @(Get-LauncherRoots | Where-Object { Test-Path -LiteralPath $_ })) { $roots += $r }
        if ($roots.Count -eq 0) { Write-Warn "No launcher folders found to scan." }
        foreach ($r in $roots) {
            Write-Step "Launcher folder: $r"
            foreach ($g in @(Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue)) {
                if ($Script:SKIP_DIRS -contains $g.Name.ToLower()) { continue }
                Add-GameDir $g.FullName
            }
        }
    } else {
        try { $rootDir = (Get-Item -LiteralPath $Root).FullName } catch { Fail "Root not found: $Root" }
        Write-Step "Deep scan: $rootDir (depth $Depth)"
        $queue = New-Object System.Collections.Generic.Queue[object]
        $queue.Enqueue([pscustomobject]@{ Path = $rootDir; D = 0 })
        $scanned = 0
        while ($queue.Count -gt 0) {
            $cur = $queue.Dequeue()
            $dirs = @()
            try { $dirs = @(Get-ChildItem -LiteralPath $cur.Path -Directory -Force -ErrorAction SilentlyContinue) } catch {}
            if ($cur.D -ge $Depth) { continue }
            foreach ($d in $dirs) {
                $nm = $d.Name.ToLower()
                if ($nm -eq 'windows' -or $Script:DEEP_SKIP -contains $nm -or $nm.StartsWith('$')) { continue }
                $queue.Enqueue([pscustomobject]@{ Path = $d.FullName; D = $cur.D + 1 })
            }
            try {
                $hasExe = @(Get-ChildItem -LiteralPath $cur.Path -Filter '*.exe' -File -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch $Script:NOT_A_GAME })
                if ($hasExe.Count -gt 0) {
                    Add-GameDir $cur.Path
                    $scanned++
                    if ($scanned -ge 600) { Write-Warn "Reached scan limit (600 game folders) - stopping deep scan."; break }
                }
            } catch {}
        }
        if ($scanned -eq 0) { Write-Warn "No game folders found under $rootDir" }
    }

    return [pscustomobject]@{
        action = 'discover'
        launchers = $launcherMode
        root = $Root
        folders = $found.ToArray()
        scans = $scans.ToArray()
    }
}

# ---------------------------------------------------------------------------
# entry
# ---------------------------------------------------------------------------
if ($Help) {
    Get-Content -LiteralPath $MyInvocation.MyCommand.Path -TotalCount 50 |
        Where-Object { $_ -match '^\s*#' } | ForEach-Object { $_ }
    exit 0
}

if ($BuildKit) { New-Kit; exit 0 }
if ($ListKit)  { Invoke-ListKit; exit 0 }

if ($Discover) {
    $d = if ($ScanRoot) { Invoke-Discover -Root $ScanRoot -Depth $Depth } else { Invoke-Discover }
    if ($Json) { $d | ConvertTo-Json -Compress -Depth 8 }
    exit 0
}

if ($Scan -or ($Install -and $GamePath) -or $Verify -or $Uninstall -or $FixHooks) {
    if (-not $GamePath) { Fail "Missing -GamePath <folder>" }
    if (-not (Test-Path -LiteralPath $GamePath)) { Fail "Game path not found: $GamePath" }
    $item = Get-Item -LiteralPath $GamePath
    $gameDir = if ($item.PSIsContainer) { $item.FullName } else { Split-Path -Parent $item.FullName }
}

if ($Scan) {
    $s = Get-GameScan $gameDir
    if ($Json) {
        [pscustomobject]@{
            action = 'scan'
            gameDir = $gameDir
            chosen = $s.Chosen
            candidates = @($s.Candidates)
            hasNativeDlss = [bool]$s.HasNativeDlss
            reshade = [pscustomobject]@{ present = [bool]$s.ReShade.Installed; file = $s.ReShade.File; version = $s.ReShade.Version }
        } | ConvertTo-Json -Compress -Depth 6
        exit 0
    }
    Write-Step "Scan: $gameDir"
    Write-Host ("  {0,-24} {1,-8} {2,-20} {3}" -f 'exe','bits','api','via')
    foreach ($c in $s.Candidates) {
        Write-Host ("  {0,-24} {1,-8} {2,-20} {3}" -f $c.Name, $c.Bitness, $c.Label, $c.Via)
    }
    $chosen = if ($s.Chosen) { $s.Chosen.Name } else { 'none' }
    Write-Step "Chosen: $chosen | native DLSS present: $($s.HasNativeDlss)"
    if ($s.ReShade -and $s.ReShade.Installed) { Write-Step "ReShade present: $($s.ReShade.File) v$($s.ReShade.Version)" }
    exit 0
}

if ($FixHooks) {
    if (-not $Json) { Write-Step "Fixing RenoDX hook mode for $gameDir ..." }
    $f = Invoke-FixHooks $gameDir
    if ($Json -and $f) { $f | ConvertTo-Json -Compress -Depth 6 }
    exit 0
}
if ($Install) {
    $styleIndex = switch ($Style) { 'natural' {1} 'cinematic' {2} default {0} }
    $apiArg = $Api
    if (-not $KitPath -and -not (Test-Kit)) {
        Write-Warn "Kit not built yet. Building now..."
        New-Kit
    }
    $r = Install-Stack -GameDir $gameDir -ApiOverride $apiArg -Provider $Provider -Passes $Passes `
        -WorkPercent $WorkResolution -StyleIndex $styleIndex -NrxPreset $Preset `
        -NrxIntensity $Intensity -SymMv $MVProvider -SymCleanFry $CleanFry `
        -SymTexBoost $TextureBoost -SymUplift $NeuralUplift -FeederMode $Feeder -ExeName $Exe `
        -MfgAddon $MFGAddon -LoadFromDllMain $LoadFromDllMain
    if ($Json -and $r) { $r | ConvertTo-Json -Compress -Depth 6 }
    exit 0
}

if ($Verify) {
    $v = Invoke-VerifyStack $gameDir
    if ($Json -and $v) { $v | ConvertTo-Json -Compress -Depth 6 }
    exit 0
}
if ($Uninstall) {
    if ($DryRun) { Write-Step "[dry] would uninstall $gameDir" }
    else {
        $u = Invoke-UninstallStack $gameDir
        if ($Json -and $u) { $u | ConvertTo-Json -Compress -Depth 6 }
    }
    exit 0
}

Write-Host "DLSS 5 Swapper"
Write-Host "  .\DLSS5-Swapper.ps1 -BuildKit"
Write-Host "  .\DLSS5-Swapper.ps1 -Scan -GamePath <folder>"
Write-Host "  .\DLSS5-Swapper.ps1 -Install -GamePath <folder> [-Provider chicken|renodx] [-Passes N] [-Api d3d12|vulkan|...] [-MFGAddon]"
Write-Host "  .\DLSS5-Swapper.ps1 -Verify -GamePath <folder>"
Write-Host "  .\DLSS5-Swapper.ps1 -FixHooks -GamePath <folder> [-RenoHooks auto|ngx|streamline]"
Write-Host "  .\DLSS5-Swapper.ps1 -Uninstall -GamePath <folder>"
Write-Host "  .\DLSS5-Swapper.ps1 -Help"
