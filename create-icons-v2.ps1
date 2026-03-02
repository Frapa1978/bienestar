Add-Type -AssemblyName System.Drawing

function Create-MedicalCrossIcon {
    param([int]$size, [string]$outputPath)
    
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.InterpolationMode = 'HighQualityBicubic'
    $graphics.SmoothingMode = 'AntiAlias'
    
    # Fill background with white
    $graphics.Clear([System.Drawing.Color]::White)
    
    # Medical cross color (blue: #4f46e5)
    $crossColor = [System.Drawing.Color]::FromArgb(79, 70, 229)
    $brush = New-Object System.Drawing.SolidBrush($crossColor)
    
    # Cross proportions (centered)
    $crossSize = $size * 0.5  # total cross size
    $barThickness = $size * 0.15  # thickness of bars
    $start = ($size - $crossSize) / 2  # starting position to center
    
    # Vertical bar (centered horizontally)
    $verticalX = ($size - $barThickness) / 2
    $verticalY = $start
    $graphics.FillRectangle($brush, $verticalX, $verticalY, $barThickness, $crossSize)
    
    # Horizontal bar (centered vertically)
    $horizontalX = $start
    $horizontalY = ($size - $barThickness) / 2
    $graphics.FillRectangle($brush, $horizontalX, $horizontalY, $crossSize, $barThickness)
    
    $graphics.Dispose()
    
    # Save as PNG
    $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/png' }
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 100)
    
    $bitmap.Save($outputPath, $encoder, $encoderParams)
    $bitmap.Dispose()
    Write-Host "✓ Icono creado: $outputPath"
}

Write-Host "Generando iconos de cruz médica..."
Create-MedicalCrossIcon -size 192 -outputPath "D:\Bienestar\icon-192.png"
Create-MedicalCrossIcon -size 512 -outputPath "D:\Bienestar\icon-512.png"
Write-Host "¡Iconos listos!"
