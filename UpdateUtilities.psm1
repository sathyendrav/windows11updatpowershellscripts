<#
.SYNOPSIS
    Core utility module providing logging, configuration, and pre-flight checks.

.DESCRIPTION
    This module provides shared functionality for all update scripts including:
    - Configuration management
    - Logging and transcript management
    - Pre-flight system checks
    - Report generation
    - Notification handling
#>

# ============================================================================
# Configuration Management
# ============================================================================

function Get-UpdateConfig {
    <#
    .SYNOPSIS
        Loads configuration from config.json file.
    #>
    param(
        [string]$ConfigPath = "$PSScriptRoot\..\config.json"
    )
    
    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            return $config
        } catch {
            Write-Warning "Failed to load config.json. Using defaults. Error: $_"
            return $null
        }
    } else {
        Write-Warning "config.json not found at $ConfigPath. Using defaults."
        return $null
    }
}

# ============================================================================
# Logging Functions
# ============================================================================

function Initialize-Logging {
    <#
    .SYNOPSIS
        Initializes logging for the update session.
    #>
    param(
        [string]$LogDirectory = ".\logs",
        [string]$ScriptName = "update-script"
    )
    
    # Create logs directory if it doesn't exist
    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    
    # Generate log filename with timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $logFile = Join-Path $LogDirectory "$ScriptName-$timestamp.log"
    
    # Start transcript
    try {
        Start-Transcript -Path $logFile -Append -ErrorAction Stop
        Write-Log "=== Update Session Started ===" -Level "Info"
        Write-Log "Script: $ScriptName" -Level "Info"
        Write-Log "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "Info"
        return $logFile
    } catch {
        Write-Warning "Failed to start transcript: $_"
        return $null
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message with timestamp and level.
    #>
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info",
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with color unless suppressed
    if (-not $NoConsole) {
        $color = switch ($Level) {
            "Info"    { "White" }
            "Warning" { "Yellow" }
            "Error"   { "Red" }
            "Success" { "Green" }
        }
        Write-Host $logMessage -ForegroundColor $color
    }
    
    # Write to transcript (automatically logged when transcript is active)
    Write-Verbose $logMessage
}

function Stop-Logging {
    <#
    .SYNOPSIS
        Stops the transcript logging session.
    #>
    param(
        [string]$LogFile
    )
    
    Write-Log "=== Update Session Completed ===" -Level "Info"
    Write-Log "Log file: $LogFile" -Level "Info"
    
    try {
        Stop-Transcript -ErrorAction SilentlyContinue
    } catch {
        # Transcript may not be running
    }
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Performs pre-flight checks before running updates.
    #>
    param(
        [switch]$CheckInternet,
        [switch]$CheckDiskSpace,
        [switch]$CheckAdmin,
        [int]$MinFreeSpaceGB = 10
    )
    
    $allChecksPassed = $true
    
    Write-Log "Running pre-flight checks..." -Level "Info"
    
    # Check Administrator privileges
    if ($CheckAdmin) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Log "NOT running as Administrator. Some features may not work." -Level "Warning"
        } else {
            Write-Log "Running with Administrator privileges." -Level "Success"
        }
    }
    
    # Check internet connectivity
    if ($CheckInternet) {
        try {
            $testConnection = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction Stop
            if ($testConnection) {
                Write-Log "Internet connectivity: OK" -Level "Success"
            } else {
                Write-Log "No internet connectivity detected." -Level "Error"
                $allChecksPassed = $false
            }
        } catch {
            Write-Log "Could not verify internet connectivity: $_" -Level "Warning"
        }
    }
    
    # Check disk space
    if ($CheckDiskSpace) {
        $systemDrive = Get-PSDrive -Name ($env:SystemDrive -replace ':', '') -ErrorAction SilentlyContinue
        if ($systemDrive) {
            $freeSpaceGB = [math]::Round($systemDrive.Free / 1GB, 2)
            if ($freeSpaceGB -lt $MinFreeSpaceGB) {
                Write-Log "Low disk space: ${freeSpaceGB}GB free (minimum ${MinFreeSpaceGB}GB recommended)" -Level "Warning"
                $allChecksPassed = $false
            } else {
                Write-Log "Disk space: ${freeSpaceGB}GB free" -Level "Success"
            }
        }
    }
    
    Write-Log "Pre-flight checks completed." -Level "Info"
    return $allChecksPassed
}

function Test-UpdateSource {
    <#
    .SYNOPSIS
        Tests if an update source (Winget, Chocolatey, Store) is available.
    #>
    param(
        [ValidateSet("Winget", "Chocolatey", "Store")]
        [string]$Source
    )
    
    switch ($Source) {
        "Winget" {
            return (Get-Command winget -ErrorAction SilentlyContinue) -ne $null
        }
        "Chocolatey" {
            return (Get-Command choco -ErrorAction SilentlyContinue) -ne $null
        }
        "Store" {
            # Check if MDM namespace is accessible
            try {
                $null = Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" -ErrorAction Stop
                return $true
            } catch {
                return $false
            }
        }
    }
}

# ============================================================================
# Update History Database (JSON)
# ============================================================================

function Initialize-UpdateHistory {
    <#
    .SYNOPSIS
        Initializes the update history database (JSON file).
    .DESCRIPTION
        Creates the update history JSON file if it doesn't exist.
    .PARAMETER HistoryPath
        Path to the history JSON file.
    .EXAMPLE
        Initialize-UpdateHistory -HistoryPath ".\logs\update-history.json"
    #>
    param(
        [string]$HistoryPath = ".\logs\update-history.json"
    )
    
    try {
        # Ensure directory exists
        $directory = Split-Path -Parent $HistoryPath
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # Create file if it doesn't exist
        if (-not (Test-Path $HistoryPath)) {
            @() | ConvertTo-Json | Set-Content -Path $HistoryPath -Encoding UTF8
            Write-Verbose "Created new update history database at: $HistoryPath"
        }
        
        return $true
    } catch {
        Write-Warning "Failed to initialize update history: $_"
        return $false
    }
}

function Add-UpdateHistoryEntry {
    <#
    .SYNOPSIS
        Adds an entry to the update history database.
    .DESCRIPTION
        Records package update operations with timestamp, version info, and status.
    .PARAMETER PackageName
        Name/ID of the package.
    .PARAMETER Version
        Version that was installed/upgraded to.
    .PARAMETER PreviousVersion
        Previous version before the update (if available).
    .PARAMETER Source
        Package source: Store, Winget, or Chocolatey.
    .PARAMETER Operation
        Type of operation: Install, Upgrade, Uninstall, Rollback.
    .PARAMETER Success
        Whether the operation succeeded.
    .PARAMETER ErrorMessage
        Error message if the operation failed.
    .PARAMETER HistoryPath
        Path to the history JSON file.
    .EXAMPLE
        Add-UpdateHistoryEntry -PackageName "7zip.7zip" -Version "23.01" -Source "Winget" -Operation "Upgrade" -Success $true
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [string]$Version,
        
        [string]$PreviousVersion = "Unknown",
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Install", "Upgrade", "Uninstall", "Rollback", "Scan")]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [bool]$Success,
        
        [string]$ErrorMessage = "",
        
        [string]$HistoryPath = ".\logs\update-history.json"
    )
    
    try {
        # Initialize history file if needed
        Initialize-UpdateHistory -HistoryPath $HistoryPath | Out-Null
        
        # Create new entry
        $entry = [PSCustomObject]@{
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            PackageName = $PackageName
            Version = $Version
            PreviousVersion = $PreviousVersion
            Source = $Source
            Operation = $Operation
            Success = $Success
            ErrorMessage = $ErrorMessage
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
        }
        
        # Load existing history
        $history = @()
        if (Test-Path $HistoryPath) {
            $content = Get-Content -Path $HistoryPath -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $history = $content | ConvertFrom-Json
                if ($history -isnot [array]) {
                    $history = @($history)
                }
            }
        }
        
        # Add new entry
        $history += $entry
        
        # Save back to file
        $history | ConvertTo-Json -Depth 10 | Set-Content -Path $HistoryPath -Encoding UTF8
        
        Write-Verbose "Added update history entry for $PackageName"
        return $true
    } catch {
        Write-Warning "Failed to add update history entry: $_"
        return $false
    }
}

function Get-UpdateHistory {
    <#
    .SYNOPSIS
        Retrieves update history from the database.
    .DESCRIPTION
        Queries the update history JSON file with optional filters.
    .PARAMETER PackageName
        Filter by package name (supports wildcards).
    .PARAMETER Source
        Filter by source: Store, Winget, or Chocolatey.
    .PARAMETER Operation
        Filter by operation type.
    .PARAMETER Days
        Number of days of history to retrieve (default: all).
    .PARAMETER Success
        Filter by success status (true/false).
    .PARAMETER HistoryPath
        Path to the history JSON file.
    .EXAMPLE
        Get-UpdateHistory -Days 7
    .EXAMPLE
        Get-UpdateHistory -PackageName "*chrome*" -Source Winget
    .EXAMPLE
        Get-UpdateHistory -Success $false
    #>
    param(
        [string]$PackageName,
        
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [ValidateSet("Install", "Upgrade", "Uninstall", "Rollback", "Scan")]
        [string]$Operation,
        
        [int]$Days,
        
        [bool]$Success,
        
        [string]$HistoryPath = ".\logs\update-history.json"
    )
    
    try {
        # Check if history file exists
        if (-not (Test-Path $HistoryPath)) {
            Write-Verbose "No update history found at: $HistoryPath"
            return @()
        }
        
        # Load history
        $content = Get-Content -Path $HistoryPath -Raw
        if (-not $content) {
            return @()
        }
        
        $history = $content | ConvertFrom-Json
        if ($history -isnot [array]) {
            $history = @($history)
        }
        
        # Apply filters
        if ($PackageName) {
            $history = $history | Where-Object { $_.PackageName -like $PackageName }
        }
        
        if ($Source) {
            $history = $history | Where-Object { $_.Source -eq $Source }
        }
        
        if ($Operation) {
            $history = $history | Where-Object { $_.Operation -eq $Operation }
        }
        
        if ($PSBoundParameters.ContainsKey('Success')) {
            $history = $history | Where-Object { $_.Success -eq $Success }
        }
        
        if ($Days) {
            $cutoffDate = (Get-Date).AddDays(-$Days)
            $history = $history | Where-Object { 
                [DateTime]::Parse($_.Timestamp) -gt $cutoffDate 
            }
        }
        
        return $history
    } catch {
        Write-Warning "Failed to retrieve update history: $_"
        return @()
    }
}

function Clear-UpdateHistory {
    <#
    .SYNOPSIS
        Clears old entries from the update history database.
    .DESCRIPTION
        Removes entries older than specified days to keep database manageable.
    .PARAMETER Days
        Keep entries from the last N days (default: 90).
    .PARAMETER HistoryPath
        Path to the history JSON file.
    .EXAMPLE
        Clear-UpdateHistory -Days 30
    #>
    param(
        [int]$Days = 90,
        [string]$HistoryPath = ".\logs\update-history.json"
    )
    
    try {
        if (-not (Test-Path $HistoryPath)) {
            Write-Verbose "No history file to clear"
            return $true
        }
        
        # Load history
        $content = Get-Content -Path $HistoryPath -Raw
        if (-not $content) {
            return $true
        }
        
        $history = $content | ConvertFrom-Json
        if ($history -isnot [array]) {
            $history = @($history)
        }
        
        $originalCount = $history.Count
        $cutoffDate = (Get-Date).AddDays(-$Days)
        
        # Keep only recent entries
        $history = $history | Where-Object { 
            [DateTime]::Parse($_.Timestamp) -gt $cutoffDate 
        }
        
        # Save filtered history
        $history | ConvertTo-Json -Depth 10 | Set-Content -Path $HistoryPath -Encoding UTF8
        
        $removed = $originalCount - $history.Count
        Write-Verbose "Cleared $removed old entries from update history"
        return $true
    } catch {
        Write-Warning "Failed to clear update history: $_"
        return $false
    }
}

