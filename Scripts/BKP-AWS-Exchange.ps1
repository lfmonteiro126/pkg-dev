<#
.SYNOPSIS
    Scans Exchange 2019 mailboxes for recent modifications, exports modified mailboxes to PST, 
    uploads them to AWS S3, and sends an HTML summary report.

.DESCRIPTION
    This script checks mailbox folder statistics for modifications within a specified timeframe. 
    If modifications are found, it initiates an asynchronous Exchange Export Request to a UNC share, 
    waits for completion, uploads the PST to AWS S3, and cleans up the local file.

.PARAMETER DaysToCheck
    Number of days to check for mailbox modifications (default: 7)

.PARAMETER SkipEmailReport
    Skip sending email report after completion

.EXAMPLE
    .\BKP-AWS-Exchange.ps1
    
.EXAMPLE
    .\BKP-AWS-Exchange.ps1 -DaysToCheck 14 -SkipEmailReport
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$DaysToCheck = 7,
    
    [Parameter()]
    [switch]$SkipEmailReport
)

# ============================================================================
# CONFIGURATION
# ============================================================================
$config = @{
    # Exchange Settings
    DaysToCheckForModification = $DaysToCheck
    ExportUncPath              = "\\FILESERVER\ExchangeExports$" # MUST be a UNC path with Read/Write permissions
    
    # AWS S3 Settings
    S3BucketName               = "your-company-exchange-backups"
    S3Prefix                   = "exchange-mailboxes"            # Folder structure inside the bucket
    AWSRegion                  = "us-east-1"                     # Change to your AWS region
    # Note: For production, use IAM Roles (if on EC2) or AWS Credential profiles instead of plain text keys.
    # AWSAccessKey             = "YOUR_ACCESS_KEY"               # Uncomment if not using IAM role/Profile
    # AWSSecretKey             = "YOUR_SECRET_KEY"               # Uncomment if not using IAM role/Profile
    
    # Email Report Settings
    SmtpServer                 = "smtp.yourdomain.com"
    SmtpPort                   = 587
    UseSsl                     = $true
    EmailFrom                  = "exchange-backup@yourdomain.com"
    EmailTo                    = "admin@yourdomain.com"
    EmailSubject               = "Exchange to S3 Backup Report - $(Get-Date -Format 'yyyy-MM-dd')"
    EmailCredential            = $null # e.g., Get-Credential, or leave $null for anonymous/internal relay
}

# ============================================================================
# INITIALIZATION & LOGGING
# ============================================================================
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogPath = Join-Path $env:TEMP "ExchangeS3Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ReportData = [System.Collections.Generic.List[object]]::new()

<#
.SYNOPSIS
    Writes a log entry to file and console.
.PARAMETER Message
    The message to log.
.PARAMETER Level
    Log level (INFO, WARN, ERROR).
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logEntry -ErrorAction Stop
    
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        default { Write-Host $logEntry -ForegroundColor Green }
    }
}

<#
.SYNOPSIS
    Initializes AWS credentials and session.
