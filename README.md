# PowerShell Inventory and Detection Scripts

A collection of PowerShell scripts for system inventory, application detection, and Exchange mailbox backup to AWS S3.

## Scripts Overview

### 1. InventoryCommon.psm1 (Module)
A shared PowerShell module containing common functions used by other scripts:
- `Get-HardwareInfo` - Retrieves hardware information (make, model, OS, memory, disk space)
- `Get-SoftwareInfo` - Retrieves installed software information from registry
- `Invoke-Detection` - Checks if specific applications with required versions are installed

**Usage:**
```powershell
Import-Module .\InventoryCommon.psm1
$hardware = Get-HardwareInfo
$software = Get-SoftwareInfo -CurrentUser
$detection = Invoke-Detection -CheckFilePath ".\detect_apps.json"
```

### 2. Get-Inventory.ps1
Retrieves and displays hardware or software inventory information.

**Usage:**
```powershell
# Hardware mode
.\Get-Inventory.ps1 -Hardware

# Software mode (all users)
.\Get-Inventory.ps1 -Software

# Software mode (current user only)
.\Get-Inventory.ps1 -Software -CurrentUser
```

### 3. Get-detect.ps1
Detects hardware, software inventory, or checks for specific application versions.

**Usage:**
```powershell
# Hardware mode
.\Get-detect.ps1 -Hardware

# Software mode
.\Get-detect.ps1 -Software

# Application detection mode
.\Get-detect.ps1 -Detect .\detect_apps.json
```

### 4. BKP-AWS-Exchange.ps1
Scans Exchange 2019 mailboxes for recent modifications, exports modified mailboxes to PST, uploads them to AWS S3, and sends an HTML summary report.

**Usage:**
```powershell
# Default execution (7 days check)
.\BKP-AWS-Exchange.ps1

# Custom days to check, skip email report
.\BKP-AWS-Exchange.ps1 -DaysToCheck 14 -SkipEmailReport
```

## Configuration Files

### detect_apps.json
JSON configuration file specifying applications and versions to detect.

**Format:**
```json
{
    "Applications": [
        {
            "Name": "Application Name",
            "Version": "1.0.0"
        }
    ]
}
```

## Requirements

### For All Scripts
- PowerShell 5.1 or later
- Windows operating system

### For BKP-AWS-Exchange.ps1
- Exchange Management Shell
- AWS Tools for PowerShell (`AWSPowerShell` module)
- Access to a UNC share for PST exports
- SMTP server access for email reports

## Installation

1. Clone or download this repository
2. For BKP-AWS-Exchange.ps1, install AWS Tools:
   ```powershell
   Install-Module -Name AWSPowerShell -Force
   ```

## Notes

- To bypass execution policy restrictions:
  ```powershell
  powershell -ExecutionPolicy Bypass -File "C:\Path\To\Script.ps1"
  ```

- For production use of BKP-AWS-Exchange.ps1, configure AWS credentials using IAM roles or AWS CLI profiles instead of plain text keys.

## Author
Luiz Monteiro

## License
Use at your own risk. Review and test scripts in a non-production environment before deployment.
