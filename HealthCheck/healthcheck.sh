#!/usr/bin/env bash
# ==============================================================================
# PortOfMorrow Desktop System Health Check Utility
# Master Script: Projects/BinScrpts/HealthCheck/healthcheck.sh
# User Command:  healthcheck (via ~/.local/bin/healthcheck)
# Role: Real-time desktop telemetry, GPU compute, thermals, NVMe/BTRFS storage integrity,
#       network mesh & local AI/container service audit.
# ==============================================================================

set -u

# Load machine-specific settings from the repo-root .env (resolved through symlinks)
_ENV_FILE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.env"
if [ -f "$_ENV_FILE" ]; then set -a; . "$_ENV_FILE"; set +a; fi

# --- Color Scheme & Formatting ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

STATUS_OVERALL="OK"
declare -a WARNINGS=()
declare -a CRITICALS=()

print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"
}

print_ok() {
    echo -e "  ${GREEN}[+]${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}[!]${NC} $1"
    WARNINGS+=("$1")
    [ "$STATUS_OVERALL" != "CRIT" ] && STATUS_OVERALL="WARN"
}

print_crit() {
    echo -e "  ${RED}[-]${NC} $1"
    CRITICALS+=("$1")
    STATUS_OVERALL="CRIT"
}

print_info() {
    echo -e "  ${CYAN}[*]${NC} $1"
}

show_help() {
    cat << EOF
Usage: healthcheck [OPTIONS]

PortOfMorrow Desktop System Health Check Utility

Options:
  -q, --quick     Output a condensed single-line health summary.
  -h, --help      Display this help message and exit.

EOF
    exit 0
}

# --- Parse Arguments ---
MODE="full"
if [ $# -gt 0 ]; then
    case "$1" in
        -q|--quick)
            MODE="quick"
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Run 'healthcheck --help' for usage."
            exit 1
            ;;
    esac
fi

# --- 1. Host & Compute ---
HOST=$(hostname)
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'( |,|:)+' '{if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0"d "h+0"h "m+0"m"}')
LOAD=$(awk '{print $1", "$2", "$3}' /proc/loadavg)
CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name:" | sed 's/Model name:[ \t]*//' | head -n1)
[ -z "$CPU_MODEL" ] && CPU_MODEL="AMD Ryzen Processor"
CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)

if [ "$MODE" = "full" ]; then
    print_header "HOST & COMPUTE"
    print_info "Host: ${BOLD}${HOST}${NC} | Kernel: ${KERNEL}"
    print_info "CPU: ${CPU_MODEL} (${CPU_CORES} Threads)"
    print_info "Uptime: ${UPTIME} | Load Average (1m, 5m, 15m): ${LOAD}"
fi

# --- 2. Memory & Swap ---
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
MEM_AVAIL=$(free -m | awk '/Mem:/ {print $7}')
SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')

MEM_PCT=0
if [ "$MEM_TOTAL" -gt 0 ]; then
    MEM_PCT=$(( 100 * MEM_USED / MEM_TOTAL ))
fi

if [ "$MEM_PCT" -gt 90 ]; then
    print_crit "RAM Usage Critical: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}% used, Available: ${MEM_AVAIL}MB)"
elif [ "$MEM_PCT" -gt 80 ]; then
    print_warn "RAM Usage High: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}% used, Available: ${MEM_AVAIL}MB)"
elif [ "$MODE" = "full" ]; then
    print_header "MEMORY & SWAP"
    print_ok "RAM Usage: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}% used, Available: ${MEM_AVAIL}MB)"
    if [ "$SWAP_TOTAL" -gt 0 ]; then
        SWAP_PCT=$(( 100 * SWAP_USED / SWAP_TOTAL ))
        if [ "$SWAP_PCT" -gt 80 ]; then
            print_warn "Swap Usage High: ${SWAP_USED}MB / ${SWAP_TOTAL}MB (${SWAP_PCT}% used)"
        else
            print_info "Swap Usage: ${SWAP_USED}MB / ${SWAP_TOTAL}MB (${SWAP_PCT}% used)"
        fi
    fi
