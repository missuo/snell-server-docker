#!/bin/bash

# Mieru (mita) Server Installation Script
# Supports: install, update, uninstall, start, stop, restart, enable, disable, status, info

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
CONFIG_DIR="/etc/mita"
CONFIG_FILE="$CONFIG_DIR/server_config.json"
META_FILE="$CONFIG_DIR/.install_meta"
SERVICE_NAME="mita"
GITHUB_REPO="enfein/mieru"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# Print helpers
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}===========================================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}===========================================================${NC}"
    echo ""
}

print_success() { echo -e "${GREEN}[OK] $1${NC}"; }
print_error()   { echo -e "${RED}[ERROR] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[WARN] $1${NC}"; }
print_info()    { echo -e "${CYAN}[INFO] $1${NC}"; }

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Detect package manager / family: deb or rpm
detect_pkg_family() {
    if command -v dpkg &> /dev/null && command -v apt-get &> /dev/null; then
        echo "deb"
    elif command -v rpm &> /dev/null && (command -v dnf &> /dev/null || command -v yum &> /dev/null); then
        echo "rpm"
    else
        print_error "Unsupported OS: requires Debian/Ubuntu (dpkg) or RHEL/Fedora/CentOS (rpm)"
        exit 1
    fi
}

# Detect architecture
detect_arch() {
    local arch=$(uname -m)
    local family="$1"
    case "$arch" in
        x86_64)
            if [ "$family" = "deb" ]; then echo "amd64"; else echo "x86_64"; fi
            ;;
        aarch64|arm64)
            if [ "$family" = "deb" ]; then echo "arm64"; else echo "aarch64"; fi
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Get latest release tag from GitHub (e.g. v3.32.0)
get_latest_version() {
    local version
    version=$(curl -fsSL "$GITHUB_API" | grep '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$version" ]; then
        print_error "Failed to get latest version from GitHub API"
        exit 1
    fi
    echo "$version"
}

# Get installed mita version
get_installed_version() {
    if command -v mita &> /dev/null; then
        # mita version output style varies; grab first version-like token
        mita version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    fi
}

# Required tools
check_requirements() {
    local missing=()
    for tool in curl wget; do
        command -v "$tool" &> /dev/null || missing+=("$tool")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_info "Installing required tools: ${missing[*]}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y "${missing[@]}"
        elif command -v dnf &> /dev/null; then
            dnf install -y "${missing[@]}"
        elif command -v yum &> /dev/null; then
            yum install -y "${missing[@]}"
        else
            print_error "Cannot install required tools. Please install manually: ${missing[*]}"
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

# Generate strong password
generate_password() {
    openssl rand -base64 18 | tr -d '/+=' | cut -c1-24
}

generate_random_string() {
    local length=${1:-8}
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "$length" | head -n 1
}

# URL encode (for sharing link)
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

# Download and install mita package
install_mita_package() {
    print_header "Installing mieru (mita)"

    check_requirements

    local family=$(detect_pkg_family)
    local arch=$(detect_arch "$family")
    local tag=$(get_latest_version)
    local version="${tag#v}"

    print_info "OS family: $family"
    print_info "Architecture: $arch"
    print_info "Latest version: $tag"

    local filename download_url
    if [ "$family" = "deb" ]; then
        filename="mita_${version}_${arch}.deb"
    else
        filename="mita-${version}-1.${arch}.rpm"
    fi
    download_url="https://github.com/${GITHUB_REPO}/releases/download/${tag}/${filename}"

    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    print_info "Downloading from: $download_url"
    if ! wget -q --show-progress "$download_url" -O "$filename"; then
        print_error "Failed to download $filename"
        rm -rf "$temp_dir"
        exit 1
    fi

    print_info "Installing package..."
    if [ "$family" = "deb" ]; then
        if ! dpkg -i "$filename"; then
            print_info "Resolving dependencies..."
            apt-get install -f -y
            dpkg -i "$filename" || { print_error "Package install failed"; rm -rf "$temp_dir"; exit 1; }
        fi
    else
        if command -v dnf &> /dev/null; then
            dnf install -y "$filename" || rpm -Uvh --force "$filename"
        else
            yum install -y "$filename" || rpm -Uvh --force "$filename"
        fi
    fi

    cd /
    rm -rf "$temp_dir"

    mkdir -p "$CONFIG_DIR"
    echo "version=$tag" > "$META_FILE"

    print_success "mieru $tag installed"
}

# Interactive configuration builder
create_config() {
    print_header "Creating Configuration"

    mkdir -p "$CONFIG_DIR"

    # Protocol
    echo -e "${BOLD}Select transport protocol:${NC}"
    echo -e "${GREEN}1)${NC} TCP ${YELLOW}(default, recommended for most use cases)${NC}"
    echo -e "${GREEN}2)${NC} UDP"
    read -p "$(echo -e "${CYAN}Enter your choice (1-2, default: 1): ${NC}")" proto_choice
    local protocol
    case "${proto_choice:-1}" in
        2) protocol="UDP" ;;
        *) protocol="TCP" ;;
    esac

    # Port mode
    echo ""
    echo -e "${BOLD}Select port mode:${NC}"
    echo -e "${GREEN}1)${NC} Single port ${YELLOW}(default)${NC}"
    echo -e "${GREEN}2)${NC} Port range"
    read -p "$(echo -e "${CYAN}Enter your choice (1-2, default: 1): ${NC}")" port_mode_choice

    local port_binding_json
    local display_port
    case "${port_mode_choice:-1}" in
        2)
            local default_range="2012-2022"
            read -p "$(echo -e "${CYAN}Enter port range (e.g. 2012-2022, default: $default_range): ${NC}")" input_range
            local port_range=${input_range:-$default_range}
            if ! [[ "$port_range" =~ ^[0-9]+-[0-9]+$ ]]; then
                print_error "Invalid port range format"
                exit 1
            fi
            port_binding_json="        {\n            \"portRange\": \"$port_range\",\n            \"protocol\": \"$protocol\"\n        }"
            display_port="$port_range"
            ;;
        *)
            local default_port=$(( RANDOM % 20000 + 30000 ))
            read -p "$(echo -e "${CYAN}Enter server port (default: $default_port): ${NC}")" input_port
            local port=${input_port:-$default_port}
            if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1025 ] || [ "$port" -gt 65535 ]; then
                print_error "Port must be between 1025 and 65535"
                exit 1
            fi
            port_binding_json="        {\n            \"port\": $port,\n            \"protocol\": \"$protocol\"\n        }"
            display_port="$port"
            ;;
    esac

    # Users
    echo ""
    echo -e "${BOLD}Configure users (multi-user supported):${NC}"
    read -p "$(echo -e "${CYAN}Number of users (default: 1): ${NC}")" user_count
    user_count=${user_count:-1}
    if ! [[ "$user_count" =~ ^[0-9]+$ ]] || [ "$user_count" -lt 1 ]; then
        user_count=1
    fi

    local users_json=""
    local users_summary=""
    local first_user_name=""
    local first_user_pass=""

    for (( i=1; i<=user_count; i++ )); do
        echo ""
        echo -e "${BOLD}User $i:${NC}"
        local default_name="mieru$(generate_random_string 4)"
        read -p "$(echo -e "${CYAN}  Username (default: $default_name): ${NC}")" uname
        uname=${uname:-$default_name}

        read -p "$(echo -e "${CYAN}  Password (leave empty for random): ${NC}")" upass
        if [ -z "$upass" ]; then
            upass=$(generate_password)
        fi

        if [ "$i" -gt 1 ]; then
            users_json="${users_json},"$'\n'
        fi
        users_json="${users_json}        {"$'\n'"            \"name\": \"$uname\","$'\n'"            \"password\": \"$upass\""$'\n'"        }"

        users_summary="${users_summary}  - ${uname} / ${upass}\n"

        if [ "$i" -eq 1 ]; then
            first_user_name="$uname"
            first_user_pass="$upass"
        fi
    done

    # MTU (only meaningful for UDP, but harmless to include)
    local mtu=1400

    # Compose JSON
    cat > "$CONFIG_FILE" <<EOF
{
    "portBindings": [
$(echo -e "$port_binding_json")
    ],
    "users": [
$(echo -e "$users_json")
    ],
    "loggingLevel": "INFO",
    "mtu": $mtu
}
EOF

    chmod 600 "$CONFIG_FILE"

    # Persist meta for info display
    {
        echo "protocol=$protocol"
        echo "port=$display_port"
        echo "first_user=$first_user_name"
        echo "first_pass=$first_user_pass"
        # Re-write version line if present
        grep "^version=" "$META_FILE" 2>/dev/null || true
    } > "${META_FILE}.tmp" && mv "${META_FILE}.tmp" "$META_FILE"

    print_success "Configuration written to $CONFIG_FILE"
    echo ""
    print_info "Users:"
    echo -e "$users_summary"

    # Apply config
    print_info "Applying configuration..."
    if ! mita apply config "$CONFIG_FILE"; then
        print_error "Failed to apply configuration. Check the file at $CONFIG_FILE"
        exit 1
    fi
    print_success "Configuration applied"
}

