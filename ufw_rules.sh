#!/bin/bash

# UFW Script - Automated Firewall Configuration
# =========================================================
#
# This script automates UFW (Uncomplicated Firewall) configuration with focus on security
# and ease of use. It configures specific rules for a home server environment
# with self hosted services like Plex and others.
#
# MAIN FEATURES:
# - Configuration of external rules (public ports): HTTP/HTTPS, Game Servers, etc.
# - Configuration of local rules by CIDR: SSH, HTTP/HTTPS, dashboards, etc.
# - Automatic Docker network detection to allow communication between containers
# - IPv4 and IPv6 support with basic CIDR validation
# - Dry-run mode to preview changes before applying
# - Safe reset of existing rules with confirmation
# - Integrated color system using .colors file
# - Prerequisites validation (UFW installed, sudo privileges)
# - Robust error handling with automatic cleanup
#
# MODULAR CONFIGURATION:
# - LOCAL_NETWORKS: defines local networks that can access internal services
# - EXTERNAL_RULES: defines public ports accessible externally
# - LOCAL_SERVICES: defines services accessible only by local networks
# - ENABLE_DOCKER_RULES: controls whether Docker rules should be configured
#
# CUSTOMIZATION:
# To adapt this script to your environment, edit the CSV configuration files.
# On first run, example files will be copied to create your configuration.
#
# USAGE: ./ufw_rules.sh [--dry-run] [--reset] [--force] [--docker-cidr CIDR]
#                       [--no-docker] [--show-config] [--help]

set -euo pipefail  # Abort on error, undefined variables and pipes with failure

# =============================
# ENVIRONMENT SETTINGS
# =============================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

# CSV file paths
LOCAL_NETWORKS_CSV="$CONFIG_DIR/local_networks.csv"
EXTERNAL_RULES_CSV="$CONFIG_DIR/external_rules.csv"
LOCAL_SERVICES_CSV="$CONFIG_DIR/local_services.csv"

# Arrays to store configuration loaded from CSV files
LOCAL_NETWORKS=()
EXTERNAL_RULES=()
LOCAL_SERVICES=()

# Script default settings
RESET_RULES=false
DRY_RUN=false
FORCE_YES=false
DOCKER_CIDR=""
ENABLE_DOCKER_RULES=true  # Defines whether Docker rules should be configured

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color definitions
Red='\033[0;31m'
Green='\033[0;32m'
Yellow='\033[0;33m'
BYellow='\033[1;33m'
Blue='\033[0;34m'
Purple='\033[0;35m'
Cyan='\033[0;36m'
White='\033[0;37m'
Color_Off='\033[0m'

# Function to display colored messages
log_info() { echo -e "${Blue}[INFO]${Color_Off} $1"; }
log_warn() { echo -e "${BYellow}[WARN]${Color_Off} $1"; }
log_error() { echo -e "${Red}[ERROR]${Color_Off} $1"; }
log_success() { echo -e "${Green}[SUCCESS]${Color_Off} $1"; }

# Function to ensure CSV files exist (copy from .example if needed)
ensure_csv_files() {
    local files_created=false

    # Create config directory if it doesn't exist
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_info "Creating config directory: $CONFIG_DIR"
        mkdir -p "$CONFIG_DIR"
    fi

    if [[ ! -f "$LOCAL_NETWORKS_CSV" && -f "${LOCAL_NETWORKS_CSV}.example" ]]; then
        log_info "Creating $LOCAL_NETWORKS_CSV from example file..."
        cp "${LOCAL_NETWORKS_CSV}.example" "$LOCAL_NETWORKS_CSV"
        files_created=true
    fi

    if [[ ! -f "$EXTERNAL_RULES_CSV" && -f "${EXTERNAL_RULES_CSV}.example" ]]; then
        log_info "Creating $EXTERNAL_RULES_CSV from example file..."
        cp "${EXTERNAL_RULES_CSV}.example" "$EXTERNAL_RULES_CSV"
        files_created=true
    fi

    if [[ ! -f "$LOCAL_SERVICES_CSV" && -f "${LOCAL_SERVICES_CSV}.example" ]]; then
        log_info "Creating $LOCAL_SERVICES_CSV from example file..."
        cp "${LOCAL_SERVICES_CSV}.example" "$LOCAL_SERVICES_CSV"
        files_created=true
    fi

    if [[ "$files_created" == true ]]; then
        echo
        log_warn "Configuration files were created from examples in $CONFIG_DIR"
        log_warn "Please review and customize them before running this script again."
        echo
        exit 0
    fi
}

