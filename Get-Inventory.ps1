#Usage Mode

# Hardware mode
# .\Get-Inventory.ps1 -Hardware

# Software mode
# .\Get-Inventory.ps1 -Software

# Software mode (current user)
# .\Get-Inventory.ps1 -Software -CurrentUser

#note: PowerShell has built-in security to prevent the execution of potentially malicious scripts. The execution policy determines the conditions under which scripts can run
#use the parameter below, This will allow that script to run even if the execution policy is more restrictive
#powershell -ExecutionPolicy Bypass -File "C:\Path\To\Get-Inventory.ps1"

# Writen by Luiz Monteiro 

###############################################################################################################################################################################

param(
    [Parameter(Mandatory=$true, ParameterSetName='Hardware')]
    [switch]$Hardware,
    
    [Parameter(Mandatory=$true, ParameterSetName='Software')]
    [switch]$Software,
    
    [Parameter(ParameterSetName='Software')]
    [switch]$CurrentUser
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

if ($Hardware) {
    Get-HardwareInfo
}
elseif ($Software) {
    Get-SoftwareInfo -CurrentUser:$CurrentUser
}