# Configure firewall to allow the port(s)
configure_firewall() {
    [ -f "$META_FILE" ] || return 0

    local protocol=$(grep '^protocol=' "$META_FILE" | cut -d= -f2)
    local port=$(grep '^port=' "$META_FILE" | cut -d= -f2)
    [ -z "$port" ] && return 0

    local proto_lower=$(echo "$protocol" | tr '[:upper:]' '[:lower:]')

    if command -v ufw &> /dev/null; then
        print_info "Configuring UFW firewall..."
        if [[ "$port" == *-* ]]; then
            ufw allow "${port/-/:}/${proto_lower}" > /dev/null 2>&1
        else
            ufw allow "${port}/${proto_lower}" > /dev/null 2>&1
        fi
        print_success "UFW: ${port}/${proto_lower} allowed"
    elif command -v firewall-cmd &> /dev/null && firewall-cmd --state &>/dev/null; then
        print_info "Configuring firewalld..."
        if [[ "$port" == *-* ]]; then
            firewall-cmd --permanent --add-port="${port}/${proto_lower}" > /dev/null 2>&1
        else
            firewall-cmd --permanent --add-port="${port}/${proto_lower}" > /dev/null 2>&1
        fi
        firewall-cmd --reload > /dev/null 2>&1
        print_success "firewalld: ${port}/${proto_lower} allowed"
    else
        print_info "No supported firewall detected, skipping firewall config"
    fi
}

