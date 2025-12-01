Write-Host "Checking for Microsoft Store app updates..." -ForegroundColor Yellow
try {
    Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" | Invoke-CimMethod -MethodName UpdateScanMethod
} catch {
    Write-Host "Failed to check Microsoft Store updates: $_" -ForegroundColor Red
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "`nChecking for Winget package updates..." -ForegroundColor Yellow
    winget upgrade --all --silent
} else {
    Write-Host "Winget is not available on this system" -ForegroundColor Red
}

if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Host "`nChecking for Chocolatey package updates..." -ForegroundColor Yellow
    choco upgrade all -y
} else {
    Write-Host "Chocolatey is not available on this system" -ForegroundColor Red
}

Write-Host "`nUpdate check completed!" -ForegroundColor Green

