# Fabrique AutoInstall.exe (et l'icône) avec le compilateur C# inclus dans Windows.
# Usage : powershell -ExecutionPolicy Bypass -File outils\Compiler-Exe.ps1

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath
$root = Split-Path -Parent $here
$ico  = Join-Path $root 'AutoInstall.ico'
$exe  = Join-Path $root 'AutoInstall.exe'

# --- Icône : carré bleu arrondi avec une flèche de téléchargement ---
function New-IconImage([int]$size) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object Drawing.Bitmap($size, $size)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $r = [float]($size * 0.22)
    $s = [float]($size - 1)
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $r, $r, 180, 90); $path.AddArc($s - $r, 0, $r, $r, 270, 90)
    $path.AddArc($s - $r, $s - $r, $r, $r, 0, 90); $path.AddArc(0, $s - $r, $r, $r, 90, 90)
    $path.CloseFigure()
    $brush = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Point(0, 0)), (New-Object Drawing.Point(0, $size)),
        [Drawing.Color]::FromArgb(0, 140, 240), [Drawing.Color]::FromArgb(0, 90, 180))
    $g.FillPath($brush, $path)
    $u = $size / 16.0
    $white = [Drawing.Brushes]::White
    $g.FillRectangle($white, [float](6.6 * $u), [float](2.8 * $u), [float](2.8 * $u), [float](5.6 * $u))
    $g.FillPolygon($white, [Drawing.PointF[]]@(
        (New-Object Drawing.PointF([float](3.6 * $u), [float](7.6 * $u))),
        (New-Object Drawing.PointF([float](12.4 * $u), [float](7.6 * $u))),
        (New-Object Drawing.PointF([float](8 * $u), [float](12 * $u)))))
    $g.FillRectangle($white, [float](3.4 * $u), [float](12.6 * $u), [float](9.2 * $u), [float](1.4 * $u))
    $g.Dispose()
    $bmp
}

# Fichier .ico avec plusieurs tailles (images PNG intégrées)
$sizes = 16, 24, 32, 48, 64, 256
$pngs = foreach ($sz in $sizes) {
    $ms = New-Object IO.MemoryStream
    (New-IconImage $sz).Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    , $ms.ToArray()
}
$out = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter($out)
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $sz = $sizes[$i]
    $w.Write([byte]($sz % 256)); $w.Write([byte]($sz % 256)); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $w.Write($p) }
[IO.File]::WriteAllBytes($ico, $out.ToArray())
Write-Host "Icône : $ico"

# --- Compilation ---
$csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
& $csc /nologo /target:winexe /optimize+ "/out:$exe" "/win32icon:$ico" "/win32manifest:$(Join-Path $here 'AutoInstall.manifest')" `
    /reference:System.Windows.Forms.dll /reference:System.Core.dll (Join-Path $here 'Lanceur.cs')
if ($LASTEXITCODE -ne 0) { throw "La compilation a échoué ($LASTEXITCODE)." }
Write-Host "Exe : $exe ($([Math]::Round((Get-Item $exe).Length / 1KB)) Ko)"
