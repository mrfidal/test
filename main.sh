#!/bin/bash

# Color codes
WHITE="\033[97m"
GREEN="\033[92m"
CYAN="\033[96m"
RED="\033[91m"
YELLOW="\033[93m"
BLUE="\033[94m"
MAGENTA="\033[95m"
RESET="\033[0m"

# Default values
DEFAULT_PORT=8080
SERVICE_NAME="hidden_service"
WAIT_TIME=120
BACKUP_DIR="/tmp/torhost_backups"
TERMUX_PREFIX="/data/data/com.termux/files"

# Detect if we're in Termux
is_termux() {
    [[ -d "$TERMUX_PREFIX" ]] || [[ "$PREFIX" == *"com.termux"* ]]
}

# Get Termux home directory properly
get_termux_home() {
    if is_termux; then
        echo "/data/data/com.termux/files/home"
    else
        echo "$HOME"
    fi
}

show_banner() {
    clear
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

# Run command with proper error handling
run() {
    local cmd="$1"
    local check="${2:-false}"
    local capture_output="${3:-true}"
    
    if [ "$check" = "true" ]; then
        if [ "$capture_output" = "true" ]; then
            eval "$cmd"
        else
            eval "$cmd" >/dev/null 2>&1
        fi
    else
        if [ "$capture_output" = "true" ]; then
            eval "$cmd" 2>/dev/null
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

# Check if we have root/sudo access
check_root() {
    if [ "$EUID" -eq 0 ]; then
        return 0
    elif command_exists sudo && sudo -n true 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Detect Tor user
detect_tor_user() {
    if is_termux; then
        echo "$(whoami)"
        return
    fi
    
    # Check common Tor usernames
    for user in "debian-tor" "tor"; do
        if id "$user" &>/dev/null; then
            echo "$user"
            return
        fi
    done
    
    # Try to get from running process
    local tor_user=$(ps aux | grep -E "[t]or " | head -1 | awk '{print $1}')
    if [ -n "$tor_user" ]; then
        echo "$tor_user"
        return
    fi
    
    # Default
    echo "tor"
}

# Get Tor directory paths
get_tor_paths() {
    if is_termux; then
        TOR_DIR="$PREFIX/var/lib/tor"
        TORRC="$PREFIX/etc/tor/torrc"
        TOR_LOG="$PREFIX/var/log/tor/log"
        TOR_BIN="$PREFIX/bin/tor"
    else
        TOR_DIR="/var/lib/tor"
        TORRC="/etc/tor/torrc"
        TOR_LOG="/var/log/tor/log"
        TOR_BIN="/usr/bin/tor"
        
        # Alternative paths
        [ -f "$TORRC" ] || TORRC="/etc/tor/torrc"
        [ -d "$TOR_DIR" ] || TOR_DIR="/var/lib/tor"
    fi
    
    echo "$TOR_DIR:$TORRC:$TOR_LOG:$TOR_BIN"
}

# Install Tor on different systems
install_tor() {
    if command_exists tor; then
        echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Tor is already installed.${RESET}"
        return 0
    fi
    
    echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Tor not found. Installing...${RESET}"
    
    if is_termux; then
        echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Installing Tor for Termux...${RESET}"
        pkg update -y && pkg upgrade -y
        pkg install tor -y
        pkg install nano -y
        pkg install openssl-tool -y
        
        # Create necessary directories
        mkdir -p $PREFIX/var/lib/tor
        mkdir -p $PREFIX/var/log/tor
        mkdir -p $PREFIX/etc/tor
        
        return $?
        
    elif command_exists apt && command_exists apt-get; then
        echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Detected Debian/Ubuntu based system${RESET}"
        if check_root; then
            apt update && apt install tor torsocks -y
        else
            sudo apt update && sudo apt install tor torsocks -y
        fi
        
    elif command_exists yum; then
        echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Detected RHEL/CentOS based system${RESET}"
        if check_root; then
            yum install epel-release -y
            yum install tor -y
        else
            sudo yum install epel-release -y
            sudo yum install tor -y
        fi
        
    elif command_exists dnf; then
        echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Detected Fedora based system${RESET}"
        if check_root; then
            dnf install tor -y
        else
            sudo dnf install tor -y
        fi
        
    elif command_exists pacman; then
        echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Detected Arch based system${RESET}"
        if check_root; then
            pacman -S tor --noconfirm
        else
            sudo pacman -S tor --noconfirm
        fi
        
    elif command_exists apk; then
        echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Detected Alpine Linux${RESET}"
        if check_root; then
            apk add tor
        else
            sudo apk add tor
        fi
        
    else
        echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Unsupported package manager.${RESET}"
        echo -e "${WHITE} [${YELLOW}!${WHITE}] ${YELLOW}Please install Tor manually:${RESET}"
        echo -e "${WHITE}     ${CYAN}https://www.torproject.org/download/${RESET}"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Tor installed successfully.${RESET}"
        return 0
    else
        echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Failed to install Tor.${RESET}"
        return 1
    fi
}

# Start/stop Tor service
manage_tor_service() {
    local action="$1"  # start, stop, restart, status
    
    if is_termux; then
        case "$action" in
            "start")
                echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Starting Tor in Termux...${RESET}"
                pkill -f "tor" 2>/dev/null
                sleep 2
                tor > /dev/null 2>&1 &
                sleep 5
                if pgrep -f "tor" >/dev/null; then
                    echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Tor started successfully.${RESET}"
                    return 0
                else
                    echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Failed to start Tor.${RESET}"
                    return 1
                fi
                ;;
            "stop")
                pkill -f "tor" 2>/dev/null
                sleep 2
                if ! pgrep -f "tor" >/dev/null; then
                    echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Tor stopped.${RESET}"
                    return 0
                fi
                ;;
            "restart")
                pkill -f "tor" 2>/dev/null
                sleep 2
                tor > /dev/null 2>&1 &
                sleep 5
                if pgrep -f "tor" >/dev/null; then
                    echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Tor restarted.${RESET}"
                    return 0
                fi
                return 1
                ;;
            "status")
                if pgrep -f "tor" >/dev/null; then
                    echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Tor is running.${RESET}"
                    return 0
                else
                    echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Tor is not running.${RESET}"
                    return 1
                fi
                ;;
        esac
    else
        # Systemd based systems
        if command_exists systemctl; then
            if check_root; then
                case "$action" in
                    "start")
                        systemctl start tor 2>/dev/null || systemctl start tor.service 2>/dev/null
                        ;;
                    "stop")
                        systemctl stop tor 2>/dev/null || systemctl stop tor.service 2>/dev/null
                        ;;
                    "restart")
                        systemctl restart tor 2>/dev/null || systemctl restart tor.service 2>/dev/null
                        ;;
                    "status")
                        systemctl is-active tor 2>/dev/null || systemctl is-active tor.service 2>/dev/null
                        return $?
                        ;;
                esac
            else
                case "$action" in
                    "start")
                        sudo systemctl start tor 2>/dev/null || sudo systemctl start tor.service 2>/dev/null
                        ;;
                    "stop")
                        sudo systemctl stop tor 2>/dev/null || sudo systemctl stop tor.service 2>/dev/null
                        ;;
                    "restart")
                        sudo systemctl restart tor 2>/dev/null || sudo systemctl restart tor.service 2>/dev/null
                        ;;
                    "status")
                        sudo systemctl is-active tor 2>/dev/null || sudo systemctl is-active tor.service 2>/dev/null
                        return $?
                        ;;
                esac
            fi
            
            sleep 3
            if [ "$action" != "status" ]; then
                if manage_tor_service "status"; then
                    echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Tor $action completed.${RESET}"
                    return 0
                else
                    echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Failed to $action Tor.${RESET}"
                    return 1
                fi
            fi
            
        # Init.d based systems
        elif [ -f /etc/init.d/tor ]; then
            if check_root; then
                /etc/init.d/tor "$action"
            else
                sudo /etc/init.d/tor "$action"
            fi
            sleep 3
            
        # Manual start
        else
            case "$action" in
                "start")
                    pkill tor 2>/dev/null
                    sleep 2
                    tor --runasdaemon 1 >/dev/null 2>&1 &
                    sleep 5
                    ;;
                "stop")
                    pkill tor 2>/dev/null
                    sleep 2
                    ;;
                "restart")
                    pkill tor 2>/dev/null
                    sleep 2
                    tor --runasdaemon 1 >/dev/null 2>&1 &
                    sleep 5
                    ;;
            esac
        fi
    fi
    
    # Verify Tor is running
    if [ "$action" = "start" ] || [ "$action" = "restart" ]; then
        sleep 5
        if check_tor_running; then
            return 0
        else
            return 1
        fi
    fi
    
    return 0
}

