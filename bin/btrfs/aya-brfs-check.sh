#!/bin/bash

set -euo pipefail

# Soft colors for elegant output
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'

# Primary colors
BLUE='\033[38;5;75m'
GREEN='\033[38;5;41m'
YELLOW='\033[38;5;221m'
ORANGE='\033[38;5;215m'
RED='\033[38;5;203m'
PURPLE='\033[38;5;141m'
CYAN='\033[38;5;87m'

# Optimized configurations for SSD
SSD_SCRUB_SETTINGS=("--limit" "500M")

# Check if terminal supports colors and UTF-8
check_terminal_capabilities() {
    if [[ -n "${TERM:-}" && "${TERM}" != "dumb" ]]; then
        if command -v tput > /dev/null && tput colors > /dev/null 2>&1; then
            return 0
        fi
    fi
    # Disable all colors and special characters if terminal doesn't support them
    RESET=''; BOLD=''; DIM=''; ITALIC=''
    BLUE=''; GREEN=''; YELLOW=''; ORANGE=''; RED=''; PURPLE=''; CYAN=''
    return 1
}

# Elegant utility functions
print_header() {
    local title="$1"
    if [[ -n "${BOLD}" ]]; then
        echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${BOLD}${BLUE}║${RESET} ${BOLD}${CYAN}${title}${RESET} ${BOLD}${BLUE}║${RESET}"
        echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}"
    else
        echo "=== ${title} ==="
    fi
    echo
}

print_section() {
    local title="$1"
    if [[ -n "${DIM}" ]]; then
        echo -e "${DIM}${BLUE}── ${BOLD}${title} ${BLUE}──${RESET}"
    else
        echo "-- ${title} --"
    fi
}

print_success() {
    if [[ -n "${GREEN}" ]]; then
        echo -e "${GREEN}✓${RESET} ${BOLD}$1${RESET}"
    else
        echo "[SUCCESS] $1"
    fi
}

print_warning() {
    if [[ -n "${YELLOW}" ]]; then
        echo -e "${YELLOW}⚠${RESET} ${BOLD}$1${RESET}"
    else
        echo "[WARNING] $1"
    fi
}

print_error() {
    if [[ -n "${RED}" ]]; then
        echo -e "${RED}✗${RESET} ${BOLD}$1${RESET}"
    else
        echo "[ERROR] $1"
    fi
}

print_info() {
    if [[ -n "${BLUE}" ]]; then
        echo -e "${BLUE}ℹ${RESET} ${BOLD}$1${RESET}"
    else
        echo "[INFO] $1"
    fi
}

print_bullet() {
    if [[ -n "${DIM}" ]]; then
        echo -e "${DIM}${BLUE}•${RESET} $1"
    else
        echo "• $1"
    fi
}

draw_separator() {
    if [[ -n "${DIM}" ]]; then
        echo -e "${DIM}${BLUE}────────────────────────────────────────────────────────────────${RESET}"
    else
        echo "----------------------------------------"
    fi
}