fi

# --- 3. GPU & Compute (ROCm / AMDGPU) ---
GPU_SUMMARY="dGPU: Active"
if command -v rocm-smi >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    ROCM_DATA=$(rocm-smi --showtemp --showuse --showpower --showmeminfo vram --json 2>/dev/null || true)
    if [ -n "$ROCM_DATA" ]; then
        if [ "$MODE" = "full" ]; then
            print_header "GPU COMPUTE & VRAM (ROCm)"
        fi

        CARD_KEYS=$(echo "$ROCM_DATA" | jq -r 'keys[]' 2>/dev/null || true)
        CARD_IDX=0
        for card in $CARD_KEYS; do
            EDGE_T=$(echo "$ROCM_DATA" | jq -r ".[\"$card\"][\"Temperature (Sensor edge) (C)\"] // \"N/A\"")
            JUNC_T=$(echo "$ROCM_DATA" | jq -r ".[\"$card\"][\"Temperature (Sensor junction) (C)\"] // \"N/A\"")
            MEM_T=$(echo "$ROCM_DATA" | jq -r ".[\"$card\"][\"Temperature (Sensor memory) (C)\"] // \"N/A\"")
            PWR_W=$(echo "$ROCM_DATA" | jq -r ".[\"$card\"][\"Average Graphics Package Power (W)\"] // .[\"$card\"][\"Current Socket Graphics Package Power (W)\"] // \"N/A\"")
            GPU_USE=$(echo "$ROCM_DATA" | jq -r ".[\"$card\"][\"GPU use (%)\"] // \"0\"")
            VRAM_USED_B=$(echo "$ROCM_DATA" | jq -r ".[\"$card\"][\"VRAM Total Used Memory (B)\"] // \"0\"")
            VRAM_TOTAL_B=$(echo "$ROCM_DATA" | jq -r ".[\"$card\"][\"VRAM Total Memory (B)\"] // \"0\"")

            VRAM_USED_MB=$(( VRAM_USED_B / 1048576 ))
            VRAM_TOTAL_MB=$(( VRAM_TOTAL_B / 1048576 ))
            VRAM_PCT=0
            if [ "$VRAM_TOTAL_MB" -gt 0 ]; then
                VRAM_PCT=$(( 100 * VRAM_USED_MB / VRAM_TOTAL_MB ))
            fi

            CARD_NAME="GPU $CARD_IDX"
            if [ "$CARD_IDX" -eq 0 ]; then
                CARD_NAME="AMD Radeon RX 9070 Series (Discrete)"
                GPU_SUMMARY="dGPU: ${EDGE_T}°C (${VRAM_USED_MB}MB/${VRAM_TOTAL_MB}MB)"
            elif [ "$CARD_IDX" -eq 1 ]; then
                CARD_NAME="AMD Radeon Graphics (Ryzen 9 9900X iGPU)"
            fi

            # Thresholds
            EDGE_INT=${EDGE_T%.*}
            if [ "$EDGE_INT" != "N/A" ] && [ "$EDGE_INT" -gt 90 ] 2>/dev/null; then
                print_crit "$CARD_NAME Edge Temp Critical: ${EDGE_T}°C"
            elif [ "$EDGE_INT" != "N/A" ] && [ "$EDGE_INT" -gt 80 ] 2>/dev/null; then
                print_warn "$CARD_NAME Edge Temp High: ${EDGE_T}°C"
            fi

            JUNC_INT=${JUNC_T%.*}
            if [ "$JUNC_INT" != "N/A" ] && [ "$JUNC_INT" -gt 105 ] 2>/dev/null; then
                print_crit "$CARD_NAME Junction Temp Critical: ${JUNC_T}°C"
            elif [ "$JUNC_INT" != "N/A" ] && [ "$JUNC_INT" -gt 95 ] 2>/dev/null; then
                print_warn "$CARD_NAME Junction Temp High: ${JUNC_T}°C"
            fi

            if [ "$VRAM_PCT" -gt 95 ]; then
                print_warn "$CARD_NAME VRAM Near Full: ${VRAM_USED_MB}MB / ${VRAM_TOTAL_MB}MB (${VRAM_PCT}%)"
            fi

            if [ "$MODE" = "full" ]; then
                TEMP_STR="Edge: ${EDGE_T}°C"
                [ "$JUNC_T" != "N/A" ] && TEMP_STR="${TEMP_STR} | Junction: ${JUNC_T}°C"
                [ "$MEM_T" != "N/A" ] && TEMP_STR="${TEMP_STR} | Mem: ${MEM_T}°C"
                
                print_ok "${BOLD}${CARD_NAME}${NC}"
                print_info "  Thermals: ${TEMP_STR} | Power: ${PWR_W}W"
                print_info "  Activity: Load: ${GPU_USE}% | VRAM: ${VRAM_USED_MB}MB / ${VRAM_TOTAL_MB}MB (${VRAM_PCT}% used)"
            fi
            CARD_IDX=$(( CARD_IDX + 1 ))
        done
    fi
