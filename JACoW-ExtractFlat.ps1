#Requires -Version 5.1
<#
.SYNOPSIS
Installs "JACoW: Extract Flat Here", or extracts the ZIP supplied as argument 1.
.DESCRIPTION
Run without a ZIP in an elevated PowerShell session on Windows to install.
Installation supports Windows PowerShell 5.1 and PowerShell 7 (pwsh.exe).
The registered context-menu command uses Windows' built-in powershell.exe.
Registration launches powershell.exe with -WindowStyle Hidden. A brief console
flash may still occur. No EXE launcher or compilation is used.
Keep this script and jacow_extract.ico together in a permanent local directory.
The registry verb is a top-level CLASSIC menu entry. Windows 11 normally exposes
classic verbs under Show more options; this is not a modern IExplorerCommand.
Extraction runs as the clicking user, never automatically elevated. Failures are
logged to %LOCALAPPDATA%\JACoW\ExtractFlat\errors.log without interactive UI.
An existing destination folder is reused; matching files are overwritten.
For duplicate flattened names, the last entry in archive order wins.
.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Tools\JACoW-ExtractFlat.ps1"
.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Tools\JACoW-ExtractFlat.ps1" "C:\Incoming\Conference papers.zip"
.NOTES
Optional future feature: a compiled Windows GUI launcher can eliminate the console
flash by starting PowerShell with UseShellExecute=false and CreateNoWindow=true.
To request this later, use this prompt:
"Add an optional -NoConsoleFlash installation switch to JACoW-ExtractFlat.ps1.
Compile a small Windows GUI EXE launcher locally using the .NET Framework compiler,
and register that launcher for the context-menu command. Have it invoke this script
with one safely quoted ZIP path, UseShellExecute=false, and CreateNoWindow=true.
Preserve overwrite behavior, the icon, error logging, and the default PowerShell-only
installation. Test paths containing spaces, brackets, ampersands, and apostrophes."
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $ZipPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-FailureLog {
    param([string] $Message)
    try {
        $logRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'JACoW\ExtractFlat'
        [void] [IO.Directory]::CreateDirectory($logRoot)
        $line = '[{0:O}] {1}{2}' -f [DateTime]::Now, $Message, [Environment]::NewLine
        [IO.File]::AppendAllText((Join-Path $logRoot 'errors.log'), $line, [Text.Encoding]::UTF8)
    }
    catch { # Logging must never open UI or mask the original failure.
    }
}

function Get-SafeLeafName {
    param([string] $ArchiveName)
    # Split both ZIP separators; never combine an archive path with the target.
    $leaf = ($ArchiveName -split '[/\\]')[-1]
    foreach ($character in [IO.Path]::GetInvalidFileNameChars()) {
        $leaf = $leaf.Replace([string] $character, '_')
    }
    $leaf = $leaf.TrimEnd([char[]] @(' ', '.'))
    if ([string]::IsNullOrEmpty($leaf)) { $leaf = '_file' }
    if ($leaf -match '^(?i:CON|PRN|AUX|NUL|COM[1-9\u00B9\u00B2\u00B3]|LPT[1-9\u00B9\u00B2\u00B3])(?:\.|$)') {
        $leaf = '_' + $leaf
    }
    return $leaf
}

