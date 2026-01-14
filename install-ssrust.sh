#!/bin/bash

# Shadowsocks-Rust Installation Script
# Supports: install, update, uninstall, start, stop, restart, enable, disable

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/shadowsocks-rust"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_NAME="shadowsocks-rust"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
GITHUB_REPO="shadowsocks/shadowsocks-rust"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# Print functions
print_colored() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

print_header() {
    local message="$1"
    echo ""
    echo -e "${BOLD}${BLUE}===========================================================${NC}"
    echo -e "${BOLD}${BLUE}  $message${NC}"
    echo -e "${BOLD}${BLUE}===========================================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

print_info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Detect system architecture
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Get latest version from GitHub API
get_latest_version() {
    local version
    version=$(curl -s "$GITHUB_API" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$version" ]; then
        print_error "Failed to get latest version from GitHub API"
        exit 1
    fi
    echo "$version"
}

# Get current installed version
get_installed_version() {
    if [ -f "$INSTALL_DIR/ssserver" ]; then
        "$INSTALL_DIR/ssserver" --version 2>/dev/null | head -1 | awk '{print $2}'
    else
        echo ""
    fi
}

# Check required tools
check_requirements() {
    local missing_tools=()

    for tool in curl wget tar openssl qrencode; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_info "Installing required tools: ${missing_tools[*]}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y "${missing_tools[@]}"
        elif command -v yum &> /dev/null; then
            yum install -y epel-release && yum install -y "${missing_tools[@]}"
        elif command -v dnf &> /dev/null; then
            dnf install -y epel-release && dnf install -y "${missing_tools[@]}"
        else
            print_error "Cannot install required tools. Please install manually: ${missing_tools[*]}"
            exit 1
        fi
    fi
}

# Get server's public IPv4 address
get_ipv4() {
    curl -s -4 --connect-timeout 5 ifconfig.me 2>/dev/null || \
    curl -s -4 --connect-timeout 5 ip.sb 2>/dev/null || \
    curl -s -4 --connect-timeout 5 ipinfo.io/ip 2>/dev/null || \
    echo "YOUR_SERVER_IP"
}

# Generate random password using openssl (32 bytes base64)
generate_password() {
    openssl rand -base64 32
}

# Generate random string
generate_random_string() {
    local length=${1:-8}
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "$length" | head -n 1
}

# URL encode a string
url_encode() {
    local string="$1"
    local length="${#string}"
    local encoded=""

    for (( i=0; i<length; i++ )); do
        local c="${string:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            *) encoded+=$(printf '%%%02X' "'$c") ;;
        esac
    done

    echo "$encoded"
}

# Base64 encode (URL-safe without padding for SS URI)
base64_encode() {
    echo -n "$1" | base64 | tr -d '\n'
}

# Base64 encode URL-safe (for SIP002 format)
base64_url_encode() {
    echo -n "$1" | base64 | tr '+/' '-_' | tr -d '=\n'
}

# Generate SS URI links
generate_ss_uri() {
    local method="$1"
    local password="$2"
    local server_ip="$3"
    local port="$4"
    local tag="$5"

    # URL encode the password
    local encoded_password=$(url_encode "$password")
    local encoded_tag=$(url_encode "$tag")

    # Format 1: SIP002 (ss://BASE64(method:password)@host:port#tag)
    local user_info="${method}:${password}"
    local user_info_base64=$(base64_url_encode "$user_info")
    local sip002_uri="ss://${user_info_base64}@${server_ip}:${port}#${encoded_tag}"

    # Format 2: Plain format (ss://method:password@host:port#tag)
    local plain_uri="ss://${method}:${encoded_password}@${server_ip}:${port}#${encoded_tag}"

    # Format 3: Legacy base64 (ss://BASE64(method:password@host:port)#tag)
    local full_info="${method}:${password}@${server_ip}:${port}"
    local full_base64=$(base64_encode "$full_info")
    local legacy_uri="ss://${full_base64}#${encoded_tag}"

    echo "SIP002_URI=$sip002_uri"
    echo "PLAIN_URI=$plain_uri"
    echo "LEGACY_URI=$legacy_uri"
}

# Download and install shadowsocks-rust
install_ssrust() {
    print_header "Installing Shadowsocks-Rust"

    # Check requirements
    check_requirements

    # Detect architecture
    local arch=$(detect_arch)
    print_info "Detected architecture: $arch"

    # Get latest version
    print_info "Fetching latest version..."
    local version=$(get_latest_version)
    print_info "Latest version: $version"

    # Build download URL (using musl for better compatibility)
    local filename="shadowsocks-${version}.${arch}-unknown-linux-musl.tar.xz"
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/${filename}"

    print_info "Downloading from: $download_url"

    # Create temp directory
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    # Download
    if ! wget -q --show-progress "$download_url" -O "$filename"; then
        print_error "Failed to download shadowsocks-rust"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Extract
    print_info "Extracting..."
    if ! tar -xf "$filename"; then
        print_error "Failed to extract archive"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Stop service if running
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        print_info "Stopping existing service..."
        systemctl stop "$SERVICE_NAME"
    fi

    # Install binary
    print_info "Installing ssserver to $INSTALL_DIR..."
    cp ssserver "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/ssserver"

    # Clean up
    cd /
    rm -rf "$temp_dir"

    print_success "Shadowsocks-Rust $version installed successfully"
}

# Create configuration file
create_config() {
    print_header "Creating Configuration"

    # Create config directory
    mkdir -p "$CONFIG_DIR"

    # Ask for port
    local default_port=8388
    read -p "$(echo -e "${CYAN}Enter server port (default: $default_port): ${NC}")" input_port
    local port=${input_port:-$default_port}

    # Ask for encryption method
    echo ""
    echo -e "${BOLD}Select encryption method:${NC}"
    echo -e "${GREEN}1)${NC} 2022-blake3-aes-256-gcm ${YELLOW}(Recommended - AEAD-2022)${NC}"
    echo -e "${GREEN}2)${NC} 2022-blake3-aes-128-gcm"
    echo -e "${GREEN}3)${NC} 2022-blake3-chacha20-poly1305"
    echo -e "${GREEN}4)${NC} chacha20-ietf-poly1305 ${YELLOW}(Legacy)${NC}"
    echo -e "${GREEN}5)${NC} aes-256-gcm ${YELLOW}(Legacy)${NC}"
    echo ""
    read -p "$(echo -e "${CYAN}Enter your choice (1-5, default: 1): ${NC}")" method_choice

    local method
    case "${method_choice:-1}" in
        1) method="2022-blake3-aes-256-gcm" ;;
        2) method="2022-blake3-aes-128-gcm" ;;
        3) method="2022-blake3-chacha20-poly1305" ;;
        4) method="chacha20-ietf-poly1305" ;;
        5) method="aes-256-gcm" ;;
        *) method="2022-blake3-aes-256-gcm" ;;
    esac

    # Generate password
    local password=$(generate_password)

    # Ask for node name/tag
    echo ""
    read -p "$(echo -e "${CYAN}Enter node name/tag (leave empty for random): ${NC}")" node_tag
    if [ -z "$node_tag" ]; then
        node_tag="SS-$(generate_random_string 6)"
    fi

    # Create config file
    cat > "$CONFIG_FILE" << EOF
{
    "server": "0.0.0.0",
    "server_port": $port,
    "password": "$password",
    "method": "$method",
    "mode": "tcp_and_udp",
    "fast_open": true
}
EOF

    print_success "Configuration created at $CONFIG_FILE"

    # Store tag for later use
    echo "$node_tag" > "$CONFIG_DIR/.node_tag"
}

