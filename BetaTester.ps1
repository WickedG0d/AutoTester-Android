# ==============================================================================
#                      PLAYKEEPER / ANDROID BETA TEST AUTOMATOR
#       Automated Continuous Testing for Google Play 14-Day / 20-Tester Requirements
#                         ADB Wireless + Windows Task Scheduler
# ==============================================================================

param(
    [switch]$AutoRun
)

$ErrorActionPreference = "SilentlyContinue"

$ConfigFile = "$PSScriptRoot\config.json"
$LogFile    = "$PSScriptRoot\betatester.log"


# ==============================================================================
# LOGGING & NOTIFICATIONS
# ==============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        [switch]$NoConsole
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"

    try {
        Add-Content -Path $LogFile -Value $logLine -ErrorAction SilentlyContinue
    }
    catch {}

    if (!$NoConsole) {
        $color = switch ($Level) {
            "WARN"    { "Yellow" }
            "ERROR"   { "Red" }
            "SUCCESS" { "Green" }
            default   { "White" }
        }
        Write-Host "[$timestamp] $Message" -ForegroundColor $color
    }
}

function Send-DesktopNotification {
    param(
        [string]$Title,
        [string]$Message,
        [switch]$IsError
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        if ($IsError) {
            $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error
        } else {
            $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        }
        $notify.BalloonTipTitle = $Title
        $notify.BalloonTipText  = $Message
        $notify.Visible = $true
        $notify.ShowBalloonTip(5000)
        Start-Sleep -Milliseconds 500
        $notify.Dispose()
    }
    catch {
        # Fallback silently if system forms are unavailable in background
    }
}


# ==============================================================================
# ADB DEVICE FUNCTIONS
# ==============================================================================

function Get-ADBDevices {
    $lines = @(adb devices 2>$null)
    $devices = @()

    foreach ($line in $lines) {
        if ($line -match "^\s*(\S+)\s+device\s*$") {
            $devices += $matches[1]
        }
    }

    return @($devices)
}

function Test-ADBDevice {
    param(
        [string]$Device
    )

    if (!$Device) {
        return $false
    }

    $devices = @(Get-ADBDevices)
    return ($devices -contains $Device)
}

function Get-PhoneIP {
    param(
        [string]$Device
    )

    if (!$Device) {
        return $null
    }

    if ($Device -match "^(.+):(\d+)$") {
        return $matches[1]
    }

    return $null
}

function Find-WirelessADBDevice {
    Write-Log "Searching for Wireless Debugging device via mDNS..." -Level "INFO"

    $output = @(adb mdns services 2>$null)
    $candidates = @()

    foreach ($line in $output) {
        if ($line -match "(\d{1,3}(?:\.\d{1,3}){3}):(\d+).*(adb-tls-connect)") {
            $ip = $matches[1]
            $port = $matches[2]
            $endpoint = "$ip`:$port"
            $candidates += $endpoint
        }
    }

    if ($candidates.Count -eq 0) {
        Write-Log "No Wireless Debugging devices discovered." -Level "WARN"
        return $null
    }

    foreach ($endpoint in $candidates) {
        Write-Log "Attempting connection to $endpoint..." -Level "INFO"
        $null = adb connect $endpoint 2>&1
        Start-Sleep -Seconds 2

        if (Test-ADBDevice $endpoint) {
            Write-Log "Connected to $endpoint successfully." -Level "SUCCESS"
            return $endpoint
        }
    }

    return $null
}

function Connect-Phone {
    param(
        [string]$SavedDevice
    )

    # 1. Check existing connections
    $devices = @(Get-ADBDevices)
    if ($devices.Count -ge 1) {
        if ($SavedDevice -and ($devices -contains $SavedDevice)) {
            Write-Log "Device already connected: $SavedDevice" -Level "SUCCESS"
            return $SavedDevice
        }
        Write-Log "Phone already connected: $($devices[0])" -Level "SUCCESS"
        return $devices[0]
    }

    # 2. Try previous IP/port
    $ip = Get-PhoneIP $SavedDevice
    if ($ip -and $SavedDevice -match ":(\d+)$") {
        $oldPort = $matches[1]
        $endpoint = "$ip`:$oldPort"
        Write-Log "Attempting to reconnect to previous phone address: $endpoint..." -Level "INFO"
        adb connect $endpoint 2>$null | Out-Null
        Start-Sleep -Seconds 2

        if (Test-ADBDevice $endpoint) {
            Write-Log "Reconnected to $endpoint successfully." -Level "SUCCESS"
            return $endpoint
        }
    }

    # 3. Try mDNS discovery
    Write-Log "Previous connection unavailable. Discovering via mDNS..." -Level "INFO"
    $found = Find-WirelessADBDevice
    if ($found) {
        return $found
    }

    # 4. Check adb devices once more
    $devices = @(Get-ADBDevices)
    if ($devices.Count -gt 0) {
        return $devices[0]
    }

    Write-Log "Could not locate or connect to any Android device." -Level "ERROR"
    return $null
}

