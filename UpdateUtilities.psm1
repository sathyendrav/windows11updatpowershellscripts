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
<html>
<head>
    <title>Windows Update Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
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
    </style>
</head>
<body>
    <div class="container">
        <h1>🔄 Windows Update Report</h1>
        <div class="info">
            <p><strong>Generated:</strong> <span class="timestamp">$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</span></p>
            <p><strong>System:</strong> $($Data.SystemInfo.OS)</p>
            <p><strong>Version:</strong> $($Data.SystemInfo.Version)</p>
        </div>
        
        <h2>Update Summary</h2>
        <table>
            <tr><th>Source</th><th>Status</th><th>Updates Found</th></tr>
            <tr><td>Microsoft Store</td><td class="$($Data.Store.Status)">$($Data.Store.Status)</td><td>$($Data.Store.Count)</td></tr>
            <tr><td>Winget</td><td class="$($Data.Winget.Status)">$($Data.Winget.Status)</td><td>$($Data.Winget.Count)</td></tr>
            <tr><td>Chocolatey</td><td class="$($Data.Chocolatey.Status)">$($Data.Chocolatey.Status)</td><td>$($Data.Chocolatey.Count)</td></tr>
        </table>
        
        <p style="margin-top: 20px; text-align: center; color: #666; font-size: 0.9em;">
            Generated by Windows Update Helper Scripts
        </p>
    </div>
</body>
</html>
"@
    
    return $html
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
    'Export-UpdateReport'
)