fi

# --- 4. Hardware Thermals ---
if [ "$MODE" = "full" ]; then
    print_header "HARDWARE THERMAL SENSORS"
fi

for i in /sys/class/hwmon/hwmon*/temp*_input; do
    [ -f "$i" ] || continue
    hwmon_dir=$(dirname "$i")
    hwmon_name=$(cat "$hwmon_dir/name" 2>/dev/null || echo "hwmon")
    label_file="${i%_input}_label"
    if [ -f "$label_file" ]; then
        label=$(cat "$label_file" 2>/dev/null)
    else
        label=$(basename "$i")
    fi

    temp_raw=$(cat "$i" 2>/dev/null || echo "0")
    temp_c=$(awk "BEGIN {printf \"%.1f\", $temp_raw / 1000}")
    temp_int=${temp_c%.*}

    case "$hwmon_name" in
        k10temp)
            if [ "$label" = "Tctl" ]; then
                if [ "$temp_int" -gt 85 ] 2>/dev/null; then
                    print_crit "CPU Package High Temp (Tctl): ${temp_c}°C"
                elif [ "$temp_int" -gt 75 ] 2>/dev/null; then
                    print_warn "CPU Package Elevated Temp (Tctl): ${temp_c}°C"
                elif [ "$MODE" = "full" ]; then
                    print_ok "CPU Package (Tctl): ${temp_c}°C"
                fi
            elif [ "$MODE" = "full" ] && { [ "$label" = "Tccd1" ] || [ "$label" = "Tccd2" ]; }; then
                print_info "CPU Core Die (${label}): ${temp_c}°C"
            fi
            ;;
        nvme)
            if [ "$label" = "Composite" ]; then
                dev=$(basename "$(readlink -f "$hwmon_dir/device" 2>/dev/null)" 2>/dev/null)
                model=$(cat "$hwmon_dir/device/model" 2>/dev/null || cat "$hwmon_dir/device/device/model" 2>/dev/null || echo "$dev")
                model=$(echo "$model" | xargs)
                if [ "$temp_int" -gt 75 ] 2>/dev/null; then
                    print_crit "NVMe High Temp ($dev - $model): ${temp_c}°C"
                elif [ "$temp_int" -gt 65 ] 2>/dev/null; then
                    print_warn "NVMe Elevated Temp ($dev - $model): ${temp_c}°C"
                elif [ "$MODE" = "full" ]; then
                    print_ok "NVMe SSD ($dev - $model): ${temp_c}°C"
                fi
            fi
            ;;
        spd5118)
            num=$(echo "$hwmon_dir" | grep -o '[0-9]*$')
            if [ "$temp_int" -gt 70 ] 2>/dev/null; then
                print_crit "DDR5 RAM Module Temp Critical (Slot hwmon$num): ${temp_c}°C"
            elif [ "$temp_int" -gt 60 ] 2>/dev/null; then
                print_warn "DDR5 RAM Module Temp High (Slot hwmon$num): ${temp_c}°C"
            elif [ "$MODE" = "full" ]; then
                print_ok "DDR5 RAM Module (Slot hwmon$num): ${temp_c}°C"
            fi
            ;;
        r8169*)
            if [ "$temp_int" -gt 85 ] 2>/dev/null; then
                print_warn "NIC High Temp (Realtek 2.5GbE): ${temp_c}°C"
            elif [ "$MODE" = "full" ]; then
                print_ok "Network NIC (Realtek 2.5GbE): ${temp_c}°C"
            fi
            ;;
        mt7925*)
            if [ "$temp_int" -gt 75 ] 2>/dev/null; then
                print_warn "Wi-Fi High Temp (MediaTek Wi-Fi 7): ${temp_c}°C"
            elif [ "$MODE" = "full" ]; then
                print_ok "Wi-Fi Adapter (MediaTek Wi-Fi 7): ${temp_c}°C"
            fi
            ;;
    esac
