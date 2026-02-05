#!/bin/bash

# Colors
WHITE="\033[97m"
GREEN="\033[92m"
CYAN="\033[96m"
RED="\033[91m"
YELLOW="\033[93m"
RESET="\033[0m"

# Defaults
DEFAULT_PORT=8080
SERVICE_NAME="hidden_service"
WAIT_TIME=90

# Banner function
show_banner() {
    echo -e "${WHITE} +---------------------------------------------------------------+"
    echo -e "${WHITE} |${GREEN} ░░░░░░░█ ░░░░░█ ░░░░░█ ░░█  ░░█ ░░░░░█ ░░░░░░█░░░░░░░█ ${WHITE} |"
    echo -e "${WHITE} |${GREEN} █████░█ ░░████████░░█ ░░█  ░░█ ███████░░█ ████████░░█ ${WHITE} |"
    echo -e "${WHITE} |${GREEN}    ░░█   ░░█   ░░█░░█░░░░█░░█ ░░█   ░░█░░░░░░░░█   ░░█    ${WHITE} |"
    echo -e "${WHITE} |${GREEN}    ░░█   ░░█   ░░█░░████░░█ ░░█ ░░█   ░░█ ██████░░█   ░░█    ${WHITE} |"
    echo -e "${WHITE} |${GREEN}    ░░█   █░░░░░░░███░░█  ░░█ ░░█ ░░█  ░░█ █░░░░░░░░█   ░░█    ${WHITE} |"
    echo -e "${WHITE} |${GREEN}    ███    ████████ ███  ███ ███  ██████ █████████   ███    ${WHITE} |"
    echo -e "${WHITE} +-------------------------${CYAN}(${RED}ByteBreach${CYAN})${WHITE}--------------------------+"
    echo -e "${RESET}"
}