function Expand-FlatZip {
    param([string] $LiteralZipPath)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $item = Get-Item -LiteralPath $LiteralZipPath -Force
    if ($item -isnot [IO.FileInfo] -or $item.Extension -ine '.zip') {
        throw 'Argument 1 must be the literal path of a .zip file.'
    }
    $baseName = [IO.Path]::GetFileNameWithoutExtension($item.Name)
    if ([string]::IsNullOrWhiteSpace($baseName)) { throw 'The ZIP has no usable base name.' }
    $destination = [IO.Path]::Combine($item.DirectoryName, $baseName)
    # Open the ZIP before creating any output, so invalid ZIPs leave no folder.
    $archive = [IO.Compression.ZipFile]::OpenRead($item.FullName)
    $failureCount = 0
    try {
        if ([IO.File]::Exists($destination)) {
            throw "A file already occupies the destination folder path: $destination"
        }
        [void] [IO.Directory]::CreateDirectory($destination)
        if (([IO.File]::GetAttributes($destination) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "The destination is a junction or symbolic link: $destination"
        }

        foreach ($entry in $archive.Entries) {
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) { continue }
            $outputStream = $null
            $inputStream = $null
            $createdPath = $null
            $entryComplete = $false
            try {
                $leaf = Get-SafeLeafName $entry.FullName
                $candidate = [IO.Path]::Combine($destination, $leaf)
                if (Test-Path -LiteralPath $candidate) {
                    $attributes = [IO.File]::GetAttributes($candidate)
                    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw "The output file is a junction or symbolic link: $candidate"
                    }
                    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                        throw "A directory occupies the output file path: $candidate"
                    }
                    if (($attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {
                        [IO.File]::SetAttributes($candidate, ($attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
                    }
                }
                $inputStream = $entry.Open()
                # Create truncates an existing file, including any longer old content.
                # Later entries with the same flattened name replace earlier entries.
                $outputStream = [IO.File]::Open($candidate, [IO.FileMode]::Create,
                    [IO.FileAccess]::Write, [IO.FileShare]::None)
                $createdPath = $candidate
                $inputStream.CopyTo($outputStream)
                $outputStream.Flush()
                $entryComplete = $true
            }
            catch {
                $failureCount++
                Write-FailureLog ('ZIP: {0}; entry: {1}; {2}' -f $item.FullName, $entry.FullName, $_.Exception.Message)
            }
            finally {
                if ($null -ne $inputStream) { $inputStream.Dispose() }
                if ($null -ne $outputStream) { $outputStream.Dispose() }
                if (-not $entryComplete -and $null -ne $createdPath) {
                    try { [IO.File]::Delete($createdPath) }
                    catch { Write-FailureLog "Could not remove partial file '$createdPath': $($_.Exception.Message)" }
                }
            }
        }
    }
    finally { $archive.Dispose() }
    if ($failureCount -gt 0) {
        throw "$failureCount entry/entries failed. Successfully extracted files have been retained in '$destination'."
    }
}



function Install-ContextMenu {
    param([string] $ScriptPath)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Installation requires an elevated PowerShell session (Run as administrator).'
        }
    }
    finally { $identity.Dispose() }

    $icon = Join-Path ([IO.Path]::GetDirectoryName($ScriptPath)) 'jacow_extract.ico'
    if (-not [IO.File]::Exists($icon)) { throw "Place jacow_extract.ico beside the script first: $icon" }
    # Exact command requested. %1 is passed as a quoted argument to -File,
    # never interpolated into executable PowerShell source.
    $command = 'powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "{0}" "%1"' -f $ScriptPath

    # Explicit registry view also works when installation uses 32-bit PowerShell.
    $view = [Microsoft.Win32.RegistryView]::Registry32
    if ([Environment]::Is64BitOperatingSystem) { $view = [Microsoft.Win32.RegistryView]::Registry64 }
    $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
    $verb = $null
    $commandKey = $null
    try {
        $verb = $hklm.CreateSubKey('SOFTWARE\Classes\SystemFileAssociations\.zip\Shell\ExtractFlat')
        $verb.SetValue('', 'JACoW: Extract Flat Here', [Microsoft.Win32.RegistryValueKind]::String)
        $verb.SetValue('MUIVerb', 'JACoW: Extract Flat Here', [Microsoft.Win32.RegistryValueKind]::String)
        $verb.SetValue('Icon', ('"{0}",0' -f $icon), [Microsoft.Win32.RegistryValueKind]::String)
        $verb.SetValue('MultiSelectModel', 'Single', [Microsoft.Win32.RegistryValueKind]::String)
        $verb.SetValue('Position', 'Top', [Microsoft.Win32.RegistryValueKind]::String)
        $commandKey = $verb.CreateSubKey('command')
        $commandKey.SetValue('', $command, [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally {
        if ($null -ne $commandKey) { $commandKey.Dispose() }
        if ($null -ne $verb) { $verb.Dispose() }
        $hklm.Dispose()
    }
    Write-Host 'Installed: JACoW: Extract Flat Here'
    Write-Host ('Command: ' + $command)
}

if ($PSBoundParameters.ContainsKey('ZipPath')) {
    try {
        Expand-FlatZip $ZipPath
        exit 0
    }
    catch {
        Write-FailureLog ('ZIP: {0}; {1}' -f $ZipPath, $_.Exception.Message)
        exit 1
    }
}

try {
    Install-ContextMenu -ScriptPath $PSCommandPath
}
catch {
    Write-FailureLog ('Installation: ' + $_.Exception.Message)
    Write-Error $_ -ErrorAction Continue
    exit 1
}