function Select-Device {
    $devices = @(Get-ADBDevices)

    if ($devices.Count -eq 0) {
        $found = Find-WirelessADBDevice
        if ($found) {
            return $found
        }

        Write-Host ""
        Write-Host "No Android device connected." -ForegroundColor Red
        return $null
    }

    if ($devices.Count -eq 1) {
        return $devices[0]
    }

    Clear-Host
    Write-Host "========================================"
    Write-Host "          SELECT ANDROID DEVICE"
    Write-Host "========================================"
    Write-Host ""

    for ($i = 0; $i -lt $devices.Count; $i++) {
        Write-Host "[$($i + 1)] $($devices[$i])"
    }

    Write-Host ""
    $choice = Read-Host "Select your phone"
    if ($choice -match "^\d+$") {
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $devices.Count) {
            return $devices[$index]
        }
    }

    return $null
}


# ==============================================================================
# SCREEN WAKE, UNLOCK & GEOMETRY
# ==============================================================================

function Get-DeviceScreenMetrics {
    param(
        [string]$Device
    )

    $width  = 1080
    $height = 2400

    try {
        $sizeOutput = adb -s $Device shell wm size 2>$null
        foreach ($line in $sizeOutput) {
            if ($line -match "(\d{3,4})x(\d{3,4})") {
                $width  = [int]$matches[1]
                $height = [int]$matches[2]
            }
        }
    }
    catch {}

    return [PSCustomObject]@{
        Width      = $width
        Height     = $height
        SafeMinX   = [int]($width * 0.15)
        SafeMaxX   = [int]($width * 0.85)
        SafeMinY   = [int]($height * 0.22)
        SafeMaxY   = [int]($height * 0.78)
        ScrollMidX = [int]($width * 0.50)
        ScrollTopY = [int]($height * 0.35)
        ScrollBtmY = [int]($height * 0.65)
    }
}

function Wake-And-Unlock-Device {
    param(
        [string]$Device,
        [string]$Pin
    )

    Write-Log "Waking up device screen..." -Level "INFO"

    # Send wake up
    adb -s $Device shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null
    Start-Sleep -Milliseconds 600

    # Dismiss keyguard / swipe lock
    adb -s $Device shell wm dismiss-keyguard 2>$null | Out-Null
    Start-Sleep -Milliseconds 400

    # Simulate swipe up to dismiss lock screen if required
    $metrics = Get-DeviceScreenMetrics $Device
    adb -s $Device shell input swipe $metrics.ScrollMidX $metrics.ScrollBtmY $metrics.ScrollMidX $metrics.ScrollTopY 250 2>$null | Out-Null
    Start-Sleep -Milliseconds 400

    # If PIN is configured, input it
    if ($Pin) {
        Write-Log "Inputting device PIN for unlock..." -Level "INFO"
        adb -s $Device shell input text $Pin 2>$null | Out-Null
        Start-Sleep -Milliseconds 200
        adb -s $Device shell input keyevent 66 2>$null | Out-Null # KEYCODE_ENTER
        Start-Sleep -Milliseconds 500
    }
}

function Lock-Device {
    param(
        [string]$Device
    )

    Write-Log "Turning off device screen..." -Level "INFO"
    adb -s $Device shell input keyevent KEYCODE_SLEEP 2>$null | Out-Null
}


# ==============================================================================
# REALISTIC USER INTERACTION SIMULATOR (GOOGLE PLAY COMPLIANCE)
# ==============================================================================

