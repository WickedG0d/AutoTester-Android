# ==============================================================================
#           AUTOTESTER-ANDROID - WINDOWS DEPENDENCY INSTALLER
# ==============================================================================

Write-Host "Checking system requirements for AutoTester-Android..." -ForegroundColor Cyan
Write-Host ""

# Check PowerShell Version
$psVer = $PSVersionTable.PSVersion
Write-Host "PowerShell Version : $psVer"
if ($psVer.Major -lt 5) {
    Write-Host "[WARNING] PowerShell 5.1 or newer is strongly recommended." -ForegroundColor Yellow
} else {
    Write-Host "[OK] PowerShell version is supported." -ForegroundColor Green
}

# Check ADB
Write-Host ""
Write-Host "Checking Android Debug Bridge (adb)..."
$adbPath = (Get-Command adb -ErrorAction SilentlyContinue).Source

if ($adbPath) {
    Write-Host "[OK] ADB is already installed at: $adbPath" -ForegroundColor Green
    & adb version
} else {
    Write-Host "[MISSING] ADB not found in system PATH." -ForegroundColor Yellow
    Write-Host "Attempting installation via Windows Package Manager (winget)..." -ForegroundColor Cyan

    $wingetPath = (Get-Command winget -ErrorAction SilentlyContinue).Source
    if ($wingetPath) {
        try {
            Write-Host "Running: winget install --id Google.PlatformTools -e --source winget"
            winget install --id Google.PlatformTools -e --source winget --accept-package-agreements --accept-source-agreements
            Write-Host ""
            Write-Host "[SUCCESS] Android Platform Tools installed!" -ForegroundColor Green
            Write-Host "Please restart your PowerShell terminal for PATH changes to take effect." -ForegroundColor Yellow
        } catch {
            Write-Host "[ERROR] Failed to install via winget: $_" -ForegroundColor Red
        }
    } else {
        Write-Host ""
        Write-Host "Winget is not available on this machine." -ForegroundColor Yellow
        Write-Host "Please manually download the Android Platform Tools from:"
        Write-Host "👉 https://developer.android.com/tools/releases/platform-tools" -ForegroundColor Cyan
        Write-Host "Extract the zip file and add the folder containing 'adb.exe' to your system PATH."
    }
}

Write-Host ""
Write-Host "================================================================="
Write-Host "Dependency check complete." -ForegroundColor Green
Write-Host "================================================================="