# Enable BBR only if it's not already active.
# Respect any existing user setup (e.g. BBR+CAKE, BBR+fq_codel) — we only act
# when the running congestion control is NOT bbr.
enable_bbr() {
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)

    if [ "$current_cc" = "bbr" ]; then
        local current_qdisc
        current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        print_info "BBR is already enabled (qdisc: ${current_qdisc:-unknown}); leaving congestion control untouched"
        return 0
    fi

    print_info "Enabling BBR congestion control (current: ${current_cc:-unknown})..."
    local SYSCTL_CONF="/etc/sysctl.conf"

    if ! grep -q "^net.core.default_qdisc" "$SYSCTL_CONF" 2>/dev/null; then
        echo "net.core.default_qdisc = fq" >> "$SYSCTL_CONF"
    fi

    if grep -q "^net.ipv4.tcp_congestion_control" "$SYSCTL_CONF" 2>/dev/null; then
        sed -i 's/^net.ipv4.tcp_congestion_control.*/net.ipv4.tcp_congestion_control = bbr/' "$SYSCTL_CONF"
    else
        echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYSCTL_CONF"
    fi

    sysctl -p > /dev/null 2>&1
    print_success "BBR enabled"
}

# Generate mierus:// simple sharing link for one user
generate_mierus_link() {
    local username="$1"
    local password="$2"
    local server="$3"
    local port="$4"
    local protocol="$5"
    local profile="default"

    local enc_user=$(url_encode "$username")
    local enc_pass=$(url_encode "$password")

    local port_query
    if [[ "$port" == *-* ]]; then
        port_query="port=${port}"
    else
        port_query="port=${port}"
    fi

    echo "mierus://${enc_user}:${enc_pass}@${server}?profile=${profile}&${port_query}&protocol=${protocol}&mtu=1400"
}

