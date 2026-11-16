# Shared Windows packaging logic for Eir. Dot-source from packaging scripts.
# Keeps version, identity, payload and tool discovery behaviour in one place.

function Get-EirWindowsVersionInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [string]$Version
    )
    $pubspec = Join-Path $Project 'pubspec.yaml'
    $pubVersion = $null
    $pubBuild = $null
    if (Test-Path -LiteralPath $pubspec) {
        $line = Select-String -LiteralPath $pubspec -Pattern '^version:\s*(\S+)\s*$' | Select-Object -First 1
        if ($line) {
            $value = $line.Matches[0].Groups[1].Value
            if ($value -notmatch '^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$') {
                throw "pubspec.yaml version must be stable semantic version+build, got: $value"
            }
            $pubVersion = $Matches[1]
            $pubBuild = [int]$Matches[2]
        }
    }

    if ([string]::IsNullOrWhiteSpace($Version)) {
        if ($null -eq $pubVersion) {
            throw 'No version supplied and pubspec.yaml does not contain a stable version+build line'
        }
        $versionPart = $pubVersion
        $buildPart = $pubBuild
    } else {
        $value = $Version.Trim()
        if ($value -match '^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$') {
            $versionPart = $Matches[1]
            $buildPart = [int]$Matches[2]
        } elseif ($value -match '^([0-9]+\.[0-9]+\.[0-9]+)$') {
            if ($null -eq $pubVersion) {
                throw 'A build number (+N) is required when pubspec.yaml is unavailable'
            }
            $versionPart = $Matches[1]
            $buildPart = $pubBuild
        } else {
            throw "Invalid version (expected X.Y.Z or X.Y.Z+N): $value"
        }
        if ($null -ne $pubVersion -and $versionPart -ne $pubVersion) {
            throw "Supplied version $versionPart does not match pubspec.yaml version $pubVersion"
        }
        if ($null -ne $pubBuild -and $buildPart -ne $pubBuild) {
            throw "Supplied build $buildPart does not match pubspec.yaml build $pubBuild"
        }
    }

    $parts = @($versionPart.Split('.') | ForEach-Object { [int]$_ })
    if ($parts[0] -lt 1) { throw "Major version must be at least 1: $versionPart" }
    foreach ($part in $parts) {
        if ($part -gt 65535) { throw "Version component exceeds 65535: $versionPart" }
    }
    if ($buildPart -lt 1 -or $buildPart -gt 65535) {
        throw "Build number must be between 1 and 65535, got: $buildPart"
    }

    [pscustomobject]@{
        Version     = $versionPart
        Build       = $buildPart
        Full        = "$versionPart+$buildPart"
        Msix        = "$versionPart.0"
        VersionInfo = "$versionPart.$buildPart"
    }
}

function Get-EirWindowsArtifactNames {
    param([Parameter(Mandatory = $true)]$VersionInfo)
    $setupBase = "eir-$($VersionInfo.Version)-windows-x64-setup"
    [pscustomobject]@{
        SetupBase   = $setupBase
        SetupExe    = "$setupBase.exe"
        PortableZip = "eir-v$($VersionInfo.Version)-windows-x64.zip"
        StoreMsix   = "eir-$($VersionInfo.Msix)-windows-x64-store.msix"
        Manifest    = 'store-AppxManifest.xml'
    }
}

function Get-EirWindowsStoreIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [string]$IdentityFile
    )
    if ([string]::IsNullOrWhiteSpace($IdentityFile)) {
        $IdentityFile = Join-Path $Project 'tool\windows_store_identity.json'
    }
    if (-not (Test-Path -LiteralPath $IdentityFile)) {
        throw "Store identity file is required: $IdentityFile"
    }
    $json = [IO.File]::ReadAllText($IdentityFile, [Text.Encoding]::UTF8)
    $identity = $json | ConvertFrom-Json
    foreach ($field in @('Name', 'Publisher', 'PublisherDisplayName', 'DisplayName')) {
        if ([string]::IsNullOrWhiteSpace([string]$identity.$field)) {
            throw "Store identity field is missing: $field"
        }
    }
    [pscustomobject]@{
        Name                 = [string]$identity.Name
        Publisher            = [string]$identity.Publisher
        PublisherDisplayName = [string]$identity.PublisherDisplayName
        DisplayName          = [string]$identity.DisplayName
    }
}