done

# --- 5. Storage & Filesystem Health ---
if [ "$MODE" = "full" ]; then
    print_header "LOCAL STORAGE & DRIVES"
fi

# List of desktop drives to monitor
read -ra LOCAL_MOUNTS <<< "${HEALTHCHECK_LOCAL_MOUNTS:-/}"

for mnt in "${LOCAL_MOUNTS[@]}"; do
    if mountpoint -q "$mnt" 2>/dev/null; then
        USAGE_INFO=$(df -hP "$mnt" 2>/dev/null | tail -n 1)
        TOTAL_SZ=$(echo "$USAGE_INFO" | awk '{print $2}')
        USED_SZ=$(echo "$USAGE_INFO" | awk '{print $3}')
        AVAIL_SZ=$(echo "$USAGE_INFO" | awk '{print $4}')
        USE_PCT=$(echo "$USAGE_INFO" | awk '{print $5}' | tr -d '%')
        
        name=$(basename "$mnt")
        [ "$mnt" = "/" ] && name="System Root (/)"

        if [ "$USE_PCT" -gt 92 ] 2>/dev/null; then
            print_crit "Drive $name ($mnt) is critically full: ${USED_SZ}/${TOTAL_SZ} (${USE_PCT}% used, Free: ${AVAIL_SZ})"
        elif [ "$USE_PCT" -gt 85 ] 2>/dev/null; then
            print_warn "Drive $name ($mnt) is getting full: ${USED_SZ}/${TOTAL_SZ} (${USE_PCT}% used, Free: ${AVAIL_SZ})"
        elif [ "$MODE" = "full" ]; then
            print_ok "Drive ${BOLD}${name}${NC} (${mnt}): ${USED_SZ} / ${TOTAL_SZ} (${USE_PCT}% used, Free: ${AVAIL_SZ})"
        fi
    else
        print_warn "Local drive volume $mnt is not mounted"
    fi
done

# Optional Network Shares (Informational only on desktop)
if [ "$MODE" = "full" ]; then
    read -ra NETWORK_MOUNTS <<< "${HEALTHCHECK_NETWORK_MOUNTS:-}"
    NET_HEADER_PRINTED=false
    for net_mnt in "${NETWORK_MOUNTS[@]}"; do
        if mountpoint -q "$net_mnt" 2>/dev/null; then
            if [ "$NET_HEADER_PRINTED" = false ]; then
                echo -e "\n  ${CYAN}[Network Attached Storage Shares]${NC}"
                NET_HEADER_PRINTED=true
            fi
            USAGE_INFO=$(df -hP "$net_mnt" 2>/dev/null | tail -n 1)
            TOTAL_SZ=$(echo "$USAGE_INFO" | awk '{print $2}')
            USED_SZ=$(echo "$USAGE_INFO" | awk '{print $3}')
            AVAIL_SZ=$(echo "$USAGE_INFO" | awk '{print $4}')
            USE_PCT=$(echo "$USAGE_INFO" | awk '{print $5}' | tr -d '%')
            name=$(basename "$net_mnt")
            print_ok "Share $name: ${USED_SZ} / ${TOTAL_SZ} (${USE_PCT}% used, Free: ${AVAIL_SZ})"
        fi
    done