spinner() {
    local pid="$1"
    local delay=0.1
    local spinstr='|/-\'
    
    while ps -p "${pid}" > /dev/null 2>&1; do
        local temp="${spinstr#?}"
        printf " [%c]  " "${spinstr}"
        local spinstr="${temp}${spinstr%"$temp"}"
        sleep "${delay}"
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to get device info
get_device_type() {
    local mount_point="$1"
    local devices
    local device_type="unknown"
    
    if ! devices=$(btrfs filesystem show "${mount_point}" 2>/dev/null | grep -o '/dev/[^ ]*'); then
        echo "unknown"
        return 1
    fi
    
    # Check all devices and determine type
    local ssd_count=0
    local hdd_count=0
    local total_count=0
    
    for device in ${devices}; do
        if [[ -e "${device}" ]]; then
            if lsblk -d -o rota "${device}" > /dev/null 2>&1; then
                if [[ $(lsblk -d -o rota "${device}" 2>/dev/null | tail -1) -eq 0 ]]; then
                    ssd_count=$((ssd_count + 1))
                else
                    hdd_count=$((hdd_count + 1))
                fi
                total_count=$((total_count + 1))
            fi
        fi
    done
    
    if [[ ${total_count} -eq 0 ]]; then
        echo "unknown"
    elif [[ ${ssd_count} -eq ${total_count} ]]; then
        echo "ssd"
    elif [[ ${hdd_count} -eq ${total_count} ]]; then
        echo "hdd"
    else
        echo "mixed"
    fi
}

# Requirements checking function
check_requirements() {
    local missing=0
    
    print_header "SYSTEM REQUIREMENTS CHECK"
    
    # Check Bash version
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        print_error "Bash 4.0+ required (current: ${BASH_VERSION})"
        missing=$((missing + 1))
    else
        print_success "Bash version: ${BASH_VERSION}"
    fi

    # Check BTRFS tools
    if ! command -v btrfs > /dev/null 2>&1; then
        print_error "btrfs-progs not installed"
        missing=$((missing + 1))
    else
        local btrfs_version
        btrfs_version=$(btrfs version | head -1)
        print_success "BTRFS: ${btrfs_version}"
    fi

    # Check core utilities
    local core_tools=("mount" "awk" "grep" "lsblk" "ps")
    for tool in "${core_tools[@]}"; do
        if ! command -v "${tool}" > /dev/null 2>&1; then
            print_warning "${tool} not found (some features limited)"
        else
            print_success "${tool} available"
        fi
    done

    # Check optional tools
    local optional_tools=("ionice" "sysctl" "fio" "hdparm" "tput")
    for tool in "${optional_tools[@]}"; do
        if command -v "${tool}" > /dev/null 2>&1; then
            print_info "${tool} available (enhanced features)"
        else
            print_bullet "${tool} not found (optional)"
        fi
    done

    # Check terminal capabilities
    if check_terminal_capabilities; then
        print_success "Terminal supports colors and UTF-8"
    else
        print_warning "Limited terminal capabilities - using basic output"
    fi

    # Check BTRFS filesystems
    if mount | grep -q btrfs; then
        print_success "BTRFS filesystems mounted"
    else
        print_warning "No BTRFS filesystems currently mounted"
    fi

    echo
    if [[ ${missing} -gt 0 ]]; then
        print_error "${missing} critical requirements missing"
        return 1
    else
        print_success "All requirements satisfied"
        return 0
    fi
}

# Elegant BTRFS information display
show_btrfs_info() {
    local mount_point="$1"
    local verbose="${2:-false}"
    
    if [[ ! -d "${mount_point}" ]]; then
        print_error "Mount point '${mount_point}' not found or not accessible"
        return 1
    fi
    
    local device_type
    if ! device_type=$(get_device_type "${mount_point}"); then
        device_type="unknown"
    fi
    
    local device_icon=""
    if [[ -n "${BOLD}" ]]; then
        case "${device_type}" in
            "ssd") device_icon="⚡" ;;
            "hdd") device_icon="💾" ;;
            "mixed") device_icon="🔀" ;;
            *) device_icon="🖴" ;;
        esac
    fi
    
    print_header "BTRFS FILESYSTEM ${device_icon}  ${mount_point}"
    
    echo -e "${DIM}Device type: ${BOLD}${device_type^^}${RESET}"
    echo

    # Filesystem information in elegant layout
    print_section "BASIC INFORMATION"
    local fs_info
    if fs_info=$(btrfs filesystem show "${mount_point}" 2>/dev/null); then
        while IFS= read -r line; do
            echo -e "  ${DIM}${line}${RESET}"
        done <<< "${fs_info}"
    else
        print_error "Cannot show filesystem information"
    fi
    
    draw_separator
    
    # Storage usage in a clean format
    print_section "STORAGE USAGE"
    echo -e "  ${BOLD}Device usage:${RESET}"
    local device_usage
    if device_usage=$(btrfs device usage "${mount_point}" 2>/dev/null); then
        while IFS= read -r line; do
            print_bullet "${line}"
        done <<< "${device_usage}"
    else
        print_error "Cannot show device usage"
    fi
    
    echo
    echo -e "  ${BOLD}Filesystem usage:${RESET}"
    local fs_usage
    if fs_usage=$(btrfs filesystem usage "${mount_point}" 2>/dev/null); then
        while IFS= read -r line; do
            print_bullet "${line}"
        done <<< "${fs_usage}"
    else
        print_error "Cannot show filesystem usage"
    fi
    
    draw_separator
    
    # Space information
    print_section "SPACE ALLOCATION"
    local space_info
    if space_info=$(btrfs filesystem df "${mount_point}" 2>/dev/null); then
        while IFS= read -r line; do
            print_bullet "${line}"
        done <<< "${space_info}"
    else
        print_error "Cannot show space allocation"
    fi
    
    draw_separator
    
    # Scrub status with visual indicators
    print_section "SCRUB STATUS"
    local scrub_status
    if scrub_status=$(btrfs scrub status "${mount_point}" 2>/dev/null); then
        if echo "${scrub_status}" | grep -q "running"; then
            echo -e "  ${YELLOW}⏳ Scrub in progress${RESET}"
        elif echo "${scrub_status}" | grep -q "finished"; then
            echo -e "  ${GREEN}✅ Scrub completed${RESET}"
        else
            echo -e "  ${BLUE}💤 Scrub not running${RESET}"
        fi
        while IFS= read -r line; do
            print_bullet "${line}"
        done <<< "${scrub_status}"
    else
        echo -e "  ${DIM}Scrub status unavailable${RESET}"
    fi
    
    draw_separator
    
    # Device statistics
    print_section "DEVICE STATISTICS"
    local stats_output
    if stats_output=$(btrfs device stats "${mount_point}" 2>/dev/null); then
        while IFS= read -r line; do
            if echo "${line}" | grep -q " 0$"; then
                print_bullet "${line}"
            else
                echo -e "  ${ORANGE}⚠  ${line}${RESET}"
            fi
        done <<< "${stats_output}"
    else
        echo -e "  ${DIM}No device statistics available${RESET}"
    fi
    
    # SSD optimizations hint
    if [[ "${device_type}" == "ssd" ]] || [[ "${device_type}" == "mixed" ]]; then
        draw_separator
        print_section "OPTIMIZATIONS"
        print_bullet "${CYAN}SSD-optimized scrub available${RESET}"
        print_bullet "Use 'scrub --priority' for maximum performance"
    fi
    
    echo
}

