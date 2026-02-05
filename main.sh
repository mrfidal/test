#!/bin/bash

# Colors
WHITE="\033[97m"
GREEN="\033[92m"
CYAN="\033[96m"
RED="\033[91m"
YELLOW="\033[93m"
BLUE="\033[94m"
MAGENTA="\033[95m"
RESET="\033[0m"

# Defaults
DEFAULT_PORT=8080
SERVICE_NAME="hidden_service"
WAIT_TIME=90
BACKUP_DIR="/tmp/torhost_backups"

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
        if systemctl list-unit-files 2>/dev/null | grep -q "$svc"; then
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

# Delete old onion service and create backup
delete_old_onion() {
    echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Cleaning up old hidden service..."
    
    # Determine paths
    if is_termux; then
        TOR_DIR="$HOME/../usr/var/lib/tor"
    else
        TOR_DIR="/var/lib/tor"
    fi
    
    HS_DIR="$TOR_DIR/$SERVICE_NAME"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Backup existing hidden service if it exists
    if [ -d "$HS_DIR" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_path="$BACKUP_DIR/${SERVICE_NAME}_${timestamp}"
        
        echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Backing up old hidden service..."
        
        # Backup hostname file if it exists
        if [ -f "$HS_DIR/hostname" ]; then
            local old_onion=$(cat "$HS_DIR/hostname" 2>/dev/null | xargs)
            echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Old Onion Address: ${CYAN}$old_onion${RESET}"
            echo "$old_onion" > "$backup_path.hostname"
        fi
        
        # Backup the entire directory
        cp -r "$HS_DIR" "$backup_path" 2>/dev/null
        
        # Remove the old hidden service
        rm -rf "$HS_DIR"
        echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Old hidden service removed."
    else
        echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}No previous hidden service found."
    fi
    
    # Clean up old backups (keep last 5)
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(ls -1d "$BACKUP_DIR"/* 2>/dev/null | wc -l)
        if [ $backup_count -gt 5 ]; then
            echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Cleaning up old backups..."
            ls -1d "$BACKUP_DIR"/* 2>/dev/null | head -n -5 | xargs rm -rf 2>/dev/null
        fi
    fi
}

# Add custom text to torrc
add_custom_text() {
    local torrc="$1"
    local custom_text="$2"
    
    if [ -z "$custom_text" ]; then
        return 0
    fi
    
    echo -e "${WHITE} [${MAGENTA}+${WHITE}] ${MAGENTA}Adding custom configuration..."
    
    # Remove any previous custom text from this script
    sed -i '/^# CUSTOM TEXT - TORHOST SCRIPT/,/^# END CUSTOM TEXT/d' "$torrc" 2>/dev/null
    
    # Add the new custom text
    {
        echo ""
        echo "# CUSTOM TEXT - TORHOST SCRIPT"
        echo "# Added on: $(date)"
        echo "$custom_text"
        echo "# END CUSTOM TEXT"
        echo ""
    } >> "$torrc"
    
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Custom configuration added."
}

# Parse arguments
parse_args() {
    PORT="$DEFAULT_PORT"
    CUSTOM_TEXT=""
    FORCE_NEW=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --port)
                if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] && [ "$2" -le 65535 ]; then
                    PORT="$2"
                    shift 2
                else
                    echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Invalid port number: $2"
                    exit 1
                fi
                ;;
            --text)
                if [ -n "$2" ]; then
                    CUSTOM_TEXT="$2"
                    shift 2
                else
                    echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Custom text cannot be empty"
                    exit 1
                fi
                ;;
            --text-file)
                if [ -f "$2" ]; then
                    CUSTOM_TEXT=$(cat "$2")
                    shift 2
                else
                    echo -e "${WHITE} [${RED}!${WHITE}] ${RED}File not found: $2"
                    exit 1
                fi
                ;;
            --force-new)
                FORCE_NEW=true
                shift
                ;;
            --list-backups)
                echo -e "${WHITE} [${CYAN}i${WHITE}] ${CYAN}Available backups:"
                if [ -d "$BACKUP_DIR" ]; then
                    ls -la "$BACKUP_DIR/" 2>/dev/null || echo "No backups found"
                else
                    echo "No backup directory found"
                fi
                exit 0
                ;;
            --restore-backup)
                if [ -d "$2" ] || [ -f "$2.hostname" ]; then
                    echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Restoring from backup..."
                    # Determine paths
                    if is_termux; then
                        TOR_DIR="$HOME/../usr/var/lib/tor"
                    else
                        TOR_DIR="/var/lib/tor"
                    fi
                    HS_DIR="$TOR_DIR/$SERVICE_NAME"
                    
                    # Remove current if exists
                    rm -rf "$HS_DIR" 2>/dev/null
                    
                    # Restore from backup
                    if [ -d "$2" ]; then
                        cp -r "$2" "$HS_DIR" 2>/dev/null
                    fi
                    
                    # Set proper permissions
                    TOR_USER=$(detect_tor_user)
                    if ! is_termux && [ "$EUID" -eq 0 ]; then
                        chown -R "$TOR_USER:$TOR_USER" "$HS_DIR" 2>/dev/null
                    fi
                    chmod 700 "$HS_DIR" 2>/dev/null
                    
                    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Backup restored. Restarting Tor..."
                    restart_tor
                    
                    if [ -f "$HS_DIR/hostname" ]; then
                        ONION=$(cat "$HS_DIR/hostname" 2>/dev/null | xargs)
                        echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Restored Onion Address: ${CYAN}http://$ONION${RESET}"
                    fi
                else
                    echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Backup not found: $2"
                fi
                exit 0
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Set up a Tor hidden service (deletes old and creates new)"
                echo ""
                echo "Options:"
                echo "  --port PORT          Local port to expose (default: 8080)"
                echo "  --text \"TEXT\"        Add custom text to torrc configuration"
                echo "  --text-file FILE     Add custom text from file to torrc"
                echo "  --force-new          Force creation of new onion address"
                echo "  --list-backups       List available backups"
                echo "  --restore-backup DIR Restore from backup directory"
                echo "  --help, -h           Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 --port 80"
                echo "  $0 --text \"SocksPort 9050\""
                echo "  $0 --text-file my_tor_config.txt"
                echo "  $0 --force-new"
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
    echo -e "${WHITE} [${YELLOW}⚠${WHITE}] ${YELLOW}This will delete old onion address and create a new one${RESET}"
    
    # Require sudo
    require_sudo "$@"
    
    # Install Tor
    if ! install_tor; then
        echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Cannot continue without Tor."
        exit 1
    fi
    
    # Delete old onion service
    delete_old_onion
    
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
    
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Configuring new Tor hidden service..."
    
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
        cp "$TORRC" "${TORRC}.backup.$(date +%s)" 2>/dev/null
    fi
    
    # Remove existing hidden service configuration
    if [ -f "$TORRC" ]; then
        # Remove only the hidden service config for our service
        grep -v "^HiddenServiceDir $HS_DIR" "$TORRC" | \
        grep -v "^HiddenServicePort 80 127.0.0.1:" | \
        grep -v "^HiddenServiceVersion 3" | \
        grep -v "^# TorHost Hidden Service" > "${TORRC}.tmp" 2>/dev/null
        
        # Remove empty lines at end
        sed -i '/^$/N;/^\n$/D' "${TORRC}.tmp" 2>/dev/null
        
        mv "${TORRC}.tmp" "$TORRC" 2>/dev/null
    fi
    
    # Add new configuration
    {
        echo ""
        echo "# TorHost Hidden Service Configuration"
        echo "# Created on: $(date)"
        echo "HiddenServiceDir $HS_DIR"
        echo "HiddenServiceVersion 3"
        echo "HiddenServicePort 80 127.0.0.1:$PORT"
        echo ""
    } >> "$TORRC"
    
    # Add custom text if provided
    if [ -n "$CUSTOM_TEXT" ]; then
        add_custom_text "$TORRC" "$CUSTOM_TEXT"
    fi
    
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Updated torrc configuration."
    
    # Restart Tor
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Restarting Tor service..."
    if ! restart_tor; then
        echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Failed to restart Tor."
        exit 1
    fi
    
    # Wait for new onion address
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Generating new onion address..."
    echo -e "${WHITE} [${YELLOW}⚠${WHITE}] ${YELLOW}This may take up to ${WAIT_TIME} seconds...${RESET}"
    
    for ((i=0; i<WAIT_TIME; i++)); do
        if [ -f "$HOSTNAME_FILE" ]; then
            ONION=$(cat "$HOSTNAME_FILE" 2>/dev/null | xargs)
            
            if validate_onion_address "$ONION"; then
                echo -e "\n${WHITE} ╔══════════════════════════════════════════════════════════════╗"
                echo -e "${WHITE} ║${GREEN}                    NEW HIDDEN SERVICE READY                   ${WHITE}║"
                echo -e "${WHITE} ╠══════════════════════════════════════════════════════════════╣"
                echo -e "${WHITE}  ${GREEN}  New Onion Address: ${CYAN}http://${ONION}                ${WHITE}"
                echo -e "${WHITE}  ${GREEN}  Local Port       : ${CYAN}${PORT}                                  ${WHITE}"
                if [ -n "$CUSTOM_TEXT" ]; then
                    echo -e "${WHITE}  ${GREEN}  Custom Config    : ${CYAN}Added${WHITE}                                    "
                fi
                echo -e "${WHITE} ╚══════════════════════════════════════════════════════════════╝${RESET}"
                echo -e "\n${WHITE} [${GREEN}+${WHITE}] ${GREEN}Make sure you have a service running on port ${PORT}"
                echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Old onion address has been backed up"
                
                # Save new onion to backup directory for reference
                mkdir -p "$BACKUP_DIR"
                echo "$ONION" > "$BACKUP_DIR/last_onion.txt"
                
                return
            fi
        fi
        
        # Show progress
        if [ $((i % 10)) -eq 0 ]; then
            echo -ne "${WHITE} [${YELLOW}…${WHITE}] ${YELLOW}Waiting... ${i}/${WAIT_TIME} seconds${RESET}\r"
        fi
        sleep 1
    done
    
    echo -e "${WHITE} [${RED}!${WHITE}] ${RED}Timed out waiting for new onion address."
    echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Check Tor logs for errors:"
    echo -e "${WHITE}     ${YELLOW}Termux: ~/../usr/var/log/tor/log"
    echo -e "${WHITE}     ${YELLOW}Other: /var/log/tor/log${RESET}"
    exit 1
}

# Trap Ctrl+C
trap 'echo -e "\n${WHITE} [${RED}!${WHITE}] ${RED}Interrupted by user."; exit 1' INT

# Run main function
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
