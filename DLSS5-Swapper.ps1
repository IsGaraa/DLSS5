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
  DirectX 8/9 (dgVoodoo translation required), OpenGL.

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
    -Feeder auto|forced|off                              DLSS5-Feeder transport
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
    [ValidateSet('auto','forced','off')]
    [string]$Feeder = 'auto',
    [string]$KitPath = '',
    [string]$ExeFilter = '',
[switch]$Force,
    [switch]$DryRun,
    [switch]$Launch,
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
        $null = $br.ReadUInt32(); $null = $br.ReadUInt32(); $null = $br.ReadUInt32(); $null = $br.ReadUInt32()
        $optSize = $br.ReadUInt16()
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
    param([string[]]$Imports)
    $has = { param($n) $Imports -contains $n }
    if (& $has 'd3d12.dll')   { return @{ api = 'dxgi';    label = 'DirectX 12'; via = 'imports' } }
    if (& $has 'd3d11.dll')   { return @{ api = 'dxgi';    label = 'DirectX 11'; via = 'imports' } }
    if ((& $has 'd3d10.dll') -or (& $has 'd3d10_1.dll')) { return @{ api = 'd3d10'; label = 'DirectX 10'; via = 'imports' } }
    if (& $has 'dxgi.dll')    { return @{ api = 'dxgi';    label = 'DirectX (DXGI)'; via = 'imports' } }
    if (& $has 'vulkan-1.dll'){ return @{ api = 'vulkan';  label = 'Vulkan'; via = 'imports' } }
    if (& $has 'd3d9.dll')    { return @{ api = 'd3d9';    label = 'DirectX 9'; via = 'imports' } }
    if (& $has 'd3d8.dll')    { return @{ api = 'd3d8';    label = 'DirectX 8'; via = 'imports' } }
    if (& $has 'opengl32.dll'){ return @{ api = 'opengl';  label = 'OpenGL'; via = 'imports' } }
    return $null
}

