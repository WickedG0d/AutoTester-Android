# 📦 System & Hardware Requirements

This document outlines all software, hardware, and network requirements for running **AutoTester-Android** on **Windows** and **Linux**.

---

## 🖥️ Operating System Requirements

### 1. Windows
| Component | Minimum Version | Recommended | Purpose |
|---|---|---|---|
| **OS** | Windows 10 (64-bit) | Windows 11 (64-bit) | Host operating system |
| **PowerShell** | PowerShell 5.1 (Built-in) | PowerShell 7.x | Automation scripting engine |
| **ADB** | Android Platform Tools v30+ | Latest release | Communicates with Android devices |
| **Task Scheduler** | Windows Task Scheduler 2.0 | Built-in | Daily automated unattended runs |

### 2. Linux & Raspberry Pi
| Component | Minimum Version | Package Name | Purpose |
|---|---|---|---|
| **OS** | Linux Kernel 4.19+ | Ubuntu 22.04+, Debian 11+, Fedora 38+, Arch, Raspberry Pi OS | Host operating system |
| **Shell** | Bash 4.2+ | `bash` | Automation scripting engine |
| **ADB** | Android Platform Tools v30+ | `android-tools-adb` or `android-tools` | Communicates with Android devices |
| **JSON Parser** | `jq` 1.6+ | `jq` | CLI configuration parser and updater |
| **Notifications** | `notify-send` | `libnotify-bin` or `libnotify` | Desktop pop-up notifications (Optional on headless) |
| **Cron** | Standard Vixie/Dillon Cron | `cron` / `cronie` | Daily automated unattended runs |

---

## 📱 Android Device Requirements

| Requirement | Specification | How to Configure |
|---|---|---|
| **Android OS** | Android 7.0+ (Nougat) | Recommended: **Android 11+** for native Wireless Debugging without USB pairing |
| **Developer Options** | Enabled | *Settings > About Phone* > Tap **Build Number** 7 times |
| **USB Debugging** | Enabled | *Settings > System > Developer Options > USB Debugging* |
| **Wireless Debugging** | Enabled (for untethered testing) | *Settings > System > Developer Options > Wireless Debugging* |
| **Stay Awake While Charging** | Recommended | *Settings > Developer Options > Stay awake* (Keeps device accessible) |
| **Lock Screen** | Swipe, Numeric PIN, or Alphanumeric Password | Supported automatically (Biometrics like fingerprint/face cannot be entered via ADB) |

---

## 🌐 Network Requirements (For Wireless ADB)

- **Local Area Network (LAN):** The host PC and the Android device must be connected to the **same local Wi-Fi network / subnet**.
- **Wi-Fi Isolation (AP Isolation):** Must be **disabled** on your router so local devices can communicate with each other.
- **Port Availability:** Android Wireless Debugging dynamically assigns ports between `30000` and `49999` (or default port `5555`). Ensure local firewall allows outbound traffic to this range.
- **Static DHCP Lease (Recommended):** In your router settings, assign a reserved/static IP to your test phone so its IP address never changes across reboots.

---

## ⚡ 1-Click Automated Dependency Installation

### On Windows (Run in PowerShell as Administrator):
```powershell
powershell -ExecutionPolicy Bypass -File .\install-deps.ps1
```
*Installs Android Platform Tools (`adb`) via Windows Package Manager (`winget`) and configures system PATH.*

### On Linux (Ubuntu / Debian / Fedora / Arch / Raspberry Pi):
```bash
chmod +x install-deps.sh
./install-deps.sh
```
*Detects your distribution's package manager (`apt`, `dnf`, `pacman`, `zypper`) and installs `adb`, `jq`, and `libnotify`.*
