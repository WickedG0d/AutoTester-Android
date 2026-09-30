# AutoTester-Android 🚀
### Automated Android Beta Testing for Google Play Console Closed Testing (14 Days / 20 Testers)

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)](https://microsoft.com/windows)
[![ADB](https://img.shields.io/badge/ADB-Android%20Debug%20Bridge-green.svg)](https://developer.android.com/tools/adb)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**AutoTester-Android** is a lightweight, zero-dependency automation engine designed for Android developers to satisfy Google Play Console's strict **20 testers opted in for 14 continuous days** closed testing requirement.

It automatically connects to your Android test device over **Wireless ADB** (or USB), wakes and unlocks the phone, launches your beta apps, simulates natural human interactions (scrolling, tapping, navigating), records test metrics, and cleanly locks the device upon completion—every single day via Windows Task Scheduler.

---

## 🎯 Why AutoTester-Android?

Since November 2023, Google requires personal developer accounts to run closed tests with **at least 20 testers for at least 14 days continuously** before applying for production access. 

Google’s automated review algorithms flag and reject production access requests if:
- Apps are opened for only a few seconds without user activity.
- Daily active engagement is sporadic or non-existent.
- Testers do not interact with app views.

AutoTester-Android solves this by emulating **genuine human engagement** across your suite of test apps on a daily schedule without requiring you to manually open 20+ apps every day.

---

## ✨ Features

- **📶 Wireless ADB Auto-Discovery:** Seamlessly connects and reconnects using mDNS TLS discovery (`adb mdns services`) and previous IP/port caching.
- **👆 Humanized Interaction Emulation:** Rather than leaving apps idle, AutoTester-Android generates natural swipe-down, swipe-up, safe-viewport taps, and in-app back navigation to simulate realistic user engagement.
- **🔓 Automated Wake & Unlock:** Wakes the phone screen, dismisses the keyguard/swipe lock, optionally inputs a PIN, and turns the screen back off when testing completes.
- **⏱️ Configurable Test Durations:** Customize minimum and maximum dwell times (recommended: 30–60s) to create randomized, organic testing patterns.
- **🧹 Memory & Thermal Management:** Optional automatic force-stopping (`am force-stop`) after each app session prevents background apps from draining battery or bogging down RAM.
- **🕒 Windows Task Scheduler Integration:** Installs a self-healing daily task with a single click. Runs seamlessly in the background with no blocking prompts or hanging processes.
- **⚡ Supercharged App Catalog:** Caches app display names locally to deliver an instantaneous interactive CLI experience.
- **🔔 Desktop Notifications & Audit Logs:** Logs detailed timestamps, app execution outcomes, and connection health to `betatester.log`, accompanied by Windows toast/balloon notifications.

---

## 📋 Prerequisites

1. **Android Device (Android 11+ recommended for Wireless Debugging):**
   - Enable **Developer Options** (Tap *Build Number* 7 times in *Settings > About Phone*).
   - Enable **USB Debugging**.
   - Enable **Wireless Debugging** (if running untethered).
2. **Android Platform Tools (ADB):**
   - Download the official [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools).
   - Add the folder containing `adb.exe` to your Windows System `PATH`.
   - Verify by running `adb version` in PowerShell.
3. **Windows 10 / 11** with PowerShell 5.1 or PowerShell 7+.

---

## 🚀 Quick Start

### 1. Clone the Repository
```powershell
git clone https://github.com/<your-username>/AutoTester-Android.git
cd AutoTester-Android
```

### 2. Connect Your Device via Wireless ADB
1. On your phone, go to **Settings > Developer Options > Wireless Debugging**.
2. If pairing for the first time:
   - Tap **Pair device with pairing code**.
   - Run in your terminal:
     ```powershell
     adb pair <ip>:<port> <pairing-code>
     ```
3. Once paired, connect to the endpoint:
   ```powershell
   adb connect <ip>:<port>
   ```

### 3. Launch AutoTester-Android
Run the script interactively:
```powershell
powershell -ExecutionPolicy Bypass -File .\BetaTester.ps1
```

### 4. Interactive Menu Overview
```text
=================================================================
   AUTOTESTER-ANDROID - BETA TEST AUTOMATOR
=================================================================

Connected Device : 192.168.1.50:39841
Selected Apps    : 25
Session Duration : 30-60s per app
Daily Schedule   : 22:00
Simulate Gestures: YES
Random Order     : YES
-----------------------------------------------------------------
[1] Select / Manage Apps
[2] Change App Testing Duration (Min/Max)
[3] Change Daily Schedule Time
[4] Run Full Test Now (All Selected Apps)
[5] Quick Test a Single App (Verify Gestures & Unlocking)
[6] Advanced Automation Settings (Gestures, PIN, Sleep, Locks)
[7] Toggle Random App Order
[8] Install / Update Daily Windows Task Scheduler
[9] View Recent Logs
[0] Exit
```

- **Option [1]:** Search, select, and filter your installed beta test apps.
- **Option [4]:** Run a manual verification test across all selected apps.
- **Option [5]:** Quick-test a single app to verify gestures and unlock behavior.
- **Option [8]:** Register the automated daily Windows Scheduled Task.

---

## ⚙️ Configuration (`config.json`)

Configuration settings are stored in `config.json`. You can modify them through the interactive CLI or directly edit the file:

```json
{
    "MinDelay": 30,
    "MaxDelay": 60,
    "Schedule": "22:00",
    "Randomize": true,
    "SimulateGestures": true,
    "ForceStopAfter": true,
    "AutoWakeAndUnlock": true,
    "AutoLockOnFinish": true,
    "DevicePin": "",
    "DesktopNotifications": true,
    "LastDevice": "192.168.1.50:39841",
    "SelectedApps": [
        "com.example.myapp1",
        "com.example.myapp2"
    ],
    "AppCache": {}
}
```

| Key | Default | Description |
|---|---|---|
| `MinDelay` | `30` | Minimum test session duration per app (seconds). |
| `MaxDelay` | `60` | Maximum test session duration per app (seconds). |
| `Schedule` | `"22:00"` | Daily execution time (24-hour format `HH:mm`). |
| `Randomize` | `true` | Shuffles app launch order every run to prevent repetitive patterns. |
| `SimulateGestures` | `true` | Generates natural scrolls, safe taps, and navigation events. |
| `ForceStopAfter` | `true` | Calls `am force-stop` on each app after testing to prevent memory exhaustion. |
| `AutoWakeAndUnlock`| `true` | Wakes the screen and dismisses keyguard automatically. |
| `AutoLockOnFinish` | `true` | Puts the screen back to sleep when all apps have finished testing. |
| `DevicePin` | `""` | Optional lock screen PIN or alphanumeric password if your device uses a lock. |
| `DesktopNotifications` | `true` | Displays Windows toast/balloon notifications when runs start/complete. |
| `SelectedApps` | `[]` | List of package identifiers targeted for testing. |

---

## 💡 Best Practices for Passing Google Play Closed Testing

1. **Test Continuously for at Least 14 Full Days:** Do not pause or stop testing before the full 14-day window completes on Google Play Console.
2. **Realistic Session Length:** Set `MinDelay` and `MaxDelay` to at least 30–90 seconds per app. Google flags instant open-and-close sequences.
3. **Tester Opt-in Confirmation:** Ensure all 20+ tester Google accounts have accepted the web/Play Store invite link and have the app installed.
4. **Gather Play Store Feedback:** Encourage your test group to submit at least 1–2 pieces of in-app feedback via the Play Store tester feedback box.
5. **Static IP / DHCP Reservation:** In your Wi-Fi router settings, reserve a static IP for your Android test phone so Wireless Debugging reconnects effortlessly.

---

## 🛠️ Headless / Automated Execution

To invoke a silent test run manually from scripts or third-party schedulers:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BetaTester.ps1 -AutoRun
```

In `-AutoRun` mode, the script runs completely headless, executes no blocking pauses, logs all actions to `betatester.log`, and triggers a Windows notification upon completion.

---

## 📜 License

Distributed under the [MIT License](LICENSE). Free for personal and commercial use.