# Display connection information
show_connection_info() {
    print_header "Connection Information"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "No configuration found at $CONFIG_FILE"
        return 1
    fi

    local server_ip=$(get_ipv4)
    local protocol port
    if [ -f "$META_FILE" ]; then
        protocol=$(grep '^protocol=' "$META_FILE" | cut -d= -f2)
        port=$(grep '^port=' "$META_FILE" | cut -d= -f2)
    fi

    echo -e "${BOLD}Server Address:${NC} $server_ip"
    echo -e "${BOLD}Port:${NC}           $port"
    echo -e "${BOLD}Protocol:${NC}       $protocol"
    echo ""
    echo -e "${BOLD}Users (name / password):${NC}"

    # Parse users from config via python (most distros have python3) or fallback to grep
    if command -v python3 &> /dev/null; then
        python3 -c "
import json, sys
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)
for u in cfg.get('users', []):
    print('  - %s / %s' % (u.get('name',''), u.get('password','')))
" 2>/dev/null
    else
        awk '/"name"/{name=$0} /"password"/{print "  - " name " / " $0}' "$CONFIG_FILE" \
            | sed 's/[",]//g; s/name://g; s/password://g' \
            | awk '{$1=$1; print}'
    fi

    print_header "Sharing Link (mierus://)"

    if command -v python3 &> /dev/null; then
        python3 - <<EOF
import json, urllib.parse
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)
bindings = cfg.get('portBindings', [])
qs_parts = []
for b in bindings:
    if 'portRange' in b:
        qs_parts.append(('port', b['portRange']))
    elif 'port' in b:
        qs_parts.append(('port', str(b['port'])))
    qs_parts.append(('protocol', b.get('protocol','TCP')))
qs_parts.insert(0, ('profile','default'))
qs_parts.append(('mtu','1400'))
qs = urllib.parse.urlencode(qs_parts)
server = "$server_ip"
for u in cfg.get('users', []):
    n = urllib.parse.quote(u.get('name',''), safe='')
    p = urllib.parse.quote(u.get('password',''), safe='')
    print("\033[0;32mmierus://%s:%s@%s?%s\033[0m" % (n, p, server, qs))
EOF
    else
        # Fallback: just emit single-user single-port link from meta
        local meta_user=$(grep '^first_user=' "$META_FILE" | cut -d= -f2)
        local meta_pass=$(grep '^first_pass=' "$META_FILE" | cut -d= -f2)
        local link=$(generate_mierus_link "$meta_user" "$meta_pass" "$server_ip" "$port" "$protocol")
        echo -e "${GREEN}$link${NC}"
    fi

    echo ""
    print_info "Use 'mieru import config <URL>' on the client side, or configure manually."
    echo -e "${BLUE}===========================================================${NC}"
}

# Service lifecycle: the deb/rpm provides systemd unit `mita`.
# `mita start` / `mita stop` instructs the daemon to start/stop the proxy.