fi

# BTRFS Device Integrity Verification
for btrfs_mnt in ${HEALTHCHECK_BTRFS_MOUNTS:-}; do
    if mountpoint -q "$btrfs_mnt" 2>/dev/null; then
        BTRFS_ERRORS=$(btrfs device stats "$btrfs_mnt" 2>/dev/null | awk '$2 > 0 {print $0}')
        if [ -n "$BTRFS_ERRORS" ]; then
            print_crit "BTRFS I/O errors detected on $btrfs_mnt:\n$BTRFS_ERRORS"
        elif [ "$MODE" = "full" ]; then
            print_ok "BTRFS integrity on $(basename "$btrfs_mnt") (${btrfs_mnt}): 0 errors"
        fi
    fi
done

# --- 6. Network & Connectivity ---
if [ "$MODE" = "full" ]; then
    print_header "NETWORK & MESH"
fi

LAN_IP=$(ip -4 addr show "${HEALTHCHECK_LAN_IFACE:-eno1}" 2>/dev/null | awk '/inet / {print $2}' | cut -d'/' -f1)
DEFAULT_GW=$(ip route show default 2>/dev/null | awk '/default/ {print $3}')
if [ -n "$LAN_IP" ]; then
    if [ "$MODE" = "full" ]; then
        print_ok "LAN Interface (eno1): ${LAN_IP} (Gateway: ${DEFAULT_GW:-None})"
    fi
else
    print_warn "LAN Interface (eno1) has no active IPv4 address"
fi

# Tailscale Mesh Check
if command -v tailscale >/dev/null 2>&1; then
    TS_STATUS=$(tailscale status --json 2>/dev/null || true)
    if [ -n "$TS_STATUS" ] && command -v jq >/dev/null 2>&1; then
        TS_ONLINE=$(echo "$TS_STATUS" | jq -r '.Self.Online // false')
        TS_IP=$(echo "$TS_STATUS" | jq -r '.Self.TailscaleIPs[0] // "None"')
        if [ "$TS_ONLINE" = "true" ]; then
            if [ "$MODE" = "full" ]; then
                print_ok "Tailscale Mesh: Connected (IP: ${TS_IP})"
            fi
        else
            print_warn "Tailscale Mesh: Disconnected or Offline"
        fi
    else
        if [ "$MODE" = "full" ]; then
            print_info "Tailscale installed (daemon check skipped)"
        fi
    fi
fi

# WAN Connectivity Probe
if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    if [ "$MODE" = "full" ]; then
        print_ok "WAN Internet Connectivity: Reachable (1.1.1.1)"
    fi
else
    print_warn "WAN Internet Connectivity: Ping probe failed"
fi

# --- 7. Local Services & Container Fleet ---
if [ "$MODE" = "full" ]; then
    print_header "LOCAL SERVICES & CONTAINERS"
fi

# Docker Fleet
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    RUNNING_CNT=$(docker ps -q 2>/dev/null | wc -l)
    TOTAL_CNT=$(docker ps -a -q 2>/dev/null | wc -l)
    UNHEALTHY_CNT=$(docker ps --filter "health=unhealthy" -q 2>/dev/null | wc -l)
    RESTARTING_CNT=$(docker ps --filter "status=restarting" -q 2>/dev/null | wc -l)

    if [ "$UNHEALTHY_CNT" -gt 0 ]; then
        UNHEALTHY_NAMES=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" | tr '\n' ' ')
        print_crit "Unhealthy Containers ($UNHEALTHY_CNT): $UNHEALTHY_NAMES"
    fi
    if [ "$RESTARTING_CNT" -gt 0 ]; then
        RESTARTING_NAMES=$(docker ps --filter "status=restarting" --format "{{.Names}}" | tr '\n' ' ')
        print_crit "Restarting Containers ($RESTARTING_CNT): $RESTARTING_NAMES"
    fi
    
    if [ "$MODE" = "full" ]; then
        if [ "$RUNNING_CNT" -gt 0 ]; then
            RUNNING_NAMES=$(docker ps --format "{{.Names}}" | tr '\n' ', ' | sed 's/,[ ]*$//')
            print_ok "Docker: ${RUNNING_CNT} active container(s) (${RUNNING_NAMES}) [Total: ${TOTAL_CNT}]"
        else
            print_ok "Docker: Daemon online (${TOTAL_CNT} total containers, 0 running)"
        fi
    fi
