param(
  [Parameter(Mandatory = $true)][string]$JsonIn
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$req = Get-Content -Raw -LiteralPath $JsonIn | ConvertFrom-Json

$outDir = $req.outDir
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$result = @{}
foreach ($item in $req.icons) {
  $key = [string]$item.key
  $exe = [string]$item.path
  $outFile = Join-Path $outDir ($key + '.png')
  $ok = $false
  if ((Test-Path -LiteralPath $exe) -and ($exe -like '*.exe')) {
    try {
      $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
      if ($null -ne $ico) {
        $bmp = $ico.ToBitmap()
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        [System.IO.File]::WriteAllBytes($outFile, $ms.ToArray())
        $ms.Dispose(); $bmp.Dispose(); $ico.Dispose()
        $ok = $true
      }
    } catch {
      $ok = $false
    }
  }
  $result[$key] = $ok
}

$result | ConvertTo-Json -Compress