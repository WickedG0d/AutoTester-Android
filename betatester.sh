#!/usr/bin/env bash
# ==============================================================================
#                  AUTOTESTER-ANDROID / BETA TEST AUTOMATOR
#       Automated Continuous Testing for Google Play 14-Day / 20-Tester Requirements
#                         ADB Wireless + Linux Cron Scheduler
# ==============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
LOG_FILE="$SCRIPT_DIR/betatester.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# ==============================================================================
# PREREQUISITE CHECK
# ==============================================================================

check_prerequisites() {
    local missing=()
    if ! command -v adb >/dev/null 2>&1; then
        missing+=("adb (Android Platform Tools)")
    fi
    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq (Command-line JSON processor)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}[ERROR] Missing required dependencies:${NC}"
        for item in "${missing[@]}"; do
            echo -e "  - $item"
        done
        echo ""
        echo "Please install missing packages using your package manager:"
        echo "  Ubuntu/Debian: sudo apt update && sudo apt install -y android-tools-adb jq libnotify-bin"
        echo "  Fedora:        sudo dnf install -y android-tools jq libnotify"
        echo "  Arch Linux:    sudo pacman -S android-tools jq libnotify"
        echo ""
        exit 1
    fi
}

# ==============================================================================
# LOGGING & NOTIFICATIONS
# ==============================================================================

write_log() {
    local level="$1"
    local message="$2"
    local no_console="${3:-false}"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_line="[$timestamp] [$level] $message"

    echo "$log_line" >> "$LOG_FILE" 2>/dev/null || true

    if [ "$no_console" = "false" ]; then
        case "$level" in
            "WARN")    echo -e "${YELLOW}[$timestamp] $message${NC}" ;;
            "ERROR")   echo -e "${RED}[$timestamp] $message${NC}" ;;
            "SUCCESS") echo -e "${GREEN}[$timestamp] $message${NC}" ;;
            *)         echo -e "[$timestamp] $message" ;;
        esac
    fi
}

send_desktop_notification() {
    local title="$1"
    local message="$2"
    local is_error="${3:-false}"

    if command -v notify-send >/dev/null 2>&1; then
        local urgency="normal"
        if [ "$is_error" = "true" ]; then
            urgency="critical"
        fi
        notify-send -u "$urgency" -a "AutoTester-Android" "$title" "$message" 2>/dev/null || true
    fi
}

# ==============================================================================
# CONFIGURATION MANAGEMENT (jq)
# ==============================================================================

init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat <<'EOF' > "$CONFIG_FILE"
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
    "LastDevice": "",
    "SelectedApps": [],
    "AppCache": {}
}
EOF
    fi

    # Ensure required keys exist
    local tmp
    tmp=$(jq '. | 
        .MinDelay //= 30 |
        .MaxDelay //= 60 |
        .Schedule //= "22:00" |
        .Randomize //= true |
        .SimulateGestures //= true |
        .ForceStopAfter //= true |
        .AutoWakeAndUnlock //= true |
        .AutoLockOnFinish //= true |
        .DevicePin //= "" |
        .DesktopNotifications //= true |
        .LastDevice //= (.Device // "") |
        .SelectedApps //= [] |
        .AppCache //= {}
    ' "$CONFIG_FILE" 2>/dev/null)
    
    if [ -n "$tmp" ]; then
        echo "$tmp" > "$CONFIG_FILE"
    fi
}

get_config_val() {
    local key="$1"
    jq -r ".$key" "$CONFIG_FILE" 2>/dev/null
}

set_config_val() {
    local key="$1"
    local raw_val="$2"
    local is_json="${3:-false}"

    local tmp
    if [ "$is_json" = "true" ]; then
        tmp=$(jq --argjson v "$raw_val" ".$key = \$v" "$CONFIG_FILE" 2>/dev/null)
    else
        tmp=$(jq --arg v "$raw_val" ".$key = \$v" "$CONFIG_FILE" 2>/dev/null)
    fi

    if [ -n "$tmp" ]; then
        echo "$tmp" > "$CONFIG_FILE"
    fi
}

# ==============================================================================
# ADB DEVICE FUNCTIONS
# ==============================================================================

get_adb_devices() {
    adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}'
}

test_adb_device() {
    local dev="$1"
    [ -z "$dev" ] && return 1
    local list
    list=$(get_adb_devices)
    echo "$list" | grep -qx "$dev"
}