#>
function Initialize-AWSSession {
    try {
        Write-Log "Initializing AWS session..."
        
        if ($config.AWSAccessKey -and $config.AWSSecretKey) {
            $secureSecret = ConvertTo-SecureString $config.AWSSecretKey -AsPlainText -Force
            $awsCreds = New-Object Amazon.Runtime.BasicAWSCredentials($config.AWSAccessKey, $secureSecret)
            Set-AWSCredential -Credential $awsCreds -Region $config.AWSRegion
        }
        else {
            # Falls back to IAM Role (if on EC2) or default AWS CLI credentials profile
            Set-AWSCredential -Region $config.AWSRegion
        }
        
        Write-Log "AWS session initialized successfully."
    }
    catch {
        Write-Log "Failed to initialize AWS session: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

<#
.SYNOPSIS
    Checks if a mailbox has been modified within the specified timeframe.
.PARAMETER MailboxIdentity
    The mailbox identity to check.
.PARAMETER CutoffDate
    The cutoff date for modifications.
.OUTPUTS
    Boolean indicating if modifications were found.
#>
function Test-MailboxModified {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MailboxIdentity,
        
        [Parameter(Mandatory = $true)]
        [datetime]$CutoffDate
    )
    
    try {
        $recentChange = Get-MailboxFolderStatistics -Identity $MailboxIdentity | 
                        Where-Object { $_.LastModificationTime -gt $CutoffDate } | 
                        Select-Object -First 1
        
        return $null -ne $recentChange
    }
    catch {
        Write-Log "Error checking mailbox folders for $MailboxIdentity : $($_.Exception.Message)" -Level ERROR
        throw
    }
}

<#
.SYNOPSIS
    Exports a mailbox to PST file.
.PARAMETER MailboxIdentity
    The mailbox identity to export.
.PARAMETER FilePath
    The destination file path for the PST.
.OUTPUTS
    The export request object.
#>
function Start-MailboxExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MailboxIdentity,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    try {
        # Clean up any stale export requests for this mailbox
        Get-MailboxExportRequest -Mailbox $MailboxIdentity -ErrorAction SilentlyContinue | 
            Remove-MailboxExportRequest -Confirm:$false
        
        # Start Export Request
        $exportReq = New-MailboxExportRequest -Mailbox $MailboxIdentity -FilePath $FilePath -BadItemLimit 50 -AcceptLargeDataLoss
        
        # Wait for completion
        $status = "InProgress"
        while ($status -in @("Queued", "InProgress")) {
            Start-Sleep -Seconds 15
            $currentReq = Get-MailboxExportRequest -Mailbox $MailboxIdentity
            $status = $currentReq.Status
            Write-Log "Export status for $MailboxIdentity : $status"
        }
        
        return $status -eq "Completed"
    }
    catch {
        Write-Log "Error exporting mailbox $MailboxIdentity : $($_.Exception.Message)" -Level ERROR
        throw
    }
}

<#
.SYNOPSIS
    Uploads a file to AWS S3.
.PARAMETER FilePath
    Local file path to upload.
.PARAMETER BucketName
    S3 bucket name.
.PARAMETER Key
    S3 object key.
#>
function Upload-ToS3 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$BucketName,
        
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    
    try {
        Write-S3Object -BucketName $BucketName -Key $Key -File $FilePath -Region $config.AWSRegion
        Write-Log "S3 upload successful for $Key"
    }
    catch {
        Write-Log "S3 upload failed for $Key : $($_.Exception.Message)" -Level ERROR
        throw
    }
}

<#
.SYNOPSIS
    Cleans up export request and local PST file.
.PARAMETER MailboxIdentity
    The mailbox identity.
.PARAMETER FilePath
    Local PST file path.
