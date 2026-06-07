# Get-detect.ps1
# Detection script for hardware, software inventory and application version detection
# Author: Luiz Monteiro

# Usage Examples:
# Hardware mode:      .\Get-detect.ps1 -Hardware
# Software mode:      .\Get-detect.ps1 -Software
# Current user:       .\Get-detect.ps1 -Software -CurrentUser
# Detection mode:     .\Get-detect.ps1 -Detect .\detect_apps.json
# Note: To bypass execution policy: powershell -ExecutionPolicy Bypass -File "C:\Path\To\Get-detect.ps1"

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Hardware')]
    [switch]$Hardware,
    
    [Parameter(Mandatory = $true, ParameterSetName = 'Software')]
    [switch]$Software,
    
    [Parameter(ParameterSetName = 'Software')]
    [switch]$CurrentUser,

    [Parameter(Mandatory = $true, ParameterSetName = 'Detect')]
    [ValidateScript({ Test-Path $_ })]
    [string]$Detect
)

# Import common functions from module
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptDir "InventoryCommon.psm1") -Force

<#
.SYNOPSIS
    Displays hardware information in a formatted manner.
#>
function Show-HardwareInfo {
    try {
        $hardware = Get-HardwareInfo
        
        Write-Host "`n=== Hardware Information ===" -ForegroundColor Cyan
        Write-Host "Make:               $($hardware.Make)"
        Write-Host "Model:              $($hardware.Model)"
        Write-Host "OS Name:            $($hardware.OSName)"
        Write-Host "OS Version:         $($hardware.OSVersion)"
        Write-Host "Total Physical Memory: $($hardware.TotalPhysicalMemoryGB) GB"
        Write-Host "Free Disk Space (C:): $($hardware.FreeDiskSpaceGB) GB"
        Write-Host ""
    }
    catch {
        Write-Error "Failed to display hardware information: $_"
        exit 1
    }
}

<#
.SYNOPSIS
    Displays software information in a formatted manner.
#>
function Show-SoftwareInfo {
    param([switch]$CurrentUser)
    
    try {
        $software = Get-SoftwareInfo -CurrentUser:$CurrentUser
        
        if (-not $software) {
            Write-Host "No software found."
            return
        }
        
        Write-Host "`n=== Software Information ===" -ForegroundColor Cyan
        Write-Host "Total applications found: $($software.Count)`n"
        
        foreach ($app in $software) {
            Write-Host "Name:             $($app.Name)"
            Write-Host "Version:          $($app.Version)"
            Write-Host "Install Date:     $($app.InstallDate)"
            Write-Host "Publisher:        $($app.Publisher)"
            Write-Host "Uninstall String: $($app.UninstallString)"
            Write-Host "---"
        }
    }
    catch {
        Write-Error "Failed to display software information: $_"
        exit 1
    }
}

<#
.SYNOPSIS
    Displays detection results in a formatted manner.
#>
function Show-DetectionResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CheckFilePath
    )
    
    try {
        $results = Invoke-Detection -CheckFilePath $CheckFilePath
        
        Write-Host "`n=== Application Detection Results ===" -ForegroundColor Cyan
        Write-Host ""
        
        foreach ($result in $results) {
            $statusColor = switch ($result.Status) {
                "Match"           { "Green" }
                "UpgradeRequired" { "Yellow" }
                "NotFound"        { "Red" }
                default           { "White" }
            }
            
            Write-Host "Application: $($result.ApplicationName)" -ForegroundColor White
            Write-Host "Target Version: $($result.TargetVersion)"
            Write-Host "Installed Version: $($result.InstalledVersion)"
            Write-Host "Status: $($result.Status)" -ForegroundColor $statusColor
            Write-Host "Details: $($result.Message)"
            Write-Host "---"
        }
    }
    catch {
        Write-Error "Failed to perform detection: $_"
        exit 1
    }
}

# Main execution logic
try {
    if ($Hardware) {
        Show-HardwareInfo
    }
    elseif ($Software) {
        Show-SoftwareInfo -CurrentUser:$CurrentUser
    }
    elseif ($Detect) {
        Show-DetectionResults -CheckFilePath $Detect
    }
}
catch {
    Write-Error "Script execution failed: $_"
    exit 1
}