# Run command with optional error checking
run() {
    local cmd="$1"
    local check="${2:-false}"
    local capture_output="${3:-true}"
    
    if [ "$capture_output" = "true" ]; then
        if [ "$check" = "true" ]; then
            eval "$cmd"
        else
            eval "$cmd" 2>/dev/null
        fi
    else
        if [ "$check" = "true" ]; then
            eval "$cmd" >/dev/null 2>&1
        else
            eval "$cmd" >/dev/null 2>&1
        fi
    fi
    return $?
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running in Termux
is_termux() {
    [[ "$PREFIX" == *"com.termux"* ]]
}

# Require sudo/root
require_sudo() {
    if is_termux; then
        return 0
    fi
    
    if [ "$EUID" -ne 0 ]; then
        echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Root privileges required. Trying to get sudo..."
        if command_exists sudo; then
            exec sudo "$0" "$@"
        else
            echo -e "${WHITE} [${RED}!${WHITE}] ${RED}sudo not found. Continuing without root..."
            return 1
        fi
    fi
    return 0
}

# Detect Tor user
detect_tor_user() {
    if is_termux; then
        echo "$USER"
        return
    fi
    
    for user in "debian-tor" "tor"; do
        if id "$user" &>/dev/null; then
            echo "$user"
            return
        fi
    done
    
    local tor_user=$(ps aux | grep -E "[t]or " | head -1 | awk '{print $1}')
    if [ -n "$tor_user" ]; then
        echo "$tor_user"
        return
    fi
    
    echo "tor"
}

# Install Tor
install_tor() {
    if command_exists tor; then
        echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Tor is already installed."
        return 0
    fi
    
    echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Tor not found. Installing..."
    
    if is_termux; then
        pkg install tor -y
    elif command_exists apt; then
        if [ "$EUID" -eq 0 ]; then
            apt update && apt install tor -y
        else
            sudo apt update && sudo apt install tor -y
        fi
    elif command_exists apt-get; then
        if [ "$EUID" -eq 0 ]; then
            apt-get update && apt-get install tor -y
        else
            sudo apt-get update && sudo apt-get install tor -y
        fi
    elif command_exists yum; then
        if [ "$EUID" -eq 0 ]; then
            yum install tor -y
        else
            sudo yum install tor -y
        fi
    elif command_exists dnf; then
        if [ "$EUID" -eq 0 ]; then
            dnf install tor -y
        else
            sudo dnf install tor -y
        fi
    elif command_exists pacman; then
        if [ "$EUID" -eq 0 ]; then
            pacman -S tor --noconfirm
        else
            sudo pacman -S tor --noconfirm
        fi
    else
        echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Unsupported package manager. Install Tor manually."
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Tor installed successfully."
        return 0
    else
        echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Failed to install Tor."
        return 1
    fi
}

# Restart Tor service
restart_tor() {
    if is_termux; then
        pkill -f tor 2>/dev/null || true
        sleep 2
        tor 2>/dev/null &
        sleep 5
        if pgrep -f tor >/dev/null; then
            return 0
        fi
        return 1
    fi
    
    # Try systemctl services
    local services=("tor@default" "tor" "tor.service")
    for svc in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "$svc"; then
            if [ "$EUID" -eq 0 ]; then
                systemctl restart "$svc" 2>/dev/null
            else
                sudo systemctl restart "$svc" 2>/dev/null
            fi
            
            if [ $? -eq 0 ]; then
                sleep 3
                local status
                if [ "$EUID" -eq 0 ]; then
                    status=$(systemctl is-active "$svc" 2>/dev/null)
                else
                    status=$(sudo systemctl is-active "$svc" 2>/dev/null)
                fi
                
                if [ "$status" = "active" ]; then
                    return 0
                fi
            fi
        fi
    done
    
    # Fallback to killing and starting manually
    pkill tor 2>/dev/null || true
    sleep 2
    tor --runasdaemon 1 2>/dev/null &
    sleep 5
    
    if pgrep tor >/dev/null; then
        return 0
    fi
    
    return 1
}

# Check if Tor is running
check_tor_running() {
    if is_termux; then
        pgrep -f tor >/dev/null
        return $?
    fi
    
    local status
    if [ "$EUID" -eq 0 ]; then
        status=$(systemctl is-active tor 2>/dev/null || systemctl is-active tor.service 2>/dev/null || true)
    else
        status=$(sudo systemctl is-active tor 2>/dev/null || sudo systemctl is-active tor.service 2>/dev/null || true)
    fi
    
    if [[ "$status" == *"active"* ]]; then
        return 0
    fi
    
    pgrep -x tor >/dev/null
    return $?
}

# Validate onion address
validate_onion_address() {
    local onion="$1"
    
    if [ -z "$onion" ]; then
        return 1
    fi
    
    onion=$(echo "$onion" | xargs)
    
    if [ ${#onion} -eq 56 ] && [[ "$onion" == *.onion ]]; then
        return 0
    fi
    
    if [[ "$onion" == *.onion ]]; then
        return 0
    fi
    
    return 1
}

# Parse arguments
parse_args() {
    PORT="$DEFAULT_PORT"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --port)
                if [[ "$2" =~ ^[0-9]+$ ]]; then
                    PORT="$2"
                    shift 2
                else
                    echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Invalid port number"
                    exit 1
                fi
                ;;
            --help|-h)
                echo "Usage: $0 [--port PORT]"
                echo "Set up a Tor hidden service"
                echo ""
                echo "Options:"
                echo "  --port PORT    Local port to expose (default: 8080)"
                echo "  --help, -h     Show this help message"
                exit 0
                ;;
            *)
                echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    # Show banner
    show_banner
    
    # Parse arguments
    parse_args "$@"
    
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Starting Tor Hidden Service setup..."
    
    # Require sudo
    require_sudo "$@"
    
    # Install Tor
    if ! install_tor; then
        echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Cannot continue without Tor."
        exit 1
    fi
    
    # Check/start Tor
    if ! check_tor_running; then
        if ! restart_tor; then
            echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Failed to start Tor."
            exit 1
        fi
    fi
    
    # Determine paths
    if is_termux; then
        TORRC="$HOME/../usr/etc/tor/torrc"
        TOR_DIR="$HOME/../usr/var/lib/tor"
    else
        TORRC="/etc/tor/torrc"
        TOR_DIR="/var/lib/tor"
    fi
    
    # Detect Tor user
    TOR_USER=$(detect_tor_user)
    if [ -z "$TOR_USER" ]; then
        TOR_USER="tor"
    fi
    
    HS_DIR="$TOR_DIR/$SERVICE_NAME"
    HOSTNAME_FILE="$HS_DIR/hostname"
    
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Configuring Tor hidden service..."
    
    # Create hidden service directory
    mkdir -p "$HS_DIR" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Failed to create hidden service directory"
        exit 1
    fi
    
    chmod 700 "$HS_DIR"
    chmod 755 "$TOR_DIR"
    
    if ! is_termux && [ "$EUID" -eq 0 ]; then
        chown -R "$TOR_USER:$TOR_USER" "$HS_DIR" 2>/dev/null
    fi
    
    # Backup original torrc
    if [ -f "$TORRC" ]; then
        cp "$TORRC" "${TORRC}.backup" 2>/dev/null
    fi
    
    # Remove existing hidden service configuration
    if [ -f "$TORRC" ]; then
        grep -v "^HiddenService" "$TORRC" | grep -v "^# TorHost Hidden Service" > "${TORRC}.tmp" 2>/dev/null
        mv "${TORRC}.tmp" "$TORRC" 2>/dev/null
    fi
    
    # Add new configuration
    {
        echo ""
        echo "# TorHost Hidden Service Configuration"
        echo "HiddenServiceDir $HS_DIR"
        echo "HiddenServiceVersion 3"
        echo "HiddenServicePort 80 127.0.0.1:$PORT"
        echo ""
    } >> "$TORRC"
    
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Updated torrc configuration."
    
    # Restart Tor
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Restarting Tor service..."
    if ! restart_tor; then
        echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Failed to restart Tor."
        exit 1
    fi
    
    # Wait for onion address
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Waiting for onion address..."
    
    for ((i=0; i<WAIT_TIME; i++)); do
        if [ -f "$HOSTNAME_FILE" ]; then
            ONION=$(cat "$HOSTNAME_FILE" 2>/dev/null | xargs)
            
            if validate_onion_address "$ONION"; then
                echo -e "\n${WHITE} ╔══════════════════════════════════════════════════════════════╗"
                echo -e "${WHITE} ║${GREEN}                    HIDDEN SERVICE READY                      ${WHITE}║"
                echo -e "${WHITE} ╠══════════════════════════════════════════════════════════════╣"
                echo -e "${WHITE}  ${GREEN}  Onion Address: ${CYAN}http://${ONION}                ${WHITE}"
                echo -e "${WHITE}  ${GREEN}  Local Port   : ${CYAN}${PORT}                                  ${WHITE}"
                echo -e "${WHITE} ╚══════════════════════════════════════════════════════════════╝${RESET}"
                echo -e "\n${WHITE} [${GREEN}+${WHITE}] ${GREEN}Make sure you have a service running on port ${PORT}"
                return
            fi
        fi
        sleep 1
    done
    
    echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Timed out waiting for onion address."
    exit 1
}

# Trap Ctrl+C
trap 'echo -e "\n${WHITE} [${RED}!${WHITE}] ${RED}Interrupted by user."; exit 1' INT

# Run main function
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