# Check if Tor is running
check_tor_running() {
    if is_termux; then
        pgrep -f "tor" >/dev/null 2>&1
        return $?
    fi
    
    # Try systemd first
    if command_exists systemctl; then
        if check_root; then
            systemctl is-active tor >/dev/null 2>&1 || systemctl is-active tor.service >/dev/null 2>&1
            if [ $? -eq 0 ]; then return 0; fi
        else
            sudo systemctl is-active tor >/dev/null 2>&1 || sudo systemctl is-active tor.service >/dev/null 2>&1
            if [ $? -eq 0 ]; then return 0; fi
        fi
    fi
    
    # Check process
    pgrep -x tor >/dev/null 2>&1
    return $?
}

# Validate onion address
validate_onion_address() {
    local onion="$1"
    
    if [ -z "$onion" ]; then
        return 1
    fi
    
    onion=$(echo "$onion" | tr -d '[:space:]')
    
    # Check if it ends with .onion
    if [[ "$onion" != *.onion ]]; then
        return 1
    fi
    
    # Remove .onion suffix and check length
    local onion_part="${onion%.onion}"
    
    # v3 onion addresses are 56 characters
    if [ ${#onion_part} -eq 56 ]; then
        return 0
    fi
    
    # v2 onion addresses are 16 characters
    if [ ${#onion_part} -eq 16 ]; then
        return 0
    fi
    
    return 1
}

# Delete old onion service
delete_old_onion() {
    echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Cleaning up old hidden service...${RESET}"
    
    local paths=$(get_tor_paths)
    local TOR_DIR=$(echo "$paths" | cut -d: -f1)
    local HS_DIR="$TOR_DIR/$SERVICE_NAME"
    
    mkdir -p "$BACKUP_DIR"
    
    if [ -d "$HS_DIR" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_path="$BACKUP_DIR/${SERVICE_NAME}_${timestamp}"
        
        echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Backing up old hidden service...${RESET}"
        
        if [ -f "$HS_DIR/hostname" ]; then
            local old_onion=$(cat "$HS_DIR/hostname" 2>/dev/null | xargs)
            echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Old Onion Address: ${CYAN}$old_onion${RESET}"
            echo "$old_onion" > "$backup_path.hostname"
        fi
        
        cp -r "$HS_DIR" "$backup_path" 2>/dev/null
        
        rm -rf "$HS_DIR"
        echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Old hidden service removed.${RESET}"
    else
        echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}No previous hidden service found.${RESET}"
    fi
    
    # Clean up old backups (keep last 5)
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(ls -1 "$BACKUP_DIR"/*.hostname 2>/dev/null | wc -l)
        if [ $backup_count -gt 5 ]; then
            echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Cleaning up old backups...${RESET}"
            ls -1t "$BACKUP_DIR"/*.hostname 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
            ls -1dt "$BACKUP_DIR"/${SERVICE_NAME}_* 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null
        fi
    fi
}

# Add custom configuration to torrc
add_custom_config() {
    local torrc="$1"
    local custom_text="$2"
    
    if [ -z "$custom_text" ]; then
        return 0
    fi
    
    echo -e "${WHITE} [${MAGENTA}+${WHITE}] ${MAGENTA}Adding custom configuration...${RESET}"
    
    # Remove previous custom configuration
    sed -i '/^# TORHOST CUSTOM CONFIG START/,/^# TORHOST CUSTOM CONFIG END/d' "$torrc" 2>/dev/null
    
    # Add new custom configuration
    {
        echo ""
        echo "# TORHOST CUSTOM CONFIG START"
        echo "# Added on: $(date)"
        echo "#"
        echo "$custom_text"
        echo "#"
        echo "# TORHOST CUSTOM CONFIG END"
        echo ""
    } >> "$torrc"
    
    echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Custom configuration added.${RESET}"
}

# Parse command line arguments
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
                    echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Invalid port number: $2${RESET}"
                    exit 1
                fi
                ;;
            --text)
                if [ -n "$2" ]; then
                    CUSTOM_TEXT="$2"
                    shift 2
                else
                    echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Custom text cannot be empty${RESET}"
                    exit 1
                fi
                ;;
            --text-file)
                if [ -f "$2" ]; then
                    CUSTOM_TEXT=$(cat "$2")
                    shift 2
                else
                    echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}File not found: $2${RESET}"
                    exit 1
                fi
                ;;
            --force-new)
                FORCE_NEW=true
                shift
                ;;
            --list-backups)
                echo -e "${WHITE} [${CYAN}i${WHITE}] ${CYAN}Available backups:${RESET}"
                if [ -d "$BACKUP_DIR" ]; then
                    echo -e "${WHITE}Backup directory: $BACKUP_DIR${RESET}"
                    ls -la "$BACKUP_DIR/" 2>/dev/null || echo -e "${WHITE}No backups found${RESET}"
                else
                    echo -e "${WHITE}No backup directory found${RESET}"
                fi
                exit 0
                ;;
            --restore-backup)
                if [ -n "$2" ]; then
                    local backup_path="$2"
                    if [ -d "$backup_path" ] || [ -f "${backup_path}.hostname" ]; then
                        echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Restoring from backup...${RESET}"
                        
                        local paths=$(get_tor_paths)
                        local TOR_DIR=$(echo "$paths" | cut -d: -f1)
                        local HS_DIR="$TOR_DIR/$SERVICE_NAME"
                        
                        # Stop Tor first
                        manage_tor_service "stop"
                        
                        # Remove existing service
                        rm -rf "$HS_DIR" 2>/dev/null
                        
                        # Restore backup
                        if [ -d "$backup_path" ]; then
                            cp -r "$backup_path" "$HS_DIR" 2>/dev/null
                            echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Backup directory restored.${RESET}"
                        fi
                        
                        if [ -f "${backup_path}.hostname" ]; then
                            cp "${backup_path}.hostname" "$HS_DIR/hostname" 2>/dev/null
                            echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Hostname file restored.${RESET}"
                        fi
                        
                        # Set permissions
                        local TOR_USER=$(detect_tor_user)
                        if ! is_termux && check_root; then
                            chown -R "$TOR_USER:$TOR_USER" "$HS_DIR" 2>/dev/null
                        fi
                        chmod 700 "$HS_DIR" 2>/dev/null
                        
                        # Start Tor
                        echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Starting Tor...${RESET}"
                        manage_tor_service "start"
                        
                        if [ -f "$HS_DIR/hostname" ]; then
                            local ONION=$(cat "$HS_DIR/hostname" 2>/dev/null | xargs)
                            echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Restored Onion Address: ${CYAN}http://$ONION${RESET}"
                        fi
                    else
                        echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Backup not found: $2${RESET}"
                        exit 1
                    fi
                else
                    echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Please specify backup path${RESET}"
                    exit 1
                fi
                exit 0
                ;;
            --help|-h)
                echo -e "${WHITE}Usage: $0 [OPTIONS]${RESET}"
                echo -e "${WHITE}Set up a Tor hidden service${RESET}"
                echo ""
                echo -e "${WHITE}Options:${RESET}"
                echo -e "  ${CYAN}--port PORT${RESET}          Local port to expose (default: 8080)"
                echo -e "  ${CYAN}--text \"TEXT\"${RESET}        Add custom text to torrc configuration"
                echo -e "  ${CYAN}--text-file FILE${RESET}     Add custom text from file to torrc"
                echo -e "  ${CYAN}--force-new${RESET}          Force creation of new onion address"
                echo -e "  ${CYAN}--list-backups${RESET}       List available backups"
                echo -e "  ${CYAN}--restore-backup DIR${RESET} Restore from backup directory"
                echo -e "  ${CYAN}--help, -h${RESET}           Show this help message"
                echo ""
                echo -e "${WHITE}Examples:${RESET}"
                echo -e "  ${YELLOW}$0 --port 80${RESET}"
                echo -e "  ${YELLOW}$0 --text \"SocksPort 9050\"${RESET}"
                echo -e "  ${YELLOW}$0 --text-file my_tor_config.txt${RESET}"
                echo -e "  ${YELLOW}$0 --force-new${RESET}"
                exit 0
                ;;
            *)
                echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Unknown option: $1${RESET}"
                echo -e "${WHITE}Use --help for usage information${RESET}"
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    show_banner
    
    parse_args "$@"
    
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Starting Tor Hidden Service setup...${RESET}"
    echo -e "${WHITE} [${YELLOW}⚠${WHITE}] ${YELLOW}This will delete old onion address and create a new one${RESET}"
    echo ""
    
    # Install Tor if not present
    if ! install_tor; then
        echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Cannot continue without Tor.${RESET}"
        exit 1
    fi
    
    # Get paths
    local paths=$(get_tor_paths)
    local TOR_DIR=$(echo "$paths" | cut -d: -f1)
    local TORRC=$(echo "$paths" | cut -d: -f2)
    local TOR_LOG=$(echo "$paths" | cut -d: -f3)
    local TOR_BIN=$(echo "$paths" | cut -d: -f4)
    
    # Create directories if they don't exist
    if is_termux; then
        mkdir -p "$PREFIX/var/lib/tor"
        mkdir -p "$PREFIX/var/log/tor"
        mkdir -p "$PREFIX/etc/tor"
    fi
    
    # Check if Tor is running
    if ! check_tor_running; then
        echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Tor is not running. Starting it...${RESET}"
        if ! manage_tor_service "start"; then
            echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Failed to start Tor.${RESET}"
            exit 1
        fi
    else
        echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Tor is already running.${RESET}"
    fi
    
    # Delete old onion service
    delete_old_onion
    
    # Stop Tor before making changes
    echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Stopping Tor to apply changes...${RESET}"
    manage_tor_service "stop"
    
    # Create hidden service directory
    local HS_DIR="$TOR_DIR/$SERVICE_NAME"
    local HOSTNAME_FILE="$HS_DIR/hostname"
    
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Configuring new Tor hidden service...${RESET}"
    
    # Create directory with proper permissions
    mkdir -p "$HS_DIR" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Failed to create hidden service directory${RESET}"
        exit 1
    fi
    
    chmod 700 "$HS_DIR"
    
    # Set ownership
    if ! is_termux; then
        local TOR_USER=$(detect_tor_user)
        if check_root; then
            chown -R "$TOR_USER:$TOR_USER" "$HS_DIR" 2>/dev/null
            chown -R "$TOR_USER:$TOR_USER" "$TOR_DIR" 2>/dev/null
        fi
    fi
    
    # Backup original torrc
    if [ -f "$TORRC" ]; then
        cp "$TORRC" "${TORRC}.backup.$(date +%s)" 2>/dev/null
        echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}Backed up torrc configuration.${RESET}"
    fi
    
    # Create or update torrc
    if [ ! -f "$TORRC" ]; then
        echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Creating new torrc file...${RESET}"
        touch "$TORRC"
    fi
    
    # Remove existing hidden service configuration
    if [ -f "$TORRC" ]; then
        grep -v "^HiddenServiceDir $HS_DIR" "$TORRC" | \
        grep -v "^HiddenServicePort" | \
        grep -v "^# TORHOST" > "${TORRC}.tmp" 2>/dev/null
        
        # Clean up empty lines
        sed -i '/^$/N;/^\n$/D' "${TORRC}.tmp" 2>/dev/null
        
        mv "${TORRC}.tmp" "$TORRC" 2>/dev/null
    fi
    
    # Add hidden service configuration
    {
        echo ""
        echo "# TORHOST HIDDEN SERVICE CONFIGURATION"
        echo "# Created on: $(date)"
        echo "#"
        echo "HiddenServiceDir $HS_DIR"
        echo "HiddenServiceVersion 3"
        echo "HiddenServicePort 80 127.0.0.1:$PORT"
        echo "#"
        echo "# TORHOST CONFIGURATION END"
        echo ""
    } >> "$TORRC"
    
    # Add custom configuration if specified
    if [ -n "$CUSTOM_TEXT" ]; then
        add_custom_config "$TORRC" "$CUSTOM_TEXT"
    fi
    
    echo -e "${WHITE} [${GREEN}✓${WHITE}] ${GREEN}torrc configuration updated.${RESET}"
    
    # Start Tor
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Starting Tor with new configuration...${RESET}"
    if ! manage_tor_service "start"; then
        echo -e "${WHITE} [${RED}✗${WHITE}] ${RED}Failed to start Tor.${RESET}"
        echo -e "${WHITE} [${YELLOW}!${WHITE}] ${YELLOW}Check Tor logs: $TOR_LOG${RESET}"
        exit 1
    fi
    
    echo -e "${WHITE} [${GREEN}+${WHITE}] ${GREEN}Generating new onion address...${RESET}"
    echo -e "${WHITE} [${YELLOW}⚠${WHITE}] ${YELLOW}This may take up to ${WAIT_TIME} seconds...${RESET}"
    echo ""
    
    # Wait for onion address generation
    local onion_found=false
    for ((i=0; i<WAIT_TIME; i++)); do
        if [ -f "$HOSTNAME_FILE" ]; then
            local ONION=$(cat "$HOSTNAME_FILE" 2>/dev/null | xargs)
            
            if validate_onion_address "$ONION"; then
                onion_found=true
                
                # Display success banner
                clear
                show_banner
                echo -e "${WHITE} ╔══════════════════════════════════════════════════════════════╗"
                echo -e "${WHITE} ║${GREEN}                    HIDDEN SERVICE READY                     ${WHITE}║"
                echo -e "${WHITE} ╠══════════════════════════════════════════════════════════════╣"
                echo -e "${WHITE} ║                                                              ║"
                echo -e "${WHITE} ║  ${GREEN}🔗 Onion Address: ${CYAN}http://$ONION${WHITE}               ║"
                echo -e "${WHITE} ║  ${GREEN}📡 Local Port   : ${CYAN}$PORT${WHITE}                                     ║"
                echo -e "${WHITE} ║  ${GREEN}📂 Service Name : ${CYAN}$SERVICE_NAME${WHITE}                             ║"
                if [ -n "$CUSTOM_TEXT" ]; then
                    echo -e "${WHITE} ║  ${GREEN}⚙️  Custom Config: ${CYAN}Enabled${WHITE}                                 ║"
                fi
                echo -e "${WHITE} ║                                                              ║"
                echo -e "${WHITE} ╠══════════════════════════════════════════════════════════════╣"
                echo -e "${WHITE} ║${YELLOW}          Note: Make sure a service is running on port $PORT       ${WHITE}║"
                echo -e "${WHITE} ╚══════════════════════════════════════════════════════════════╝${RESET}"
                echo ""
                
                # Save onion address
                mkdir -p "$BACKUP_DIR"
                echo "$ONION" > "$BACKUP_DIR/last_onion.txt"
                echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Onion address saved to: $BACKUP_DIR/last_onion.txt${RESET}"
                echo ""
                
                # Test the onion service
                echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Testing hidden service...${RESET}"
                sleep 3
                
                return 0
            fi
        fi
        
        # Show progress
        if [ $((i % 10)) -eq 0 ]; then
            local progress=$((i * 100 / WAIT_TIME))
            echo -ne "${WHITE} [${YELLOW}…${WHITE}] ${YELLOW}Waiting... ${i}/${WAIT_TIME}s (${progress}%)${RESET}\r"
        fi
        sleep 1
    done
    
    if [ "$onion_found" = false ]; then
        echo -e "\n${WHITE} [${RED}✗${WHITE}] ${RED}Timed out waiting for onion address generation.${RESET}"
        echo -e "${WHITE} [${YELLOW}!${WHITE}] ${YELLOW}Possible issues:${RESET}"
        echo -e "${WHITE}     ${YELLOW}1. Check Tor logs: $TOR_LOG${RESET}"
        echo -e "${WHITE}     ${YELLOW}2. Verify Tor is running: $0 --check${RESET}"
        echo -e "${WHITE}     ${YELLOW}3. Check permissions on $HS_DIR${RESET}"
        
        # Show last few lines of Tor log
        if [ -f "$TOR_LOG" ]; then
            echo -e "\n${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Last 10 lines of Tor log:${RESET}"
            tail -10 "$TOR_LOG" 2>/dev/null || echo "Cannot read log file"
        fi
    fi
    
    exit 1
}

# Additional utility functions
check_dependencies() {
    echo -e "${WHITE} [${BLUE}i${WHITE}] ${BLUE}Checking dependencies...${RESET}"
    
    local deps=("curl" "wget")
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            echo -e "${WHITE} [${YELLOW}+${WHITE}] ${YELLOW}Installing $dep...${RESET}"
            if is_termux; then
                pkg install "$dep" -y
            elif check_root; then
                apt install "$dep" -y 2>/dev/null || yum install "$dep" -y 2>/dev/null
            fi
        fi
    done
}

# Set trap for Ctrl+C
trap 'echo -e "\n${WHITE} [${RED}✗${WHITE}] ${RED}Script interrupted by user.${RESET}"; exit 1' INT

# Run main function
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    # Check if running with bash
    if [ -z "$BASH_VERSION" ]; then
        echo -e "${RED}Please run this script with bash: bash $0${RESET}"
        exit 1
    fi
    
    main "$@"
fi
