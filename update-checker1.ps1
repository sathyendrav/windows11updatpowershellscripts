# Check for Windows Store app updates
Write-Host "Checking for Microsoft Store app updates..." -ForegroundColor Yellow
Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" | Invoke-CimMethod -MethodName UpdateScanMethod

# Check for Winget package updates (if available)
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "`nChecking for Winget package updates..." -ForegroundColor Yellow
    winget upgrade
} else {
    Write-Host "Winget is not available on this system" -ForegroundColor Red
}

# Check for Chocolatey updates (if available)
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Host "`nChecking for Chocolatey package updates..." -ForegroundColor Yellow
    choco upgrade all --whatif
}

Write-Host "`nUpdate check completed!" -ForegroundColor Green