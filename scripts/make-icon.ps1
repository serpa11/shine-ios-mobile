<#
.SYNOPSIS
    Draws the Shine app icon: the word "Shine" in bold white on black.

.DESCRIPTION
    The desktop icon is only 256px, which iOS will not accept. This renders the
    same mark at 1024px, the single size Xcode 14 and later expect.

    The bitmap is 24bpp on purpose. iOS rejects an app icon that carries an
    alpha channel, and a 32bpp ARGB surface would write one even when every pixel
    is fully opaque.

    Run with: pwsh -File Scripts/make-icon.ps1
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$Size    = 1024
$Text    = 'Shine'
$Family  = 'Segoe UI'
$Colour  = [System.Drawing.Color]::White
$Back    = [System.Drawing.Color]::Black

$OutDir = Join-Path $PSScriptRoot '..\Shine\Resources\Assets.xcassets\AppIcon.appiconset'
$OutDir = (New-Item -ItemType Directory -Force -Path $OutDir).FullName
$OutPath = Join-Path $OutDir 'icon-1024.png'

$bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear($Back)

$brush  = New-Object System.Drawing.SolidBrush($Colour)
$rect   = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
$format = New-Object System.Drawing.StringFormat
$format.Alignment     = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center
$format.FormatFlags   = [System.Drawing.StringFormatFlags]::NoWrap -bor [System.Drawing.StringFormatFlags]::NoClip

# Fit the word to ~86% of the square, measuring and resizing a few times so the
# text stays optically even rather than simply centred at a guessed size.
$target = $Size * 0.86
$fontSize = [double]$Size
for ($i = 0; $i -lt 4; $i++) {
    $font = New-Object System.Drawing.Font($Family, [float]$fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $measured = $g.MeasureString($Text, $font, [System.Drawing.SizeF]::new($Size * 8, $Size * 8), $format)
    $font.Dispose()
    if ($measured.Width -le 0) { $fontSize = $Size * 0.5; break }
    $fontSize = $fontSize * ($target / $measured.Width)
}
if ($fontSize -gt $Size) { $fontSize = $Size }

$font = New-Object System.Drawing.Font($Family, [float]$fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString($Text, $font, $brush, $rect, $format)
$font.Dispose(); $brush.Dispose(); $format.Dispose(); $g.Dispose()

$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Host "Wrote $OutPath (${Size}x${Size}, 24bpp)"