function Simulate-AppInteraction {
    param(
        [string]$Device,
        [int]$DurationSeconds,
        $Metrics
    )

    $startTime = Get-Date
    $actionCount = 0

    while (((Get-Date) - $startTime).TotalSeconds -lt $DurationSeconds) {
        $remaining = [int]($DurationSeconds - ((Get-Date) - $startTime).TotalSeconds)
        if ($remaining -le 2) { break }

        # Choose random human gesture
        # 1-4: Scroll Down, 5-6: Scroll Up, 7-8: Gentle Tap, 9-10: In-App Back
        $dice = Get-Random -Minimum 1 -Maximum 11

        switch ($dice) {
            { $_ -in 1, 2, 3, 4 } {
                # Natural scroll down
                $startX = Get-Random -Minimum ($Metrics.ScrollMidX - 40) -Maximum ($Metrics.ScrollMidX + 40)
                $durationMs = Get-Random -Minimum 250 -Maximum 450
                adb -s $Device shell input swipe $startX $Metrics.ScrollBtmY $startX $Metrics.ScrollTopY $durationMs 2>$null | Out-Null
            }
            { $_ -in 5, 6 } {
                # Natural scroll up
                $startX = Get-Random -Minimum ($Metrics.ScrollMidX - 40) -Maximum ($Metrics.ScrollMidX + 40)
                $durationMs = Get-Random -Minimum 250 -Maximum 450
                adb -s $Device shell input swipe $startX $Metrics.ScrollTopY $startX $Metrics.ScrollBtmY $durationMs 2>$null | Out-Null
            }
            { $_ -in 7, 8 } {
                # Gentle tap in safe central viewport
                $tapX = Get-Random -Minimum $Metrics.SafeMinX -Maximum $Metrics.SafeMaxX
                $tapY = Get-Random -Minimum $Metrics.SafeMinY -Maximum $Metrics.SafeMaxY
                adb -s $Device shell input tap $tapX $tapY 2>$null | Out-Null
            }
            default {
                # Navigate back within the app to simulate view switching
                adb -s $Device shell input keyevent KEYCODE_BACK 2>$null | Out-Null
            }
        }

        $actionCount++
        $sleepInterval = Get-Random -Minimum 3 -Maximum 7
        Start-Sleep -Seconds $sleepInterval
    }

    return $actionCount
}


# ==============================================================================
# CONFIGURATION
# ==============================================================================

function Load-Config {
    $defaults = [PSCustomObject]@{
        MinDelay             = 30
        MaxDelay             = 60
        Schedule             = "22:00"
        Randomize            = $true
        SimulateGestures     = $true
        ForceStopAfter       = $true
        AutoWakeAndUnlock    = $true
        AutoLockOnFinish     = $true
        DevicePin            = ""
        DesktopNotifications = $true
        LastDevice           = ""
        SelectedApps         = @()
        AppCache             = @{}
    }

    if (Test-Path $ConfigFile) {
        try {
            $raw = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            
            # Map legacy "Device" key if present
            if ($raw.PSObject.Properties['Device'] -and !$raw.PSObject.Properties['LastDevice']) {
                $raw | Add-Member -MemberType NoteProperty -Name "LastDevice" -Value $raw.Device -Force
            }

            # Merge with defaults for missing properties
            foreach ($prop in $defaults.PSObject.Properties) {
                if (!$raw.PSObject.Properties[$prop.Name]) {
                    $raw | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
                }
            }

            # Convert AppCache to hashtable if deserialized as PSCustomObject
            if ($raw.AppCache -is [PSCustomObject]) {
                $ht = @{}
                foreach ($p in $raw.AppCache.PSObject.Properties) {
                    $ht[$p.Name] = $p.Value
                }
                $raw.AppCache = $ht
            }

            return $raw
        }
        catch {
            Write-Log "Failed to parse $ConfigFile, reverting to defaults: $_" -Level "WARN"
        }
    }

    return $defaults
}

function Save-Config {
    param(
        $Config
    )

    try {
        $Config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
    }
    catch {
        Write-Log "Failed to save configuration: $_" -Level "ERROR"
    }
}


# ==============================================================================
# APP CATALOG & CACHING
# ==============================================================================

function Get-AppPackageList {
    param(
        [string]$Device
    )

    $result = @(adb -s $Device shell pm list packages -3 2>$null)
    $packages = @()

    foreach ($line in $result) {
        if ($line -match "^package:(.+)$") {
            $package = $matches[1].Trim()
            if ($package) {
                $packages += $package
            }
        }
    }

    return @($packages | Sort-Object)
}

function Get-AppName {
    param(
        [string]$Device,
        [string]$Package,
        $Config
    )

    # Check cache first to avoid slow adb dumpsys calls
    if ($Config.AppCache -and $Config.AppCache.ContainsKey($Package)) {
        return $Config.AppCache[$Package]
    }

    $name = $Package
    try {
        $dump = @(adb -s $Device shell dumpsys package $Package 2>$null)
        foreach ($line in $dump) {
            if ($line -match "application-label(?:-en)?:(.+)") {
                $parsed = $matches[1].Trim()
                if ($parsed -and $parsed -ne $Package) {
                    $name = $parsed
                    break
                }
            }
        }
    }
    catch {}

    if (!$Config.AppCache) {
        $Config.AppCache = @{}
    }
    $Config.AppCache[$Package] = $name

    return $name
}