function Export-UpdateHistoryReport {
    <#
    .SYNOPSIS
        Exports update history to a formatted report.
    .DESCRIPTION
        Generates HTML or CSV report from update history database.
    .PARAMETER Format
        Report format: HTML or CSV.
    .PARAMETER OutputPath
        Path to save the report.
    .PARAMETER Days
        Number of days of history to include.
    .PARAMETER HistoryPath
        Path to the history JSON file.
    .EXAMPLE
        Export-UpdateHistoryReport -Format HTML -OutputPath ".\reports\history.html" -Days 30
    #>
    param(
        [ValidateSet("HTML", "CSV")]
        [string]$Format = "HTML",
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [int]$Days = 30,
        
        [string]$HistoryPath = ".\logs\update-history.json"
    )
    
    try {
        # Get history
        $history = Get-UpdateHistory -Days $Days -HistoryPath $HistoryPath
        
        if ($history.Count -eq 0) {
            Write-Warning "No history entries found for the specified period"
            return $false
        }
        
        # Ensure output directory exists
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        switch ($Format) {
            "CSV" {
                $history | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            }
            "HTML" {
                $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Update History Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        .summary { background: #e7f3ff; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #0078d4; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f9f9f9; }
        .success { color: #107c10; font-weight: bold; }
        .failure { color: #d13438; font-weight: bold; }
        .source-store { background: #0078d4; color: white; padding: 3px 8px; border-radius: 3px; font-size: 0.85em; }
        .source-winget { background: #f7630c; color: white; padding: 3px 8px; border-radius: 3px; font-size: 0.85em; }
        .source-chocolatey { background: #80b5e3; color: white; padding: 3px 8px; border-radius: 3px; font-size: 0.85em; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Update History Report</h1>
        <div class="summary">
            <strong>Period:</strong> Last $Days days<br>
            <strong>Total Entries:</strong> $($history.Count)<br>
            <strong>Successful:</strong> $($history | Where-Object { $_.Success } | Measure-Object | Select-Object -ExpandProperty Count)<br>
            <strong>Failed:</strong> $($history | Where-Object { -not $_.Success } | Measure-Object | Select-Object -ExpandProperty Count)<br>
            <strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        </div>
        
        <table>
            <tr>
                <th>Timestamp</th>
                <th>Package</th>
                <th>Version</th>
                <th>Previous</th>
                <th>Source</th>
                <th>Operation</th>
                <th>Status</th>
            </tr>
"@
                foreach ($entry in ($history | Sort-Object Timestamp -Descending)) {
                    $statusClass = if ($entry.Success) { "success" } else { "failure" }
                    $statusText = if ($entry.Success) { "Success" } else { "Failed" }
                    $sourceClass = "source-$($entry.Source.ToLower())"
                    
                    $html += @"
            <tr>
                <td>$($entry.Timestamp)</td>
                <td>$($entry.PackageName)</td>
                <td>$($entry.Version)</td>
                <td>$($entry.PreviousVersion)</td>
                <td><span class="$sourceClass">$($entry.Source)</span></td>
                <td>$($entry.Operation)</td>
                <td class="$statusClass">$statusText</td>
            </tr>
"@
                }
                
                $html += @"
        </table>
        
        <div class="footer">
            <p>Generated by Windows Update Helper Scripts</p>
        </div>
    </div>
</body>
</html>
"@
                
                $html | Set-Content -Path $OutputPath -Encoding UTF8
            }
        }
        
        Write-Verbose "Exported update history report to: $OutputPath"
        return $true
    } catch {
        Write-Warning "Failed to export update history report: $_"
        return $false
    }
}

# ============================================================================
# System Restore Point
# ============================================================================

function New-UpdateRestorePoint {
    <#
    .SYNOPSIS
        Creates a system restore point before updates.
    #>
    param(
        [string]$Description = "Windows Update Helper - Before Updates"
    )
    
    try {
        Write-Log "Creating system restore point..." -Level "Info"
        
        # Enable system restore if not enabled
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        
        # Create restore point
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS"
        Write-Log "System restore point created successfully." -Level "Success"
        return $true
    } catch {
        Write-Log "Failed to create restore point: $_" -Level "Warning"
        return $false
    }
}

# ============================================================================
# Report Generation
# ============================================================================

function Export-UpdateReport {
    <#
    .SYNOPSIS
        Exports update results to HTML or CSV format.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$ReportData,
        
        [ValidateSet("HTML", "CSV", "JSON")]
        [string]$Format = "HTML",
        
        [string]$OutputPath = ".\reports"
    )
    
    # Create reports directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $fileName = "update-report-$timestamp"
    
    switch ($Format) {
        "HTML" {
            $filePath = Join-Path $OutputPath "$fileName.html"
            $html = ConvertTo-HtmlReport -Data $ReportData
            $html | Out-File -FilePath $filePath -Encoding UTF8
        }
        "CSV" {
            $filePath = Join-Path $OutputPath "$fileName.csv"
            $ReportData.Updates | Export-Csv -Path $filePath -NoTypeInformation
        }
        "JSON" {
            $filePath = Join-Path $OutputPath "$fileName.json"
            $ReportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $filePath -Encoding UTF8
        }
    }
    
    Write-Log "Report saved to: $filePath" -Level "Success"
    return $filePath
}

function ConvertTo-HtmlReport {
    <#
    .SYNOPSIS
        Converts report data to HTML format.
    #>
    param(
        [hashtable]$Data
    )
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Windows Update Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0078D4; border-bottom: 2px solid #0078D4; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 20px; }
        .info { background-color: #E8F4FD; padding: 10px; border-left: 4px solid #0078D4; margin: 10px 0; }
        .success { color: #107C10; font-weight: bold; }
        .warning { color: #FF8C00; font-weight: bold; }
        .error { color: #D13438; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th { background-color: #0078D4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .timestamp { color: #666; font-size: 0.9em; }
        .footer { margin-top: 20px; text-align: center; color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Windows Update Report</h1>
        <div class="info">
            <p><strong>Generated:</strong> <span class="timestamp">$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</span></p>
            <p><strong>System:</strong> $($Data.SystemInfo.OS)</p>
            <p><strong>Version:</strong> $($Data.SystemInfo.Version)</p>
        </div>
        
        <h2>Update Summary</h2>
        <table>
            <tr><th>Source</th><th>Status</th><th>Updates Found</th></tr>
            <tr><td>Microsoft Store</td><td class="$($Data.Store.Status.ToLower())">$($Data.Store.Status)</td><td>$($Data.Store.Count)</td></tr>
            <tr><td>Winget</td><td class="$($Data.Winget.Status.ToLower())">$($Data.Winget.Status)</td><td>$($Data.Winget.Count)</td></tr>
            <tr><td>Chocolatey</td><td class="$($Data.Chocolatey.Status.ToLower())">$($Data.Chocolatey.Status)</td><td>$($Data.Chocolatey.Count)</td></tr>
        </table>
        
        <div class="footer">
            <p>Generated by Windows Update Helper Scripts</p>
        </div>
    </div>
</body>
</html>
"@
    
    return $html
}

# ============================================================================
# Rollback Functions
# ============================================================================

function Get-SystemRestorePoints {
    <#
    .SYNOPSIS
        Lists all available system restore points.
    .DESCRIPTION
        Retrieves system restore points created by Windows and this script.
    .EXAMPLE
        Get-SystemRestorePoints | Format-Table
    #>
    try {
        $restorePoints = Get-ComputerRestorePoint | Select-Object -Property `
            SequenceNumber,
            CreationTime,
            Description,
            RestorePointType,
            @{Name='Size';Expression={[math]::Round($_.Size/1GB, 2)}}
        
        return $restorePoints
    } catch {
        Write-Warning "Failed to retrieve restore points: $_"
        return $null
    }
}

function Invoke-SystemRestore {
    <#
    .SYNOPSIS
        Restores system to a previous restore point.
    .DESCRIPTION
        Initiates system restore to a specified restore point sequence number.
        Requires administrator privileges and will restart the computer.
    .PARAMETER SequenceNumber
        The sequence number of the restore point to restore to.
    .PARAMETER Confirm
        If specified, prompts for confirmation before restoring.
    .EXAMPLE
        Invoke-SystemRestore -SequenceNumber 123 -Confirm
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$SequenceNumber,
        
        [switch]$Confirm
    )
    
    # Check admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Warning "System restore requires Administrator privileges"
        return $false
    }
    
    try {
        # Verify restore point exists
        $restorePoint = Get-ComputerRestorePoint | Where-Object { $_.SequenceNumber -eq $SequenceNumber }
        
        if (-not $restorePoint) {
            Write-Warning "Restore point with sequence number $SequenceNumber not found"
            return $false
        }
        
        Write-Host "Restore Point Details:" -ForegroundColor Cyan
        Write-Host "  Sequence Number: $($restorePoint.SequenceNumber)" -ForegroundColor White
        Write-Host "  Created: $($restorePoint.CreationTime)" -ForegroundColor White
        Write-Host "  Description: $($restorePoint.Description)" -ForegroundColor White
        Write-Host ""
        
        if ($Confirm) {
            $response = Read-Host "This will restart your computer. Continue? (Y/N)"
            if ($response -ne 'Y' -and $response -ne 'y') {
                Write-Host "System restore cancelled" -ForegroundColor Yellow
                return $false
            }
        }
        
        Write-Host "Initiating system restore..." -ForegroundColor Yellow
        Write-Host "Your computer will restart and restore to the selected point" -ForegroundColor Yellow
        
        # Restore using rstrui.exe with /offline parameter for automated restore
        Restore-Computer -RestorePoint $SequenceNumber -Confirm:$false
        
        return $true
    } catch {
        Write-Warning "Failed to initiate system restore: $_"
        return $false
    }
}

function Get-PackageHistory {
    <#
    .SYNOPSIS
        Retrieves package installation/update history.
    .DESCRIPTION
        Gets history of package operations from Winget and Chocolatey.
    .PARAMETER Source
        The package source: Winget, Chocolatey, or All.
    .PARAMETER Days
        Number of days of history to retrieve (default: 30).
    .EXAMPLE
        Get-PackageHistory -Source All -Days 7
    #>
    param(
        [ValidateSet("Winget", "Chocolatey", "All")]
        [string]$Source = "All",
        
        [int]$Days = 30
    )
    
    $history = @()
    $startDate = (Get-Date).AddDays(-$Days)
    
    # Winget history (from logs)
    if ($Source -in @("Winget", "All")) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                # Winget doesn't have built-in history command, check logs
                $wingetLogPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir"
                if (Test-Path $wingetLogPath) {
                    $logFiles = Get-ChildItem -Path $wingetLogPath -Filter "*.log" | 
                                Where-Object { $_.LastWriteTime -gt $startDate }
                    
                    Write-Host "Note: Winget history available in logs at: $wingetLogPath" -ForegroundColor Gray
                }
            } catch {
                Write-Verbose "Could not access Winget history: $_"
            }
        }
    }
    
    # Chocolatey history
    if ($Source -in @("Chocolatey", "All")) {
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            try {
                $chocoLogPath = "$env:ChocolateyInstall\logs\chocolatey.log"
                if (Test-Path $chocoLogPath) {
                    $logContent = Get-Content $chocoLogPath | Select-Object -Last 1000
                    $recentOps = $logContent | Where-Object { 
                        $_ -match "installed|upgraded|uninstalled" 
                    }
                    
                    foreach ($op in $recentOps) {
                        if ($op -match "\[.*?\] (.+?) v([\d\.]+)") {
                            $history += [PSCustomObject]@{
                                Source = "Chocolatey"
                                Package = $matches[1]
                                Version = $matches[2]
                                Operation = if ($op -match "installed") { "Install" } 
                                           elseif ($op -match "upgraded") { "Upgrade" } 
                                           else { "Uninstall" }
                                Timestamp = "See log file"
                            }
                        }
                    }
                }
            } catch {
                Write-Verbose "Could not access Chocolatey history: $_"
            }
        }
    }
    
    return $history
}

function Invoke-PackageRollback {
    <#
    .SYNOPSIS
        Rolls back a package to a previous version.
    .DESCRIPTION
        Attempts to downgrade a package using Winget or Chocolatey.
    .PARAMETER PackageName
        The name/ID of the package to rollback.
    .PARAMETER Version
        The target version to rollback to.
    .PARAMETER Source
        The package source: Winget or Chocolatey.
    .EXAMPLE
        Invoke-PackageRollback -PackageName "7zip.7zip" -Version "21.07" -Source Winget
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [string]$Version,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Winget", "Chocolatey")]
        [string]$Source
    )
    
    Write-Host "Attempting to rollback $PackageName to version $Version..." -ForegroundColor Yellow
    
    try {
        switch ($Source) {
            "Winget" {
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    # Winget doesn't support direct downgrade, need to uninstall and install specific version
                    Write-Host "Uninstalling current version..." -ForegroundColor Yellow
                    $uninstallResult = winget uninstall $PackageName --silent --accept-source-agreements
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Installing version $Version..." -ForegroundColor Yellow
                        $installResult = winget install $PackageName --version $Version --silent --accept-source-agreements --accept-package-agreements
                        
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "Successfully rolled back $PackageName to version $Version" -ForegroundColor Green
                            return $true
                        }
                    }
                    
                    Write-Warning "Rollback failed. Check if version $Version is available."
                    return $false
                } else {
                    Write-Warning "Winget is not available"
                    return $false
                }
            }
            
            "Chocolatey" {
                if (Get-Command choco -ErrorAction SilentlyContinue) {
                    # Chocolatey supports version pinning
                    Write-Host "Installing specific version using Chocolatey..." -ForegroundColor Yellow
                    $result = choco install $PackageName --version $Version --allow-downgrade --yes --force
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Successfully rolled back $PackageName to version $Version" -ForegroundColor Green
                        return $true
                    } else {
                        Write-Warning "Rollback failed. Check if version $Version is available."
                        return $false
                    }
                } else {
                    Write-Warning "Chocolatey is not available"
                    return $false
                }
            }
        }
    } catch {
        Write-Warning "Error during rollback: $_"
        return $false
    }
}

# ============================================================================
# Notification Functions
# ============================================================================

function Send-ToastNotification {
    <#
    .SYNOPSIS
        Sends a Windows toast notification.
    .DESCRIPTION
        Creates and displays a native Windows 10/11 toast notification using
        the Windows.UI.Notifications API.
    .PARAMETER Title
        The title/heading of the notification.
    .PARAMETER Message
        The main message body of the notification.
    .PARAMETER AppId
        The application identifier (default: Windows PowerShell).
    .PARAMETER Icon
        The type of icon to display: Info, Success, Warning, Error.
    .EXAMPLE
        Send-ToastNotification -Title "Updates Available" -Message "5 packages can be updated" -Icon Info
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [string]$AppId = "Windows.PowerShell.UpdateHelper",
        
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Icon = "Info"
    )
    
    try {
        # Load required Windows Runtime assemblies
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        
        # Map icon types to scenario strings
        $scenarioMap = @{
            "Info"    = "reminder"
            "Success" = "reminder"
            "Warning" = "alarm"
            "Error"   = "alarm"
        }
        $scenario = $scenarioMap[$Icon]
        
        # Create toast XML template
        $toastXml = @"
<toast scenario="$scenario">
    <visual>
        <binding template="ToastGeneric">
            <text>$([System.Security.SecurityElement]::Escape($Title))</text>
            <text>$([System.Security.SecurityElement]::Escape($Message))</text>
        </binding>
    </visual>
    <audio src="ms-winsoundevent:Notification.Default" />
</toast>
"@
        
        # Create XML document
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($toastXml)
        
        # Create and show toast notification
        $toast = New-Object Windows.UI.Notifications.ToastNotification($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
        $notifier.Show($toast)
        
        return $true
    } catch {
        Write-Warning "Failed to send toast notification: $_"
        return $false
    }
}

function Send-UpdateNotification {
    <#
    .SYNOPSIS
        Sends update-specific notifications based on configuration.
    .DESCRIPTION
        Helper function that checks notification settings and sends appropriate
        toast notifications for update operations.
    .PARAMETER Type
        The type of notification: Start, Complete, Error, UpdatesFound, NoUpdates.
    .PARAMETER Details
        Additional details to include in the notification message.
    .PARAMETER Config
        Configuration object containing notification settings.
    .EXAMPLE
        Send-UpdateNotification -Type "Complete" -Details "15 packages updated successfully" -Config $config
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Start", "Complete", "Error", "UpdatesFound", "NoUpdates")]
        [string]$Type,
        
        [string]$Details = "",
        
        [object]$Config = $null
    )
    
    # Check if notifications are enabled
    if (-not $Config -or -not $Config.Notifications -or -not $Config.Notifications.EnableToastNotifications) {
        return $false
    }
    
    # Define notification templates
    $templates = @{
        "Start" = @{
            Title = "Update Check Started"
            Message = "Scanning for available updates..."
            Icon = "Info"
        }
        "Complete" = @{
            Title = "Updates Complete"
            Message = if ($Details) { $Details } else { "Update process completed successfully" }
            Icon = "Success"
        }
        "Error" = @{
            Title = "Update Error"
            Message = if ($Details) { $Details } else { "An error occurred during the update process" }
            Icon = "Error"
        }
        "UpdatesFound" = @{
            Title = "Updates Available"
            Message = if ($Details) { $Details } else { "Updates are available for installation" }
            Icon = "Warning"
        }
        "NoUpdates" = @{
            Title = "System Up to Date"
            Message = "All packages are up to date"
            Icon = "Success"
        }
    }
    
    $template = $templates[$Type]
    
    # Send the notification
    return Send-ToastNotification -Title $template.Title -Message $template.Message -Icon $template.Icon
}

# ============================================================================
# Differential Update Cache Functions
# ============================================================================

function Initialize-PackageCache {
    <#
    .SYNOPSIS
        Initializes the package version cache.
    .DESCRIPTION
        Creates the cache directory and file structure if they don't exist.
    .PARAMETER CachePath
        Path to the cache file. Defaults to .\cache\package-cache.json
    #>
    param(
        [string]$CachePath = "$PSScriptRoot\..\cache\package-cache.json"
    )
    
    $cacheDir = Split-Path $CachePath -Parent
    
    # Create cache directory if it doesn't exist
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        Write-Log "Created cache directory: $cacheDir" -Level "Info"
    }
    
    # Create empty cache file if it doesn't exist
    if (-not (Test-Path $CachePath)) {
        $emptyCache = @{
            LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Packages = @{
                Store = @()
                Winget = @()
                Chocolatey = @()
            }
        }
        
        $emptyCache | ConvertTo-Json -Depth 10 | Set-Content $CachePath -Encoding UTF8
        Write-Log "Initialized package cache: $CachePath" -Level "Info"
    }
}

function Get-PackageCache {
    <#
    .SYNOPSIS
        Retrieves the package version cache.
    .DESCRIPTION
        Loads and returns the cached package versions.
    .PARAMETER CachePath
        Path to the cache file.
    .PARAMETER Source
        Filter by source (Store, Winget, or Chocolatey). Returns all if not specified.
    #>
    param(
        [string]$CachePath = "$PSScriptRoot\..\cache\package-cache.json",
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source
    )
    
    if (-not (Test-Path $CachePath)) {
        Write-Log "Cache file not found. Initializing..." -Level "Warning"
        Initialize-PackageCache -CachePath $CachePath
    }
    
    try {
        $cache = Get-Content $CachePath -Raw | ConvertFrom-Json
        
        if ($Source) {
            return $cache.Packages.$Source
        } else {
            return $cache
        }
    } catch {
        Write-Log "Error reading cache: $_" -Level "Error"
        return $null
    }
}

function Update-PackageCache {
    <#
    .SYNOPSIS
        Updates the package version cache with current package information.
    .DESCRIPTION
        Stores package name, version, and source in the cache for future comparison.
    .PARAMETER PackageName
        Name of the package.
    .PARAMETER Version
        Current version of the package.
    .PARAMETER Source
        Package source (Store, Winget, or Chocolatey).
    .PARAMETER CachePath
        Path to the cache file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [string]$Version,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [string]$CachePath = "$PSScriptRoot\..\cache\package-cache.json"
    )
    
    Initialize-PackageCache -CachePath $CachePath
    
    try {
        $cache = Get-Content $CachePath -Raw | ConvertFrom-Json
        
        # Find existing package entry
        $existingIndex = -1
        for ($i = 0; $i -lt $cache.Packages.$Source.Count; $i++) {
            if ($cache.Packages.$Source[$i].Name -eq $PackageName) {
                $existingIndex = $i
                break
            }
        }
        
        $packageEntry = @{
            Name = $PackageName
            Version = $Version
            LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        # Update or add package entry
        if ($existingIndex -ge 0) {
            $cache.Packages.$Source[$existingIndex] = $packageEntry
        } else {
            $cache.Packages.$Source += $packageEntry
        }
        
        # Update cache timestamp
        $cache.LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Save cache
        $cache | ConvertTo-Json -Depth 10 | Set-Content $CachePath -Encoding UTF8
        
        Write-Log "Updated cache for $Source package: $PackageName ($Version)" -Level "Info"
        return $true
    } catch {
        Write-Log "Error updating cache: $_" -Level "Error"
        return $false
    }
}

function Compare-PackageVersions {
    <#
    .SYNOPSIS
        Compares current package list with cached versions to detect changes.
    .DESCRIPTION
        Returns only packages that have version differences or are new.
    .PARAMETER CurrentPackages
        Array of current package objects with Name and Version properties.
    .PARAMETER Source
        Package source (Store, Winget, or Chocolatey).
    .PARAMETER CachePath
        Path to the cache file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$CurrentPackages,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [string]$CachePath = "$PSScriptRoot\..\cache\package-cache.json"
    )
    
    $cachedPackages = Get-PackageCache -CachePath $CachePath -Source $Source
    $changedPackages = @()
    
    foreach ($package in $CurrentPackages) {
        $cached = $cachedPackages | Where-Object { $_.Name -eq $package.Name }
        
        if (-not $cached) {
            # New package
            $package | Add-Member -MemberType NoteProperty -Name "ChangeType" -Value "New" -Force
            $package | Add-Member -MemberType NoteProperty -Name "PreviousVersion" -Value "N/A" -Force
            $changedPackages += $package
        } elseif ($cached.Version -ne $package.Version) {
            # Version changed
            $package | Add-Member -MemberType NoteProperty -Name "ChangeType" -Value "Updated" -Force
            $package | Add-Member -MemberType NoteProperty -Name "PreviousVersion" -Value $cached.Version -Force
            $changedPackages += $package
        }
        # If versions match, skip (no change)
    }
    
    return $changedPackages
}

function Clear-PackageCache {
    <#
    .SYNOPSIS
        Clears the package version cache.
    .DESCRIPTION
        Removes all cached package information or specific source.
    .PARAMETER Source
        Clear only specific source (Store, Winget, or Chocolatey). Clears all if not specified.
    .PARAMETER CachePath
        Path to the cache file.
    #>
    param(
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [string]$CachePath = "$PSScriptRoot\..\cache\package-cache.json"
    )
    
    if (-not (Test-Path $CachePath)) {
        Write-Log "Cache file not found. Nothing to clear." -Level "Warning"
        return $true
    }
    
    try {
        if ($Source) {
            # Clear specific source
            $cache = Get-Content $CachePath -Raw | ConvertFrom-Json
            $cache.Packages.$Source = @()
            $cache.LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $cache | ConvertTo-Json -Depth 10 | Set-Content $CachePath -Encoding UTF8
            Write-Log "Cleared $Source cache" -Level "Info"
        } else {
            # Clear entire cache
            Remove-Item $CachePath -Force
            Initialize-PackageCache -CachePath $CachePath
            Write-Log "Cleared entire package cache" -Level "Info"
        }
        
        return $true
    } catch {
        Write-Log "Error clearing cache: $_" -Level "Error"
        return $false
    }
}

function Get-CacheStatistics {
    <#
    .SYNOPSIS
        Gets statistics about the package cache.
    .DESCRIPTION
        Returns information about cached packages and cache age.
    .PARAMETER CachePath
        Path to the cache file.
    #>
    param(
        [string]$CachePath = "$PSScriptRoot\..\cache\package-cache.json"
    )
    
    if (-not (Test-Path $CachePath)) {
        return @{
            Exists = $false
            Message = "Cache not initialized"
        }
    }
    
    try {
        $cache = Get-Content $CachePath -Raw | ConvertFrom-Json
        $lastUpdated = [DateTime]::ParseExact($cache.LastUpdated, "yyyy-MM-dd HH:mm:ss", $null)
        $age = (Get-Date) - $lastUpdated
        
        return @{
            Exists = $true
            LastUpdated = $cache.LastUpdated
            AgeInHours = [math]::Round($age.TotalHours, 2)
            AgeInDays = [math]::Round($age.TotalDays, 2)
            StorePackages = $cache.Packages.Store.Count
            WingetPackages = $cache.Packages.Winget.Count
            ChocolateyPackages = $cache.Packages.Chocolatey.Count
            TotalPackages = $cache.Packages.Store.Count + $cache.Packages.Winget.Count + $cache.Packages.Chocolatey.Count
        }
    } catch {
        Write-Log "Error reading cache statistics: $_" -Level "Error"
        return @{
            Exists = $true
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# Package Priority and Ordering Functions
# ============================================================================

function Get-PackagePriority {
    <#
    .SYNOPSIS
        Gets the priority level of a package.
    .DESCRIPTION
        Returns the priority level (Critical, High, Normal, Low, Deferred) for a given package.
    .PARAMETER PackageName
        Name or ID of the package.
    .PARAMETER Source
        Package source (Store, Winget, or Chocolatey).
    .PARAMETER Config
        Configuration object containing priority settings.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [Parameter(Mandatory = $false)]
        [object]$Config
    )
    
    if (-not $Config) {
        $Config = Get-UpdateConfig
    }
    
    # Check if priority ordering is enabled
    if (-not $Config.PackagePriority.EnablePriorityOrdering) {
        return "Normal"
    }
    
    # Check each priority level
    if ($Config.PackagePriority.CriticalPackages.$Source -contains $PackageName) {
        return "Critical"
    }
    
    if ($Config.PackagePriority.HighPriorityPackages.$Source -contains $PackageName) {
        return "High"
    }
    
    if ($Config.PackagePriority.LowPriorityPackages.$Source -contains $PackageName) {
        return "Low"
    }
    
    if ($Config.PackagePriority.DeferredPackages.$Source -contains $PackageName) {
        return "Deferred"
    }
    
    return "Normal"
}

function Sort-PackagesByPriority {
    <#
    .SYNOPSIS
        Sorts packages by priority level.
    .DESCRIPTION
        Sorts an array of packages based on configured priority levels and ordering strategy.
    .PARAMETER Packages
        Array of package objects with Name property.
    .PARAMETER Source
        Package source (Store, Winget, or Chocolatey).
    .PARAMETER Config
        Configuration object containing priority settings.
    .PARAMETER Strategy
        Ordering strategy: PriorityOnly, PriorityThenAlphabetical, or PriorityThenReverseAlphabetical.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Packages,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [Parameter(Mandatory = $false)]
        [object]$Config,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("PriorityOnly", "PriorityThenAlphabetical", "PriorityThenReverseAlphabetical")]
        [string]$Strategy
    )
    
    if (-not $Config) {
        $Config = Get-UpdateConfig
    }
    
    if (-not $Strategy) {
        $Strategy = $Config.PackagePriority.OrderingStrategy
    }
    
    # Add priority property to each package
    $packagesWithPriority = $Packages | ForEach-Object {
        $pkg = $_
        $priority = Get-PackagePriority -PackageName $pkg.Name -Source $Source -Config $Config
        
        # Assign numeric value for sorting
        $priorityValue = switch ($priority) {
            "Critical" { 1 }
            "High"     { 2 }
            "Normal"   { 3 }
            "Low"      { 4 }
            "Deferred" { 5 }
            default    { 3 }
        }
        
        $pkg | Add-Member -MemberType NoteProperty -Name "Priority" -Value $priority -Force
        $pkg | Add-Member -MemberType NoteProperty -Name "PriorityValue" -Value $priorityValue -Force
        $pkg
    }
    
    # Sort based on strategy
    switch ($Strategy) {
        "PriorityOnly" {
            $sorted = $packagesWithPriority | Sort-Object PriorityValue
        }
        "PriorityThenAlphabetical" {
            $sorted = $packagesWithPriority | Sort-Object PriorityValue, Name
        }
        "PriorityThenReverseAlphabetical" {
            $sorted = $packagesWithPriority | Sort-Object PriorityValue, @{Expression="Name"; Descending=$true}
        }
        default {
            $sorted = $packagesWithPriority | Sort-Object PriorityValue, Name
        }
    }
    
    return $sorted
}

function Get-PrioritySummary {
    <#
    .SYNOPSIS
        Gets a summary of package priorities from configuration.
    .DESCRIPTION
        Returns counts and lists of packages by priority level.
    .PARAMETER Config
        Configuration object containing priority settings.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [object]$Config
    )
    
    if (-not $Config) {
        $Config = Get-UpdateConfig
    }
    
    if (-not $Config.PackagePriority) {
        return @{
            Enabled = $false
            Message = "Priority ordering not configured"
        }
    }
    
    $summary = @{
        Enabled = $Config.PackagePriority.EnablePriorityOrdering
        Strategy = $Config.PackagePriority.OrderingStrategy
        Critical = @{
            Winget = @($Config.PackagePriority.CriticalPackages.Winget).Count
            Chocolatey = @($Config.PackagePriority.CriticalPackages.Chocolatey).Count
            Store = @($Config.PackagePriority.CriticalPackages.Store).Count
        }
        High = @{
            Winget = @($Config.PackagePriority.HighPriorityPackages.Winget).Count
            Chocolatey = @($Config.PackagePriority.HighPriorityPackages.Chocolatey).Count
            Store = @($Config.PackagePriority.HighPriorityPackages.Store).Count
        }
        Low = @{
            Winget = @($Config.PackagePriority.LowPriorityPackages.Winget).Count
            Chocolatey = @($Config.PackagePriority.LowPriorityPackages.Chocolatey).Count
            Store = @($Config.PackagePriority.LowPriorityPackages.Store).Count
        }
        Deferred = @{
            Winget = @($Config.PackagePriority.DeferredPackages.Winget).Count
            Chocolatey = @($Config.PackagePriority.DeferredPackages.Chocolatey).Count
            Store = @($Config.PackagePriority.DeferredPackages.Store).Count
        }
    }
    
    return $summary
}

function Add-PackageToPriority {
    <#
    .SYNOPSIS
        Adds a package to a priority level.
    .DESCRIPTION
        Updates config.json to add a package to the specified priority level.
    .PARAMETER PackageName
        Name or ID of the package.
    .PARAMETER Source
        Package source (Store, Winget, or Chocolatey).
    .PARAMETER Priority
        Priority level (Critical, High, Low, or Deferred).
    .PARAMETER ConfigPath
        Path to config.json file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Critical", "High", "Low", "Deferred")]
        [string]$Priority,
        
        [string]$ConfigPath = "$PSScriptRoot\config.json"
    )
    
    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        
        # Determine the target array
        $targetArray = switch ($Priority) {
            "Critical" { $config.PackagePriority.CriticalPackages.$Source }
            "High"     { $config.PackagePriority.HighPriorityPackages.$Source }
            "Low"      { $config.PackagePriority.LowPriorityPackages.$Source }
            "Deferred" { $config.PackagePriority.DeferredPackages.$Source }
        }
        
        # Add package if not already present
        if ($targetArray -notcontains $PackageName) {
            $targetArray += $PackageName
            
            # Update the config object
            switch ($Priority) {
                "Critical" { $config.PackagePriority.CriticalPackages.$Source = $targetArray }
                "High"     { $config.PackagePriority.HighPriorityPackages.$Source = $targetArray }
                "Low"      { $config.PackagePriority.LowPriorityPackages.$Source = $targetArray }
                "Deferred" { $config.PackagePriority.DeferredPackages.$Source = $targetArray }
            }
            
            # Save config
            $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
            Write-Log "Added $PackageName to $Priority priority ($Source)" -Level "Info"
            return $true
        } else {
            Write-Log "$PackageName already in $Priority priority ($Source)" -Level "Warning"
            return $false
        }
    } catch {
        Write-Log "Error adding package to priority: $_" -Level "Error"
        return $false
    }
}

function Remove-PackageFromPriority {
    <#
    .SYNOPSIS
        Removes a package from all priority levels.
    .DESCRIPTION
        Updates config.json to remove a package from priority lists.
    .PARAMETER PackageName
        Name or ID of the package.
    .PARAMETER Source
        Package source (Store, Winget, or Chocolatey).
    .PARAMETER ConfigPath
        Path to config.json file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [string]$ConfigPath = "$PSScriptRoot\config.json"
    )
    
    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $removed = $false
        
        # Remove from all priority levels
        $priorities = @("CriticalPackages", "HighPriorityPackages", "LowPriorityPackages", "DeferredPackages")
        
        foreach ($priorityLevel in $priorities) {
            $array = @($config.PackagePriority.$priorityLevel.$Source | Where-Object { $_ -ne $PackageName })
            
            if ($array.Count -ne $config.PackagePriority.$priorityLevel.$Source.Count) {
                $config.PackagePriority.$priorityLevel.$Source = $array
                $removed = $true
            }
        }
        
        if ($removed) {
            # Save config
            $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
            Write-Log "Removed $PackageName from priority lists ($Source)" -Level "Info"
            return $true
        } else {
            Write-Log "$PackageName not found in priority lists ($Source)" -Level "Warning"
            return $false
        }
    } catch {
        Write-Log "Error removing package from priority: $_" -Level "Error"
        return $false
    }
}

# ============================================================================
# Update Validation Functions
# ============================================================================

function Get-PackageVersion {
    <#
    .SYNOPSIS
        Gets the currently installed version of a package.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source
    )
    
    try {
        switch ($Source) {
            "Winget" {
                $output = winget list --id $PackageName --exact 2>&1 | Out-String
                if ($output -match "$PackageName\s+(\S+)") {
                    return $matches[1]
                }
                return $null
            }
            
            "Chocolatey" {
                $output = choco list --local-only $PackageName --exact 2>&1 | Out-String
                if ($output -match "$PackageName\s+(\S+)") {
                    return $matches[1]
                }
                return $null
            }
            
            "Store" {
                Write-Log "Store app version detection not fully supported" -Level "Warning"
                return "Unknown"
            }
        }
    } catch {
        Write-Log "Error getting package version: $_" -Level "Error"
        return $null
    }
}

function Test-PackageInstalled {
    <#
    .SYNOPSIS
        Tests if a package is installed.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source
    )
    
    $version = Get-PackageVersion -PackageName $PackageName -Source $Source
    return ($null -ne $version -and $version -ne "Unknown")
}

function Test-UpdateSuccess {
    <#
    .SYNOPSIS
        Validates that an update was successful.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [Parameter(Mandatory = $false)]
        [string]$PreviousVersion,
        
        [Parameter(Mandatory = $false)]
        [string]$ExpectedVersion,
        
        [Parameter(Mandatory = $false)]
        [object]$Config
    )
    
    if (-not $Config) {
        $Config = Get-UpdateConfig
    }
    
    if (-not $Config.UpdateValidation.EnableValidation) {
        return @{
            Success = $true
            Method = "Skipped"
            Message = "Validation disabled"
        }
    }
    
    Write-Log "Validating update for $PackageName ($Source)..." -Level "Info"
    
    $currentVersion = Get-PackageVersion -PackageName $PackageName -Source $Source
    
    if (-not $currentVersion) {
        return @{
            Success = $false
            Method = "VersionCheck"
            Message = "Package not found after update"
            PreviousVersion = $PreviousVersion
            CurrentVersion = $null
        }
    }
    
    if ($Config.UpdateValidation.VerifyVersionChange -and $PreviousVersion) {
        if ($currentVersion -eq $PreviousVersion) {
            return @{
                Success = $false
                Method = "VersionCheck"
                Message = "Version unchanged after update"
                PreviousVersion = $PreviousVersion
                CurrentVersion = $currentVersion
            }
        }
    }
    
    if ($ExpectedVersion -and $currentVersion -ne $ExpectedVersion) {
        return @{
            Success = $false
            Method = "VersionCheck"
            Message = "Version mismatch"
            PreviousVersion = $PreviousVersion
            CurrentVersion = $currentVersion
            ExpectedVersion = $ExpectedVersion
        }
    }
    
    if ($Config.UpdateValidation.CheckPackageHealth) {
        $healthCheck = Test-PackageHealth -PackageName $PackageName -Source $Source -Config $Config
        
        if (-not $healthCheck.Success) {
            return @{
                Success = $false
                Method = "HealthCheck"
                Message = $healthCheck.Message
                PreviousVersion = $PreviousVersion
                CurrentVersion = $currentVersion
                HealthCheckDetails = $healthCheck
            }
        }
    }
    
    return @{
        Success = $true
        Method = "Complete"
        Message = "Update validated successfully"
        PreviousVersion = $PreviousVersion
        CurrentVersion = $currentVersion
    }
}

function Test-PackageHealth {
    <#
    .SYNOPSIS
        Performs health check on a package.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [Parameter(Mandatory = $false)]
        [object]$Config
    )
    
    if (-not $Config) {
        $Config = Get-UpdateConfig
    }
    
    $healthCommand = $Config.UpdateValidation.HealthCheckCommands.$PackageName
    
    if ([string]::IsNullOrWhiteSpace($healthCommand)) {
        return @{
            Success = $true
            Method = "NoCheck"
            Message = "No health check configured"
        }
    }
    
    try {
        Write-Log "Running health check for ${PackageName}: $healthCommand" -Level "Info"
        
        $output = Invoke-Expression $healthCommand 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            return @{
                Success = $true
                Method = "Command"
                Message = "Health check passed"
                Command = $healthCommand
                Output = $output.Trim()
            }
        } else {
            return @{
                Success = $false
                Method = "Command"
                Message = "Health check failed (exit code: $exitCode)"
                Command = $healthCommand
                Output = $output.Trim()
                ExitCode = $exitCode
            }
        }
    } catch {
        return @{
            Success = $false
            Method = "Command"
            Message = "Health check error: $_"
            Command = $healthCommand
            Error = $_.Exception.Message
        }
    }
}

function Invoke-UpdateValidation {
    <#
    .SYNOPSIS
        Performs comprehensive update validation.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Packages,
        
        [Parameter(Mandatory = $false)]
        [object]$Config
    )
    
    if (-not $Config) {
        $Config = Get-UpdateConfig
    }
    
    $results = @()
    
    foreach ($package in $Packages) {
        $validation = Test-UpdateSuccess `
            -PackageName $package.Name `
            -Source $package.Source `
            -PreviousVersion $package.PreviousVersion `
            -ExpectedVersion $package.ExpectedVersion `
            -Config $Config
        
        $result = [PSCustomObject]@{
            PackageName = $package.Name
            Source = $package.Source
            PreviousVersion = $package.PreviousVersion
            CurrentVersion = $validation.CurrentVersion
            ValidationSuccess = $validation.Success
            ValidationMethod = $validation.Method
            ValidationMessage = $validation.Message
        }
        
        $results += $result
        
        if ($validation.Success) {
            Write-Log "Validation passed: $($package.Name) ($($validation.CurrentVersion))" -Level "Success"
        } else {
            Write-Log "Validation failed: $($package.Name) - $($validation.Message)" -Level "Error"
        }
    }
    
    return $results
}

function New-ValidationReport {
    <#
    .SYNOPSIS
        Creates a validation report.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$ValidationResults,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("HTML", "JSON", "Text")]
        [string]$Format = "HTML"
    )
    
    try {
        $successCount = ($ValidationResults | Where-Object { $_.ValidationSuccess }).Count
        $failureCount = ($ValidationResults | Where-Object { -not $_.ValidationSuccess }).Count
        $totalCount = $ValidationResults.Count
        
        switch ($Format) {
            "HTML" {
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                
                $html = @'
<!DOCTYPE html>
<html>
<head>
    <title>Update Validation Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin: 20px 0; }
        .summary-card { padding: 20px; border-radius: 8px; text-align: center; }
        .total { background: #3498db; color: white; }
        .success { background: #2ecc71; color: white; }
        .failure { background: #e74c3c; color: white; }
        .summary-number { font-size: 36px; font-weight: bold; }
        .summary-label { font-size: 14px; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #34495e; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f8f9fa; }
        .status-success { color: #2ecc71; font-weight: bold; }
        .status-failure { color: #e74c3c; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Update Validation Report</h1>
        <p><strong>Generated:</strong> {0}</p>
        <div class="summary">
            <div class="summary-card total"><div class="summary-number">{1}</div><div class="summary-label">Total</div></div>
            <div class="summary-card success"><div class="summary-number">{2}</div><div class="summary-label">Validated</div></div>
            <div class="summary-card failure"><div class="summary-number">{3}</div><div class="summary-label">Failed</div></div>
        </div>
        <table><tr><th>Package</th><th>Source</th><th>Previous</th><th>Current</th><th>Status</th><th>Message</th></tr>
'@
                
                $html = $html -f $timestamp, $totalCount, $successCount, $failureCount
                
                foreach ($result in $ValidationResults) {
                    $statusClass = if ($result.ValidationSuccess) { "status-success" } else { "status-failure" }
                    $statusText = if ($result.ValidationSuccess) { "Passed" } else { "Failed" }
                    
                    $html += "<tr><td>$($result.PackageName)</td><td>$($result.Source)</td><td>$($result.PreviousVersion)</td><td>$($result.CurrentVersion)</td><td class=`"$statusClass`">$statusText</td><td>$($result.ValidationMessage)</td></tr>"
                }
                
                $html += "</table></div></body></html>"
                $html | Set-Content $OutputPath -Encoding UTF8
            }
            
            "JSON" {
                $report = @{
                    GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Summary = @{
                        Total = $totalCount
                        Successful = $successCount
                        Failed = $failureCount
                    }
                    Results = $ValidationResults
                }
                
                $report | ConvertTo-Json -Depth 10 | Set-Content $OutputPath -Encoding UTF8
            }
            
            "Text" {
                $lines = @()
                $lines += "Update Validation Report"
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $lines += "Generated: $timestamp"
                $lines += ""
                $lines += "Summary:"
                $lines += "Total: $totalCount - Validated: $successCount - Failed: $failureCount"
                $lines += ""
                
                foreach ($result in $ValidationResults) {
                    if ($result.ValidationSuccess) {
                        $status = "[PASS]"
                    } else {
                        $status = "[FAIL]"
                    }
                    $line = "{0} {1} ({2}) - Prev: {3} - Curr: {4} - {5}" -f $status, $result.PackageName, $result.Source, $result.PreviousVersion, $result.CurrentVersion, $result.ValidationMessage
                    $lines += $line
                }
                
                $output = $lines -join [Environment]::NewLine
                $output | Set-Content $OutputPath -Encoding UTF8
            }
        }
        
        Write-Log "Validation report saved: $OutputPath" -Level "Info"
        return $true
    } catch {
        Write-Log "Error creating validation report: $_" -Level "Error"
        return $false
    }
}

# ============================================================================
# Dependency Installation Functions
# ============================================================================

function Test-WingetInstalled {
    <#
    .SYNOPSIS
        Checks if Windows Package Manager (Winget) is installed.
    #>
    try {
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetPath) {
            Write-Log "Winget is installed at: $($wingetPath.Source)" -Level "Info"
            return $true
        } else {
            Write-Log "Winget is not installed" -Level "Warning"
            return $false
        }
    } catch {
        Write-Log "Error checking Winget installation: $_" -Level "Error"
        return $false
    }
}

function Test-ChocolateyInstalled {
    <#
    .SYNOPSIS
        Checks if Chocolatey package manager is installed.
    #>
    try {
        $chocoPath = Get-Command choco -ErrorAction SilentlyContinue
        if ($chocoPath) {
            Write-Log "Chocolatey is installed at: $($chocoPath.Source)" -Level "Info"
            return $true
        } else {
            Write-Log "Chocolatey is not installed" -Level "Warning"
            return $false
        }
    } catch {
        Write-Log "Error checking Chocolatey installation: $_" -Level "Error"
        return $false
    }
}

function Test-PowerShellModule {
    <#
    .SYNOPSIS
        Checks if a PowerShell module is installed.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        
        [Parameter(Mandatory = $false)]
        [version]$MinimumVersion
    )
    
    try {
        $module = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
        
        if ($module) {
            if ($MinimumVersion) {
                if ($module.Version -ge $MinimumVersion) {
                    Write-Log "Module '$ModuleName' version $($module.Version) is installed (minimum: $MinimumVersion)" -Level "Info"
                    return $true
                } else {
                    Write-Log "Module '$ModuleName' version $($module.Version) is below minimum required version $MinimumVersion" -Level "Warning"
                    return $false
                }
            } else {
                Write-Log "Module '$ModuleName' version $($module.Version) is installed" -Level "Info"
                return $true
            }
        } else {
            Write-Log "Module '$ModuleName' is not installed" -Level "Warning"
            return $false
        }
    } catch {
        Write-Log "Error checking module '$ModuleName': $_" -Level "Error"
        return $false
    }
}

function Get-WingetVersion {
    <#
    .SYNOPSIS
        Gets the installed version of Winget.
    #>
    try {
        if (-not (Test-WingetInstalled)) {
            return $null
        }
        
        $versionOutput = winget --version 2>&1
        if ($versionOutput -match 'v?(\d+\.\d+\.\d+)') {
            $version = [version]$matches[1]
            Write-Log "Winget version: $version" -Level "Info"
            return $version
        } else {
            Write-Log "Could not parse Winget version from output: $versionOutput" -Level "Warning"
            return $null
        }
    } catch {
        Write-Log "Error getting Winget version: $_" -Level "Error"
        return $null
    }
}

function Get-ChocolateyVersion {
    <#
    .SYNOPSIS
        Gets the installed version of Chocolatey.
    #>
    try {
        if (-not (Test-ChocolateyInstalled)) {
            return $null
        }
        
        $versionOutput = choco --version 2>&1
        if ($versionOutput -match '(\d+\.\d+\.\d+)') {
            $version = [version]$matches[1]
            Write-Log "Chocolatey version: $version" -Level "Info"
            return $version
        } else {
            Write-Log "Could not parse Chocolatey version from output: $versionOutput" -Level "Warning"
            return $null
        }
    } catch {
        Write-Log "Error getting Chocolatey version: $_" -Level "Error"
        return $null
    }
}

function Test-DependencyVersion {
    <#
    .SYNOPSIS
        Checks if a dependency meets minimum version requirements.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Winget", "Chocolatey", "PowerShell")]
        [string]$Dependency,
        
        [Parameter(Mandatory = $true)]
        [version]$MinimumVersion
    )
    
    try {
        $currentVersion = $null
        
        switch ($Dependency) {
            "Winget" {
                $currentVersion = Get-WingetVersion
            }
            "Chocolatey" {
                $currentVersion = Get-ChocolateyVersion
            }
            "PowerShell" {
                $currentVersion = $PSVersionTable.PSVersion
            }
        }
        
        if ($null -eq $currentVersion) {
            Write-Log "$Dependency is not installed or version could not be determined" -Level "Warning"
            return $false
        }
        
        if ($currentVersion -ge $MinimumVersion) {
            Write-Log "$Dependency version $currentVersion meets minimum requirement $MinimumVersion" -Level "Info"
            return $true
        } else {
            Write-Log "$Dependency version $currentVersion is below minimum requirement $MinimumVersion" -Level "Warning"
            return $false
        }
    } catch {
        Write-Log "Error checking $Dependency version: $_" -Level "Error"
        return $false
    }
}

function Install-WingetCLI {
    <#
    .SYNOPSIS
        Installs Windows Package Manager (Winget) via Microsoft Store or GitHub.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("MicrosoftStore", "GitHub")]
        [string]$Method = "MicrosoftStore",
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300
    )
    
    try {
        Write-Log "Installing Winget using method: $Method" -Level "Info"
        
        if ($Method -eq "MicrosoftStore") {
            # Install via Microsoft Store (App Installer package)
            Write-Log "Installing App Installer (Winget) from Microsoft Store..." -Level "Info"
            
            # Check if running Windows 10/11
            $osVersion = [System.Environment]::OSVersion.Version
            if ($osVersion.Major -lt 10) {
                Write-Log "Winget requires Windows 10 or later" -Level "Error"
                return $false
            }
            
            # Try to install via winget itself (if partially working) or use Add-AppxPackage
            $appInstallerUrl = "https://aka.ms/getwinget"
            Write-Log "Attempting to trigger Winget installation from Microsoft Store..." -Level "Info"
            Start-Process "ms-windows-store://pdp/?productid=9nblggh4nns1" -ErrorAction SilentlyContinue
            
            # Wait for installation
            $timeout = [DateTime]::Now.AddSeconds($TimeoutSeconds)
            $installed = $false
            
            while ([DateTime]::Now -lt $timeout -and -not $installed) {
                Start-Sleep -Seconds 10
                if (Test-WingetInstalled) {
                    $installed = $true
                    Write-Log "Winget installation detected" -Level "Success"
                    break
                }
            }
            
            if (-not $installed) {
                Write-Log "Winget installation timed out. Please install manually from Microsoft Store" -Level "Warning"
                return $false
            }
            
            return $true
            
        } elseif ($Method -eq "GitHub") {
            # Install from GitHub releases
            Write-Log "Installing Winget from GitHub releases..." -Level "Info"
            
            $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -ErrorAction Stop
            $msixBundle = $latestRelease.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
            
            if (-not $msixBundle) {
                Write-Log "Could not find Winget msixbundle in GitHub releases" -Level "Error"
                return $false
            }
            
            $downloadPath = "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
            Write-Log "Downloading Winget from: $($msixBundle.browser_download_url)" -Level "Info"
            
            Invoke-WebRequest -Uri $msixBundle.browser_download_url -OutFile $downloadPath -ErrorAction Stop
            
            Write-Log "Installing Winget package..." -Level "Info"
            Add-AppxPackage -Path $downloadPath -ErrorAction Stop
            
            # Verify installation
            Start-Sleep -Seconds 5
            if (Test-WingetInstalled) {
                Write-Log "Winget installed successfully from GitHub" -Level "Success"
                Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
                return $true
            } else {
                Write-Log "Winget installation failed verification" -Level "Error"
                return $false
            }
        }
    } catch {
        Write-Log "Error installing Winget: $_" -Level "Error"
        return $false
    }
}

function Install-Chocolatey {
    <#
    .SYNOPSIS
        Installs Chocolatey package manager.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300
    )
    
    try {
        Write-Log "Installing Chocolatey package manager..." -Level "Info"
        
        # Check if already installed
        if (Test-ChocolateyInstalled) {
            Write-Log "Chocolatey is already installed" -Level "Info"
            return $true
        }
        
        # Set execution policy for the installation
        Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
        
        # Download and install Chocolatey
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        
        $installScript = Invoke-WebRequest -Uri "https://community.chocolatey.org/install.ps1" -UseBasicParsing -ErrorAction Stop
        
        Write-Log "Executing Chocolatey installation script..." -Level "Info"
        Invoke-Expression $installScript.Content
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Verify installation
        Start-Sleep -Seconds 5
        if (Test-ChocolateyInstalled) {
            Write-Log "Chocolatey installed successfully" -Level "Success"
            
            # Configure Chocolatey
            choco feature enable -n allowGlobalConfirmation 2>&1 | Out-Null
            
            return $true
        } else {
            Write-Log "Chocolatey installation failed verification" -Level "Error"
            return $false
        }
    } catch {
        Write-Log "Error installing Chocolatey: $_" -Level "Error"
        return $false
    }
}

function Install-PowerShellModule {
    <#
    .SYNOPSIS
        Installs a PowerShell module from PSGallery.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        
        [Parameter(Mandatory = $false)]
        [version]$MinimumVersion,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("CurrentUser", "AllUsers")]
        [string]$Scope = "CurrentUser",
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300
    )
    
    try {
        Write-Log "Installing PowerShell module: $ModuleName" -Level "Info"
        
        # Check if already installed
        if (Test-PowerShellModule -ModuleName $ModuleName -MinimumVersion $MinimumVersion) {
            Write-Log "Module '$ModuleName' is already installed with required version" -Level "Info"
            return $true
        }
        
        # Install NuGet provider if needed
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nugetProvider) {
            Write-Log "Installing NuGet package provider..." -Level "Info"
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope $Scope -ErrorAction Stop | Out-Null
        }
        
        # Set PSGallery as trusted
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Write-Log "Setting PSGallery as trusted repository..." -Level "Info"
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }
        
        # Install the module
        Write-Log "Installing module '$ModuleName' from PSGallery..." -Level "Info"
        if ($MinimumVersion) {
            Install-Module -Name $ModuleName -MinimumVersion $MinimumVersion -Scope $Scope -Force -AllowClobber -ErrorAction Stop
        } else {
            Install-Module -Name $ModuleName -Scope $Scope -Force -AllowClobber -ErrorAction Stop
        }
        
        # Verify installation
        Start-Sleep -Seconds 2
        if (Test-PowerShellModule -ModuleName $ModuleName -MinimumVersion $MinimumVersion) {
            Write-Log "Module '$ModuleName' installed successfully" -Level "Success"
            return $true
        } else {
            Write-Log "Module '$ModuleName' installation failed verification" -Level "Error"
            return $false
        }
    } catch {
        Write-Log "Error installing module '$ModuleName': $_" -Level "Error"
        return $false
    }
}

function Install-Dependency {
    <#
    .SYNOPSIS
        Installs a specific dependency (Winget, Chocolatey, or PowerShell module).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Winget", "Chocolatey", "PowerShellModule")]
        [string]$DependencyType,
        
        [Parameter(Mandatory = $false)]
        [string]$ModuleName,
        
        [Parameter(Mandatory = $false)]
        [version]$MinimumVersion,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$InstallationOptions = @{}
    )
    
    try {
        Write-Log "Installing dependency: $DependencyType" -Level "Info"
        
        $result = $false
        
        switch ($DependencyType) {
            "Winget" {
                $method = if ($InstallationOptions.Method) { $InstallationOptions.Method } else { "MicrosoftStore" }
                $timeout = if ($InstallationOptions.Timeout) { $InstallationOptions.Timeout } else { 300 }
                $result = Install-WingetCLI -Method $method -TimeoutSeconds $timeout
            }
            "Chocolatey" {
                $timeout = if ($InstallationOptions.Timeout) { $InstallationOptions.Timeout } else { 300 }
                $result = Install-Chocolatey -TimeoutSeconds $timeout
            }
            "PowerShellModule" {
                if (-not $ModuleName) {
                    Write-Log "ModuleName is required for PowerShellModule dependency type" -Level "Error"
                    return $false
                }
                
                $scope = if ($InstallationOptions.Scope) { $InstallationOptions.Scope } else { "CurrentUser" }
                $timeout = if ($InstallationOptions.Timeout) { $InstallationOptions.Timeout } else { 300 }
                
                $result = Install-PowerShellModule -ModuleName $ModuleName -MinimumVersion $MinimumVersion -Scope $scope -TimeoutSeconds $timeout
            }
        }
        
        return $result
    } catch {
        Write-Log "Error in Install-Dependency: $_" -Level "Error"
        return $false
    }
}

function Invoke-DependencyInstallation {
    <#
    .SYNOPSIS
        Checks and installs all required dependencies based on configuration.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Config
    )
    
    try {
        if (-not $Config) {
            $Config = Get-UpdateConfig
        }
        
        $depConfig = $Config.DependencyInstallation
        
        if (-not $depConfig.EnableDependencyCheck) {
            Write-Log "Dependency check is disabled in configuration" -Level "Info"
            return @{
                Success = $true
                Message = "Dependency check disabled"
                Dependencies = @()
            }
        }
        
        if ($depConfig.SkipDependencyCheck) {
            Write-Log "Skipping dependency check as configured" -Level "Info"
            return @{
                Success = $true
                Message = "Dependency check skipped"
                Dependencies = @()
            }
        }
        
        Write-Log "Starting dependency installation check..." -Level "Info"
        
        $results = @()
        $allSuccess = $true
        
        # Check Winget
        if ($depConfig.RequiredDependencies.Winget -or $Config.UpdateSettings.EnableWinget) {
            Write-Log "Checking Winget dependency..." -Level "Info"
            
            $wingetInstalled = Test-WingetInstalled
            $wingetVersionOk = $false
            
            if ($wingetInstalled) {
                $minVersion = [version]$depConfig.MinimumVersions.Winget
                $wingetVersionOk = Test-DependencyVersion -Dependency "Winget" -MinimumVersion $minVersion
            }
            
            if (-not $wingetInstalled -or -not $wingetVersionOk) {
                if ($depConfig.AutoInstallMissingDependencies) {
                    Write-Log "Installing Winget..." -Level "Info"
                    $method = $depConfig.InstallationMethods.Winget
                    $timeout = $depConfig.InstallationTimeout
                    $installResult = Install-WingetCLI -Method $method -TimeoutSeconds $timeout
                    
                    if ($installResult -and $depConfig.ValidateAfterInstallation) {
                        $wingetInstalled = Test-WingetInstalled
                        $minVersion = [version]$depConfig.MinimumVersions.Winget
                        $wingetVersionOk = Test-DependencyVersion -Dependency "Winget" -MinimumVersion $minVersion
                    }
                    
                    $results += @{
                        Dependency = "Winget"
                        Required = $true
                        Installed = $wingetInstalled
                        VersionOk = $wingetVersionOk
                        Action = "Installed"
                        Success = $installResult
                    }
                    
                    if (-not $installResult) {
                        $allSuccess = $false
                    }
                } else {
                    $results += @{
                        Dependency = "Winget"
                        Required = $true
                        Installed = $wingetInstalled
                        VersionOk = $wingetVersionOk
                        Action = "NotInstalled"
                        Success = $false
                    }
                    $allSuccess = $false
                }
            } else {
                $results += @{
                    Dependency = "Winget"
                    Required = $true
                    Installed = $true
                    VersionOk = $true
                    Action = "AlreadyInstalled"
                    Success = $true
                }
            }
        }
        
        # Check Chocolatey
        if ($depConfig.RequiredDependencies.Chocolatey -or $Config.UpdateSettings.EnableChocolatey) {
            Write-Log "Checking Chocolatey dependency..." -Level "Info"
            
            $chocoInstalled = Test-ChocolateyInstalled
            $chocoVersionOk = $false
            
            if ($chocoInstalled) {
                $minVersion = [version]$depConfig.MinimumVersions.Chocolatey
                $chocoVersionOk = Test-DependencyVersion -Dependency "Chocolatey" -MinimumVersion $minVersion
            }
            
            if (-not $chocoInstalled -or -not $chocoVersionOk) {
                if ($depConfig.AutoInstallMissingDependencies) {
                    Write-Log "Installing Chocolatey..." -Level "Info"
                    $timeout = $depConfig.InstallationTimeout
                    $installResult = Install-Chocolatey -TimeoutSeconds $timeout
                    
                    if ($installResult -and $depConfig.ValidateAfterInstallation) {
                        $chocoInstalled = Test-ChocolateyInstalled
                        $minVersion = [version]$depConfig.MinimumVersions.Chocolatey
                        $chocoVersionOk = Test-DependencyVersion -Dependency "Chocolatey" -MinimumVersion $minVersion
                    }
                    
                    $results += @{
                        Dependency = "Chocolatey"
                        Required = $true
                        Installed = $chocoInstalled
                        VersionOk = $chocoVersionOk
                        Action = "Installed"
                        Success = $installResult
                    }
                    
                    if (-not $installResult) {
                        $allSuccess = $false
                    }
                } else {
                    $results += @{
                        Dependency = "Chocolatey"
                        Required = $true
                        Installed = $chocoInstalled
                        VersionOk = $chocoVersionOk
                        Action = "NotInstalled"
                        Success = $false
                    }
                    $allSuccess = $false
                }
            } else {
                $results += @{
                    Dependency = "Chocolatey"
                    Required = $true
                    Installed = $true
                    VersionOk = $true
                    Action = "AlreadyInstalled"
                    Success = $true
                }
            }
        }
        
        # Check PowerShell modules
        if ($depConfig.RequiredDependencies.PowerShellModules -and $depConfig.RequiredDependencies.PowerShellModules.Count -gt 0) {
            foreach ($moduleName in $depConfig.RequiredDependencies.PowerShellModules) {
                Write-Log "Checking PowerShell module: $moduleName" -Level "Info"
                
                $moduleInstalled = Test-PowerShellModule -ModuleName $moduleName
                
                if (-not $moduleInstalled) {
                    if ($depConfig.AutoInstallMissingDependencies) {
                        Write-Log "Installing PowerShell module: $moduleName" -Level "Info"
                        $scope = $depConfig.InstallationMethods.PowerShellModules
                        $timeout = $depConfig.InstallationTimeout
                        
                        $installResult = Install-PowerShellModule -ModuleName $moduleName -Scope $scope -TimeoutSeconds $timeout
                        
                        $results += @{
                            Dependency = "Module:$moduleName"
                            Required = $true
                            Installed = $installResult
                            VersionOk = $installResult
                            Action = "Installed"
                            Success = $installResult
                        }
                        
                        if (-not $installResult) {
                            $allSuccess = $false
                        }
                    } else {
                        $results += @{
                            Dependency = "Module:$moduleName"
                            Required = $true
                            Installed = $false
                            VersionOk = $false
                            Action = "NotInstalled"
                            Success = $false
                        }
                        $allSuccess = $false
                    }
                } else {
                    $results += @{
                        Dependency = "Module:$moduleName"
                        Required = $true
                        Installed = $true
                        VersionOk = $true
                        Action = "AlreadyInstalled"
                        Success = $true
                    }
                }
            }
        }
        
        # Log summary
        $installedCount = ($results | Where-Object { $_.Installed }).Count
        $totalCount = $results.Count
        
        Write-Log "Dependency check complete: $installedCount/$totalCount dependencies satisfied" -Level "Info"
        
        if (-not $allSuccess -and $depConfig.FailOnMissingDependencies) {
            Write-Log "Some required dependencies are missing and FailOnMissingDependencies is enabled" -Level "Error"
            return @{
                Success = $false
                Message = "Required dependencies missing"
                Dependencies = $results
            }
        }
        
        return @{
            Success = $allSuccess
            Message = "Dependency check completed"
            Dependencies = $results
        }
    } catch {
        Write-Log "Error in Invoke-DependencyInstallation: $_" -Level "Error"
        return @{
            Success = $false
            Message = "Error during dependency installation: $_"
            Dependencies = @()
        }
    }
}

# ============================================================================
# Security Validation Functions
# ============================================================================

function Get-FileHash256 {
    <#
    .SYNOPSIS
        Calculates SHA256 hash of a file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("SHA256", "SHA512", "MD5", "SHA1")]
        [string]$Algorithm = "SHA256"
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            Write-Log "File not found: $FilePath" -Level "Warning"
            return $null
        }
        
        $hash = Get-FileHash -Path $FilePath -Algorithm $Algorithm -ErrorAction Stop
        return $hash.Hash
    } catch {
        Write-Log "Error calculating hash for ${FilePath}: $_" -Level "Error"
        return $null
    }
}

function Get-PackageExecutablePath {
    <#
    .SYNOPSIS
        Finds the main executable path for a package.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source
    )
    
    try {
        switch ($Source) {
            "Winget" {
                $wingetInfo = winget show --id $PackageName --exact 2>&1 | Out-String
                if ($wingetInfo -match 'Install Location:\s*(.+)') {
                    $installPath = $matches[1].Trim()
                    if (Test-Path $installPath) {
                        $exeFiles = Get-ChildItem -Path $installPath -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($exeFiles) {
                            return $exeFiles.FullName
                        }
                    }
                }
                
                $programFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs")
                foreach ($baseDir in $programFiles) {
                    $searchName = $PackageName -replace '\..*$', ''
                    $possiblePath = Get-ChildItem -Path $baseDir -Filter "$searchName*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($possiblePath) {
                        return $possiblePath.FullName
                    }
                }
            }
            
            "Chocolatey" {
                $chocoPath = "$env:ChocolateyInstall\lib\$PackageName"
                if (Test-Path $chocoPath) {
                    $exeFiles = Get-ChildItem -Path $chocoPath -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | 
                        Where-Object { $_.Name -notmatch 'uninstall|setup|installer' } | 
                        Select-Object -First 1
                    if ($exeFiles) {
                        return $exeFiles.FullName
                    }
                }
            }
            
            "Store" {
                Write-Log "Store app path detection not fully supported" -Level "Warning"
                return $null
            }
        }
        
        return $null
    } catch {
        Write-Log "Error finding executable for ${PackageName}: $_" -Level "Error"
        return $null
    }
}

function Test-AuthenticodeSignature {
    <#
    .SYNOPSIS
        Validates the digital signature of a file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [string[]]$TrustedPublishers = @(),
        
        [Parameter(Mandatory = $false)]
        [bool]$RequireValidSignature = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$CheckRevocation = $true
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            return @{
                IsValid = $false
                Status = "FileNotFound"
                Message = "File not found: $FilePath"
            }
        }
        
        $signature = Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction Stop
        
        $result = @{
            IsValid = $false
            Status = $signature.Status.ToString()
            SignerCertificate = $null
            Publisher = $null
            Thumbprint = $null
            Message = ""
        }
        
        if ($signature.Status -eq 'Valid') {
            $result.IsValid = $true
            $result.SignerCertificate = $signature.SignerCertificate
            $result.Publisher = $signature.SignerCertificate.Subject
            $result.Thumbprint = $signature.SignerCertificate.Thumbprint
            $result.Message = "Signature is valid"
            
            if ($TrustedPublishers.Count -gt 0) {
                $isTrusted = $false
                foreach ($publisher in $TrustedPublishers) {
                    if ($result.Publisher -like "*$publisher*") {
                        $isTrusted = $true
                        break
                    }
                }
                
                if (-not $isTrusted) {
                    $result.IsValid = $false
                    $result.Message = "Publisher not in trusted list: $($result.Publisher)"
                }
            }
        } else {
            $result.Message = "Signature status: $($signature.Status)"
            
            if ($signature.Status -eq 'NotSigned') {
                $result.Message = "File is not digitally signed"
            } elseif ($signature.Status -eq 'HashMismatch') {
                $result.Message = "File hash does not match signature"
            } elseif ($signature.Status -eq 'NotTrusted') {
                $result.Message = "Certificate is not trusted"
            }
            
            if ($RequireValidSignature) {
                $result.IsValid = $false
            }
        }
        
        return $result
    } catch {
        return @{
            IsValid = $false
            Status = "Error"
            Message = "Error validating signature: $_"
        }
    }
}

function Initialize-HashDatabase {
    <#
    .SYNOPSIS
        Initializes the package hash database.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath = ".\cache\package-hashes.json"
    )
    
    try {
        $dbDir = Split-Path -Parent $DatabasePath
        if (-not (Test-Path $dbDir)) {
            New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
        }
        
        if (-not (Test-Path $DatabasePath)) {
            $initialDb = @{
                CreatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                LastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                Packages = @{}
            }
            
            $initialDb | ConvertTo-Json -Depth 10 | Set-Content $DatabasePath -Encoding UTF8
            Write-Log "Hash database initialized: $DatabasePath" -Level "Info"
        }
        
        return $true
    } catch {
        Write-Log "Error initializing hash database: $_" -Level "Error"
        return $false
    }
}

function Get-HashDatabase {
    <#
    .SYNOPSIS
        Retrieves the package hash database.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath = ".\cache\package-hashes.json"
    )
    
    try {
        if (-not (Test-Path $DatabasePath)) {
            Initialize-HashDatabase -DatabasePath $DatabasePath
        }
        
        $db = Get-Content $DatabasePath -Raw | ConvertFrom-Json
        return $db
    } catch {
        Write-Log "Error reading hash database: $_" -Level "Error"
        return $null
    }
}

function Save-PackageHash {
    <#
    .SYNOPSIS
        Saves package hash to database.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [Parameter(Mandatory = $true)]
        [string]$Version,
        
        [Parameter(Mandatory = $true)]
        [string]$Hash,
        
        [Parameter(Mandatory = $false)]
        [string]$FilePath = "",
        
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath = ".\cache\package-hashes.json"
    )
    
    try {
        $db = Get-HashDatabase -DatabasePath $DatabasePath
        if (-not $db) { return $false }
        
        $key = "$Source/$PackageName"
        $db.Packages.$key = @{
            PackageName = $PackageName
            Source = $Source
            Version = $Version
            Hash = $Hash
            Algorithm = "SHA256"
            FilePath = $FilePath
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
        
        $db.LastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        $db | ConvertTo-Json -Depth 10 | Set-Content $DatabasePath -Encoding UTF8
        
        return $true
    } catch {
        Write-Log "Error saving package hash: $_" -Level "Error"
        return $false
    }
}

function Get-PackageHash {
    <#
    .SYNOPSIS
        Retrieves stored hash for a package.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath = ".\cache\package-hashes.json"
    )
    
    try {
        $db = Get-HashDatabase -DatabasePath $DatabasePath
        if (-not $db) { return $null }
        
        $key = "$Source/$PackageName"
        if ($db.Packages.PSObject.Properties.Name -contains $key) {
            return $db.Packages.$key
        }
        
        return $null
    } catch {
        Write-Log "Error retrieving package hash: $_" -Level "Error"
        return $null
    }
}

function Test-PackageIntegrity {
    <#
    .SYNOPSIS
        Validates package integrity using hash and signature.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Store", "Winget", "Chocolatey")]
        [string]$Source,
        
        [Parameter(Mandatory = $false)]
        [string]$ExpectedHash = "",
        
        [Parameter(Mandatory = $false)]
        [object]$Config
    )
    
    if (-not $Config) {
        $Config = Get-UpdateConfig
    }
    
    if (-not $Config.SecurityValidation.EnableHashVerification -and 
        -not $Config.SecurityValidation.EnableSignatureValidation) {
        return @{
            Success = $true
            Method = "Skipped"
            Message = "Security validation disabled"
        }
    }
    
    $result = @{
        Success = $true
        HashValidation = $null
        SignatureValidation = $null
        Message = ""
    }
    
    try {
        $exePath = Get-PackageExecutablePath -PackageName $PackageName -Source $Source
        
        if (-not $exePath) {
            return @{
                Success = $false
                Method = "PathNotFound"
                Message = "Could not locate package executable"
            }
        }
        
        if ($Config.SecurityValidation.EnableHashVerification) {
            $currentHash = Get-FileHash256 -FilePath $exePath -Algorithm $Config.SecurityValidation.HashAlgorithm
            
            if ($currentHash) {
                $storedHash = Get-PackageHash -PackageName $PackageName -Source $Source -DatabasePath $Config.SecurityValidation.HashDatabasePath
                
                $hashResult = @{
                    CurrentHash = $currentHash
                    StoredHash = $storedHash.Hash
                    Algorithm = $Config.SecurityValidation.HashAlgorithm
                    IsValid = $true
                    Message = "Hash calculated successfully"
                }
                
                if ($ExpectedHash -and $currentHash -ne $ExpectedHash) {
                    $hashResult.IsValid = $false
                    $hashResult.Message = "Hash mismatch with expected value"
                    $result.Success = $false
                } elseif ($storedHash -and $currentHash -ne $storedHash.Hash) {
                    $hashResult.IsValid = $false
                    $hashResult.Message = "Hash mismatch with stored value"
                    $result.Success = $false
                } else {
                    if ($Config.SecurityValidation.SaveHashDatabase) {
                        Save-PackageHash -PackageName $PackageName -Source $Source `
                            -Version "Latest" -Hash $currentHash -FilePath $exePath `
                            -DatabasePath $Config.SecurityValidation.HashDatabasePath
                    }
                }
                
                $result.HashValidation = $hashResult
            } else {
                $result.Success = $false
                $result.Message = "Failed to calculate hash"
            }
        }
        
        if ($Config.SecurityValidation.EnableSignatureValidation) {
            $signatureResult = Test-AuthenticodeSignature -FilePath $exePath `
                -TrustedPublishers $Config.SecurityValidation.TrustedPublishers `
                -RequireValidSignature $Config.SecurityValidation.RequireValidSignature `
                -CheckRevocation $Config.SecurityValidation.CheckCertificateRevocation
            
            $result.SignatureValidation = $signatureResult
            
            if (-not $signatureResult.IsValid -and $Config.SecurityValidation.RequireValidSignature) {
                $result.Success = $false
                $result.Message += " Signature validation failed: $($signatureResult.Message)"
            }
            
            if ($Config.SecurityValidation.BlockUntrustedPackages -and -not $signatureResult.IsValid) {
                $result.Success = $false
                $result.Message += " Package blocked: untrusted signature"
            }
        }
        
        if ($result.Success) {
            $result.Message = "Package integrity validated successfully"
        }
        
        return $result
    } catch {
        return @{
            Success = $false
            Method = "Error"
            Message = "Error validating package integrity: $_"
        }
    }
}

function Invoke-SecurityValidation {
    <#
    .SYNOPSIS
        Performs security validation on multiple packages.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Packages,
        
        [Parameter(Mandatory = $false)]
        [object]$Config
    )
    
    if (-not $Config) {
        $Config = Get-UpdateConfig
    }
    
    $results = @()
    
    foreach ($package in $Packages) {
        Write-Log "Validating security for $($package.Name) ($($package.Source))..." -Level "Info"
        
        $validation = Test-PackageIntegrity `
            -PackageName $package.Name `
            -Source $package.Source `
            -Config $Config
        
        $result = [PSCustomObject]@{
            PackageName = $package.Name
            Source = $package.Source
            SecurityPassed = $validation.Success
            HashValid = if ($validation.HashValidation) { $validation.HashValidation.IsValid } else { $null }
            SignatureValid = if ($validation.SignatureValidation) { $validation.SignatureValidation.IsValid } else { $null }
            Publisher = if ($validation.SignatureValidation) { $validation.SignatureValidation.Publisher } else { $null }
            Message = $validation.Message
        }
        
        $results += $result
        
        if ($validation.Success) {
            Write-Log "Security validation passed: $($package.Name)" -Level "Success"
        } else {
            Write-Log "Security validation failed: $($package.Name) - $($validation.Message)" -Level "Warning"
        }
    }
    
    return $results
}

function New-SecurityReport {
    <#
    .SYNOPSIS
        Creates a security validation report.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$ValidationResults,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("HTML", "JSON", "Text")]
        [string]$Format = "HTML"
    )
    
    try {
        $passedCount = ($ValidationResults | Where-Object { $_.SecurityPassed }).Count
        $failedCount = ($ValidationResults | Where-Object { -not $_.SecurityPassed }).Count
        $totalCount = $ValidationResults.Count
        
        switch ($Format) {
            "HTML" {
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                
                $html = @'
<!DOCTYPE html>
<html>
<head>
    <title>Security Validation Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #e74c3c; padding-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin: 20px 0; }
        .summary-card { padding: 20px; border-radius: 8px; text-align: center; }
        .total { background: #3498db; color: white; }
        .success { background: #2ecc71; color: white; }
        .failure { background: #e74c3c; color: white; }
        .summary-number { font-size: 36px; font-weight: bold; }
        .summary-label { font-size: 14px; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #e74c3c; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f8f9fa; }
        .status-pass { color: #2ecc71; font-weight: bold; }
        .status-fail { color: #e74c3c; font-weight: bold; }
        .status-na { color: #95a5a6; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Security Validation Report</h1>
        <p><strong>Generated:</strong> {0}</p>
        <div class="summary">
            <div class="summary-card total"><div class="summary-number">{1}</div><div class="summary-label">Total</div></div>
            <div class="summary-card success"><div class="summary-number">{2}</div><div class="summary-label">Passed</div></div>
            <div class="summary-card failure"><div class="summary-number">{3}</div><div class="summary-label">Failed</div></div>
        </div>
        <table><tr><th>Package</th><th>Source</th><th>Hash</th><th>Signature</th><th>Publisher</th><th>Status</th></tr>
'@
                
                $html = $html -f $timestamp, $totalCount, $passedCount, $failedCount
                
                foreach ($result in $ValidationResults) {
                    $statusClass = if ($result.SecurityPassed) { "status-pass" } else { "status-fail" }
                    $statusText = if ($result.SecurityPassed) { "Passed" } else { "Failed" }
                    $hashStatus = if ($null -eq $result.HashValid) { "N/A" } elseif ($result.HashValid) { "Valid" } else { "Invalid" }
                    $sigStatus = if ($null -eq $result.SignatureValid) { "N/A" } elseif ($result.SignatureValid) { "Valid" } else { "Invalid" }
                    $publisher = if ($result.Publisher) { $result.Publisher } else { "N/A" }
                    
                    $html += "<tr><td>$($result.PackageName)</td><td>$($result.Source)</td><td>$hashStatus</td><td>$sigStatus</td><td>$publisher</td><td class=`"$statusClass`">$statusText</td></tr>"
                }
                
                $html += "</table></div></body></html>"
                $html | Set-Content $OutputPath -Encoding UTF8
            }
            
            "JSON" {
                $report = @{
                    GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Summary = @{
                        Total = $totalCount
                        Passed = $passedCount
                        Failed = $failedCount
                    }
                    Results = $ValidationResults
                }
                
                $report | ConvertTo-Json -Depth 10 | Set-Content $OutputPath -Encoding UTF8
            }
            
            "Text" {
                $lines = @()
                $lines += "Security Validation Report"
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $lines += "Generated: $timestamp"
                $lines += ""
                $lines += "Summary:"
                $lines += "Total: $totalCount - Passed: $passedCount - Failed: $failedCount"
                $lines += ""
                
                foreach ($result in $ValidationResults) {
                    if ($result.SecurityPassed) {
                        $status = "[PASS]"
                    } else {
                        $status = "[FAIL]"
                    }
                    $line = "{0} {1} ({2}) - Hash: {3} - Sig: {4} - {5}" -f $status, $result.PackageName, $result.Source, 
                        $(if ($null -eq $result.HashValid) { "N/A" } elseif ($result.HashValid) { "Valid" } else { "Invalid" }),
                        $(if ($null -eq $result.SignatureValid) { "N/A" } elseif ($result.SignatureValid) { "Valid" } else { "Invalid" }),
                        $result.Message
                    $lines += $line
                }
                
                $output = $lines -join [Environment]::NewLine
                $output | Set-Content $OutputPath -Encoding UTF8
            }
        }
        
        Write-Log "Security report saved: $OutputPath" -Level "Info"
        return $true
    } catch {
        Write-Log "Error creating security report: $_" -Level "Error"
        return $false
    }
}

# ============================================================================
# FAQ Helper Function
# ============================================================================

function Get-FAQ {
    <#
    .SYNOPSIS
        Search and display FAQ entries.
    
    .DESCRIPTION
        Opens the FAQ.md file or searches for specific content.
    
    .PARAMETER Query
        Search query to find relevant FAQ entries.
    
    .PARAMETER Open
        Open FAQ.md in default editor.
    
    .EXAMPLE
        Get-FAQ
        Displays FAQ file path and usage information.
    
    .EXAMPLE
        Get-FAQ -Open
        Opens FAQ.md in the default editor.
    
    .EXAMPLE
        Get-FAQ -Query "execution"
        Searches FAQ content for "execution".
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Query,
        
        [Parameter(Mandatory = $false)]
        [switch]$Open
    )
    
    try {
        $faqPath = Join-Path $PSScriptRoot "FAQ.md"
        
        if (-not (Test-Path $faqPath)) {
            Write-Host "FAQ.md file not found at: $faqPath" -ForegroundColor Red
            Write-Host "Please ensure FAQ.md exists in the script directory." -ForegroundColor Yellow
            return
        }
        
        if ($Open) {
            Write-Host "Opening FAQ.md..." -ForegroundColor Cyan
            Start-Process $faqPath
            return
        }
        
        if ($Query) {
            Write-Host "`nSearching FAQ for: '$Query'" -ForegroundColor Cyan
            Write-Host "=" * 70 -ForegroundColor Gray
            
            $content = Get-Content $faqPath
            $matchedLines = $content | Select-String -Pattern $Query -Context 2,2
            
            if ($matchedLines) {
                Write-Host "`nFound $($matchedLines.Count) match(es):`n" -ForegroundColor Green
                foreach ($match in $matchedLines) {
                    Write-Host "Line $($match.LineNumber):" -ForegroundColor Yellow
                    Write-Host $match.Line -ForegroundColor White
                    if ($match.Context.PreContext) {
                        Write-Host "  Context: $($match.Context.PreContext -join ' ')" -ForegroundColor Gray
                    }
                    Write-Host ""
                }
            } else {
                Write-Host "`nNo matches found for '$Query'" -ForegroundColor Yellow
            }
            return
        }
        
        # No parameters - show info
        Write-Host "`nFAQ Helper" -ForegroundColor Cyan
        Write-Host "=" * 50 -ForegroundColor Gray
        Write-Host "`nFAQ file location: $faqPath" -ForegroundColor White
        Write-Host "`nUsage:" -ForegroundColor Yellow
        Write-Host "  Get-FAQ -Open              # Open FAQ in editor" -ForegroundColor Cyan
        Write-Host "  Get-FAQ -Query 'keyword'   # Search FAQ content" -ForegroundColor Cyan
        Write-Host ""
        
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Host "Error accessing FAQ: $errorMsg" -ForegroundColor Red
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-UpdateConfig',
    'Initialize-Logging',
    'Write-Log',
    'Stop-Logging',
    'Test-Prerequisites',
    'Test-UpdateSource',
    'New-UpdateRestorePoint',
    'Export-UpdateReport',
    'Send-ToastNotification',
    'Send-UpdateNotification',
    'Get-SystemRestorePoints',
    'Invoke-SystemRestore',
    'Get-PackageHistory',
    'Invoke-PackageRollback',
    'Initialize-UpdateHistory',
    'Add-UpdateHistoryEntry',
    'Get-UpdateHistory',
    'Clear-UpdateHistory',
    'Export-UpdateHistoryReport',
    'Initialize-PackageCache',
    'Get-PackageCache',
    'Update-PackageCache',
    'Compare-PackageVersions',
    'Clear-PackageCache',
    'Get-CacheStatistics',
    'Get-PackagePriority',
    'Sort-PackagesByPriority',
    'Get-PrioritySummary',
    'Add-PackageToPriority',
    'Remove-PackageFromPriority',
    'Get-PackageVersion',
    'Test-PackageInstalled',
    'Test-UpdateSuccess',
    'Test-PackageHealth',
    'Invoke-UpdateValidation',
    'New-ValidationReport',
    'Get-FileHash256',
    'Get-PackageExecutablePath',
    'Test-AuthenticodeSignature',
    'Initialize-HashDatabase',
    'Get-HashDatabase',
    'Save-PackageHash',
    'Get-PackageHash',
    'Test-PackageIntegrity',
    'Invoke-SecurityValidation',
    'New-SecurityReport',
    'Test-WingetInstalled',
    'Test-ChocolateyInstalled',
    'Test-PowerShellModule',
    'Get-WingetVersion',
    'Get-ChocolateyVersion',
    'Test-DependencyVersion',
    'Install-WingetCLI',
    'Install-Chocolatey',
    'Install-PowerShellModule',
    'Install-Dependency',
    'Invoke-DependencyInstallation',
    'Get-FAQ'
)