function New-EirWindowsMsixManifest {
    param(
        [Parameter(Mandatory = $true)]$Identity,
        [Parameter(Mandatory = $true)]$VersionInfo,
        [string[]]$Languages = @('zh-Hans', 'en', 'zh-Hant', 'ja', 'ko', 'de', 'fr', 'es', 'pt', 'ru')
    )
    if ($VersionInfo.Msix -notmatch '^[1-9][0-9]*\.[0-9]+\.[0-9]+\.0$') {
        throw "Store package version must have four parts and end in .0: $($VersionInfo.Msix)"
    }
    $nameXml = [Security.SecurityElement]::Escape([string]$Identity.Name)
    $publisherXml = [Security.SecurityElement]::Escape([string]$Identity.Publisher)
    $publisherDisplayXml = [Security.SecurityElement]::Escape([string]$Identity.PublisherDisplayName)
    $displayNameXml = [Security.SecurityElement]::Escape([string]$Identity.DisplayName)
    $versionXml = [Security.SecurityElement]::Escape([string]$VersionInfo.Msix)
    $resourceXml = ($Languages | ForEach-Object { "    <Resource Language=`"$_`" />" }) -join "`n"
    @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap rescap">
  <Identity Name="$nameXml" Publisher="$publisherXml" Version="$versionXml" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$displayNameXml</DisplayName>
    <PublisherDisplayName>$publisherDisplayXml</PublisherDisplayName>
    <Description>Synchronized co-watching and 60 FPS live screen share application.</Description>
    <Logo>Images\StoreLogo.png</Logo>
  </Properties>
  <Resources>
$resourceXml
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Applications>
    <Application Id="Eir" Executable="eir.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="$displayNameXml" Description="Synchronized co-watching and 60 FPS live screen share application."
          Square150x150Logo="Images\Square150x150Logo.png" Square44x44Logo="Images\Square44x44Logo.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
"@
}

function Get-EirWindowsPayloadStatus {
    param([Parameter(Mandatory = $true)][string]$Bundle)
    if (-not (Test-Path -LiteralPath $Bundle)) {
        throw "Release bundle does not exist: $Bundle"
    }
    $required = @(
        'eir.exe',
        'flutter_windows.dll',
        'data\app.so',
        'data\icudtl.dat',
        'data\flutter_assets'
    )
    $runtime = @('vcruntime140.dll', 'msvcp140.dll', 'vcruntime140_1.dll')
    $missing = @()
    $missingRuntime = @()
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $Bundle $relative))) {
            $missing += $relative
        }
    }
    foreach ($relative in $runtime) {
        if (-not (Test-Path -LiteralPath (Join-Path $Bundle $relative))) {
            $missingRuntime += $relative
        }
    }
    [pscustomobject]@{
        Required       = $required
        Runtime        = $runtime
        Missing        = $missing
        MissingRuntime = $missingRuntime
    }
}

function Resolve-EirMakeAppx {
    param(
        [string]$SdkBin,
        [string]$MakeAppx
    )
    if (-not [string]::IsNullOrWhiteSpace($MakeAppx)) {
        if (-not (Test-Path -LiteralPath $MakeAppx)) {
            throw "makeappx not found at explicit path: $MakeAppx"
        }
        return (Resolve-Path -LiteralPath $MakeAppx).Path
    }
    if (-not [string]::IsNullOrWhiteSpace($SdkBin)) {
        $candidate = Join-Path $SdkBin 'makeappx.exe'
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $sdkRoots = @(
        'C:\Program Files (x86)\Windows Kits\10\bin',
        'C:\Program Files\Windows Kits\10\bin'
    )
    foreach ($root in $sdkRoots) {
        if (Test-Path -LiteralPath $root) {
            $candidates = Get-ChildItem -LiteralPath $root -Directory |
                Where-Object { $_.Name -match '^[0-9]+(\.[0-9]+)*$' } |
                Sort-Object -Property {
                    try { [version]$_.Name } catch { [version]'0.0.0.0' }
                } -Descending
            foreach ($versionDir in $candidates) {
                $candidate = Join-Path $versionDir.FullName 'x64\makeappx.exe'
                if (Test-Path -LiteralPath $candidate) {
                    return $candidate
                }
            }
        }
    }
    $fromPath = Get-Command makeappx.exe -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }
    throw 'makeappx.exe not found in Windows Kits or PATH'
}