function Get-InstalledApps {
    param(
        [string]$Device,
        $Config
    )

    Write-Host ""
    Write-Host "Loading installed third-party apps..."

    $packages = @(Get-AppPackageList $Device)
    $apps = @()
    $counter = 0
    $cacheModified = $false

    foreach ($package in $packages) {
        $counter++
        $percent = 0
        if ($packages.Count -gt 0) {
            $percent = [int](($counter / $packages.Count) * 100)
        }

        Write-Progress -Activity "Loading apps" -Status "$counter / $($packages.Count)" -PercentComplete $percent

        $cached = $false
        if ($Config.AppCache -and $Config.AppCache.ContainsKey($package)) {
            $name = $Config.AppCache[$package]
            $cached = $true
        } else {
            $name = Get-AppName -Device $Device -Package $package -Config $Config
            $cacheModified = $true
        }

        $apps += [PSCustomObject]@{
            Name    = $name
            Package = $package
        }
    }

    Write-Progress -Activity "Loading apps" -Completed

    if ($cacheModified) {
        Save-Config $Config
    }

    return @($apps | Sort-Object Name)
}


# ==============================================================================
# APP SELECTION UI
# ==============================================================================

function Select-Apps {
    param(
        $Config,
        [string]$Device
    )

    Clear-Host
    Write-Host "========================================"
    Write-Host "           SELECT BETA APPS"
    Write-Host "========================================"
    Write-Host ""

    $apps = @(Get-InstalledApps -Device $Device -Config $Config)

    if ($apps.Count -eq 0) {
        Write-Host ""
        Write-Host "No user-installed apps found on $Device." -ForegroundColor Red
        Pause
        return
    }

    while ($true) {
        Clear-Host
        Write-Host "========================================"
        Write-Host "           SELECT BETA APPS"
        Write-Host "========================================"
        Write-Host ""
        Write-Host "Installed apps    : $($apps.Count)"
        Write-Host "Currently selected: $($Config.SelectedApps.Count)"
        Write-Host ""
        Write-Host "----------------------------------------"
        Write-Host "Commands:"
        Write-Host "  <name>       Search by app name or package"
        Write-Host "  <number>     Toggle selection by index (e.g. 5)"
        Write-Host "  1,3,7        Toggle multiple indices"
        Write-Host "  ALL          Select all installed apps"
        Write-Host "  CLEAR        Clear selection"
        Write-Host "  LIST         Show all selected apps"
        Write-Host "  DONE         Save and finish"
        Write-Host ""

        $query = Read-Host "Enter command or search"

        if ($query.ToUpper() -eq "DONE") {
            Save-Config $Config
            break
        }

        if ($query.ToUpper() -eq "CLEAR") {
            $Config.SelectedApps = @()
            Save-Config $Config
            Write-Host "Selection cleared." -ForegroundColor Yellow
            Start-Sleep 1
            continue
        }

        if ($query.ToUpper() -eq "ALL") {
            $Config.SelectedApps = @($apps | ForEach-Object { $_.Package })
            Save-Config $Config
            Write-Host "$($Config.SelectedApps.Count) apps selected." -ForegroundColor Green
            Start-Sleep 1
            continue
        }

        if ($query.ToUpper() -eq "LIST") {
            Clear-Host
            Write-Host "========================================"
            Write-Host "           SELECTED APPS"
            Write-Host "========================================"
            Write-Host ""

            $counter = 0
            foreach ($pkg in $Config.SelectedApps) {
                $counter++
                $app = $apps | Where-Object { $_.Package -eq $pkg }
                if ($app) {
                    Write-Host "[$counter] $($app.Name)"
                    Write-Host "     $($app.Package)" -ForegroundColor DarkGray
                } else {
                    Write-Host "[$counter] $pkg"
                }
            }
            Write-Host ""
            Pause
            continue
        }

        # Numeric index selection
        if ($query -match "^[\d,\s]+$") {
            foreach ($number in $query.Split(",")) {
                $number = $number.Trim()
                if ($number -match "^\d+$") {
                    $index = [int]$number - 1
                    if ($index -ge 0 -and $index -lt $apps.Count) {
                        $pkg = $apps[$index].Package
                        if ($Config.SelectedApps -contains $pkg) {
                            $Config.SelectedApps = @($Config.SelectedApps | Where-Object { $_ -ne $pkg })
                        } else {
                            $Config.SelectedApps += $pkg
                        }
                    }
                }
            }
            Save-Config $Config
            continue
        }

        # Search matching
        $search = $query.ToLower()
        $results = @($apps | Where-Object {
            $_.Name.ToLower().Contains($search) -or $_.Package.ToLower().Contains($search)
        })

        Clear-Host
        Write-Host "========================================"
        Write-Host "             SEARCH RESULTS"
        Write-Host "========================================"
        Write-Host "Search query: $query"
        Write-Host ""

        if ($results.Count -eq 0) {
            Write-Host "No matching apps found." -ForegroundColor Yellow
            Pause
            continue
        }

        for ($i = 0; $i -lt $results.Count; $i++) {
            $mark = if ($Config.SelectedApps -contains $results[$i].Package) { "[*]" } else { "[ ]" }
            Write-Host ("[{0,3}] {1} {2}" -f ($i + 1), $mark, $results[$i].Name)
            Write-Host ("      {0}" -f $results[$i].Package) -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "Enter numbers to toggle (e.g. 1, 3) or press Enter to return:"
        $selection = Read-Host "Selection"

        if ($selection -match "^[\d,\s]+$") {
            foreach ($number in $selection.Split(",")) {
                if ($number.Trim() -match "^\d+$") {
                    $index = [int]$number.Trim() - 1
                    if ($index -ge 0 -and $index -lt $results.Count) {
                        $pkg = $results[$index].Package
                        if ($Config.SelectedApps -contains $pkg) {
                            $Config.SelectedApps = @($Config.SelectedApps | Where-Object { $_ -ne $pkg })
                        } else {
                            $Config.SelectedApps += $pkg
                        }
                    }
                }
            }
            Save-Config $Config
        }
    }
}


# ==============================================================================
# SETTINGS CONFIGURATORS
# ==============================================================================

function Change-Delay {
    param(
        $Config
    )

    Clear-Host
    Write-Host "========================================"
    Write-Host "         APP TESTING DURATION"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Current session duration: $($Config.MinDelay) - $($Config.MaxDelay) seconds"
    Write-Host ""
    Write-Host "TIP: For Google Play 14-day closed testing compliance," -ForegroundColor Yellow
    Write-Host "     sessions of 30-90 seconds per app with human interactions" -ForegroundColor Yellow
    Write-Host "     ensure the review system records valid engagement metrics." -ForegroundColor Yellow
    Write-Host ""

    $min = Read-Host "Minimum seconds (e.g. 30)"
    if ($min -match "^\d+$") {
        $Config.MinDelay = [int]$min
    }

    $max = Read-Host "Maximum seconds (e.g. 60)"
    if ($max -match "^\d+$") {
        $Config.MaxDelay = [int]$max
    }

    if ($Config.MinDelay -lt 5) {
        $Config.MinDelay = 5
    }
    if ($Config.MaxDelay -lt $Config.MinDelay) {
        $Config.MaxDelay = $Config.MinDelay
    }

    Save-Config $Config
    Write-Host ""
    Write-Host "Saved duration: $($Config.MinDelay) - $($Config.MaxDelay) seconds" -ForegroundColor Green
    Pause
}

function Change-Schedule {
    param(
        $Config
    )

    Clear-Host
    Write-Host "========================================"
    Write-Host "             DAILY SCHEDULE"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Current scheduled time: $($Config.Schedule)"
    Write-Host ""

    $time = Read-Host "Enter new daily run time (HH:mm, 24-hour format)"

    try {
        $parsed = [DateTime]::ParseExact($time, "HH:mm", $null)
        $Config.Schedule = $parsed.ToString("HH:mm")
        Save-Config $Config
        Write-Host ""
        Write-Host "Daily schedule updated to $($Config.Schedule)." -ForegroundColor Green
        Write-Host "Remember to re-install scheduler (Option 8) to apply Windows Task updates." -ForegroundColor Yellow
    }
    catch {
        Write-Host ""
        Write-Host "Invalid time format. Please use HH:mm (e.g. 22:00)." -ForegroundColor Red
    }

    Pause
}

function Configure-Advanced-Settings {
    param(
        $Config
    )

    while ($true) {
        Clear-Host
        Write-Host "========================================"
        Write-Host "       ADVANCED & GOOGLE PLAY SETTINGS"
        Write-Host "========================================"
        Write-Host ""
        Write-Host "[1] Simulate Gestures (Scroll/Tap/Back) : $(if ($Config.SimulateGestures) { 'ENABLED' } else { 'DISABLED' })"
        Write-Host "[2] Force-Stop App After Testing        : $(if ($Config.ForceStopAfter) { 'ENABLED' } else { 'DISABLED' })"
        Write-Host "[3] Auto-Wake and Unlock Screen         : $(if ($Config.AutoWakeAndUnlock) { 'ENABLED' } else { 'DISABLED' })"
        Write-Host "[4] Auto-Lock Screen When Finished      : $(if ($Config.AutoLockOnFinish) { 'ENABLED' } else { 'DISABLED' })"
        Write-Host "[5] Device Unlock PIN                   : $(if ($Config.DevicePin) { 'SET (****)' } else { 'NOT SET (Swipe/None)' })"
        Write-Host "[6] Desktop Toast Notifications         : $(if ($Config.DesktopNotifications) { 'ENABLED' } else { 'DISABLED' })"
        Write-Host "[7] Back to Main Menu"
        Write-Host ""

        $choice = Read-Host "Choose option"

        switch ($choice) {
            "1" { $Config.SimulateGestures = !$Config.SimulateGestures }
            "2" { $Config.ForceStopAfter = !$Config.ForceStopAfter }
            "3" { $Config.AutoWakeAndUnlock = !$Config.AutoWakeAndUnlock }
            "4" { $Config.AutoLockOnFinish = !$Config.AutoLockOnFinish }
            "5" {
                $pin = Read-Host "Enter phone PIN (leave blank to clear)"
                $Config.DevicePin = $pin.Trim()
            }
            "6" { $Config.DesktopNotifications = !$Config.DesktopNotifications }
            "7" { Save-Config $Config; return }
        }

        Save-Config $Config
    }
}


# ==============================================================================
# CORE EXECUTION ENGINE
# ==============================================================================

function Run-Apps {
    param(
        $Config,
        [string]$Device,
        [switch]$IsAutoRun,
        [string]$SinglePackage = $null
    )

    $runStart = Get-Date

    if (!$Device) {
        Write-Log "Execution halted: No ADB device provided." -Level "ERROR"
        if (!$IsAutoRun) { Pause }
        return
    }

    # Verify or reconnect
    if (!(Test-ADBDevice $Device)) {
        Write-Log "ADB connection lost for $Device. Attempting reconnect..." -Level "WARN"
        $Device = Connect-Phone $Device
        if (!$Device) {
            Write-Log "Failed to reconnect to Android device. Aborting run." -Level "ERROR"
            if ($Config.DesktopNotifications) {
                Send-DesktopNotification -Title "PlayKeeper Test Failed" -Message "Device disconnected and could not reconnect." -IsError
            }
            if (!$IsAutoRun) { Pause }
            return
        }
    }

    $Config.LastDevice = $Device
    Save-Config $Config

    # Target packages
    if ($SinglePackage) {
        $apps = @($SinglePackage)
    } else {
        if ($Config.SelectedApps.Count -eq 0) {
            Write-Log "No apps configured for testing." -Level "WARN"
            if (!$IsAutoRun) { Pause }
            return
        }
        $apps = @($Config.SelectedApps)
        if ($Config.Randomize) {
            $apps = @($apps | Sort-Object { Get-Random })
        }
    }

    # Wake and unlock device
    if ($Config.AutoWakeAndUnlock) {
        Wake-And-Unlock-Device -Device $Device -Pin $Config.DevicePin
    }

    $screenMetrics = Get-DeviceScreenMetrics $Device

    Write-Log "Starting Beta Test Run on $Device ($($apps.Count) apps)..." -Level "INFO"

    $counter = 0
    $successful = 0
    $failed = 0

    foreach ($package in $apps) {
        $counter++

        # Connection health check
        if (!(Test-ADBDevice $Device)) {
            Write-Log "ADB connection lost during run. Reconnecting..." -Level "WARN"
            $newDevice = Connect-Phone $Device
            if ($newDevice) {
                $Device = $newDevice
                $Config.LastDevice = $Device
                Save-Config $Config
            } else {
                Write-Log "Device disconnected mid-run. Aborting." -Level "ERROR"
                $failed += ($apps.Count - $counter + 1)
                break
            }
        }

        # App display name
        $appName = if ($Config.AppCache -and $Config.AppCache.ContainsKey($package)) { $Config.AppCache[$package] } else { $package }

        Write-Log "[$counter/$($apps.Count)] Launching $appName ($package)..." -Level "INFO"

        # Launch via Monkey launcher
        $launchOutput = adb -s $Device shell monkey -p $package -c android.intent.category.LAUNCHER 1 2>&1

        if ($launchOutput -match "No activities found" -or $launchOutput -match "monkey aborted") {
            Write-Log "Failed to launch $package. Check if app is installed." -Level "WARN"
            $failed++
            continue
        }

        # Session duration calculation
        $duration = Get-Random -Minimum $Config.MinDelay -Maximum ($Config.MaxDelay + 1)

        if ($Config.SimulateGestures) {
            Write-Log "Interacting with $appName for $duration seconds (humanized gestures)..." -Level "INFO"
            $actions = Simulate-AppInteraction -Device $Device -DurationSeconds $duration -Metrics $screenMetrics
            Write-Log "Completed $actions simulated interaction gestures." -Level "INFO"
        } else {
            Write-Log "Keeping $appName in foreground for $duration seconds..." -Level "INFO"
            Start-Sleep -Seconds $duration
        }

        # Return Home
        adb -s $Device shell input keyevent KEYCODE_HOME 2>$null | Out-Null
        Start-Sleep -Seconds 1

        # Force-stop app if enabled to keep device cool & prevent RAM bloat
        if ($Config.ForceStopAfter) {
            adb -s $Device shell am force-stop $package 2>$null | Out-Null
        }

        $successful++
        Start-Sleep -Seconds 1
    }

    # Relock device if enabled
    if ($Config.AutoLockOnFinish) {
        Lock-Device -Device $Device
    }

    $elapsedMinutes = [math]::Round(((Get-Date) - $runStart).TotalMinutes, 1)
    $summaryMsg = "Tested $successful/$($apps.Count) apps successfully in $elapsedMinutes mins."
    Write-Log "Run Complete: $summaryMsg" -Level "SUCCESS"

    if ($Config.DesktopNotifications) {
        Send-DesktopNotification -Title "PlayKeeper Test Complete" -Message $summaryMsg
    }

    # IMPORTANT: Never call Pause in -AutoRun mode (prevents scheduled task hang)
    if (!$IsAutoRun) {
        Write-Host ""
        Write-Host "========================================"
        Write-Host "             RUN COMPLETE"
        Write-Host "========================================"
        Write-Host $summaryMsg -ForegroundColor Green
        Write-Host ""
        Pause
    }
}


# ==============================================================================
# WINDOWS TASK SCHEDULER
# ==============================================================================

function Install-Scheduler {
    param(
        $Config
    )

    Clear-Host
    Write-Host "========================================"
    Write-Host "         WINDOWS SCHEDULER"
    Write-Host "========================================"
    Write-Host ""

    $taskName   = "Android Beta Test Automator"
    $scriptPath = "$PSScriptRoot\BetaTester.ps1"

    $parts  = $Config.Schedule.Split(":")
    $hour   = [int]$parts[0]
    $minute = [int]$parts[1]

    # Run in the logged-on user's interactive session for ADB daemon access
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -AutoRun"

    $trigger = New-ScheduledTaskTrigger `
        -Daily `
        -At ([DateTime]::Today.AddHours($hour).AddMinutes($minute))

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Description "Automatically runs PlayKeeper Android beta testing apps via ADB Wireless." `
        -Force | Out-Null

    Write-Log "Scheduler task '$taskName' registered for daily execution at $($Config.Schedule)." -Level "SUCCESS"

    Write-Host ""
    Write-Host "Scheduler installed successfully." -ForegroundColor Green
    Write-Host "Task Name : $taskName"
    Write-Host "Schedule  : Daily at $($Config.Schedule)"
    Write-Host ""
    Write-Host "The task will auto-reconnect to your phone, wake & unlock the screen,"
    Write-Host "run humanized testing on all selected apps, and relock the screen."
    Write-Host ""
    Pause
}


# ==============================================================================
# LOG VIEWER
# ==============================================================================

function View-Logs {
    Clear-Host
    Write-Host "========================================"
    Write-Host "           RECENT LOG ENTRIES"
    Write-Host "========================================"
    Write-Host ""

    if (Test-Path $LogFile) {
        Get-Content $LogFile -Tail 25
    } else {
        Write-Host "No log file found at $LogFile." -ForegroundColor Yellow
    }

    Write-Host ""
    Pause
}


# ==============================================================================
# MAIN INTERACTIVE MENU
# ==============================================================================

function Main {
    $Config = Load-Config

    while ($true) {
        $Device = Select-Device

        if (!$Device) {
            Write-Host ""
            Write-Host "No Android device found." -ForegroundColor Red
            Write-Host "Please ensure USB or Wireless Debugging is enabled on your phone."
            Write-Host ""
            Pause
            return
        }

        $Config.LastDevice = $Device
        Save-Config $Config

        Clear-Host
        Write-Host "================================================================="
        Write-Host "       PLAYKEEPER - ANDROID BETA TEST AUTOMATOR"
        Write-Host "================================================================="
        Write-Host ""
        Write-Host "Connected Device : $Device" -ForegroundColor Green
        Write-Host "Selected Apps    : $($Config.SelectedApps.Count)"
        Write-Host "Session Duration : $($Config.MinDelay)-$($Config.MaxDelay)s per app"
        Write-Host "Daily Schedule   : $($Config.Schedule)"
        Write-Host "Simulate Gestures: $(if ($Config.SimulateGestures) { 'YES' } else { 'NO' })"
        Write-Host "Random Order     : $(if ($Config.Randomize) { 'YES' } else { 'NO' })"
        Write-Host ""
        Write-Host "-----------------------------------------------------------------"
        Write-Host "[1] Select / Manage Apps"
        Write-Host "[2] Change App Testing Duration (Min/Max)"
        Write-Host "[3] Change Daily Schedule Time"
        Write-Host "[4] Run Full Test Now (All Selected Apps)"
        Write-Host "[5] Quick Test a Single App (Verify Gestures & Unlocking)"
        Write-Host "[6] Advanced Automation Settings (Gestures, PIN, Sleep, Locks)"
        Write-Host "[7] Toggle Random App Order"
        Write-Host "[8] Install / Update Daily Windows Task Scheduler"
        Write-Host "[9] View Recent Logs"
        Write-Host "[0] Exit"
        Write-Host ""

        $choice = Read-Host "Choose option"

        switch ($choice) {
            "1" { Select-Apps -Config $Config -Device $Device }
            "2" { Change-Delay -Config $Config }
            "3" { Change-Schedule -Config $Config }
            "4" { Run-Apps -Config $Config -Device $Device }
            "5" {
                if ($Config.SelectedApps.Count -eq 0) {
                    Write-Host "No apps selected. Please configure apps first." -ForegroundColor Yellow
                    Pause
                } else {
                    Clear-Host
                    Write-Host "Select an app for single quick test:"
                    for ($i = 0; $i -lt $Config.SelectedApps.Count; $i++) {
                        $p = $Config.SelectedApps[$i]
                        $n = if ($Config.AppCache -and $Config.AppCache.ContainsKey($p)) { $Config.AppCache[$p] } else { $p }
                        Write-Host "[$($i + 1)] $n ($p)"
                    }
                    $subChoice = Read-Host "Enter index"
                    if ($subChoice -match "^\d+$") {
                        $idx = [int]$subChoice - 1
                        if ($idx -ge 0 -and $idx -lt $Config.SelectedApps.Count) {
                            Run-Apps -Config $Config -Device $Device -SinglePackage $Config.SelectedApps[$idx]
                        }
                    }
                }
            }
            "6" { Configure-Advanced-Settings -Config $Config }
            "7" {
                $Config.Randomize = !$Config.Randomize
                Save-Config $Config
                Write-Host "Randomize order: $($Config.Randomize)" -ForegroundColor Green
                Start-Sleep 1
            }
            "8" { Install-Scheduler -Config $Config }
            "9" { View-Logs }
            "0" { Clear-Host; return }
            default {
                Write-Host "Invalid option." -ForegroundColor Red
                Start-Sleep 1
            }
        }
    }
}


# ==============================================================================
# ENTRY POINT
# ==============================================================================

if ($AutoRun -or ($args -contains "-AutoRun")) {
    $Config = Load-Config

    Write-Log "========================================" -Level "INFO"
    Write-Log "Starting Automated Scheduled Beta Test" -Level "INFO"
    Write-Log "========================================" -Level "INFO"

    $Device = Connect-Phone $Config.LastDevice

    if (!$Device) {
        Write-Log "Phone unavailable for scheduled run. Aborting." -Level "ERROR"
        if ($Config.DesktopNotifications) {
            Send-DesktopNotification -Title "PlayKeeper Error" -Message "Scheduled test aborted: Phone unavailable." -IsError
        }
        exit 1
    }

    $Config.LastDevice = $Device
    Save-Config $Config

    # Run without pause
    Run-Apps -Config $Config -Device $Device -IsAutoRun

    exit 0
}

# Start interactive program
Main