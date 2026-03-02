Add-Type -AssemblyName System.Drawing

function Create-MedicalCrossIcon {
    param([int]$size, [string]$outputPath)
    
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    
    # Fill background with white
    $graphics.Clear([System.Drawing.Color]::White)
    
    # Draw medical cross (blue color: #4f46e5)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(79, 70, 229))
    $pen = New-Object System.Drawing.Pen($brush, 1)
    
    # Cross dimensions
    $crossWidth = $size * 0.2
    $crossThickness = $size * 0.1
    
    # Vertical bar
    $graphics.FillRectangle($brush, ($size - $crossThickness) / 2, $size * 0.1, $crossThickness, $crossWidth * 2)
    
    # Horizontal bar
    $graphics.FillRectangle($brush, $size * 0.1, ($size - $crossThickness) / 2, $crossWidth * 2, $crossThickness)
    
    $graphics.Dispose()
    $bitmap.Save($outputPath)
    $bitmap.Dispose()
    Write-Host "Created icon: $outputPath"
}

# Create 192x192 and 512x512 icons
Create-MedicalCrossIcon -size 192 -outputPath "D:\Bienestar\icon-192.png"
Create-MedicalCrossIcon -size 512 -outputPath "D:\Bienestar\icon-512.png"

Write-Host "Icons created successfully!"
