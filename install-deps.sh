#!/usr/bin/env bash
# ==============================================================================
#           AUTOTESTER-ANDROID - LINUX DEPENDENCY INSTALLER
# ==============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}Checking Linux dependencies for AutoTester-Android...${NC}\n"

# Check sudo access if not root
SUDO=""
if [ "$EUID" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo -e "${RED}[ERROR] This installer requires root or sudo privileges.${NC}"
        exit 1
    fi
fi

# Detect Package Manager
if command -v apt-get >/dev/null 2>&1; then
    echo -e "${YELLOW}Detected Debian/Ubuntu/Raspberry Pi OS (apt)...${NC}"
    $SUDO apt-get update
    $SUDO apt-get install -y android-tools-adb jq libnotify-bin cron
elif command -v dnf >/dev/null 2>&1; then
    echo -e "${YELLOW}Detected Fedora/RHEL (dnf)...${NC}"
    $SUDO dnf install -y android-tools jq libnotify cronie
elif command -v pacman >/dev/null 2>&1; then
    echo -e "${YELLOW}Detected Arch Linux (pacman)...${NC}"
    $SUDO pacman -Sy --noconfirm android-tools jq libnotify cronie
elif command -v zypper >/dev/null 2>&1; then
    echo -e "${YELLOW}Detected openSUSE (zypper)...${NC}"
    $SUDO zypper install -y android-tools jq libnotify-tools cron
else
    echo -e "${RED}[ERROR] Unsupported package manager. Please install 'adb', 'jq', and 'libnotify' manually.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}[SUCCESS] All Linux dependencies installed successfully!${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo ""
echo "Verify ADB installation:"
adb version
echo ""
echo "You can now run:"
echo "  ./betatester.sh"