start_service() {
    print_info "Starting mita daemon..."
    systemctl start "$SERVICE_NAME" || { print_error "Failed to start mita daemon"; exit 1; }
    sleep 1
    print_info "Starting proxy..."
    if mita start; then
        print_success "Proxy started"
        mita status
    else
        print_error "Failed to start proxy"
        exit 1
    fi
}

stop_service() {
    print_info "Stopping proxy..."
    mita stop > /dev/null 2>&1 || true
    print_success "Proxy stopped"
}

restart_service() {
    print_info "Restarting service..."
    systemctl restart "$SERVICE_NAME" || { print_error "Failed to restart mita daemon"; exit 1; }
    sleep 1
    mita start > /dev/null 2>&1 || true
    if mita status 2>/dev/null | grep -q "RUNNING"; then
        print_success "Proxy restarted"
    else
        print_warning "Proxy is not in RUNNING state"
    fi
    mita status
}

enable_service() {
    print_info "Enabling mita auto-start..."
    systemctl enable "$SERVICE_NAME"
    print_success "mita will start automatically on boot"
}

disable_service() {
    print_info "Disabling mita auto-start..."
    systemctl disable "$SERVICE_NAME"
    print_success "mita auto-start disabled"
}

status_service() {
    print_header "Service Status"

    if ! command -v mita &> /dev/null; then
        print_warning "mieru (mita) is not installed"
        return
    fi

    local installed_ver=$(get_installed_version)
    print_info "Installed version: ${installed_ver:-unknown}"

    echo ""
    systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null | head -8 || true
    echo ""
    print_info "Proxy status:"
    mita status 2>/dev/null || print_warning "Cannot query mita (daemon may not be running)"
}