# Configure firewall to allow the port
configure_firewall() {
    local port=$(grep '"server_port"' "$CONFIG_FILE" | grep -oE '[0-9]+')

    if command -v ufw &> /dev/null; then
        print_info "Configuring UFW firewall..."
        ufw allow "$port" > /dev/null 2>&1
        print_success "UFW: Port $port allowed"
    else
        print_info "UFW not found, skipping firewall configuration"
    fi
}

# Enable TCP Fast Open (TFO) at system level
enable_tfo() {
    print_info "Enabling TCP Fast Open (TFO)..."

    local TFO_SETTING="net.ipv4.tcp_fastopen = 3"
    local SYSCTL_CONF="/etc/sysctl.conf"

    # Check if TFO is already configured
    if grep -q "^net.ipv4.tcp_fastopen" "$SYSCTL_CONF" 2>/dev/null; then
        # Update existing setting
        sed -i 's/^net.ipv4.tcp_fastopen.*/'"$TFO_SETTING"'/' "$SYSCTL_CONF"
        print_info "Updated existing TFO setting in $SYSCTL_CONF"
    else
        # Append new setting
        echo "$TFO_SETTING" >> "$SYSCTL_CONF"
        print_info "Added TFO setting to $SYSCTL_CONF"
    fi

    # Apply the setting
    sysctl -p > /dev/null 2>&1
    print_success "TFO enabled successfully"
}