else
    if [ "$MODE" = "full" ]; then
        print_info "Docker: Daemon inactive or not running"
    fi
fi

# Ollama AI Inference Engine
if systemctl is-active --quiet ollama 2>/dev/null || curl -s --max-time 1 http://localhost:11434/api/tags >/dev/null 2>&1; then
    if command -v jq >/dev/null 2>&1; then
        MODELS=$(curl -s --max-time 2 http://localhost:11434/api/tags 2>/dev/null | jq -r '.models[].name' 2>/dev/null | tr '\n' ', ' | sed 's/,[ ]*$//')
        if [ -n "$MODELS" ]; then
            if [ "$MODE" = "full" ]; then
                print_ok "Ollama AI Engine: Online (Available models: ${MODELS})"
            fi
        else
            if [ "$MODE" = "full" ]; then
                print_ok "Ollama AI Engine: Online (No loaded models)"
            fi
        fi
    elif [ "$MODE" = "full" ]; then
        print_ok "Ollama AI Engine: Online"
    fi
fi

# Systemd Failed Services Audit
FAILED_UNITS=$(systemctl --failed --no-legend --no-pager 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
if [ -n "$FAILED_UNITS" ]; then
    print_warn "Degraded Systemd Units: ${FAILED_UNITS}"
elif [ "$MODE" = "full" ]; then
    print_ok "Systemd Services: All background units nominal (0 failed)"
fi

# --- 7b. UPS & Power (NUT / Aegis) -- only on hosts running NUT ---
if command -v upsc >/dev/null 2>&1; then
    if [ "$MODE" = "full" ]; then
        print_header "UPS & POWER (AEGIS)"
    fi
    UPS_NAME=$(upsc -l 2>/dev/null | head -n 1)
    if [ -n "$UPS_NAME" ]; then
        UPS_STATUS=$(upsc "$UPS_NAME" ups.status 2>/dev/null || echo "UNKNOWN")
        UPS_CHARGE=$(upsc "$UPS_NAME" battery.charge 2>/dev/null || echo "0")
        UPS_RUNTIME=$(upsc "$UPS_NAME" battery.runtime 2>/dev/null || echo "0")
        UPS_LOAD=$(upsc "$UPS_NAME" ups.load 2>/dev/null || echo "0")
        UPS_REALPWR=$(upsc "$UPS_NAME" ups.realpower 2>/dev/null || echo "0")
        UPS_MODEL=$(upsc "$UPS_NAME" device.model 2>/dev/null || echo "UPS")

        RUNTIME_MIN=$(( UPS_RUNTIME / 60 ))

        if [ "$UPS_STATUS" = "OL" ]; then
            if [ "$MODE" = "full" ]; then
                print_ok "Power State: Online (Grid Nominal) | Model: $UPS_MODEL"
            fi
        elif [ "$UPS_STATUS" = "OB" ]; then
            print_crit "Power State: ON BATTERY (Grid Offline) | Model: $UPS_MODEL"
        else
            print_warn "Power State: $UPS_STATUS | Model: $UPS_MODEL"
        fi

        if [ "$UPS_CHARGE" -lt 30 ]; then
            print_crit "UPS Battery Critical: ${UPS_CHARGE}% (Runtime: ~${RUNTIME_MIN}m) | Load: ${UPS_LOAD}% (~${UPS_REALPWR}W)"
        elif [ "$UPS_CHARGE" -lt 60 ]; then
            print_warn "UPS Battery Low: ${UPS_CHARGE}% (Runtime: ~${RUNTIME_MIN}m) | Load: ${UPS_LOAD}% (~${UPS_REALPWR}W)"
        elif [ "$MODE" = "full" ]; then
            print_ok "Battery Charge: ${UPS_CHARGE}% (Runtime: ~${RUNTIME_MIN}m) | Load: ${UPS_LOAD}% (~${UPS_REALPWR}W)"
        fi
    else
        print_warn "No UPS discovered via NUT"
    fi
fi

# --- 7c. VPN Tunnel (Gluetun) -- only on hosts that have a gluetun container ---
if command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^gluetun$"; then
    if [ "$MODE" = "full" ]; then
        print_header "VPN CLOAK & ROUTING"
    fi
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^gluetun$"; then
        VPN_JSON=$(docker exec gluetun wget -qO- --timeout=5 https://am.i.mullvad.net/json 2>/dev/null || true)
        if [ -n "$VPN_JSON" ]; then
            VPN_IP=$(echo "$VPN_JSON" | grep -o '"ip":"[^"]*' | cut -d'"' -f4)
            VPN_CITY=$(echo "$VPN_JSON" | grep -o '"city":"[^"]*' | cut -d'"' -f4)
            VPN_COUNTRY=$(echo "$VPN_JSON" | grep -o '"country":"[^"]*' | cut -d'"' -f4)
            VPN_ORG=$(echo "$VPN_JSON" | grep -o '"organization":"[^"]*' | cut -d'"' -f4)

            if [ "$MODE" = "full" ]; then
                print_ok "Gluetun VPN Tunnel: Active"
                print_info "Exit IP: $VPN_IP ($VPN_CITY, $VPN_COUNTRY) via $VPN_ORG"
            fi
        else
            print_warn "Gluetun container running, but external verification probe timed out"
        fi
    else
        print_warn "Gluetun container is not running"
    fi
fi

# --- 8. Overall Status Summary ---
if [ "$MODE" = "full" ]; then
    print_header "SYSTEM STATUS SUMMARY"
    if [ "$STATUS_OVERALL" = "OK" ]; then
        echo -e "${BOLD}${GREEN}[+] OVERALL HEALTH: NOMINAL (Desktop operational & healthy)${NC}\n"
    elif [ "$STATUS_OVERALL" = "WARN" ]; then
        echo -e "${BOLD}${YELLOW}[!] OVERALL HEALTH: WARNINGS DETECTED${NC}"
        for w in "${WARNINGS[@]}"; do
            echo -e "  ${YELLOW}-${NC} $w"
        done
        echo ""
    else
        echo -e "${BOLD}${RED}[-] OVERALL HEALTH: CRITICAL ISSUES DETECTED${NC}"
        for c in "${CRITICALS[@]}"; do
            echo -e "  ${RED}-${NC} $c"
        done
        echo ""
    fi
else
    # Quick Mode Output
    if [ "$STATUS_OVERALL" = "OK" ]; then
        echo -e "${BOLD}${GREEN}[+] HEALTH: NOMINAL${NC} | CPU: ${LOAD%%,*} load | RAM: ${MEM_PCT}% | ${GPU_SUMMARY} | Storage: OK"
    elif [ "$STATUS_OVERALL" = "WARN" ]; then
        echo -e "${BOLD}${YELLOW}[!] HEALTH: WARNING${NC} (${#WARNINGS[@]} warnings) | CPU: ${LOAD%%,*} load | RAM: ${MEM_PCT}%"
    else
        echo -e "${BOLD}${RED}[-] HEALTH: CRITICAL${NC} (${#CRITICALS[@]} critical issues) | CPU: ${LOAD%%,*} load | RAM: ${MEM_PCT}%"
    fi
fi

if [ "$STATUS_OVERALL" = "CRIT" ]; then
    exit 2
elif [ "$STATUS_OVERALL" = "WARN" ]; then
    exit 1
else
    exit 0
fi