function Get-ApiFromMarkers {
    param([string]$Path)
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
    param([string]$ExePath)
    $imports = Get-AsciiImports -Path $ExePath
    $d = Get-ApiFromNames -Imports $imports
    if ($d) { return $d }
    $d = Get-ApiFromMarkers -Path $ExePath
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
$detected = Get-DetectedApi $it.FullName
            if (-not $detected) {
                $detected = Get-ApiFromEngine -Dir $cur -Bitness $bitness
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
    foreach ($c in $combined) {
        if ($seen.Add($c.Name.ToLower())) { $chosen = $c; break }
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

    $dirs = @('addons','chicken','renodx','runtime','plugins','reshade','reshade-vulkan','shaders')
    foreach ($d in $dirs) { New-Item -ItemType Directory -Path (Join-Path $Script:Kit $d) -Force | Out-Null }

    $manifest = [ordered]@{}
    $copy = @{}
    $copy['addons\dlss5-feed.addon64'] = $require.feed
    $copy['chicken\deep-fried-chicken.addon64'] = $require.chicken
    $copy['chicken\deep-fried-chicken-nvngx.dll'] = (Join-Path $src.chicken 'deep-fried-chicken-nvngx.dll')
    $copy['renodx\renodx-dlss5.addon64'] = $require.renodx
    $copy['runtime\nvngx_dlss.dll'] = $require.dlssdll
    $copy['runtime\nvngx_dlssnr.dll'] = $require.dlssnr
    $copy['plugins\deep-fried-chicken-nvngx.dll'] = (Join-Path $src.chicken 'deep-fried-chicken-nvngx.dll')
    $copy['reshade\dxgi.dll'] = $require.dxgi
    $copy['shaders\DLSS5_Feed.fx'] = $require.feedfx
    $copy['shaders\lumenite_Kernel.fx'] = $require.kernel
    foreach ($n in @('vort_Motion.fx','ReShade.fxh','ReShadeUI.fxh')) {
        $p = Join-Path $src.rpcs3 "reshade-shaders\Shaders\$n"
        if (Test-Path -LiteralPath $p) { $copy["shaders\$n"] = $p }
    }
    if (Test-Path -LiteralPath (Join-Path $src.reshadeVk 'ReShade64.dll')) {
        foreach ($n in @('ReShade64.dll','ReShade64.json','ReShade32.dll','ReShade32.json')) {
            $p = Join-Path $src.reshadeVk $n
            if (Test-Path -LiteralPath $p) { $copy["reshade-vulkan\$n"] = $p }
        }
    }

    foreach ($rel in $copy.Keys) {
        $dest = Join-Path $Script:Kit $rel
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

# ---------------------------------------------------------------------------
# provider config generation
# ---------------------------------------------------------------------------
function Get-DfcConfig {
    param([int]$Layers, [int]$WorkPercent, [int]$StyleIndex, [int]$NrxPreset, [double]$NrxIntensity, [bool]$CleanFry, [bool]$TextureBoost)
    $style = switch ($StyleIndex) { 1 { 1 } 2 { 2 } default { 0 } }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('config_schema=6')
    [void]$sb.AppendLine('arm=1')
    [void]$sb.AppendLine("enabled=$([int]$true)")
    [void]$sb.AppendLine("layers=$Layers")
    [void]$sb.AppendLine("neural_work_percent=$WorkPercent")
    [void]$sb.AppendLine('neural_work_divisor=1')
    [void]$sb.AppendLine('frame_generation_coexistence=0')
    [void]$sb.AppendLine('preserve_native_tone_color=0')
    [void]$sb.AppendLine("clean_fry_enabled=$([int]$CleanFry)")
    [void]$sb.AppendLine('clean_fry_cleanup_strength=0.650')
    [void]$sb.AppendLine('clean_fry_detail_retention=0.850')
    [void]$sb.AppendLine("texture_boost=$([int]$TextureBoost)")
    [void]$sb.AppendLine('texture_boost_strength=1.000')
    [void]$sb.AppendLine('scene_paper_white_scale=1.765')
    [void]$sb.AppendLine('hdr_transfer_strength=1.000')
    [void]$sb.AppendLine('color_strength=1.000')
    for ($i = 1; $i -le 30; $i++) {
        [void]$sb.AppendLine("layer_${i}_nr_preset=$NrxPreset")
        [void]$sb.AppendLine("layer_${i}_nr_style=$style")
        [void]$sb.AppendLine("layer_${i}_intensity={0:F3}" -f $NrxIntensity)
        [void]$sb.AppendLine("layer_${i}_local_tone=2.000")
        [void]$sb.AppendLine("layer_${i}_local_structure=2.000")
        [void]$sb.AppendLine("layer_${i}_skin_structure=2.000")
        [void]$sb.AppendLine("layer_${i}_auto_mask=0")
        [void]$sb.AppendLine("layer_${i}_ui_correction=0")
        [void]$sb.AppendLine("layer_${i}_depth_convention=0")
        [void]$sb.AppendLine("layer_${i}_mvec_scale_x_multiplier=1.000")
        [void]$sb.AppendLine("layer_${i}_mvec_scale_y_multiplier=1.000")
    }
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

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
function Install-Stack {
    param($GameDir, $ApiOverride, $Provider, $Passes, $WorkPercent, $StyleIndex, $NrxPreset, $NrxIntensity, $SymMv, $SymCleanFry, $SymTexBoost, $SymUplift, $FeederMode, $ExeName)
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

    if ($api -eq 'd3d8' -or $api -eq 'd3d9') {
        Write-Warn "DirectX 8/9 needs dgVoodoo2 -> D3D11 translation before the DLSS5 stack can hook it."
        if (-not $Force) { Fail "Aborting (use -Force to copy files anyway)." }
    }
    if ($api -eq 'opengl') {
        Write-Warn "OpenGL needs an opengl32.dll ReShade proxy; none is bundled."
        if (-not $Force) { Fail "Aborting (use -Force to copy files anyway)." }
    }
    if ($exe.Bitness -ne 64) {
        Fail "This build targets 64-bit games only ($($exe.Name) is $($exe.Bitness)-bit)."
    }

    # Feeder decision
    $useFeeder = $false
    if ($FeederMode -eq 'forced') { $useFeeder = $true }
    elseif ($FeederMode -eq 'off') { $useFeeder = $false }
    else {
$native = (Test-Path -LiteralPath (Join-Path $exeDir 'sl.interposer.dll')) -or
                  (Test-Path -LiteralPath (Join-Path $exeDir 'sl.dlss.dll'))
        $useFeeder = -not $native
    }
if ($useFeeder) { Write-Step "Transport: DLSS5-Feeder (non-DLSS game)" }
    else { Write-Step "Transport: game native DLSS (Feeder skipped)" }

    # backup journal + helpers (before touching the disk)
    $backDir = Join-Path $GameDir '_DLSS5_Backup'
    if (-not $DryRun) {
        if (Test-Path -LiteralPath $backDir) {
            if (-not $Force) { Fail "A DLSS5 backup already exists in $GameDir (use -Uninstall first, or -Force to start over)." }
            $old = Get-OldManifest $GameDir
            if ($old) {
                Write-Step "Reinstall (-Force): removing $($old.added.Count) previously-added files"
                foreach ($a in $old.added) {
                    $p = Join-Path $GameDir $a
                    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
                }
            }
        }
        New-Item -ItemType Directory -Path $backDir -Force | Out-Null
    }
    $manifest = [ordered]@{
        tool = 'DLSS5-Swapper'
        date = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        game = $GameDir
        exe  = $exe.Name
        api  = $api
        apiLabel = $label
        provider = $Provider
        feeder = [bool]$useFeeder
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
    if ($api -eq 'vulkan') {
        $layer = Test-Path -LiteralPath 'C:\ProgramData\ReShade\ReShade64.dll'
        if (-not $layer) {
            $user = Join-Path $env:USERPROFILE '.dlss5vulkanlayer'
            if (-not (Test-Path -LiteralPath (Join-Path $user 'ReShade64.dll'))) {
                if ($DryRun) { Write-Step "[dry] would install user Vulkan layer" }
                else {
                    New-Item -ItemType Directory -Path $user -Force | Out-Null
                    if (Test-Path -LiteralPath (Join-Path $Script:Kit 'reshade-vulkan\ReShade64.dll')) {
                        foreach ($n in @('ReShade64.dll','ReShade64.json')) {
                            Copy-Item -LiteralPath (Join-Path $Script:Kit "reshade-vulkan\$n") -Destination (Join-Path $user $n) -Force
                        }
                        New-Item -Path 'HKCU:\Software\Khronos\Vulkan\ImplicitLayers' -Force | Out-Null
                        New-ItemProperty -Path 'HKCU:\Software\Khronos\Vulkan\ImplicitLayers' -Name (Join-Path $user 'ReShade64.json') -Value 0 -PropertyType DWord -Force | Out-Null
                    }
                }
                $reshadeRoute = $true
            } else { $reshadeRoute = $true }
        } else { $reshadeRoute = $true }
    }
    if ($api -eq 'dxgi') {
        $needsProxy = -not $reshade.Installed
        if ($needsProxy -and -not (Test-Path -LiteralPath (Join-Path $exeDir 'dxgi.dll'))) {
            if ($DryRun) { Write-Step "[dry] would copy ReShade dxgi.dll" }
            else { Install-OneFile 'reshade\dxgi.dll' 'dxgi.dll' }
            $reshadeRoute = $true
        } elseif (-not $needsProxy) {
            Write-Step "ReShade already present: $($reshade.File) v$($reshade.Version)"
        }
    }

    if (-not $reshadeRoute -and -not $DryRun) { Fail "No ReShade injection route available. Install ReShade manually, then retry." }

    if ($DryRun) {
        Write-Step "[dry] provider=$Provider passes=$Passes work=$WorkPercent% style=$StyleIndex mvProvider=$MVProvider feeder=$useFeeder route=$reshadeRoute"
        return
    }

    # runtimes
    Install-OneFile 'runtime\nvngx_dlss.dll'    'nvngx_dlss.dll'
    Install-OneFile 'runtime\nvngx_dlssnr.dll'  'nvngx_dlssnr.dll'

    if ($useFeeder) {
        Install-OneFile 'addons\dlss5-feed.addon64' 'dlss5-feed.addon64'
    }

    $earlyLoadAddon = $null
    if ($Provider -eq 'chicken') {
        Install-OneFile 'chicken\deep-fried-chicken.addon64'    'deep-fried-chicken.addon64'
        Install-OneFile 'chicken\deep-fried-chicken-nvngx.dll'  'deep-fried-chicken-nvngx.dll'
        $earlyLoadAddon = 'deep-fried-chicken.addon64'
        # generate chicken cfg
        $cfgDest = Join-Path $exeDir 'deep-fried-chicken.cfg'
        Add-Replace $cfgDest
        $cfgText = Get-DfcConfig -Layers $Passes -WorkPercent $WorkPercent -StyleIndex $StyleIndex -NrxPreset $NrxPreset -NrxIntensity $NrxIntensity -CleanFry $SymCleanFry -TextureBoost $SymTexBoost
        [System.IO.File]::WriteAllText($cfgDest, $cfgText, (New-Object System.Text.UTF8Encoding($false)))
        [void]$manifest.added.Add($cfgDest.Substring($GameDir.Length).TrimStart('\'))
    } else {
        Install-OneFile 'renodx\renodx-dlss5.addon64' 'renodx-dlss5.addon64'
        $earlyLoadAddon = 'renodx-dlss5.addon64'
    }

    if ($useFeeder) {
        $feedDest = Join-Path $exeDir 'dlss5-feed.cfg'
        Add-Replace $feedDest
        $warmup = if ($Provider -eq 'chicken') { 0 } else { 180 }
        [System.IO.File]::WriteAllText($feedDest, (Get-FeedConfig -WorkPercent $WorkPercent -Warmup $warmup), (New-Object System.Text.UTF8Encoding($false)))
        [void]$manifest.added.Add($feedDest.Substring($GameDir.Length).TrimStart('\'))
    }

    # shaders
    $shaderDestDir = Join-Path $exeDir 'reshade-shaders\Shaders'
    foreach ($n in @('DLSS5_Feed.fx','lumenite_Kernel.fx','vort_Motion.fx','ReShade.fxh','ReShadeUI.fxh')) {
        $src = Join-Path $Script:Kit "shaders\$n"
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dest = Join-Path $shaderDestDir $n
        Add-Replace $dest
        New-Item -ItemType Directory -Path $shaderDestDir -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $dest -Force
        [void]$manifest.added.Add($dest.Substring($GameDir.Length).TrimStart('\'))
    }

    # ReShade.ini
    $iniPath = Join-Path $exeDir 'ReShade.ini'
    Add-Replace $iniPath
    $sections = @{
        'ADDON'   = @{ 'AddonPath' = '.\' }
        'GENERAL' = @{
            'EffectSearchPaths' = '.\reshade-shaders\Shaders\**'
            'PresetPath'        = '.\ReShadePreset.ini'
            'PreprocessorDefinitions' = "DLSS5_MV_PROVIDER=$MVProvider"
        }
    }
    if ($earlyLoadAddon) { $sections['ADDON']['LoadFromDllMain'] = $earlyLoadAddon }
    if ($Provider -eq 'renodx') {
        $styleNum = switch ($StyleIndex) { 1 { 1 } 2 { 2 } default { 0 } }
        $sections['RenoDX.DLSS5'] = @{
            'EnableHooks'        = '2'
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
    [void]$manifest.added.Add($iniPath.Substring($GameDir.Length).TrimStart('\'))

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
        added = @($manifest.added)
        dryRun = [bool]$DryRun
        manifestPath = (Get-ManifestPath $GameDir)
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

    $checks = @()
    foreach ($n in @('nvngx_dlss.dll','nvngx_dlssnr.dll')) {
        $p = Join-Path $exeDir $n
        $checks += [pscustomobject]@{ Item = $n; Ok = (Test-Path -LiteralPath $p); Note = if (Test-Path -LiteralPath $p) { 'v' + (Get-FileProductVersion $p) } else { 'MISSING' } }
    }
    foreach ($n in @('dlss5-feed.addon64','deep-fried-chicken.addon64','deep-fried-chicken-nvngx.dll','deep-fried-chicken.cfg','renodx-dlss5.addon64','dxgi.dll')) {
        $p = Join-Path $exeDir $n
        if (Test-Path -LiteralPath $p) {
            $checks += [pscustomobject]@{ Item = $n; Ok = $true; Note = 'present' }
        }
    }
    $feedCfg = Join-Path $exeDir 'dlss5-feed.cfg'
    if (Test-Path -LiteralPath $feedCfg) {
        $text = Get-Content -LiteralPath $feedCfg -Raw
        $checks += [pscustomobject]@{ Item = 'dlss5-feed.cfg mode/warmup'; Ok = ($text -match 'mode=2'); Note = ($text -match 'warmup_rebuild=\d+') }
    }
    $dfcCfg = Join-Path $exeDir 'deep-fried-chicken.cfg'
    if (Test-Path -LiteralPath $dfcCfg) {
        $text = Get-Content -LiteralPath $dfcCfg -Raw
        $layers = if ($text -match 'layers=(\d+)') { $matches[1] } else { '?' }
        $checks += [pscustomobject]@{ Item = 'deep-fried-chicken.cfg'; Ok = ($text -match 'arm=1'); Note = "layers=$layers" }
    }
    if (Test-Path -LiteralPath (Join-Path $exeDir 'ReShade.ini')) {
        $ini = Get-Content -LiteralPath (Join-Path $exeDir 'ReShade.ini') -Raw
        $checks += [pscustomobject]@{ Item = 'ReShade.ini LoadFromDllMain'; Ok = ($ini -match 'LoadFromDllMain=.+addon64'); Note = ($ini -match 'DLSS5_MV_PROVIDER=3') }
    }

if (-not $Json) {
        foreach ($c in $checks) {
            $color = if ($c.Ok) { 'Green' } else { 'Red' }
            Write-Host ("  {0,-30} {1}  {2}" -f $c.Item, ($(if ($c.Ok) { 'OK ' } else { 'FAIL' })), $c.Note) -ForegroundColor $color
        }
    }

    # conflict detection
    $activeAddons = Get-ChildItem -LiteralPath $exeDir -Filter '*.addon64' -File -ErrorAction SilentlyContinue
    $neural = @($activeAddons | Where-Object { $_.Name -match 'chicken|renodx' })
    if ($neural.Count -gt 1) { Write-Err "!! Multiple neural providers active: $($neural.Name -join ', ') - only one may be present. Chicken stays inert beside RenoDX." }
    elseif ($neural.Count -eq 1) { Write-Ok "Neural provider: $($neural[0].Name)" }

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
        Write-Step "Manifest: provider=$($manifest.provider) api=$($manifest.api) feeder=$($manifest.feeder) files=$($manifest.added.Count)"
    }

    return [pscustomobject]@{
        action = 'verify'
        gameDir = $GameDir
        exe = $exe.Name
        api = $exe.Label
        checks = @($checks)
        provider = if ($manifest) { $manifest.provider } else { $null }
        installed = [bool]$manifest
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
    foreach ($a in $manifest.added) {
        $p = Join-Path $GameDir $a
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    foreach ($r in $manifest.replaced) {
        $bak = Join-Path $backDir $r.backup
        $dst = Join-Path $GameDir $r.file
        New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
        if (Test-Path -LiteralPath $bak) { Copy-Item -LiteralPath $bak -Destination $dst -Force }
    }
Remove-Item -LiteralPath $backDir -Recurse -Force
    Write-Ok "Uninstalled. Original files restored."
    return [pscustomobject]@{ action = 'uninstall'; gameDir = $GameDir; removed = @($manifest.added); restored = @($manifest.replaced) }
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

if ($Scan -or ($Install -and $GamePath) -or $Verify -or $Uninstall) {
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
        -SymTexBoost $TextureBoost -SymUplift $NeuralUplift -FeederMode $Feeder -ExeName $Exe
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
Write-Host "  .\DLSS5-Swapper.ps1 -Install -GamePath <folder> [-Provider chicken|renodx] [-Passes N] [-Api d3d12|vulkan|...]"
Write-Host "  .\DLSS5-Swapper.ps1 -Verify -GamePath <folder>"
Write-Host "  .\DLSS5-Swapper.ps1 -Uninstall -GamePath <folder>"
Write-Host "  .\DLSS5-Swapper.ps1 -Help"
