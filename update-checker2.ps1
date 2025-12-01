# Enhanced update checker with detailed reporting
param(
    [switch]$AutoUpdate,
    [switch]$ListOnly
)

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Check-WingetUpdates {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-ColorOutput "`n=== Winget Packages ===" "Cyan"
        try {
            $updates = winget upgrade --include-unknown | Out-String
            if ($updates -like "*No installed package*" -or $updates -like "*No applicable updates*") {
                Write-ColorOutput "All Winget packages are up to date" "Green"
            } else {
                Write-ColorOutput "Available updates found:" "Yellow"
                winget upgrade --include-unknown
                
                if ($AutoUpdate -and -not $ListOnly) {
                    $choice = Read-Host "`nDo you want to update all Winget packages? (Y/N)"
                    if ($choice -eq 'Y' -or $choice -eq 'y') {
                        winget upgrade --all --silent
                        Write-ColorOutput "Winget packages updated successfully" "Green"
                    }
                }
            }
        } catch {
            Write-ColorOutput "Error checking Winget updates: $($_.Exception.Message)" "Red"
        }
    } else {
        Write-ColorOutput "Winget is not available" "Red"
    }
}

function Check-StoreUpdates {
    Write-ColorOutput "`n=== Microsoft Store Apps ===" "Cyan"
    try {
        # Refresh store app updates
        $result = Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" | Invoke-CimMethod -MethodName UpdateScanMethod
        Write-ColorOutput "Microsoft Store update scan initiated" "Green"
        
        # Note: Store apps will show updates in the Microsoft Store app
        Write-ColorOutput "Check the Microsoft Store app for available updates" "Yellow"
    } catch {
        Write-ColorOutput "Error checking Store updates: $($_.Exception.Message)" "Red"
    }
}

function Check-ChocolateyUpdates {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-ColorOutput "`n=== Chocolatey Packages ===" "Cyan"
        try {
            choco outdated
        } catch {
            Write-ColorOutput "Error checking Chocolatey updates: $($_.Exception.Message)" "Red"
        }
    }
}

function Get-InstalledSoftware {
    Write-ColorOutput "`n=== Installed Software Overview ===" "Cyan"
    
    # Get installed programs from registry
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    $installed = Get-ItemProperty $paths | Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
    
    Write-ColorOutput "Total installed applications: $($installed.Count)" "White"
    
    # Show recently installed apps
    $recent = $installed | Sort-Object InstallDate -Descending | Select-Object -First 5
    Write-ColorOutput "`nRecently installed applications:" "Yellow"
    $recent | Format-Table DisplayName, DisplayVersion, InstallDate -AutoSize
}

# Main execution
Write-ColorOutput "Windows 11 Application Update Checker" "Magenta"
Write-ColorOutput "=====================================" "Magenta"

# Get system info
$os = Get-CimInstance Win32_OperatingSystem
Write-ColorOutput "System: $($os.Caption)" "White"
Write-ColorOutput "Version: $($os.Version)" "White"
Write-ColorOutput "Last Boot: $($os.LastBootUpTime)" "White"

# Run checks
Check-WingetUpdates
Check-StoreUpdates
Check-ChocolateyUpdates
Get-InstalledSoftware

Write-ColorOutput "`nUpdate check completed!" "Green"
if ($AutoUpdate) {
    Write-ColorOutput "Auto-update mode was enabled" "Yellow"
}