# Function to load CSV file into array
# Format: "field1:field2:field3"
load_csv_to_array() {
    local csv_file="$1"
    local array_name="$2"

    if [[ ! -f "$csv_file" ]]; then
        log_error "CSV file not found: $csv_file"
        log_error "Please create it or copy from ${csv_file}.example"
        return 1
    fi

    local line_num=0
    while IFS=, read -r col1 col2 col3; do
        line_num=$((line_num + 1))

        # Skip header line
        if [[ $line_num -eq 1 ]]; then
            continue
        fi

        # Trim whitespace and carriage returns from columns
        col1=$(echo "$col1" | tr -d '\r' | xargs)
        col2=$(echo "$col2" | tr -d '\r' | xargs)
        col3=$(echo "$col3" | tr -d '\r' | xargs)

        # Skip empty lines
        if [[ -z "$col1" ]]; then
            continue
        fi

        # Build the entry based on number of columns
        if [[ -n "$col3" ]]; then
            # Three columns (port, protocol, description OR name, cidr, extra)
            eval "${array_name}+=(\"${col1}:${col2}:${col3}\")"
        elif [[ -n "$col2" ]]; then
            # Two columns (name, cidr)
            eval "${array_name}+=(\"${col1}:${col2}\")"
        fi
    done < "$csv_file"

    return 0
}

# Load configuration from CSV files
load_configuration() {
    log_info "Loading configuration from CSV files..."

    # Ensure CSV files exist (create from examples if needed)
    ensure_csv_files

    # Load local networks
    if load_csv_to_array "$LOCAL_NETWORKS_CSV" "LOCAL_NETWORKS"; then
        log_info "Loaded ${#LOCAL_NETWORKS[@]} local network(s)"
    else
        log_error "Failed to load local networks configuration"
        exit 1
    fi

    # Load external rules
    if load_csv_to_array "$EXTERNAL_RULES_CSV" "EXTERNAL_RULES"; then
        log_info "Loaded ${#EXTERNAL_RULES[@]} external rule(s)"
    else
        log_error "Failed to load external rules configuration"
        exit 1
    fi

    # Load local services
    if load_csv_to_array "$LOCAL_SERVICES_CSV" "LOCAL_SERVICES"; then
        log_info "Loaded ${#LOCAL_SERVICES[@]} local service(s)"
    else
        log_error "Failed to load local services configuration"
        exit 1
    fi

    echo
}