# Update mieru
update_mieru() {
    print_header "Updating mieru"

    local current=$(get_installed_version)
    local latest_tag=$(get_latest_version)
    local latest=${latest_tag#v}

    print_info "Current version: ${current:-not installed}"
    print_info "Latest version:  $latest_tag"

    if [ -n "$current" ] && [ "$current" = "$latest" ]; then
        print_success "Already running the latest version"
        return
    fi

    install_mita_package

    # If a config exists, re-apply and ensure proxy is running
    if [ -f "$CONFIG_FILE" ]; then
        print_info "Re-applying configuration after upgrade..."
        systemctl restart "$SERVICE_NAME" 2>/dev/null || true
        sleep 1
        mita apply config "$CONFIG_FILE" > /dev/null 2>&1 || true
        mita start > /dev/null 2>&1 || true
    fi

    print_success "Update completed"
}

# Uninstall mieru
uninstall_mieru() {
    print_header "Uninstalling mieru"

    read -p "$(echo -e "${RED}Are you sure you want to uninstall mieru? (y/N): ${NC}")" confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_info "Uninstall cancelled"
        return
    fi

    if command -v mita &> /dev/null; then
        mita stop > /dev/null 2>&1 || true
    fi

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
    fi
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME"
    fi

    local family=$(detect_pkg_family)
    if [ "$family" = "deb" ]; then
        print_info "Removing mita package via apt..."
        apt-get remove -y mita || dpkg -r mita || true
    else
        print_info "Removing mita package via rpm..."
        if command -v dnf &> /dev/null; then
            dnf remove -y mita || rpm -e mita || true
        else
            yum remove -y mita || rpm -e mita || true
        fi
    fi

    if [ -d "$CONFIG_DIR" ]; then
        read -p "$(echo -e "${YELLOW}Remove configuration directory $CONFIG_DIR? (y/N): ${NC}")" rm_cfg
        if [ "$rm_cfg" = "y" ] || [ "$rm_cfg" = "Y" ]; then
            rm -rf "$CONFIG_DIR"
            print_info "Configuration removed"
        else
            print_info "Configuration kept at $CONFIG_DIR"
        fi
    fi

    print_success "mieru uninstalled"
}

# Reconfigure (rewrite config file and apply)
reconfigure() {
    if ! command -v mita &> /dev/null; then
        print_error "mieru is not installed. Run 'install' first."
        exit 1
    fi
    create_config
    configure_firewall
    systemctl restart "$SERVICE_NAME" || true
    sleep 1
    mita start > /dev/null 2>&1 || true
    show_connection_info
}

show_help() {
    echo -e "${BOLD}Mieru (mita) Server Management Script${NC}"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install      Install mieru and run interactive configuration"
    echo "  reconfigure  Rewrite configuration interactively and re-apply"
    echo "  update       Update mieru to the latest version"
    echo "  uninstall    Uninstall mieru"
    echo "  start        Start the proxy service"
    echo "  stop         Stop the proxy service"
    echo "  restart      Restart the proxy service"
    echo "  enable       Enable auto-start on boot"
    echo "  disable      Disable auto-start on boot"
    echo "  status       Show service status"
    echo "  info         Show connection information"
    echo "  bbr          Enable BBR congestion control (skips if already enabled)"
    echo "  help         Show this help message"
    echo ""
    echo "Without arguments, an interactive menu will be displayed."
}

show_menu() {
    echo -e "${BOLD}${MAGENTA}=====================================================${NC}"
    echo -e "${BOLD}${MAGENTA}     Mieru (mita) Server Management Script           ${NC}"
    echo -e "${BOLD}${MAGENTA}=====================================================${NC}"
    echo ""
    echo -e "${BOLD}Please select an option:${NC}"
    echo -e "${GREEN}1)${NC}  Install mieru"
    echo -e "${GREEN}2)${NC}  Update mieru"
    echo -e "${GREEN}3)${NC}  Uninstall mieru"
    echo -e "${GREEN}4)${NC}  Reconfigure"
    echo -e "${BLUE}5)${NC}  Start service"
    echo -e "${BLUE}6)${NC}  Stop service"
    echo -e "${BLUE}7)${NC}  Restart service"
    echo -e "${CYAN}8)${NC}  Enable auto-start"
    echo -e "${CYAN}9)${NC}  Disable auto-start"
    echo -e "${YELLOW}10)${NC} Show status"
    echo -e "${YELLOW}11)${NC} Show connection info"
    echo -e "${MAGENTA}12)${NC} Enable BBR"
    echo -e "${RED}0)${NC}  Exit"
    echo ""
    read -p "$(echo -e "${CYAN}Enter your choice (0-12): ${NC}")" choice

    case $choice in
        1)
            install_mita_package
            create_config
            configure_firewall
            enable_service
            systemctl start "$SERVICE_NAME"
            sleep 1
            mita start > /dev/null 2>&1 || true
            show_connection_info
            ;;
        2)  update_mieru ;;
        3)  uninstall_mieru ;;
        4)  reconfigure ;;
        5)  start_service ;;
        6)  stop_service ;;
        7)  restart_service ;;
        8)  enable_service ;;
        9)  disable_service ;;
        10) status_service ;;
        11) show_connection_info ;;
        12) enable_bbr ;;
        0)  print_info "Exiting..."; exit 0 ;;
        *)  print_error "Invalid option"; exit 1 ;;
    esac
}

main() {
    check_root

    case "${1:-}" in
        install)
            install_mita_package
            create_config
            configure_firewall
            enable_service
            systemctl start "$SERVICE_NAME"
            sleep 1
            mita start > /dev/null 2>&1 || true
            show_connection_info
            ;;
        reconfigure)  reconfigure ;;
        update)       update_mieru ;;
        uninstall)    uninstall_mieru ;;
        start)        start_service ;;
        stop)         stop_service ;;
        restart)      restart_service ;;
        enable)       enable_service ;;
        disable)      disable_service ;;
        status)       status_service ;;
        info)         show_connection_info ;;
        bbr|enable-bbr) enable_bbr ;;
        help|--help|-h) show_help ;;
        "")           show_menu ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