# Create systemd service
create_service() {
    print_header "Creating Systemd Service"

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Shadowsocks-Rust Server
Documentation=https://github.com/shadowsocks/shadowsocks-rust
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/ssserver -c $CONFIG_FILE
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload

    print_success "Systemd service created"
}

# Display connection information
show_connection_info() {
    print_header "Connection Information"

    # Read config
    local port=$(grep '"server_port"' "$CONFIG_FILE" | grep -oE '[0-9]+')
    local password=$(grep '"password"' "$CONFIG_FILE" | sed 's/.*: *"\([^"]*\)".*/\1/')
    local method=$(grep '"method"' "$CONFIG_FILE" | sed 's/.*: *"\([^"]*\)".*/\1/')
    local node_tag=$(cat "$CONFIG_DIR/.node_tag" 2>/dev/null || echo "Shadowsocks")

    # Get server IP
    local server_ip=$(get_ipv4)

    echo -e "${BOLD}Server Address:${NC} $server_ip"
    echo -e "${BOLD}Server Port:${NC} $port"
    echo -e "${BOLD}Password:${NC} $password"
    echo -e "${BOLD}Encryption:${NC} $method"
    echo -e "${BOLD}Node Tag:${NC} $node_tag"

    # Generate URIs
    print_header "Connection URIs"

    local uri_output=$(generate_ss_uri "$method" "$password" "$server_ip" "$port" "$node_tag")

    local sip002_uri=$(echo "$uri_output" | grep "SIP002_URI=" | cut -d'=' -f2-)
    local plain_uri=$(echo "$uri_output" | grep "PLAIN_URI=" | cut -d'=' -f2-)
    local legacy_uri=$(echo "$uri_output" | grep "LEGACY_URI=" | cut -d'=' -f2-)

    echo -e "${BOLD}SIP002 Format (Recommended):${NC}"
    echo -e "${GREEN}$sip002_uri${NC}"
    echo ""
    echo -e "${BOLD}Plain Format:${NC}"
    echo -e "${YELLOW}$plain_uri${NC}"
    echo ""
    echo -e "${BOLD}Legacy Base64 Format:${NC}"
    echo -e "${CYAN}$legacy_uri${NC}"

    # Generate QR code
    print_header "QR Code (SIP002 Format)"
    if command -v qrencode &> /dev/null; then
        qrencode -t UTF8 "$sip002_uri"
    else
        print_warning "qrencode not found, QR code cannot be displayed"
    fi

    echo -e "${BLUE}===========================================================${NC}"
}

# Start service
start_service() {
    print_info "Starting $SERVICE_NAME..."
    systemctl start "$SERVICE_NAME"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "$SERVICE_NAME started successfully"
    else
        print_error "Failed to start $SERVICE_NAME"
        journalctl -u "$SERVICE_NAME" --no-pager -n 10
        exit 1
    fi
}

# Stop service
stop_service() {
    print_info "Stopping $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME"
    print_success "$SERVICE_NAME stopped"
}

# Restart service
restart_service() {
    print_info "Restarting $SERVICE_NAME..."
    systemctl restart "$SERVICE_NAME"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "$SERVICE_NAME restarted successfully"
    else
        print_error "Failed to restart $SERVICE_NAME"
        exit 1
    fi
}

# Enable auto-start
enable_service() {
    print_info "Enabling $SERVICE_NAME auto-start..."
    systemctl enable "$SERVICE_NAME"
    print_success "$SERVICE_NAME will start automatically on boot"
}

# Disable auto-start
disable_service() {
    print_info "Disabling $SERVICE_NAME auto-start..."
    systemctl disable "$SERVICE_NAME"
    print_success "$SERVICE_NAME auto-start disabled"
}

# Check service status
status_service() {
    print_header "Service Status"

    if [ -f "$INSTALL_DIR/ssserver" ]; then
        local version=$("$INSTALL_DIR/ssserver" --version 2>/dev/null | head -1)
        print_info "Installed version: $version"
    else
        print_warning "Shadowsocks-Rust is not installed"
        return
    fi

    echo ""
    systemctl status "$SERVICE_NAME" --no-pager
}