# Function to display current configuration
show_configuration() {
    echo
    log_info "Current script configuration:"
    echo "======================================"

    echo -e "${Blue}Local Networks:${Color_Off}"
    if [[ ${#LOCAL_NETWORKS[@]} -eq 0 ]]; then
        echo "  No networks configured"
    else
        for network in "${LOCAL_NETWORKS[@]}"; do
            IFS=':' read -r name cidr <<< "$network"
            echo "  - $name: $cidr"
        done
    fi

    echo
    echo -e "${Blue}External Rules (Public):${Color_Off}"
    if [[ ${#EXTERNAL_RULES[@]} -eq 0 ]]; then
        echo "  No external rules configured"
    else
        for rule in "${EXTERNAL_RULES[@]}"; do
            IFS=':' read -r port protocol description <<< "$rule"
            echo "  - $port/$protocol: $description"
        done
    fi

    echo
    echo -e "${Blue}Local Services:${Color_Off}"
    if [[ ${#LOCAL_SERVICES[@]} -eq 0 ]]; then
        echo "  No local services configured"
    else
        for service in "${LOCAL_SERVICES[@]}"; do
            IFS=':' read -r port protocol description <<< "$service"
            echo "  - $port/$protocol: $description"
        done
    fi

    echo
    echo -e "${Blue}Docker:${Color_Off}"
    if [[ "$ENABLE_DOCKER_RULES" == true ]]; then
        echo "  - Enabled (CIDR: ${DOCKER_CIDR:-"auto-detect"})"
    else
        echo "  - Disabled"
    fi
    echo
}

# Function to install command alias
install_alias() {
    # Prevent running as root
    if [[ $EUID -eq 0 ]]; then
        log_error "This command should NOT be run with sudo or as root"
        log_error "Run without sudo: ./ufw_rules.sh --install-alias"
        exit 1
    fi

    local bash_aliases="$HOME/.bash_aliases"
    local script_path="$(readlink -f "${BASH_SOURCE[0]}")"
    local alias_name="autoufw"
    local alias_line="alias $alias_name=\"sudo bash $script_path\""
    local comment_line="# UFW rules Automation Script (https://github.com/luiz-surian/autoufw)"

    log_info "Installing '$alias_name' command alias..."

    # Check if alias already exists
    if [[ -f "$bash_aliases" ]] && grep -q "alias $alias_name=" "$bash_aliases" 2>/dev/null; then
        log_warn "Alias '$alias_name' already exists in $bash_aliases"
        read -p "Update existing alias? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled"
            return 0
        fi

        # Remove old alias
        sed -i "/alias $alias_name=/d" "$bash_aliases"
        sed -i "\|# UFW rules Automation Script|d" "$bash_aliases"
    fi

    # Create .bash_aliases if it doesn't exist
    if [[ ! -f "$bash_aliases" ]]; then
        touch "$bash_aliases"
        log_info "Created $bash_aliases"
    fi

    # Add alias with comment
    echo "" >> "$bash_aliases"
    echo "$comment_line" >> "$bash_aliases"
    echo "$alias_line" >> "$bash_aliases"

    log_success "Alias installed successfully!"
    echo
    log_info "Script location: $script_path"
    log_info "Alias definition: $alias_line"
    echo
    log_warn "To activate the alias, run:"
    echo "  source ~/.bash_aliases"
    echo "Or restart your terminal session."
    echo
    log_info "After activation, you can use: $alias_name [options]"

    exit 0
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [options]
Parameterizable UFW script to configure firewall rules

Options:
    --reset         Reset all existing rules (DESTRUCTIVE!)
    --dry-run       Show what would be done without executing
    --force         Don't ask for confirmation (use with caution)
    --docker-cidr   Set custom CIDR for Docker (e.g.: 172.17.0.0/16)
    --no-docker     Disable Docker rules configuration
    --show-config   Display current configuration and exit
    --install-alias Install 'autoufw' command alias in ~/.bash_aliases
    -h, --help      Show this help

Configuration:
    To customize this script for your environment, edit the CSV files in config/:
    - config/local_networks.csv: local networks that can access services
    - config/external_rules.csv: public ports accessible externally
    - config/local_services.csv: services accessible only by local networks

    On first run, the script will create these files from .example templates.Examples:
    $0                      # Add rules using current configuration
    $0 --show-config        # Show configuration without executing
    $0 --dry-run            # Preview changes without applying
    $0 --reset --force      # Reset everything without asking confirmation
    $0 --no-docker          # Configure without Docker rules
    $0 --install-alias      # Install 'autoufw' command for easy access
EOF
}

# Processa argumentos da linha de comando
while [[ $# -gt 0 ]]; do
    case $1 in
        --reset)
            RESET_RULES=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_YES=true
            shift
            ;;
        --docker-cidr)
            DOCKER_CIDR="$2"
            shift 2
            ;;
        --no-docker)
            ENABLE_DOCKER_RULES=false
            shift
            ;;
        --show-config)
            load_configuration
            show_configuration
            exit 0
            ;;
        --install-alias)
            install_alias
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if ufw is installed
    if ! command -v ufw &> /dev/null; then
        log_error "UFW is not installed. Install with: sudo apt install ufw"
        exit 1
    fi

    # Check if running as root or has sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_error "This script needs sudo privileges"
        exit 1
    fi

    # Check if IPv6 is enabled in UFW
    if grep -q "IPV6=no" /etc/default/ufw 2>/dev/null; then
        log_warn "IPv6 is disabled in UFW. IPv6 rules may not work."
        log_warn "To enable, edit /etc/default/ufw and set IPV6=yes"
    fi

    log_success "Prerequisites OK"
}

# Function to detect Docker CIDR
detect_docker_cidr() {
    if [[ "$ENABLE_DOCKER_RULES" == false ]]; then
        log_info "Docker rules disabled"
        return
    fi

    if [[ -n "$DOCKER_CIDR" ]]; then
        log_info "Using custom Docker CIDR: $DOCKER_CIDR"
        return
    fi

    if command -v docker &> /dev/null && docker info &> /dev/null; then
        local detected_cidr
        detected_cidr=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "")

        if [[ -n "$detected_cidr" ]]; then
            DOCKER_CIDR="$detected_cidr"
            log_info "Docker CIDR detected: $DOCKER_CIDR"
        else
            DOCKER_CIDR="172.17.0.0/16"
            log_warn "Could not detect Docker CIDR. Using default: $DOCKER_CIDR"
        fi
    else
        DOCKER_CIDR="172.17.0.0/16"
        log_warn "Docker not detected. Using default CIDR: $DOCKER_CIDR"
    fi
}

# Unified function to execute UFW commands (with dry-run and comments support)
run_ufw() {
    local rule="$1"
    local comment="${2:-}"  # Optional comment

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -n "$comment" ]]; then
            echo "[DRY-RUN] sudo ufw $rule"
            echo "[DRY-RUN] # Comment: $comment"
        else
            echo "[DRY-RUN] sudo ufw $rule"
        fi
    else
        # Execute rule without comment (more compatible)
        log_info "Executing: ufw $rule"
        sudo ufw $rule

        # Log comment for reference only
        if [[ -n "$comment" ]]; then
            log_info "Comment: $comment"
        fi
    fi
}

# Function to confirm destructive action
confirm_action() {
    local message="$1"

    if [[ "$FORCE_YES" == true ]]; then
        return 0
    fi

    echo -e "${BYellow}$message${Color_Off}"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Function to reset UFW rules
reset_ufw_rules() {
    log_warn "WARNING: This operation will remove ALL existing UFW rules!"
    confirm_action "Are you sure you want to reset all rules?"

    log_info "Disabling UFW..."
    run_ufw "--force disable"

    log_info "Resetting rules..."
    run_ufw "--force reset"
}

# Function to add external rules (public ports)
add_external_rules() {
    if [[ ${#EXTERNAL_RULES[@]} -eq 0 ]]; then
        log_info "No external rules configured"
        return
    fi

    log_info "Adding external rules..."

    for rule in "${EXTERNAL_RULES[@]}"; do
        # Parse format "PORT:PROTOCOL:DESCRIPTION"
        IFS=':' read -r port protocol description <<< "$rule"

        if [[ -n "$port" && -n "$protocol" && -n "$description" ]]; then
            run_ufw "allow $port/$protocol" "$description"
        else
            log_warn "Malformed external rule ignored: $rule"
        fi
    done
}

# Function to add local rules for a specific network
add_local_rules_for_network() {
    local name="$1"
    local cidr="$2"

    log_info "Adding rules for $name ($cidr)"

    # Basic CIDR validation (IPv4 or IPv6)
    # IPv4: xxx.xxx.xxx.xxx/xx
    # IPv6: accepts various formats including compressed (::)
    local ipv4_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
    local ipv6_regex='^[0-9a-fA-F:]+/[0-9]{1,3}$'

    if [[ ! "$cidr" =~ $ipv4_regex ]] && [[ ! "$cidr" =~ $ipv6_regex ]]; then
        log_warn "Invalid CIDR format: '$cidr' - Skipping network $name"
        return
    fi

    # Apply all local services for this network
    for service in "${LOCAL_SERVICES[@]}"; do
        # Parse format "PORT:PROTOCOL:DESCRIPTION"
        IFS=':' read -r port protocol description <<< "$service"

        if [[ -n "$port" && -n "$protocol" && -n "$description" ]]; then
            run_ufw "allow from $cidr to any port $port proto $protocol" "$description ($name)"
        else
            log_warn "Malformed local service ignored: $service"
        fi
    done
}

# Function to add local rules for all configured networks
add_local_rules() {
    if [[ ${#LOCAL_NETWORKS[@]} -eq 0 ]]; then
        log_info "No local networks configured"
        return
    fi

    log_info "Configuring local rules..."

    # Process all local networks
    for network in "${LOCAL_NETWORKS[@]}"; do
        # Parse format "NAME:CIDR"
        IFS=':' read -r name cidr <<< "$network"

        if [[ -n "$name" && -n "$cidr" ]]; then
            add_local_rules_for_network "$name" "$cidr"
        else
            log_warn "Malformed local network ignored: $network"
        fi
    done

    # Add Docker rules if enabled
    if [[ "$ENABLE_DOCKER_RULES" == true && -n "$DOCKER_CIDR" ]]; then
        add_local_rules_for_network "Docker" "$DOCKER_CIDR"
    fi
}

# Function to check if rule already exists (for idempotency)
rule_exists() {
    local rule_pattern="$1"
    sudo ufw status | grep -q "$rule_pattern" 2>/dev/null
}



# Main function
main() {
    echo "UFW Script - Firewall Rules Configuration"
    echo "=========================================="

    # Load configuration from CSV files
    load_configuration

    # Display current configuration
    show_configuration

    # Check prerequisites
    check_prerequisites

    # Detect Docker CIDR
    detect_docker_cidr

    # Show current configuration if not dry-run
    if [[ "$DRY_RUN" == false ]]; then
        log_info "Current UFW status:"
        sudo ufw status verbose || log_warn "UFW may be disabled"
        echo
    fi

    # Reset if requested
    if [[ "$RESET_RULES" == true ]]; then
        reset_ufw_rules
        echo
    fi

    # Add external rules
    log_info "Configuring external rules..."
    add_external_rules
    echo

    # Add local rules
    add_local_rules
    echo

    # Enable UFW
    if [[ "$DRY_RUN" == false ]]; then
        log_info "Enabling UFW..."
        run_ufw "--force enable"

        echo
        log_info "Final UFW status:"
        sudo ufw status verbose
    else
        echo "[DRY-RUN] sudo ufw --force enable"
    fi

    echo
    log_success "Configuration completed!"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "This was a dry-run. No changes were applied."
        log_info "Run again without --dry-run to apply the changes."
    fi
}

# Trap for cleanup on error
trap 'log_error "Script interrupted. UFW may be in an inconsistent state."; exit 1' ERR INT TERM

# Execute main function
main "$@"