# Run scrub and capture PID for background monitoring
run_scrub_background() {
    local mount_point="$1"
    shift
    local scrub_args=("$@")
    
    btrfs scrub start "${scrub_args[@]}" "${mount_point}" 2>&1 &
    local pid=$!
    echo "${pid}"
}

# Graceful scrub function
optimized_scrub() {
    local mount_point="$1"
    local device_type="$2"
    
    print_header "STARTING OPTIMIZED SCRUB"
    echo -e "${DIM}Device: ${BOLD}${mount_point}${RESET}"
    echo -e "${DIM}Type: ${BOLD}${device_type^^}${RESET}"
    echo
    
    local scrub_pid
    local scrub_args=()
    
    case "${device_type}" in
        "ssd")
            print_success "Using SSD-optimized settings"
            echo -e "${DIM}Batch workers: 8 | Limit: 500MB/s${RESET}"
            echo
            scrub_args=(-c 2 -n 7 "${SSD_SCRUB_SETTINGS[@]}")
            ;;
        "hdd")
            print_info "Using HDD-optimized settings"
            echo -e "${DIM}Batch workers: 2 | Limit: 100MB/s${RESET}"
            echo
            scrub_args=(-c 2 -n 2 --limit 100M)
            ;;
        "mixed"|"unknown")
            print_info "Using balanced settings for ${device_type} devices"
            echo -e "${DIM}Batch workers: 4 | Limit: 200MB/s${RESET}"
            echo
            scrub_args=(-c 2 -n 4 --limit 200M)
            ;;
    esac
    
    # Run scrub in background
    if ! scrub_pid=$(run_scrub_background "${mount_point}" "${scrub_args[@]}"); then
        print_error "Failed to start scrub process"
        return 1
    fi
    
    # Show spinner while scrub runs
    spinner "${scrub_pid}"
    
    # Wait for process to complete and get exit status
    if wait "${scrub_pid}"; then
        print_success "Scrub completed successfully"
    else
        local exit_code=$?
        print_error "Scrub failed with exit code: ${exit_code}"
        return "${exit_code}"
    fi
    
    echo
    return 0
}

