# Builds DLSS5-Wizard.exe from DLSS5-Wizard.cs using the .NET Framework csc.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cs = Join-Path $root 'DLSS5-Wizard.cs'
$out = Join-Path $root 'DLSS5-Wizard.exe'

if (-not (Test-Path -LiteralPath $cs)) { throw "Missing $cs" }

$fw = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $fw 'csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { $fw = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319'; $csc = Join-Path $fw 'csc.exe' }

$refs = @(
    'System.dll',
    'System.Core.dll',
    'System.Windows.Forms.dll',
    'System.Drawing.dll',
    'System.Web.Extensions.dll',
    'System.Xml.dll'
)
$target = '/target:winexe'
$args = @($target, '/nologo', '/optimize+', "/out:$out") + ($refs | ForEach-Object { "/reference:$fw\$_" }) + @($cs)

& $csc @args
if ($LASTEXITCODE -ne 0) { throw "csc failed with exit code $LASTEXITCODE" }

"[ok] built $out ($((Get-Item -LiteralPath $out).Length) bytes)"