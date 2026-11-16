param(
    [string]$Version,
    [string]$Project,
    [string]$SdkBin,
    [string]$MakeAppx,
    [string]$IdentityFile,
    [string]$PackageName,
    [string]$Publisher,
    [string]$PublisherDisplayName,
    [string]$DisplayName,
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows_packaging.ps1')
if (-not $Project) { $Project = Split-Path -Parent $PSScriptRoot }
$versionInfo = Get-EirWindowsVersionInfo -Project $Project -Version $Version
$names = Get-EirWindowsArtifactNames -VersionInfo $versionInfo
$identity = Get-EirWindowsStoreIdentity -Project $Project -IdentityFile $IdentityFile
if (-not [string]::IsNullOrWhiteSpace($PackageName)) { $identity.Name = $PackageName }
if (-not [string]::IsNullOrWhiteSpace($Publisher)) { $identity.Publisher = $Publisher }
if (-not [string]::IsNullOrWhiteSpace($PublisherDisplayName)) { $identity.PublisherDisplayName = $PublisherDisplayName }
if (-not [string]::IsNullOrWhiteSpace($DisplayName)) { $identity.DisplayName = $DisplayName }
$makeappx = Resolve-EirMakeAppx -SdkBin $SdkBin -MakeAppx $MakeAppx
$bundle = Join-Path $Project 'build\windows\x64\runner\Release'
$payload = Get-EirWindowsPayloadStatus -Bundle $bundle
if ($payload.Missing.Count -gt 0) {
    throw "Missing release file(s): $($payload.Missing -join ', ')"
}

$output = Join-Path $Project 'build\windows-artifacts'
$package = Join-Path $output $names.StoreMsix
if (Test-Path -LiteralPath $package) {
    Remove-Item -LiteralPath $package -Force
}
if ($ValidateOnly) {
    $manifest = New-EirWindowsMsixManifest -Identity $identity -VersionInfo $versionInfo
    $doc = New-Object System.Xml.XmlDocument
    $doc.LoadXml($manifest)
    $identityNode = $doc.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Identity']")
    Write-Output 'validate-only=msix'
    Write-Output "version=$($versionInfo.Full)"
    Write-Output "msix_version=$($versionInfo.Msix)"
    Write-Output "artifact=$package"
    Write-Output "makeappx=$makeappx"
    Write-Output "name=$($identityNode.GetAttribute('Name'))"
    Write-Output "publisher=$($identityNode.GetAttribute('Publisher'))"
    Write-Output "display_name=$($identity.DisplayName)"
    Write-Output "publisher_display_name=$($identity.PublisherDisplayName)"
    Write-Output "missing_runtime=$($payload.MissingRuntime -join ',')"
    Write-Output 'VALIDATE_OK'
    return
}

New-Item -ItemType Directory -Path $output -Force | Out-Null
$stage = Join-Path $output ('msix-staging-' + [Guid]::NewGuid().ToString('N'))
$completed = $false
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Get-ChildItem -LiteralPath $bundle | Copy-Item -Destination $stage -Recurse -Force

    # Stage VC++ CRT runtime DLLs if not already present
    foreach ($dll in @('vcruntime140.dll', 'msvcp140.dll', 'vcruntime140_1.dll')) {
        $dest = Join-Path $stage $dll
        if (-not (Test-Path $dest)) {
            $src = "C:\Windows\System32\$dll"
            if (Test-Path $src) {
                Copy-Item $src $dest -Force
                Write-Host "Staged $dll from System32"
            }
        }
    }

    foreach ($notice in @('PRIVACY.md', 'README.md')) {
        $src = Join-Path $Project $notice
        if (Test-Path $src) {
            Copy-Item -LiteralPath $src -Destination $stage -Force
        }
    }

    # Generate Windows Store tile assets from the existing app icon
    Add-Type -AssemblyName System.Drawing
    $images = Join-Path $stage 'Images'
    New-Item -ItemType Directory -Path $images -Force | Out-Null
    $iconPath = Join-Path $Project 'assets\images\app_logo.png'
    if (-not (Test-Path $iconPath)) {
        $iconPath = Join-Path $Project 'windows\runner\resources\app_icon.ico'
    }
    $source = [Drawing.Image]::FromFile($iconPath)
    try {
        $assetConfigs = @(
            @('StoreLogo', 50),
            @('Square44x44Logo', 44),
            @('Square150x150Logo', 150)
        )
        foreach ($asset in $assetConfigs) {
            foreach ($scale in @(100, 125, 150, 200, 400)) {
                $size = [int]([int]$asset[1] * $scale / 100)
                $bitmap = New-Object Drawing.Bitmap($size, $size)
                $graphics = [Drawing.Graphics]::FromImage($bitmap)
                try {
                    $graphics.Clear([Drawing.Color]::Transparent)
                    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                    $padding = [int]($size * 0.08)
                    $graphics.DrawImage($source, $padding, $padding, $size - 2 * $padding, $size - 2 * $padding)
                    $name = if ($scale -eq 100) { "$($asset[0]).png" } else { "$($asset[0]).scale-$scale.png" }
                    $bitmap.Save((Join-Path $images $name), [Drawing.Imaging.ImageFormat]::Png)
                } finally {
                    $graphics.Dispose()
                    $bitmap.Dispose()
                }
            }
        }
    } finally {
        $source.Dispose()
    }

    # Generate AppxManifest.xml
    $manifestXml = New-EirWindowsMsixManifest -Identity $identity -VersionInfo $versionInfo
    $manifestPath = Join-Path $stage 'AppxManifest.xml'
    [IO.File]::WriteAllText($manifestPath, $manifestXml, [Text.Encoding]::UTF8)

    # Pack MSIX
    Write-Host "Creating MSIX package using $makeappx..."
    $proc = Start-Process -FilePath $makeappx -ArgumentList @('pack', '/d', $stage, '/p', $package, '/nv', '/o') -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "makeappx pack failed with exit code $($proc.ExitCode)"
    }
    if (-not (Test-Path -LiteralPath $package)) {
        throw "MSIX package was not created: $package"
    }

    $hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLower()
    $size = (Get-Item -LiteralPath $package).Length
    Write-Output "msix_file=$package"
    Write-Output "msix_sha256=$hash"
    Write-Output "msix_size=$size"
    Write-Host "Successfully generated Windows Store MSIX: $package ($size bytes, SHA256: $hash)"
    $completed = $true
} finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