# Priority scrub with elegant output
priority_scrub() {
    local mount_point="$1"
    
    print_header "STARTING PRIORITY SCRUB"
    echo -e "${DIM}Device: ${BOLD}${mount_point}${RESET}"
    if [[ -n "${CYAN}" ]]; then
        echo -e "${CYAN}⚡ Maximum performance mode activated${RESET}"
    else
        echo "⚡ Maximum performance mode activated"
    fi
    echo
    
    print_success "Priority settings applied:"
    print_bullet "I/O priority: highest"
    print_bullet "Batch workers: 8"
    print_bullet "Rate limit: 800MB/s"
    print_bullet "Parallel operations: 16"
    echo
    
    local scrub_args=(-c 2 -n 7 --limit 800M)
    
    if command -v ionice > /dev/null 2>&1; then
        if ! ionice -c2 -n0 btrfs scrub start "${scrub_args[@]}" "${mount_point}"; then
            print_error "Priority scrub failed"
            return 1
        fi
    else
        print_warning "ionice not available, using standard priority settings"
        if ! btrfs scrub start "${scrub_args[@]}" "${mount_point}"; then
            print_error "Priority scrub failed"
            return 1
        fi
    fi
}

# Minimal monitoring
monitor_scrub() {
    local mount_point="$1"
    
    print_header "SCRUB MONITORING"
    echo -e "${DIM}Monitoring: ${BOLD}${mount_point}${RESET}"
    echo -e "${DIM}Press ${BOLD}Ctrl+C${DIM} to exit monitoring${RESET}"
    echo
    
    local first_run=true
    local last_status=""
    
    while true; do
        if [[ "${first_run}" != "true" ]]; then
            printf "\033[2K\r"  # Clear line
        else
            first_run=false
        fi
        
        local status
        if ! status=$(btrfs scrub status "${mount_point}" 2>/dev/null); then
            echo
            print_error "Cannot monitor scrub status"
            return 1
        fi
        
        # Only update display if status changed
        if [[ "${status}" != "${last_status}" ]]; then
            if echo "${status}" | grep -q "running"; then
                local progress
                progress=$(echo "${status}" | grep -o " [0-9.]*%" | head -1 | tr -d ' ' || echo "")
                local speed
                speed=$(echo "${status}" | grep -o "[0-9.]* MB/s" | head -1 || echo "unknown")
                
                if [[ -n "${progress}" ]]; then
                    printf "Progress: ${CYAN}%s${RESET} | Speed: ${GREEN}%s${RESET}" "${progress}" "${speed}"
                else
                    printf "Scrub in progress..."
                fi
            else
                echo
                if echo "${status}" | grep -q "finished"; then
                    print_success "Scrub completed successfully"
                else
                    print_info "Scrub not running"
                fi
                break
            fi
            last_status="${status}"
        fi
        
        sleep 2
    done
    echo
}

# Benchmark with clean output
benchmark_scrub_speed() {
    local mount_point="$1"
    local device_type="$2"
    
    print_header "SCRUB SPEED BENCHMARK"
    echo -e "${DIM}Device: ${BOLD}${mount_point}${RESET}"
    echo -e "${DIM}Type: ${BOLD}${device_type^^}${RESET}"
    echo
    
    print_section "EXPECTED PERFORMANCE"
    case "${device_type}" in
        "ssd")
            print_bullet "${GREEN}NVMe Gen4: 1.5-3.0 GB/s${RESET}"
            print_bullet "${GREEN}NVMe Gen3: 0.8-1.5 GB/s${RESET}"
            print_bullet "${CYAN}SATA SSD: 400-550 MB/s${RESET}"
            ;;
        "hdd")
            print_bullet "${YELLOW}HDD 7200rpm: 150-220 MB/s${RESET}"
            print_bullet "${YELLOW}HDD 5400rpm: 80-120 MB/s${RESET}"
            print_bullet "${ORANGE}RAID HDD: 300-600 MB/s${RESET}"
            ;;
        "mixed")
            print_bullet "${YELLOW}Mixed devices: 200-400 MB/s${RESET}"
            print_bullet "${CYAN}Performance depends on SSD/HDD ratio${RESET}"
            ;;
        *)
            print_bullet "${DIM}Unknown device type: using conservative estimates${RESET}"
            print_bullet "${YELLOW}Expected: 100-300 MB/s${RESET}"
            ;;
    esac
    
    # Time estimates
    local total_size
    if total_size=$(btrfs filesystem usage "${mount_point}" 2>/dev/null | grep "Device size" | awk '{print $3 $4}'); then
        echo
        print_section "TIME ESTIMATES"
        case "${device_type}" in
            "ssd")
                print_bullet "Estimated time: ${GREEN}10-30 minutes${RESET}"
                ;;
            "hdd")
                print_bullet "Estimated time: ${YELLOW}1-4 hours${RESET}"
                ;;
            "mixed")
                print_bullet "Estimated time: ${ORANGE}30-90 minutes${RESET}"
                ;;
            *)
                print_bullet "Estimated time: ${YELLOW}1-3 hours${RESET}"
                ;;
        esac
        print_bullet "Filesystem size: ${total_size}"
    fi
    echo
}