# Update shadowsocks-rust
update_ssrust() {
    print_header "Updating Shadowsocks-Rust"

    local current_version=$(get_installed_version)
    local latest_version=$(get_latest_version)

    # Remove 'v' prefix for comparison
    local current_clean=${current_version#v}
    local latest_clean=${latest_version#v}

    print_info "Current version: ${current_version:-Not installed}"
    print_info "Latest version: $latest_version"

    if [ "$current_clean" = "$latest_clean" ]; then
        print_success "Already running the latest version"
        return
    fi

    install_ssrust

    # Restart service if it was running
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        restart_service
    fi

    print_success "Update completed"
}

# Uninstall shadowsocks-rust
uninstall_ssrust() {
    print_header "Uninstalling Shadowsocks-Rust"

    read -p "$(echo -e "${RED}Are you sure you want to uninstall? (y/N): ${NC}")" confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_info "Uninstall cancelled"
        return
    fi

    # Stop and disable service
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        print_info "Stopping service..."
        systemctl stop "$SERVICE_NAME"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        print_info "Disabling service..."
        systemctl disable "$SERVICE_NAME"
    fi

    # Remove service file
    if [ -f "$SERVICE_FILE" ]; then
        print_info "Removing service file..."
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    # Remove binary
    if [ -f "$INSTALL_DIR/ssserver" ]; then
        print_info "Removing binary..."
        rm -f "$INSTALL_DIR/ssserver"
    fi

    # Ask about config removal
    if [ -d "$CONFIG_DIR" ]; then
        read -p "$(echo -e "${YELLOW}Remove configuration files? (y/N): ${NC}")" remove_config
        if [ "$remove_config" = "y" ] || [ "$remove_config" = "Y" ]; then
            rm -rf "$CONFIG_DIR"
            print_info "Configuration files removed"
        else
            print_info "Configuration files kept at $CONFIG_DIR"
        fi
    fi

    print_success "Shadowsocks-Rust uninstalled successfully"
}

# Show help
show_help() {
    echo -e "${BOLD}Shadowsocks-Rust Management Script${NC}"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install     Install Shadowsocks-Rust"
    echo "  update      Update to the latest version"
    echo "  uninstall   Uninstall Shadowsocks-Rust"
    echo "  start       Start the service"
    echo "  stop        Stop the service"
    echo "  restart     Restart the service"
    echo "  enable      Enable auto-start on boot"
    echo "  disable     Disable auto-start on boot"
    echo "  status      Show service status"
    echo "  info        Show connection information"
    echo "  help        Show this help message"
    echo ""
    echo "Without arguments, an interactive menu will be displayed."
}

# Interactive menu
show_menu() {
    echo -e "${BOLD}${MAGENTA}=====================================================${NC}"
    echo -e "${BOLD}${MAGENTA}     Shadowsocks-Rust Management Script              ${NC}"
    echo -e "${BOLD}${MAGENTA}=====================================================${NC}"
    echo ""
    echo -e "${BOLD}Please select an option:${NC}"
    echo -e "${GREEN}1)${NC} Install Shadowsocks-Rust"
    echo -e "${GREEN}2)${NC} Update Shadowsocks-Rust"
    echo -e "${GREEN}3)${NC} Uninstall Shadowsocks-Rust"
    echo -e "${BLUE}4)${NC} Start Service"
    echo -e "${BLUE}5)${NC} Stop Service"
    echo -e "${BLUE}6)${NC} Restart Service"
    echo -e "${CYAN}7)${NC} Enable Auto-Start"
    echo -e "${CYAN}8)${NC} Disable Auto-Start"
    echo -e "${YELLOW}9)${NC} Show Status"
    echo -e "${YELLOW}10)${NC} Show Connection Info"
    echo -e "${RED}0)${NC} Exit"
    echo ""

    read -p "$(echo -e "${CYAN}Enter your choice (0-10): ${NC}")" choice

    case $choice in
        1)
            install_ssrust
            create_config
            create_service
            enable_tfo
            configure_firewall
            enable_service
            start_service
            show_connection_info
            ;;
        2)
            update_ssrust
            ;;
        3)
            uninstall_ssrust
            ;;
        4)
            start_service
            ;;
        5)
            stop_service
            ;;
        6)
            restart_service
            ;;
        7)
            enable_service
            ;;
        8)
            disable_service
            ;;
        9)
            status_service
            ;;
        10)
            show_connection_info
            ;;
        0)
            print_info "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
}

# Main entry point
main() {
    check_root

    case "${1:-}" in
        install)
            install_ssrust
            create_config
            create_service
            enable_tfo
            configure_firewall
            enable_service
            start_service
            show_connection_info
            ;;
        update)
            update_ssrust
            ;;
        uninstall)
            uninstall_ssrust
            ;;
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        enable)
            enable_service
            ;;
        disable)
            disable_service
            ;;
        status)
            status_service
            ;;
        info)
            show_connection_info
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            show_menu
            ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
