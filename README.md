# AutoTester-Android 🚀
### Automated Android Beta Testing for Google Play Console Closed Testing (14 Days / 20 Testers)

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-lightgrey.svg)](https://github.com/WickedG0d/AutoTester-Android)
[![ADB](https://img.shields.io/badge/ADB-Android%20Debug%20Bridge-green.svg)](https://developer.android.com/tools/adb)
[![Requirements](https://img.shields.io/badge/Requirements-Documented-informational.svg)](requirements.md)
[![CI](https://github.com/WickedG0d/AutoTester-Android/actions/workflows/lint.yml/badge.svg)](https://github.com/WickedG0d/AutoTester-Android/actions/workflows/lint.yml)
[![Release](https://img.shields.io/github/v/release/WickedG0d/AutoTester-Android?color=orange)](https://github.com/WickedG0d/AutoTester-Android/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**AutoTester-Android** is a lightweight, zero-dependency cross-platform automation engine designed for Android developers to satisfy Google Play Console's strict **20 testers opted in for 14 continuous days** closed testing requirement.

It runs natively on **Windows** (`BetaTester.ps1`) and **Linux / Raspberry Pi** (`betatester.sh`). It automatically connects to your Android test device over **Wireless ADB** (or USB), wakes and unlocks the phone, launches your beta apps, simulates natural human interactions (scrolling, tapping, navigating), records test metrics, and cleanly locks the device upon completion—every single day via Windows Task Scheduler or Linux Cron.

---

## 🎯 Why AutoTester-Android?

Since November 2023, Google requires personal developer accounts to run closed tests with **at least 20 testers for at least 14 days continuously** before applying for production access. 

Google’s automated review algorithms flag and reject production access requests if:
- Apps are opened for only a few seconds without user activity.
- Daily active engagement is sporadic or non-existent.
- Testers do not interact with app views.

AutoTester-Android solves this by emulating **genuine human engagement** across your suite of test apps on a daily schedule without requiring you to manually open 20+ apps every single day.

---

## ✨ Features

- **🐧 Cross-Platform Native Support:** Dual-engine architecture with **PowerShell** for Windows and native **Bash** for Linux/Raspberry Pi.
- **📶 Wireless ADB Auto-Discovery:** Seamlessly connects and reconnects using mDNS TLS discovery (`adb mdns services`) and previous IP/port caching.
- **👆 Humanized Interaction Emulation:** Rather than leaving apps idle, AutoTester-Android generates natural swipe-down, swipe-up, safe-viewport taps, and in-app back navigation to simulate realistic user engagement.
- **🔓 Automated Wake & Unlock:** Wakes the phone screen, dismisses the keyguard/swipe lock, optionally inputs a PIN or alphanumeric password, and turns the screen back off when testing completes.
- **⏱️ Configurable Test Durations:** Customize minimum and maximum dwell times (recommended: 30–60s) to create randomized, organic testing patterns.
- **🧹 Memory & Thermal Management:** Optional automatic force-stopping (`am force-stop`) after each app session prevents background apps from draining battery or bogging down RAM.
- **🕒 Automated Daily Scheduling:** 
  - **Windows:** 1-click Windows Task Scheduler installation.
  - **Linux:** 1-click `crontab` daily scheduler installation.
- **⚡ Supercharged App Catalog:** Caches app display names locally in `config.json` to deliver an instantaneous interactive CLI experience on both OSes.
- **🔔 Desktop Notifications & Audit Logs:** Logs detailed timestamps, app execution outcomes, and connection health to `betatester.log`, accompanied by native Windows toast or Linux `notify-send` desktop alerts.

---

## 📖 Step-by-Step Setup Guide

Follow this guide to get AutoTester-Android running in under 5 minutes:

### Step 1: Clone the Repository & Install Dependencies
First, clone the project:
```bash
git clone https://github.com/WickedG0d/AutoTester-Android.git
cd AutoTester-Android
```

Install necessary tools using the provided 1-click scripts:

- **On Windows (PowerShell):**
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\install-deps.ps1
  ```
  *(Checks for ADB and installs Google Platform Tools via `winget` if missing.)*

- **On Linux / Raspberry Pi (Ubuntu / Debian / Fedora / Arch):**
  ```bash
  chmod +x install-deps.sh betatester.sh
  ./install-deps.sh
  ```
  *(Installs `adb`, `jq`, `libnotify`, and `cron` via your native package manager.)*

> 📌 *For a complete list of hardware and OS requirements, see [requirements.md](requirements.md).*

---

### Step 2: Prepare Your Android Device
1. Open **Settings > About Phone** on your Android device.
2. Tap **Build Number** 7 times until you see *"You are now a developer!"*.
3. Go to **Settings > System > Developer Options**:
   - Enable **USB Debugging**.
   - Enable **Wireless Debugging** (if testing wirelessly without a USB cable).
   - *(Optional but Recommended)* Enable **Stay Awake** (keeps the screen available while charging).

---

### Step 3: Connect Your Phone to ADB
You can connect using either **USB cable** or **Wireless ADB**:

#### Method A: Wireless Debugging (Recommended)
1. Ensure your PC and Android phone are connected to the **same Wi-Fi network**.
2. On your phone, tap into **Developer Options > Wireless Debugging**.
3. If connecting for the first time:
   - Tap **Pair device with pairing code**.
   - Note the **IP address, port, and 6-digit pairing code** shown on screen.
   - Run in your terminal:
     ```bash
     adb pair <ip>:<pairing-port> <pairing-code>
     ```
4. Once paired, connect to the main Wireless Debugging IP & port displayed on the phone:
   ```bash
   adb connect <ip>:<port>
   ```

#### Method B: USB Cable
Plug the USB cable between your PC and phone. When prompted on your phone screen, check **Always allow from this computer** and tap **Allow**.

Verify connection:
```bash
adb devices
```
*(You should see your device listed with status `device`.)*

---

### Step 4: Launch AutoTester-Android

- **On Windows:**
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\BetaTester.ps1
  ```
- **On Linux / Raspberry Pi:**
  ```bash
  ./betatester.sh
  ```

---

### Step 5: Select Your Beta Test Apps
Once the interactive menu loads:
1. Press **`1`** to enter the **Select / Manage Apps** screen.
2. The script loads all user-installed third-party apps from your phone.
3. You can:
   - Type an app name to search (e.g. `MyGame`).
   - Enter comma-separated numbers (e.g. `1, 3, 5`) to select or toggle apps.
   - Type **`ALL`** to select all user-installed apps.
   - Type **`LIST`** to review your current selection.
   - Type **`DONE`** to save your selection.

---

### Step 6: Configure Duration, Gestures & Lock Screen
1. **Testing Duration (Option `[2]`):**
   - Default is set to **30–60 seconds** per app.
   - *Why?* Google Play Console algorithms flag apps opened for less than 15–20 seconds as automated spam. Realistic session times are required for genuine engagement records.
2. **Advanced Settings (Option `[6]`):**
   - **Simulate Gestures (`ENABLED`):** Generates organic scrolls, safe viewport taps, and back navigation.
   - **Auto-Wake & Unlock (`ENABLED`):** Wakes the phone screen automatically before testing.
   - **Device PIN / Password:** If your phone uses a numeric PIN or password, select option `[5]` in this menu to enter it. AutoTester-Android will type it automatically on wake-up.
   - **Auto-Lock on Finish (`ENABLED`):** Puts the phone screen back to sleep when all apps have completed.

---

### Step 7: Perform a Quick Single-App Test
Before enabling automated runs, verify that your phone wakes up, unlocks, gestures, and closes properly:
1. Press **`5`** on the main menu (**Quick Test a Single App**).
2. Lock your phone screen manually.
3. Select any app from the list.
4. **Observe:** The phone should wake up, unlock, launch the app, perform natural scrolls/taps, return home, and turn off the screen!

---

### Step 8: Install Daily Automated Scheduler
To let AutoTester-Android run unattended every single day:
1. Set your preferred daily testing time via Option **`[3]`** (e.g. `22:00` for 10:00 PM).
2. Select Option **`[8]`** (**Install / Update Daily Scheduler**):
   - **On Windows:** Automatically registers a Windows Scheduled Task (`Android Beta Test Automator`) that wakes and runs daily.
   - **On Linux:** Automatically configures a daily user `crontab` entry.
3. The scheduler will execute in the background headless (`-AutoRun` mode), log all events to `betatester.log`, and send a notification when complete.

---

## 🖥️ Interactive Menu Overview

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
[8] Install / Update Daily Scheduler (Task Scheduler / Cron)
[9] View Recent Logs
[0] Exit
```

---

## ⚙️ Configuration Reference (`config.json`)

Both the Windows and Linux scripts read from and write to the same `config.json`:

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
        "com.example.app1",
        "com.example.app2"
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
| `DesktopNotifications` | `true` | Displays Windows toast or Linux `notify-send` desktop alerts. |
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

To invoke a silent test run manually from scripts or continuous integration:

**Windows:**
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BetaTester.ps1 -AutoRun
```

**Linux:**
```bash
./betatester.sh -AutoRun
```

In `-AutoRun` mode, the engine runs completely headless, executes no blocking pauses, logs all actions to `betatester.log`, and triggers a desktop notification upon completion.

---

## ❓ Frequently Asked Questions (FAQ) & Troubleshooting

<details>
<summary><b>Q: My phone's Wireless ADB port changes every time Wi-Fi reconnects. Does AutoTester-Android handle this?</b></summary>

Yes! AutoTester-Android features built-in **mDNS discovery (`adb mdns services`)**. It actively scans your local network for your phone's ADB TLS service name and connects to the new dynamic port automatically.
</details>

<details>
<summary><b>Q: Can AutoTester-Android bypass fingerprint or face recognition locks?</b></summary>

No. Android security prevents biometric authentication via ADB. However, you can configure a **numeric PIN or alphanumeric password** in Option `[6]`, which AutoTester-Android enters programmatically. Alternatively, set your lock screen to **Swipe** or enable **Stay Awake While Charging**.
</details>

<details>
<summary><b>Q: Why do my scheduled runs need user session on Windows?</b></summary>

ADB daemon communicates via named pipes and TCP sockets created in your Windows user session. The Windows Scheduled Task is configured to run when the user is logged on so ADB has full network and socket access.
</details>

<details>
<summary><b>Q: Where can I see what happened during the nightly test?</b></summary>

Check `betatester.log` in the project directory, or select Option **`[9] View Recent Logs`** directly inside the interactive menu.
</details>

---

## 📜 License

Distributed under the [MIT License](LICENSE). Free for personal and commercial use.