# System optimizations
setup_ssd_optimizations() {
    print_header "SYSTEM OPTIMIZATIONS"
    
    local optimized=false
    
    if [[ ${EUID} -eq 0 ]]; then
        print_section "APPLYING OPTIMIZATIONS"
        
        # Check if sysctl parameter exists before setting
        if sysctl -a 2>/dev/null | grep -q "dev.btrfs.per_stream_rate_limit"; then
            if sysctl -w dev.btrfs.per_stream_rate_limit=800000000 > /dev/null 2>&1; then
                print_success "Set BTRFS per-stream rate limit to 800MB/s"
                optimized=true
            else
                print_warning "Failed to set BTRFS rate limit"
            fi
        else
            print_info "BTRFS rate limit parameter not available in this kernel"
        fi
        
        # Apply disk-specific optimizations
        for disk in $(lsblk -d -o NAME | grep -v NAME); do
            if [[ -f "/sys/block/${disk}/queue/rotational" ]]; then
                if [[ $(cat "/sys/block/${disk}/queue/rotational") -eq 0 ]]; then
                    echo -e "  Optimizing ${CYAN}${disk}${RESET} (SSD)"
                    if echo 1024 > "/sys/block/${disk}/queue/nr_requests" 2>/dev/null; then
                        optimized=true
                    fi
                    if echo "none" > "/sys/block/${disk}/queue/scheduler" 2>/dev/null; then
                        optimized=true
                    fi
                fi
            fi
        done
        
    else
        print_warning "Root privileges required for system optimizations"
        print_info "To make optimizations persistent, add to /etc/sysctl.conf:"
        print_bullet "dev.btrfs.per_stream_rate_limit=800000000"
    fi
    
    if [[ "${optimized}" == "true" ]]; then
        print_success "System optimizations applied successfully"
        print_warning "These are temporary changes. Add to system configuration for persistence."
    else
        print_info "Using application-level optimizations only"
    fi
    echo
}

# Minimal help
show_help() {
    print_header "BTRFS MANAGEMENT TOOL"
    
    echo -e "${BOLD}${CYAN}USAGE:${RESET}"
    echo -e "  ${DIM}\$ $0 [command] [options] [arguments]${RESET}"
    echo
    
    echo -e "${BOLD}${CYAN}COMMANDS:${RESET}"
    echo -e "  ${GREEN}info${RESET}    [mount]     Show filesystem information"
    echo -e "  ${GREEN}scrub${RESET}   [mount]     Start optimized scrub"
    echo -e "  ${GREEN}monitor${RESET} [mount]     Monitor running scrub"
    echo -e "  ${GREEN}benchmark${RESET} [mount]   Show performance estimates"
    echo -e "  ${GREEN}optimize${RESET}           Apply system optimizations"
    echo -e "  ${GREEN}check-requirements${RESET} Check system requirements"
    echo -e "  ${GREEN}help${RESET}               Show this help message"
    echo
    
    echo -e "${BOLD}${CYAN}EXAMPLES:${RESET}"
    echo -e "  ${DIM}\$ $0 info /mnt/data${RESET}"
    echo -e "  ${DIM}\$ $0 scrub --priority /mnt/data${RESET}"
    echo -e "  ${DIM}\$ $0 monitor /mnt/data${RESET}"
    echo -e "  ${DIM}\$ $0 benchmark /mnt/data${RESET}"
    echo
    
    echo -e "${BOLD}${CYAN}OPTIONS:${RESET}"
    echo -e "  ${DIM}--priority    Maximum performance scrub${RESET}"
    echo -e "  ${DIM}--monitor     Auto-start monitoring${RESET}"
    echo -e "  ${DIM}--verbose     Detailed output${RESET}"
    echo -e "  ${DIM}--all         Show all mounted filesystems${RESET}"
    echo
}

