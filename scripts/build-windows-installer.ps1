[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = 'x64',

    [string]$BuildDirectory,

    [string]$OutputDirectory,

    [string]$Version,

    [string]$ArtifactLabel
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $repositoryRoot "build\windows\$Architecture\runner\Release"
}
$BuildDirectory = (Resolve-Path -LiteralPath $BuildDirectory).Path

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot 'dist'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
[void](New-Item -ItemType Directory -Force -Path $OutputDirectory)

if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionLine = Get-Content -LiteralPath (Join-Path $repositoryRoot 'pubspec.yaml') |
        Where-Object { $_ -match '^version:\s*([^+\s]+)' } |
        Select-Object -First 1
    if ($null -eq $versionLine) {
        throw 'Could not read the application version from pubspec.yaml.'
    }
    $Version = [regex]::Match($versionLine, '^version:\s*([^+\s]+)').Groups[1].Value
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Windows installer version must be X.Y.Z, got '$Version'."
}

if ([string]::IsNullOrWhiteSpace($ArtifactLabel)) {
    $ArtifactLabel = $Version
}
if ($ArtifactLabel -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') {
    throw "Artifact label contains unsupported filename characters: '$ArtifactLabel'."
}

foreach ($requiredPath in @(
    (Join-Path $BuildDirectory 'mithka.exe'),
    (Join-Path $BuildDirectory 'flutter_windows.dll'),
    (Join-Path $BuildDirectory 'tdjson.dll'),
    (Join-Path $BuildDirectory 'data\flutter_assets')
)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Windows release bundle is incomplete: missing $requiredPath. Run flutter clean before rebuilding when switching build modes."
    }
}

function Get-PeMachine([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file: $Path"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Invalid PE signature: $Path"
        }
        return $reader.ReadUInt16()
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$expectedMachine = if ($Architecture -eq 'arm64') { 0xAA64 } else { 0x8664 }
foreach ($binaryName in @('mithka.exe', 'flutter_windows.dll', 'tdjson.dll')) {
    $binaryPath = Join-Path $BuildDirectory $binaryName
    $actualMachine = Get-PeMachine $binaryPath
    if ($actualMachine -ne $expectedMachine) {
        throw ('{0} has PE machine 0x{1:X4}; expected {2} (0x{3:X4}).' -f `
            $binaryPath, $actualMachine, $Architecture, $expectedMachine)
    }
}

$command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
$compilerCandidates = @(
    $command.Source,
    $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe' }),
    $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe' }),
    $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe' }),
    $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe' }),
    $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe' }),
    $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe' })
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$compiler = $compilerCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if ($null -eq $compiler) {
    throw 'Inno Setup Compiler (ISCC.exe) was not found. Install JRSoftware.InnoSetup with winget.'
}

$outputBaseFilename = "mithka-$ArtifactLabel-windows-$Architecture-setup"
$definition = Join-Path $repositoryRoot 'windows\installer\mithka.iss'
$arguments = @(
    "/DAppVersion=$Version",
    "/DArchitecture=$Architecture",
    "/DSourceDir=$BuildDirectory",
    "/DOutputDir=$OutputDirectory",
    "/DOutputBaseFilename=$outputBaseFilename",
    "/DRepoRoot=$repositoryRoot",
    $definition
)

$compilerOutput = & $compiler @arguments 2>&1
$compilerExitCode = $LASTEXITCODE
$compilerOutput | ForEach-Object { Write-Host $_ }
if ($compilerExitCode -ne 0) {
    throw "Inno Setup failed with exit code $compilerExitCode."
}

$installer = Join-Path $OutputDirectory "$outputBaseFilename.exe"
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Inno Setup did not create the expected installer: $installer"
}

Write-Output $installer
