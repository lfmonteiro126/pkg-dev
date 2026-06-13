# Common Inventory Functions Module
# This module provides shared functions for hardware and software inventory operations
# Author: Luiz Monteiro

$script:ErrorActionPreference = "Stop"

<#
.SYNOPSIS
    Retrieves hardware information from the local system.
.DESCRIPTION
    Gathers computer manufacturer, model, OS details, memory, and disk space information.
.OUTPUTS
    PSCustomObject containing hardware properties
.EXAMPLE
    Get-HardwareInfo | Format-List
#>
function Get-HardwareInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = 'C:'" -ErrorAction Stop

        return [PSCustomObject]@{
            Make               = $computerSystem.Manufacturer
            Model              = $computerSystem.Model
            OSName             = $os.Caption
            OSVersion          = $os.Version
            TotalPhysicalMemoryGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
            FreeDiskSpaceGB    = [math]::Round($disk.FreeSpace / 1GB, 2)
        }
    }
    catch {
        Write-Error "Failed to retrieve hardware information: $_"
        throw
    }
}

<#
.SYNOPSIS
    Retrieves installed software information from the registry.
.DESCRIPTION
    Queries uninstall registry keys to gather installed application details including name, version, and install date.
.PARAMETER CurrentUser
    If specified, only queries HKCU registry hive. Otherwise, queries HKLM hives (both 32-bit and 64-bit).
.OUTPUTS
    Array of PSCustomObject containing software properties
.EXAMPLE
    Get-SoftwareInfo | Where-Object { $_.Name -like "*Office*" }
.EXAMPLE
    Get-SoftwareInfo -CurrentUser
#>
function Get-SoftwareInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [switch]$CurrentUser
    )

    try {
        if ($CurrentUser) {
            $uninstallPaths = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
        }
        else {
            $uninstallPaths = @(
                'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
                'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )
        }

        $apps = Get-ChildItem -Path $uninstallPaths -ErrorAction SilentlyContinue | 
                ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue }

        $results = foreach ($app in $apps) {
            if (-not $app.DisplayName) { 
                continue 
            }

            $installDate = $null
            if ($app.InstallDate -match '^\d{8}$') {
                $installDate = [datetime]::ParseExact($app.InstallDate, 'yyyyMMdd', $null).ToString('yyyy-MM-dd')
            }

            [PSCustomObject]@{
                Name           = $app.DisplayName
                Version        = $app.DisplayVersion
                InstallDate    = $installDate
                UninstallString = $app.UninstallString
                Publisher      = $app.Publisher
            }
        }

        return $results
    }
    catch {
        Write-Error "Failed to retrieve software information: $_"
        throw
    }
}

<#
.SYNOPSIS
    Checks if specific applications with required versions are installed.
.DESCRIPTION
    Reads a JSON configuration file specifying applications and versions to check, then compares against installed software.
.PARAMETER CheckFilePath
    Path to JSON file containing application definitions to check.
.OUTPUTS
    PSCustomObject containing detection results for each application
.EXAMPLE
    Invoke-Detection -CheckFilePath ".\detect_apps.json"
#>
function Invoke-Detection {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$CheckFilePath
    )

    try {
        $checkFile = Get-Content -Path $CheckFilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Error "Error loading check file '$CheckFilePath': $_"
        throw
    }

    $systemApps = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    $installedApps = Get-ChildItem -Path $systemApps -ErrorAction SilentlyContinue | 
                     ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue }

    foreach ($targetApp in $checkFile.Applications) {
        $app = $installedApps | Where-Object { $_.DisplayName -eq $targetApp.Name }

        $result = [PSCustomObject]@{
            ApplicationName  = $targetApp.Name
            TargetVersion    = $targetApp.Version
            InstalledVersion = $null
            Status           = $null
            Message          = $null
        }

        if (-not $app) {
            $result.Status = "NotFound"
            $result.Message = "Application not installed"
            $result
            continue
        }

        $result.InstalledVersion = $app.DisplayVersion

        try {
            $installedVersion = [version]$app.DisplayVersion
            $targetVersion = [version]$targetApp.Version

            if ($installedVersion -eq $targetVersion) {
                $result.Status = "Match"
                $result.Message = "Exact version match"
            }
            elseif ($installedVersion -lt $targetVersion) {
                $result.Status = "UpgradeRequired"
                $result.Message = "Older version installed (requires upgrade from $($app.DisplayVersion) to $($targetApp.Version))"
            }
            else {
                $result.Status = "NewerInstalled"
                $result.Message = "Newer version installed ($($app.DisplayVersion))"
            }
        }
        catch {
            # Version parsing failed, do string comparison
            if ($app.DisplayVersion -eq $targetApp.Version) {
                $result.Status = "Match"
                $result.Message = "Exact version match"
            }
            else {
                $result.Status = "VersionMismatch"
                $result.Message = "Version mismatch (installed: $($app.DisplayVersion), required: $($targetApp.Version))"
            }
        }

        $result
    }
}

# Export module members
Export-ModuleMember -Function Get-HardwareInfo, Get-SoftwareInfo, Invoke-Detection