#>
function Cleanup-Export {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MailboxIdentity,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    try {
        Get-MailboxExportRequest -Mailbox $MailboxIdentity -ErrorAction SilentlyContinue | 
            Remove-MailboxExportRequest -Confirm:$false
        
        if (Test-Path $FilePath) {
            Remove-Item -Path $FilePath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log "Cleanup warning for $MailboxIdentity : $($_.Exception.Message)" -Level WARN
    }
}

<#
.SYNOPSIS
    Generates and sends HTML email report.
#>
function Send-EmailReport {
    try {
        Write-Log "Generating HTML report..."
        
        $successCount = ($ReportData | Where-Object Status -eq "Success").Count
        $failedCount  = ($ReportData | Where-Object Status -in @("Failed", "Error")).Count
        $skippedCount = ($ReportData | Where-Object Status -eq "Skipped").Count
        
        $htmlBody = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h2 { color: #2c3e50; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; color: #333; }
        .success { color: green; font-weight: bold; }
        .failed { color: red; font-weight: bold; }
        .skipped { color: orange; font-weight: bold; }
        .summary { background-color: #e8f4f8; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h2>Exchange to S3 Backup Report</h2>
    <div class="summary">
        <strong>Date:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br>
        <strong>Total Mailboxes Evaluated:</strong> $($ReportData.Count)<br>
        <strong class="success">Successfully Backed Up:</strong> $successCount<br>
        <strong class="skipped">Skipped (No Changes):</strong> $skippedCount<br>
        <strong class="failed">Failed/Errors:</strong> $failedCount
    </div>
    <h3>Detailed Results</h3>
    <table>
        <tr>
            <th>Mailbox</th>
            <th>Status</th>
            <th>Details</th>
            <th>S3 Location</th>
        </tr>
"@
        
        foreach ($row in $ReportData) {
            $statusClass = switch ($row.Status) {
                "Success"       { "success" }
                "Failed", "Error" { "failed" }
                default         { "skipped" }
            }
            
            $htmlBody += @"
        <tr>
            <td>$($row.Mailbox)</td>
            <td class="$statusClass">$($row.Status)</td>
            <td>$($row.Details)</td>
            <td>$($row.S3Upload)</td>
        </tr>
"@
        }
        
        $htmlBody += "</table></body></html>"
        
        $mailParams = @{
            SmtpServer  = $config.SmtpServer
            Port        = $config.SmtpPort
            UseSsl      = $config.UseSsl
            From        = $config.EmailFrom
            To          = $config.EmailTo
            Subject     = $config.EmailSubject
            Body        = $htmlBody
            BodyAsHtml  = $true
        }
        
        if ($config.EmailCredential) {
            $mailParams.Credential = $config.EmailCredential
        }
        
        Send-MailMessage @mailParams
        Write-Log "Email report sent successfully to $($config.EmailTo)"
    }
    catch {
        Write-Log "Failed to send email report: $($_.Exception.Message)" -Level ERROR
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
try {
    Write-Log "Script started. Log file: $LogPath"
    
    # Initialize AWS session
    Initialize-AWSSession
    
    # Calculate cutoff date
    $cutoffDate = (Get-Date).AddDays(-$config.DaysToCheckForModification)
    Write-Log "Checking for mailboxes modified since: $cutoffDate"
    
    # Validate UNC path accessibility
    if (-not (Test-Path $config.ExportUncPath)) {
        Write-Log "Cannot access UNC Export Path: $($config.ExportUncPath)" -Level ERROR
        exit 1
    }
    
    # Get all mailboxes
    $mailboxes = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox
    Write-Log "Found $($mailboxes.Count) mailboxes to evaluate."
    
    foreach ($mbx in $mailboxes) {
        $mbxName = $mbx.PrimarySmtpAddress.ToString()
        $pstFileName = "$($mbx.Alias)_$(Get-Date -Format 'yyyyMMdd').pst"
        $localPstPath = Join-Path $config.ExportUncPath $pstFileName
        $s3Key = "$($config.S3Prefix)/$mbxName/$pstFileName"
        
        $reportEntry = [PSCustomObject]@{
            Mailbox  = $mbxName
            Status   = "Skipped"
            Details  = "No modifications found in the last $($config.DaysToCheckForModification) days."
            S3Upload = "N/A"
        }
        
        try {
            Write-Log "Evaluating mailbox: $mbxName"
            
            # Check for recent modifications
            if (-not (Test-MailboxModified -MailboxIdentity $mbx.Identity -CutoffDate $cutoffDate)) {
                Write-Log "No recent changes in $mbxName. Skipping export."
                $ReportData.Add($reportEntry)
                continue
            }
            
            Write-Log "Modifications detected in $mbxName. Initiating export..."
            
            # Export mailbox
            if (Start-MailboxExport -MailboxIdentity $mbx.Identity -FilePath $localPstPath) {
                Write-Log "Export completed for $mbxName. Uploading to S3..."
                
                # Upload to S3
                Upload-ToS3 -FilePath $localPstPath -BucketName $config.S3BucketName -Key $s3Key
                
                $reportEntry.Status = "Success"
                $reportEntry.Details = "Exported and uploaded successfully."
                $reportEntry.S3Upload = "s3://$($config.S3BucketName)/$s3Key"
                
                # Cleanup
                Cleanup-Export -MailboxIdentity $mbx.Identity -FilePath $localPstPath
            }
            else {
                $reportEntry.Status = "Failed"
                $reportEntry.Details = "Export request failed"
                Write-Log "Export failed for $mbxName" -Level ERROR
            }
        }
        catch {
            $reportEntry.Status = "Error"
            $reportEntry.Details = $_.Exception.Message
            Write-Log "Error processing $mbxName : $($_.Exception.Message)" -Level ERROR
            
            # Attempt cleanup on error
            Cleanup-Export -MailboxIdentity $mbx.Identity -FilePath $localPstPath
        }
        
        $ReportData.Add($reportEntry)
    }
    
    # Send email report if not skipped
    if (-not $SkipEmailReport) {
        Send-EmailReport
    }
    
    Write-Log "Script execution completed."
}
catch {
    Write-Log "Fatal script error: $($_.Exception.Message)" -Level ERROR
    exit 1
}