get_phone_ip() {
    local dev="$1"
    if [[ "$dev" =~ ^([^:]+):[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

find_wireless_adb_device() {
    write_log "INFO" "Searching for Wireless Debugging device via mDNS..."
    local mdns_out
    mdns_out=$(adb mdns services 2>/dev/null || true)
    local candidates=()

    while IFS= read -r line; do
        if [[ "$line" =~ ([0-9]{1,3}(\.[0-9]{1,3}){3}):([0-9]+).*adb-tls-connect ]]; then
            candidates+=("${BASH_REMATCH[1]}:${BASH_REMATCH[3]}")
        fi
    done <<< "$mdns_out"

    if [ ${#candidates[@]} -eq 0 ]; then
        write_log "WARN" "No Wireless Debugging devices discovered."
        return 1
    fi

    for endpoint in "${candidates[@]}"; do
        write_log "INFO" "Attempting connection to $endpoint..."
        adb connect "$endpoint" >/dev/null 2>&1 || true
        sleep 2
        if test_adb_device "$endpoint"; then
            write_log "SUCCESS" "Connected to $endpoint successfully."
            echo "$endpoint"
            return 0
        fi
    done

    return 1
}

connect_phone() {
    local saved_dev="$1"
    local devices
    devices=($(get_adb_devices))

    if [ ${#devices[@]} -ge 1 ]; then
        if [ -n "$saved_dev" ] && test_adb_device "$saved_dev"; then
            write_log "SUCCESS" "Device already connected: $saved_dev"
            echo "$saved_dev"
            return 0
        fi
        write_log "SUCCESS" "Phone already connected: ${devices[0]}"
        echo "${devices[0]}"
        return 0
    fi

    local ip
    ip=$(get_phone_ip "$saved_dev")
    if [ -n "$ip" ] && [[ "$saved_dev" =~ :([0-9]+)$ ]]; then
        local port="${BASH_REMATCH[1]}"
        local endpoint="$ip:$port"
        write_log "INFO" "Attempting reconnect to previous address: $endpoint..."
        adb connect "$endpoint" >/dev/null 2>&1 || true
        sleep 2
        if test_adb_device "$endpoint"; then
            write_log "SUCCESS" "Reconnected to $endpoint successfully."
            echo "$endpoint"
            return 0
        fi
    fi

    local found
    found=$(find_wireless_adb_device)
    if [ $? -eq 0 ] && [ -n "$found" ]; then
        echo "$found"
        return 0
    fi

    devices=($(get_adb_devices))
    if [ ${#devices[@]} -gt 0 ]; then
        echo "${devices[0]}"
        return 0
    fi

    write_log "ERROR" "Could not locate or connect to any Android device."
    return 1
}

select_device() {
    local devices
    devices=($(get_adb_devices))

    if [ ${#devices[@]} -eq 0 ]; then
        local found
        found=$(find_wireless_adb_device)
        if [ $? -eq 0 ] && [ -n "$found" ]; then
            echo "$found"
            return 0
        fi
        echo -e "\n${RED}No Android device connected.${NC}"
        return 1
    fi

    if [ ${#devices[@]} -eq 1 ]; then
        echo "${devices[0]}"
        return 0
    fi

    clear
    echo "========================================"
    echo "          SELECT ANDROID DEVICE"
    echo "========================================"
    echo ""
    for i in "${!devices[@]}"; do
        echo "[$((i + 1))] ${devices[i]}"
    done
    echo ""
    read -r -p "Select your phone: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#devices[@]} ]; then
        echo "${devices[$((choice - 1))]}"
        return 0
    fi

    return 1
}

# ==============================================================================
# SCREEN WAKE, UNLOCK & GEOMETRY
# ==============================================================================

get_device_screen_metrics() {
    local dev="$1"
    local width=1080
    local height=2400

    local size_out
    size_out=$(adb -s "$dev" shell wm size 2>/dev/null || true)
    if [[ "$size_out" =~ ([0-9]{3,4})x([0-9]{3,4}) ]]; then
        width="${BASH_REMATCH[1]}"
        height="${BASH_REMATCH[2]}"
    fi

    local safe_min_x=$((width * 15 / 100))
    local safe_max_x=$((width * 85 / 100))
    local safe_min_y=$((height * 22 / 100))
    local safe_max_y=$((height * 78 / 100))
    local scroll_mid_x=$((width * 50 / 100))
    local scroll_top_y=$((height * 35 / 100))
    local scroll_btm_y=$((height * 65 / 100))

    echo "$width $height $safe_min_x $safe_max_x $safe_min_y $safe_max_y $scroll_mid_x $scroll_top_y $scroll_btm_y"
}

wake_and_unlock_device() {
    local dev="$1"
    local pin="$2"

    write_log "INFO" "Waking up device screen..."
    adb -s "$dev" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    sleep 0.6

    adb -s "$dev" shell wm dismiss-keyguard >/dev/null 2>&1 || true
    sleep 0.4

    read -r width height min_x max_x min_y max_y mid_x top_y btm_y <<< "$(get_device_screen_metrics "$dev")"
    adb -s "$dev" shell input swipe "$mid_x" "$btm_y" "$mid_x" "$top_y" 250 >/dev/null 2>&1 || true
    sleep 0.4

    if [ -n "$pin" ]; then
        write_log "INFO" "Inputting device PIN/Password for unlock..."
        # Escape spaces as %s
        local escaped="${pin// /%s}"
        # Escape shell sensitive chars
        escaped=$(printf '%s' "$escaped" | sed -e 's/[][\\\"'\''$&`;()<>|]/\\&/g')
        adb -s "$dev" shell input text "$escaped" >/dev/null 2>&1 || true
        sleep 0.3
        adb -s "$dev" shell input keyevent 66 >/dev/null 2>&1 || true # KEYCODE_ENTER
        sleep 0.6
    fi
}

lock_device() {
    local dev="$1"
    write_log "INFO" "Turning off device screen..."
    adb -s "$dev" shell input keyevent KEYCODE_SLEEP >/dev/null 2>&1 || true
}

# ==============================================================================
# REALISTIC HUMAN GESTURE SIMULATOR
# ==============================================================================

simulate_app_interaction() {
    local dev="$1"
    local duration="$2"
    read -r width height min_x max_x min_y max_y mid_x top_y btm_y <<< "$(get_device_screen_metrics "$dev")"

    local start_time
    start_time=$(date +%s)
    local actions=0

    while true; do
        local now
        now=$(date +%s)
        local elapsed=$((now - start_time))
        if [ "$elapsed" -ge "$duration" ]; then
            break
        fi
        local remaining=$((duration - elapsed))
        if [ "$remaining" -le 2 ]; then
            break
        fi

        local dice=$(( (RANDOM % 10) + 1 ))

        if [ "$dice" -le 4 ]; then
            # Scroll down
            local offset=$(( (RANDOM % 80) - 40 ))
            local start_x=$((mid_x + offset))
            local swipe_ms=$(( (RANDOM % 200) + 250 ))
            adb -s "$dev" shell input swipe "$start_x" "$btm_y" "$start_x" "$top_y" "$swipe_ms" >/dev/null 2>&1 || true
        elif [ "$dice" -le 6 ]; then
            # Scroll up
            local offset=$(( (RANDOM % 80) - 40 ))
            local start_x=$((mid_x + offset))
            local swipe_ms=$(( (RANDOM % 200) + 250 ))
            adb -s "$dev" shell input swipe "$start_x" "$top_y" "$start_x" "$btm_y" "$swipe_ms" >/dev/null 2>&1 || true
        elif [ "$dice" -le 8 ]; then
            # Gentle tap in safe viewport
            local x_range=$((max_x - min_x))
            local y_range=$((max_y - min_y))
            local tap_x=$(( min_x + (RANDOM % x_range) ))
            local tap_y=$(( min_y + (RANDOM % y_range) ))
            adb -s "$dev" shell input tap "$tap_x" "$tap_y" >/dev/null 2>&1 || true
        else
            # Back key navigation
            adb -s "$dev" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
        fi

        actions=$((actions + 1))
        local sleep_sec=$(( (RANDOM % 5) + 3 ))
        sleep "$sleep_sec"
    done

    echo "$actions"
}

# ==============================================================================
# APP CATALOG & CACHING
# ==============================================================================

get_installed_apps() {
    local dev="$1"
    local packages
    packages=$(adb -s "$dev" shell pm list packages -3 2>/dev/null | sed -n 's/^package://p' | sort)

    local cache
    cache=$(jq -r '.AppCache' "$CONFIG_FILE")
    local cache_modified=false

    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        local name
        name=$(echo "$cache" | jq -r --arg p "$pkg" '.[$p] // empty' 2>/dev/null)
        if [ -z "$name" ]; then
            name=$(adb -s "$dev" shell dumpsys package "$pkg" 2>/dev/null | grep -E "application-label(-en)?:" | head -n1 | sed -E 's/.*application-label(-en)?:[ ]*//' || true)
            if [ -z "$name" ]; then
                name="$pkg"
            fi
            cache=$(echo "$cache" | jq --arg p "$pkg" --arg n "$name" '. + {($p): $n}')
            cache_modified=true
        fi
        echo "$pkg	$name"
    done <<< "$packages"

    if [ "$cache_modified" = "true" ]; then
        set_config_val "AppCache" "$cache" true
    fi
}

# ==============================================================================
# APP SELECTION UI
# ==============================================================================

select_apps() {
    local dev="$1"
    clear
    echo "========================================"
    echo "           SELECT BETA APPS"
    echo "========================================"
    echo "Loading third-party apps from device..."

    local raw_apps
    raw_apps=$(get_installed_apps "$dev")

    if [ -z "$raw_apps" ]; then
        echo -e "${RED}No user-installed apps found on $dev.${NC}"
        read -r -p "Press Enter to return..."
        return
    fi

    local pkgs=()
    local names=()
    while IFS=$'\t' read -r p n; do
        [ -z "$p" ] && continue
        pkgs+=("$p")
        names+=("$n")
    done <<< "$raw_apps"

    while true; do
        local selected
        selected=$(jq -r '.SelectedApps[]' "$CONFIG_FILE" 2>/dev/null)
        local sel_count=0
        if [ -n "$selected" ]; then
            sel_count=$(echo "$selected" | wc -l)
        fi

        clear
        echo "========================================"
        echo "           SELECT BETA APPS"
        echo "========================================"
        echo "Installed apps    : ${#pkgs[@]}"
        echo "Currently selected: $sel_count"
        echo "----------------------------------------"
        echo "Commands:"
        echo "  <name>       Search by app name or package"
        echo "  <number>     Toggle selection by index (e.g. 5)"
        echo "  1,3,7        Toggle multiple indices"
        echo "  ALL          Select all installed apps"
        echo "  CLEAR        Clear selection"
        echo "  LIST         Show all selected apps"
        echo "  DONE         Save and finish"
        echo ""

        read -r -p "Enter command or search: " query

        case "${query^^}" in
            "DONE") break ;;
            "CLEAR")
                set_config_val "SelectedApps" "[]" true
                echo -e "${YELLOW}Selection cleared.${NC}"
                sleep 1
                continue
                ;;
            "ALL")
                local all_json
                all_json=$(printf '%s\n' "${pkgs[@]}" | jq -R . | jq -s .)
                set_config_val "SelectedApps" "$all_json" true
                echo -e "${GREEN}All apps selected.${NC}"
                sleep 1
                continue
                ;;
            "LIST")
                clear
                echo "========================================"
                echo "           SELECTED APPS"
                echo "========================================"
                local idx=0
                while IFS= read -r sp; do
                    [ -z "$sp" ] && continue
                    idx=$((idx + 1))
                    local disp="$sp"
                    for j in "${!pkgs[@]}"; do
                        if [ "${pkgs[j]}" = "$sp" ]; then
                            disp="${names[j]}"
                            break
                        fi
                    done
                    echo "[$idx] $disp ($sp)"
                done <<< "$selected"
                echo ""
                read -r -p "Press Enter to return..."
                continue
                ;;
        esac

        # Comma-separated numbers
        if [[ "$query" =~ ^[0-9,[:space:]]+$ ]]; then
            IFS=',' read -ra nums <<< "$query"
            for num in "${nums[@]}"; do
                num=$(echo "$num" | tr -d '[:space:]')
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#pkgs[@]} ]; then
                    local target="${pkgs[$((num - 1))]}"
                    if echo "$selected" | grep -qx "$target"; then
                        local updated
                        updated=$(jq --arg t "$target" '.SelectedApps - [$t]' "$CONFIG_FILE")
                        echo "$updated" > "$CONFIG_FILE"
                    else
                        local updated
                        updated=$(jq --arg t "$target" '.SelectedApps + [$t]' "$CONFIG_FILE")
                        echo "$updated" > "$CONFIG_FILE"
                    fi
                fi
            done
            continue
        fi

        # Search query
        local matches_idx=()
        local q_lower="${query,,}"
        for i in "${!pkgs[@]}"; do
            local p_low="${pkgs[i],,}"
            local n_low="${names[i],,}"
            if [[ "$p_low" == *"$q_lower"* || "$n_low" == *"$q_lower"* ]]; then
                matches_idx+=("$i")
            fi
        done

        clear
        echo "========================================"
        echo "             SEARCH RESULTS"
        echo "========================================"
        echo "Search: $query"
        echo ""

        if [ ${#matches_idx[@]} -eq 0 ]; then
            echo -e "${YELLOW}No matching apps found.${NC}"
            read -r -p "Press Enter to return..."
            continue
        fi

        for k in "${!matches_idx[@]}"; do
            local mi="${matches_idx[k]}"
            local mark="[ ]"
            if echo "$selected" | grep -qx "${pkgs[mi]}"; then
                mark="[*]"
            fi
            printf "[%3d] %s %s\n" "$((k + 1))" "$mark" "${names[mi]}"
            echo -e "      ${GRAY}${pkgs[mi]}${NC}"
        done

        echo ""
        read -r -p "Enter numbers to toggle (e.g. 1, 3) or Enter to return: " sel_num
        if [[ "$sel_num" =~ ^[0-9,[:space:]]+$ ]]; then
            IFS=',' read -ra s_nums <<< "$sel_num"
            for sn in "${s_nums[@]}"; do
                sn=$(echo "$sn" | tr -d '[:space:]')
                if [[ "$sn" =~ ^[0-9]+$ ]] && [ "$sn" -ge 1 ] && [ "$sn" -le ${#matches_idx[@]} ]; then
                    local mi="${matches_idx[$((sn - 1))]}"
                    local target="${pkgs[mi]}"
                    if echo "$selected" | grep -qx "$target"; then
                        local updated
                        updated=$(jq --arg t "$target" '.SelectedApps - [$t]' "$CONFIG_FILE")
                        echo "$updated" > "$CONFIG_FILE"
                    else
                        local updated
                        updated=$(jq --arg t "$target" '.SelectedApps + [$t]' "$CONFIG_FILE")
                        echo "$updated" > "$CONFIG_FILE"
                    fi
                fi
            done
        fi
    done
}

# ==============================================================================
# SETTINGS CONFIGURATORS
# ==============================================================================

change_delay() {
    clear
    echo "========================================"
    echo "         APP TESTING DURATION"
    echo "========================================"
    echo ""
    local cur_min cur_max
    cur_min=$(get_config_val "MinDelay")
    cur_max=$(get_config_val "MaxDelay")
    echo "Current duration: $cur_min - $cur_max seconds"
    echo -e "${YELLOW}TIP: For Google Play 14-day closed testing, 30-90s per app is recommended.${NC}"
    echo ""
    read -r -p "Minimum seconds (e.g. 30): " min_in
    read -r -p "Maximum seconds (e.g. 60): " max_in

    if [[ "$min_in" =~ ^[0-9]+$ ]] && [ "$min_in" -ge 5 ]; then
        set_config_val "MinDelay" "$min_in" true
    fi
    if [[ "$max_in" =~ ^[0-9]+$ ]] && [ "$max_in" -ge "$min_in" ]; then
        set_config_val "MaxDelay" "$max_in" true
    fi
    echo -e "${GREEN}Duration updated successfully.${NC}"
    read -r -p "Press Enter to return..."
}

change_schedule() {
    clear
    echo "========================================"
    echo "             DAILY SCHEDULE"
    echo "========================================"
    echo ""
    echo "Current schedule: $(get_config_val "Schedule")"
    echo ""
    read -r -p "Enter new time (HH:mm, 24-hr format): " time_in
    if [[ "$time_in" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        set_config_val "Schedule" "$time_in"
        echo -e "${GREEN}Daily schedule set to $time_in.${NC}"
        echo -e "${YELLOW}Remember to re-install cron scheduler (Option 8) to apply.${NC}"
    else
        echo -e "${RED}Invalid time format. Please use HH:mm (e.g. 22:00).${NC}"
    fi
    read -r -p "Press Enter to return..."
}

configure_advanced_settings() {
    while true; do
        clear
        echo "========================================"
        echo "       ADVANCED & GOOGLE PLAY SETTINGS"
        echo "========================================"
        echo ""
        echo "[1] Simulate Gestures (Scroll/Tap/Back) : $(get_config_val "SimulateGestures")"
        echo "[2] Force-Stop App After Testing        : $(get_config_val "ForceStopAfter")"
        echo "[3] Auto-Wake and Unlock Screen         : $(get_config_val "AutoWakeAndUnlock")"
        echo "[4] Auto-Lock Screen When Finished      : $(get_config_val "AutoLockOnFinish")"
        local pin_status="NOT SET"
        [ -n "$(get_config_val "DevicePin")" ] && pin_status="SET (****)"
        echo "[5] Device Unlock PIN / Password        : $pin_status"
        echo "[6] Desktop Toast Notifications         : $(get_config_val "DesktopNotifications")"
        echo "[7] Back to Main Menu"
        echo ""

        read -r -p "Choose option: " opt
        case "$opt" in
            "1")
                local cur; cur=$(get_config_val "SimulateGestures")
                [ "$cur" = "true" ] && set_config_val "SimulateGestures" "false" true || set_config_val "SimulateGestures" "true" true
                ;;
            "2")
                local cur; cur=$(get_config_val "ForceStopAfter")
                [ "$cur" = "true" ] && set_config_val "ForceStopAfter" "false" true || set_config_val "ForceStopAfter" "true" true
                ;;
            "3")
                local cur; cur=$(get_config_val "AutoWakeAndUnlock")
                [ "$cur" = "true" ] && set_config_val "AutoWakeAndUnlock" "false" true || set_config_val "AutoWakeAndUnlock" "true" true
                ;;
            "4")
                local cur; cur=$(get_config_val "AutoLockOnFinish")
                [ "$cur" = "true" ] && set_config_val "AutoLockOnFinish" "false" true || set_config_val "AutoLockOnFinish" "true" true
                ;;
            "5")
                read -r -s -p "Enter phone PIN or alphanumeric password (leave empty to clear): " new_pin
                echo ""
                set_config_val "DevicePin" "$new_pin"
                ;;
            "6")
                local cur; cur=$(get_config_val "DesktopNotifications")
                [ "$cur" = "true" ] && set_config_val "DesktopNotifications" "false" true || set_config_val "DesktopNotifications" "true" true
                ;;
            "7") return ;;
        esac
    done
}

# ==============================================================================
# CORE EXECUTION ENGINE
# ==============================================================================

run_apps() {
    local dev="$1"
    local is_autorun="${2:-false}"
    local single_pkg="${3:-}"

    local run_start
    run_start=$(date +%s)

    if [ -z "$dev" ]; then
        write_log "ERROR" "Execution halted: No ADB device provided."
        [ "$is_autorun" = "false" ] && read -r -p "Press Enter to return..."
        return 1
    fi

    if ! test_adb_device "$dev"; then
        write_log "WARN" "ADB connection lost for $dev. Attempting reconnect..."
        dev=$(connect_phone "$dev")
        if [ $? -ne 0 ] || [ -z "$dev" ]; then
            write_log "ERROR" "Failed to reconnect to Android device. Aborting run."
            send_desktop_notification "AutoTester-Android Failed" "Device disconnected and could not reconnect." true
            [ "$is_autorun" = "false" ] && read -r -p "Press Enter to return..."
            return 1
        fi
    fi

    set_config_val "LastDevice" "$dev"

    local app_list=()
    if [ -n "$single_pkg" ]; then
        app_list=("$single_pkg")
    else
        while IFS= read -r line; do
            [ -n "$line" ] && app_list+=("$line")
        done < <(jq -r '.SelectedApps[]' "$CONFIG_FILE" 2>/dev/null)

        if [ ${#app_list[@]} -eq 0 ]; then
            write_log "WARN" "No apps configured for testing."
            [ "$is_autorun" = "false" ] && read -r -p "Press Enter to return..."
            return 0
        fi

        if [ "$(get_config_val "Randomize")" = "true" ]; then
            # Shuffle array
            app_list=($(printf "%s\n" "${app_list[@]}" | shuf))
        fi
    fi

    # Wake and unlock
    if [ "$(get_config_val "AutoWakeAndUnlock")" = "true" ]; then
        local pin
        pin=$(get_config_val "DevicePin")
        wake_and_unlock_device "$dev" "$pin"
    fi

    write_log "INFO" "Starting Beta Test Run on $dev (${#app_list[@]} apps)..."

    local counter=0
    local successful=0
    local failed=0
    local min_delay max_delay
    min_delay=$(get_config_val "MinDelay")
    max_delay=$(get_config_val "MaxDelay")
    local simulate_gestures force_stop
    simulate_gestures=$(get_config_val "SimulateGestures")
    force_stop=$(get_config_val "ForceStopAfter")

    for pkg in "${app_list[@]}"; do
        counter=$((counter + 1))

        if ! test_adb_device "$dev"; then
            write_log "WARN" "ADB connection lost mid-run. Reconnecting..."
            local new_dev
            new_dev=$(connect_phone "$dev")
            if [ -n "$new_dev" ]; then
                dev="$new_dev"
                set_config_val "LastDevice" "$dev"
            else
                write_log "ERROR" "Device disconnected mid-run. Aborting."
                failed=$((failed + ${#app_list[@]} - counter + 1))
                break
            fi
        fi

        local app_name
        app_name=$(jq -r --arg p "$pkg" '.AppCache[$p] // $p' "$CONFIG_FILE" 2>/dev/null)
        write_log "INFO" "[$counter/${#app_list[@]}] Launching $app_name ($pkg)..."

        local launch_out
        launch_out=$(adb -s "$dev" shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 2>&1 || true)
        if [[ "$launch_out" == *"No activities found"* || "$launch_out" == *"monkey aborted"* ]]; then
            write_log "WARN" "Failed to launch $pkg. Check if app is installed."
            failed=$((failed + 1))
            continue
        fi

        local delay_range=$((max_delay - min_delay + 1))
        local duration=$(( min_delay + (RANDOM % delay_range) ))

        if [ "$simulate_gestures" = "true" ]; then
            write_log "INFO" "Interacting with $app_name for $duration seconds (humanized gestures)..."
            local gestures
            gestures=$(simulate_app_interaction "$dev" "$duration")
            write_log "INFO" "Completed $gestures simulated interaction gestures."
        else
            write_log "INFO" "Keeping $app_name in foreground for $duration seconds..."
            sleep "$duration"
        fi

        adb -s "$dev" shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
        sleep 1

        if [ "$force_stop" = "true" ]; then
            adb -s "$dev" shell am force-stop "$pkg" >/dev/null 2>&1 || true
        fi

        successful=$((successful + 1))
        sleep 1
    done

    if [ "$(get_config_val "AutoLockOnFinish")" = "true" ]; then
        lock_device "$dev"
    fi

    local run_end
    run_end=$(date +%s)
    local elapsed_min
    elapsed_min=$(awk "BEGIN {printf \"%.1f\", ($run_end - $run_start)/60}")

    local summary="Tested $successful/${#app_list[@]} apps successfully in ${elapsed_min} mins."
    write_log "SUCCESS" "Run Complete: $summary"

    if [ "$(get_config_val "DesktopNotifications")" = "true" ]; then
        send_desktop_notification "AutoTester-Android Complete" "$summary" false
    fi

    if [ "$is_autorun" = "false" ]; then
        echo ""
        echo "========================================"
        echo "             RUN COMPLETE"
        echo "========================================"
        echo -e "${GREEN}$summary${NC}"
        echo ""
        read -r -p "Press Enter to return..."
    fi
}

# ==============================================================================
# LINUX CRON SCHEDULER
# ==============================================================================

install_scheduler() {
    clear
    echo "========================================"
    echo "         LINUX CRON SCHEDULER"
    echo "========================================"
    echo ""

    local sched
    sched=$(get_config_val "Schedule")
    local hour="${sched%%:*}"
    local minute="${sched##*:}"
    # Remove leading zeros for cron
    hour=$((10#$hour))
    minute=$((10#$minute))

    local script_path="$SCRIPT_DIR/betatester.sh"
    local cron_cmd="$minute $hour * * * /usr/bin/env bash \"$script_path\" -AutoRun >/dev/null 2>&1"
    local cron_comment="# AutoTester-Android Daily Run"

    # Read current crontab
    local cur_cron
    cur_cron=$(crontab -l 2>/dev/null | grep -v "AutoTester-Android" || true)

    # Install updated crontab
    printf "%s\n%s\n%s\n" "$cur_cron" "$cron_comment" "$cron_cmd" | sed '/^$/d' | crontab -

    write_log "SUCCESS" "Cron job installed for daily execution at $sched ($hour:$minute)."

    echo -e "${GREEN}Cron job installed successfully!${NC}"
    echo "Schedule : Every day at $sched ($hour:$minute)"
    echo "Command  : $cron_cmd"
    echo ""
    echo "To view your active cron jobs: crontab -l"
    echo "To edit or remove manually   : crontab -e"
    echo ""
    read -r -p "Press Enter to return..."
}

# ==============================================================================
# LOG VIEWER
# ==============================================================================

view_logs() {
    clear
    echo "========================================"
    echo "           RECENT LOG ENTRIES"
    echo "========================================"
    echo ""
    if [ -f "$LOG_FILE" ]; then
        tail -n 25 "$LOG_FILE"
    else
        echo -e "${YELLOW}No log file found at $LOG_FILE.${NC}"
    fi
    echo ""
    read -r -p "Press Enter to return..."
}

# ==============================================================================
# MAIN MENU
# ==============================================================================

main() {
    init_config

    while true; do
        local dev
        dev=$(select_device)
        if [ $? -ne 0 ] || [ -z "$dev" ]; then
            echo -e "${RED}No Android device found.${NC}"
            echo "Please ensure USB or Wireless Debugging is enabled on your phone."
            echo ""
            read -r -p "Press Enter to retry or Ctrl+C to exit..."
            continue
        fi

        set_config_val "LastDevice" "$dev"

        clear
        echo "================================================================="
        echo "   AUTOTESTER-ANDROID - BETA TEST AUTOMATOR (LINUX)"
        echo "================================================================="
        echo ""
        echo -e "Connected Device : ${GREEN}$dev${NC}"
        local sel_count
        sel_count=$(jq -r '.SelectedApps | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
        echo "Selected Apps    : $sel_count"
        echo "Session Duration : $(get_config_val "MinDelay")-$(get_config_val "MaxDelay")s per app"
        echo "Daily Schedule   : $(get_config_val "Schedule")"
        echo "Simulate Gestures: $(get_config_val "SimulateGestures")"
        echo "Random Order     : $(get_config_val "Randomize")"
        echo ""
        echo "-----------------------------------------------------------------"
        echo "[1] Select / Manage Apps"
        echo "[2] Change App Testing Duration (Min/Max)"
        echo "[3] Change Daily Schedule Time"
        echo "[4] Run Full Test Now (All Selected Apps)"
        echo "[5] Quick Test a Single App (Verify Gestures & Unlocking)"
        echo "[6] Advanced Automation Settings (Gestures, PIN, Sleep, Locks)"
        echo "[7] Toggle Random App Order"
        echo "[8] Install / Update Daily Cron Scheduler"
        echo "[9] View Recent Logs"
        echo "[0] Exit"
        echo ""

        read -r -p "Choose option: " choice

        case "$choice" in
            "1") select_apps "$dev" ;;
            "2") change_delay ;;
            "3") change_schedule ;;
            "4") run_apps "$dev" false ;;
            "5")
                local pkgs
                pkgs=($(jq -r '.SelectedApps[]' "$CONFIG_FILE" 2>/dev/null))
                if [ ${#pkgs[@]} -eq 0 ]; then
                    echo -e "${YELLOW}No apps selected. Please configure apps first.${NC}"
                    read -r -p "Press Enter to return..."
                else
                    clear
                    echo "Select an app for single quick test:"
                    for i in "${!pkgs[@]}"; do
                        local p="${pkgs[i]}"
                        local n
                        n=$(jq -r --arg p "$p" '.AppCache[$p] // $p' "$CONFIG_FILE" 2>/dev/null)
                        echo "[$((i + 1))] $n ($p)"
                    done
                    read -r -p "Enter index: " sidx
                    if [[ "$sidx" =~ ^[0-9]+$ ]] && [ "$sidx" -ge 1 ] && [ "$sidx" -le ${#pkgs[@]} ]; then
                        run_apps "$dev" false "${pkgs[$((sidx - 1))]}"
                    fi
                fi
                ;;
            "6") configure_advanced_settings ;;
            "7")
                local cur; cur=$(get_config_val "Randomize")
                [ "$cur" = "true" ] && set_config_val "Randomize" "false" true || set_config_val "Randomize" "true" true
                echo "Randomize order: $(get_config_val "Randomize")"
                sleep 1
                ;;
            "8") install_scheduler ;;
            "9") view_logs ;;
            "0") clear; exit 0 ;;
            *)
                echo -e "${RED}Invalid option.${NC}"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

check_prerequisites

if [[ "${1:-}" == "-AutoRun" || "${1:-}" == "--autorun" ]]; then
    init_config
    write_log "INFO" "========================================"
    write_log "INFO" "Starting Automated Scheduled Beta Test (Linux Cron)"
    write_log "INFO" "========================================"

    last_dev=$(get_config_val "LastDevice")
    dev=$(connect_phone "$last_dev")
    if [ $? -ne 0 ] || [ -z "$dev" ]; then
        write_log "ERROR" "Phone unavailable for scheduled run. Aborting."
        send_desktop_notification "AutoTester-Android Error" "Scheduled test aborted: Phone unavailable." true
        exit 1
    fi

    set_config_val "LastDevice" "$dev"
    run_apps "$dev" true
    exit 0
fi

main
