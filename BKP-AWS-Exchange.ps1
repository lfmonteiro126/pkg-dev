<#
.SYNOPSIS
    Scans Exchange 2019 mailboxes for recent modifications, exports modified mailboxes to PST, 
    uploads them to AWS S3, and sends an HTML summary report.

.DESCRIPTION
    This script checks mailbox folder statistics for modifications within a specified timeframe. 
    If modifications are found, it initiates an asynchronous Exchange Export Request to a UNC share, 
    waits for completion, uploads the PST to AWS S3, and cleans up the local file.
#>

# ============================================================================
# 1. CONFIGURATION BLOCK
# ============================================================================
$config = @{
    # Exchange Settings
    DaysToCheckForModification = 7       # Check for modifications in the last X days
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
# 2. INITIALIZATION & LOGGING
# ============================================================================
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogPath = Join-Path $env:TEMP "ExchangeS3Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ReportData = [System.Collections.Generic.List[object]]::new()

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logEntry
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN"  { Write-Log $logEntry -Level "WARN"; Write-Host $logEntry -ForegroundColor Yellow }
        default { Write-Host $logEntry -ForegroundColor Green }
    }
}

Write-Log "Script started. Log file: $LogPath"

# ============================================================================
# 3. AWS AUTHENTICATION
# ============================================================================
try {
    Write-Log "Initializing AWS session..."
    if ($config.AWSAccessKey -and $config.AWSSecretKey) {
        $secureSecret = ConvertTo-SecureString $config.AWSSecretKey -AsPlainText -Force
        $awsCreds = New-Object Amazon.Runtime.BasicAWSCredentials($config.AWSAccessKey, $secureSecret)
        Set-AWSCredential -Credential $awsCreds -Region $config.AWSRegion
    } else {
        # Falls back to IAM Role (if on EC2) or default AWS CLI credentials profile
        Set-AWSCredential -Region $config.AWSRegion
    }
    Write-Log "AWS session initialized successfully."
} catch {
    Write-Log "Failed to initialize AWS session: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ============================================================================
# 4. MAIN EXECUTION LOOP
# ============================================================================
$cutoffDate = (Get-Date).AddDays(-$config.DaysToCheckForModification)
Write-Log "Checking for mailboxes modified since: $cutoffDate"

# Ensure UNC path is accessible
if (-not (Test-Path $config.ExportUncPath)) {
    Write-Log "Cannot access UNC Export Path: $($config.ExportUncPath)" "ERROR"
    exit 1
}

$mailboxes = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox
Write-Log "Found $($mailboxes.Count) mailboxes to evaluate."

foreach ($mbx in $mailboxes) {
    $mbxName = $mbx.PrimarySmtpAddress.ToString()
    $pstFileName = "$($mbx.Alias)_$(Get-Date -Format 'yyyyMMdd').pst"
    $localPstPath = Join-Path $config.ExportUncPath $pstFileName
    $s3Key = "$($config.S3Prefix)/$mbxName/$pstFileName"
    
    $reportEntry = [PSCustomObject]@{
        Mailbox      = $mbxName
        Status       = "Skipped"
        Details      = "No modifications found in the last $($config.DaysToCheckForModification) days."
        S3Upload     = "N/A"
    }

    try {
        Write-Log "Evaluating mailbox: $mbxName"
        
        # Check for recent modifications (Optimized: stops at first match to save performance)
        $recentChange = Get-MailboxFolderStatistics -Identity $mbx.Identity | 
                        Where-Object { $_.LastModificationTime -gt $cutoffDate } | 
                        Select-Object -First PV 1 # PV is a typo prevention, just Select-Object -First 1

        if ($null -eq $recentChange) {
            Write-Log "No recent changes in $mbxName. Skipping export." "INFO"
            $ReportData.Add($reportEntry)
            continue
        }

        Write-Log "Modifications detected in $mbxName. Initiating export..."

        # Clean up any stale export requests for this mailbox
        Get-MailboxExportRequest -Mailbox $mbx.Identity -ErrorAction SilentlyContinue | Remove-MailboxExportRequest -Confirm:$false

        # Start Export Request
        $exportReq = New-MailboxExportRequest -Mailbox $mbx.Identity -FilePath $localPstPath -BadItemLimit 50 -AcceptLargeDataLoss
        
        # Wait for completion
        $status = "InProgress"
        while ($status -in @("Queued", "InProgress")) {
            Start-Sleep -Seconds 15
            $currentReq = Get-MailboxExportRequest -Mailbox $mbx.Identity
            $status = $currentReq.Status
            Write-Log "Export status for $mbxName : $status"
        }

        if ($status -eq "Completed") {
            Write-Log "Export completed for $mbxName. Uploading to S3..."
            
            # Upload to S3
            Write-S3Object -BucketName $config.S3BucketName -Key $s3Key -File $localPstPath -Region $config.AWSRegion
            
            Write-Log "S3 Upload successful for $mbxName."
            
            $reportEntry.Status = "Success"
            $reportEntry.Details = "Exported and uploaded successfully."
            $reportEntry.S3Upload = "s3://$($config.S3BucketName)/$s3Key"
            
            # Cleanup local PST and Export Request
            Remove-Item -Path $localPstPath -Force -ErrorAction SilentlyContinue
            Get-MailboxExportRequest -Mailbox $mbx.Identity | Remove-MailboxExportRequest -Confirm:$false
            
        } else {
            $reportEntry.Status = "Failed"
            $reportEntry.Details = "Export request failed with status: $status"
            Write-Log "Export failed for $mbxName. Status: $status" "ERROR"
        }
    }
    catch {
        $reportEntry.Status = "Error"
        $reportEntry.Details = $_.Exception.Message
        Write-Log "Error processing $mbxName : $($_.Exception.Message)" "ERROR"
        
        # Attempt cleanup on error
        Get-MailboxExportRequest -Mailbox $mbx.Identity -ErrorAction SilentlyContinue | Remove-MailboxExportRequest -Confirm:$false
        if (Test-Path $localPstPath) { Remove-Item -Path $localPstPath -Force -ErrorAction SilentlyContinue }
    }
    
    $ReportData.Add($reportEntry)
}

# ============================================================================
# 5. REPORT GENERATION & EMAIL
# ============================================================================
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
        "Success" { "success" }
        "Failed", "Error" { "failed" }
        default { "skipped" }
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

try {
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
} catch {
    Write-Log "Failed to send email report: $($_.Exception.Message)" "ERROR"
}

Write-Log "Script execution completed."