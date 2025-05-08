#Usage Mode

# Hardware mode
# .\Get-detect.ps1 -Hardware

# Software mode
# .\Get-detect.ps1 -Software

# Software mode (current user)
# .\Get-detect.ps1 -Software -CurrentUser

# Detection mode
# .\Get-detect.ps1 -Detect .\detect_apps.json

# Writen by Luiz Monteiro 

############################################################################################################


param(
    [Parameter(Mandatory=$true, ParameterSetName='Hardware')]
    [switch]$Hardware,
    
    [Parameter(Mandatory=$true, ParameterSetName='Software')]
    [switch]$Software,
    
    [Parameter(ParameterSetName='Software')]
    [switch]$CurrentUser,

    [Parameter(Mandatory=$true, ParameterSetName='Detect')]
    [string]$Detect
)

function Get-HardwareInfo {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = 'C:'"

    Write-Host "Hardware Information"
    Write-Host "-------------------"
    Write-Host "Make: $($computerSystem.Manufacturer)"
    Write-Host "Model: $($computerSystem.Model)"
    Write-Host "OS Name: $($os.Caption)"
    Write-Host "OS Version: $($os.Version)"
    Write-Host "Total Physical Memory: $([math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)) GB"
    Write-Host "Free Disk Space (C:): $([math]::Round($disk.FreeSpace / 1GB, 2)) GB"
}

function Get-SoftwareInfo {
    param([switch]$CurrentUser)

    if ($CurrentUser) {
        $uninstallPaths = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
    }
    else {
        $uninstallPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
    }

    $apps = Get-ChildItem -Path $uninstallPaths | ForEach-Object { Get-ItemProperty $_.PSPath }

    Write-Host "`nSoftware Information"
    Write-Host "-------------------"
    
    foreach ($app in $apps) {
        if (-not $app.DisplayName) { continue }

        $installDate = $app.InstallDate
        if ($installDate -match '^\d{8}$') {
            $installDate = [datetime]::ParseExact($installDate, 'yyyyMMdd', $null).ToString('yyyy-MM-dd')
        }

        Write-Host "Name: $($app.DisplayName)"
        Write-Host "Version: $($app.DisplayVersion)"
        Write-Host "Install Date: $installDate"
        Write-Host "Uninstall String: $($app.UninstallString)"
        Write-Host "`n"
    }
}

function Invoke-Detection {
    param(
        [string]$CheckFilePath
    )

    try {
        $checkFile = Get-Content $CheckFilePath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "Error loading check file: $_"
        exit 1
    }

    $systemApps = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installedApps = Get-ChildItem -Path $systemApps -ErrorAction SilentlyContinue | 
        ForEach-Object { Get-ItemProperty $_.PSPath }

    foreach ($targetApp in $checkFile.Applications) {
        $app = $installedApps | Where-Object { $_.DisplayName -eq $targetApp.Name }

        Write-Host "`nChecking: $($targetApp.Name)"
        Write-Host "----------------------------"

        if (-not $app) {
            Write-Host "Status: No version installed"
            continue
        }

        try {
            $installedVersion = [version]$app.DisplayVersion
            $targetVersion = [version]$targetApp.Version

            if ($installedVersion -eq $targetVersion) {
                Write-Host "Status: App already installed (exact version match)"
            }
            elseif ($installedVersion -lt $targetVersion) {
                Write-Host "Status: Older version installed (installed: $($app.DisplayVersion), required: $($targetApp.Version)"
            }
            else {
                Write-Host "Status: App installed with newer version (installed: $($app.DisplayVersion), required: $($targetApp.Version))"
            }
        }
        catch {
            if ($app.DisplayVersion -eq $targetApp.Version) {
                Write-Host "Status: App already installed (exact version match)"
            }
            else {
                Write-Host "Status: Version mismatch (installed: $($app.DisplayVersion), required: $($targetApp.Version))"
            }
        }
    }
}

# Main execution
if ($Hardware) {
    Get-HardwareInfo
}
elseif ($Software) {
    Get-SoftwareInfo -CurrentUser:$CurrentUser
}
elseif ($Detect) {
    Invoke-Detection -CheckFilePath $Detect
}