# Get all mounted BTRFS filesystems
get_btrfs_mounts() {
    mount | grep -E '^[^ ]+ on .* type btrfs' | awk '{print $3}' || true
}

# Main function with elegant command handling
main() {
    local command="info"
    local args=()
    
    # Check terminal capabilities first
    check_terminal_capabilities
    
    # Parse main command
    if [[ $# -gt 0 ]]; then
        case "$1" in
            -h|--help|help)
                show_help
                exit 0
                ;;
            info|scrub|monitor|optimize|benchmark|check-requirements)
                command="$1"
                shift
                ;;
            *)
                print_error "Unknown command: $1"
                show_help
                exit 1
                ;;
        esac
    fi
    
    # Parse options
    local show_all=false
    local verbose=false
    local priority_mode="standard"
    local auto_monitor=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all) show_all=true ;;
            -v|--verbose) verbose=true ;;
            -p|--priority) priority_mode="priority" ;;
            -m|--monitor) auto_monitor=true ;;
            --) shift; args+=("$@"); break ;;
            *) args+=("$1") ;;
        esac
        shift
    done
    
    case "${command}" in
        info)
            if [[ "${show_all}" == "true" ]] || [[ ${#args[@]} -eq 0 ]]; then
                local found=false
                local mounts
                mounts=$(get_btrfs_mounts)
                
                if [[ -z "${mounts}" ]]; then
                    print_error "No mounted BTRFS filesystems found"
                    echo
                    echo -e "${DIM}Usage: $0 info [mount_point]${RESET}"
                    exit 1
                fi
                
                while IFS= read -r mount_point; do
                    if [[ -n "${mount_point}" ]]; then
                        found=true
                        show_btrfs_info "${mount_point}" "${verbose}"
                    fi
                done <<< "${mounts}"
                
            else
                show_btrfs_info "${args[0]}" "${verbose}"
            fi
            ;;
            
        scrub)
            if [[ ${#args[@]} -eq 0 ]]; then
                print_error "Please specify a mount point"
                show_help
                exit 1
            fi
            
            local mount_point="${args[0]}"
            if [[ ! -d "${mount_point}" ]]; then
                print_error "Mount point '${mount_point}' not found or not accessible"
                exit 1
            fi
            
            local device_type
            if ! device_type=$(get_device_type "${mount_point}"); then
                device_type="unknown"
            fi
            
            if [[ "${priority_mode}" == "priority" ]]; then
                if ! priority_scrub "${mount_point}"; then
                    exit 1
                fi
            else
                if ! optimized_scrub "${mount_point}" "${device_type}"; then
                    exit 1
                fi
            fi
            
            if [[ "${auto_monitor}" == "true" ]]; then
                sleep 2
                monitor_scrub "${mount_point}"
            else
                echo
                print_info "Use '$0 monitor ${mount_point}' to monitor progress"
            fi
            ;;
            
        monitor)
            if [[ ${#args[@]} -eq 0 ]]; then
                print_error "Please specify a mount point"
                exit 1
            fi
            monitor_scrub "${args[0]}"
            ;;
            
        optimize)
            setup_ssd_optimizations
            ;;
            
        benchmark)
            if [[ ${#args[@]} -eq 0 ]]; then
                print_error "Please specify a mount point"
                exit 1
            fi
            local mount_point="${args[0]}"
            if [[ ! -d "${mount_point}" ]]; then
                print_error "Mount point '${mount_point}' not found or not accessible"
                exit 1
            fi
            local device_type
            if ! device_type=$(get_device_type "${mount_point}"); then
                device_type="unknown"
            fi
            benchmark_scrub_speed "${mount_point}" "${device_type}"
            ;;
            
        check-requirements)
            if ! check_requirements; then
                exit 1
            fi
            ;;
    esac
}

# Graceful execution with error handling
trap 'print_error "Script interrupted by user"; exit 130' INT TERM

# Always use main function for consistent behavior
main "$@"

