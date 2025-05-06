#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored text
print_colored() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to print section headers
print_header() {
    local message="$1"
    echo ""
    echo -e "${BOLD}${BLUE}===========================================================${NC}"
    echo -e "${BOLD}${BLUE}  $message${NC}"
    echo -e "${BOLD}${BLUE}===========================================================${NC}"
    echo ""
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# Function to print info messages
print_info() {
    echo -e "${CYAN}ℹ️ $1${NC}"
}

# Function to check if script is running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to check if Docker is installed and install if needed
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_info "Docker is not installed. Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
        
        # Check if Docker Compose plugin is available
        if ! docker compose version &> /dev/null; then
            print_info "Installing Docker Compose plugin..."
            apt-get update && apt-get install -y docker-compose-plugin
        fi
        
        print_success "Docker installation completed."
    else
        print_success "Docker is already installed."
        
        # Ensure Docker Compose plugin is available
        if ! docker compose version &> /dev/null; then
            print_info "Installing Docker Compose plugin..."
            apt-get update && apt-get install -y docker-compose-plugin
        fi
    fi
}

# Function to check if required tools are installed
check_required_tools() {
    local missing_tools=()
    
    # Check for qrencode
    if ! command -v qrencode &> /dev/null; then
        missing_tools+=("qrencode")
    fi
    
    # Install missing tools if any
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_info "Installing required tools: ${missing_tools[*]}"
        apt-get update && apt-get install -y "${missing_tools[@]}"
    fi
}

# Function to get the server's IPv4 address
get_ipv4() {
    curl -s -4 ifconfig.me
}

# Function to generate random passwords
generate_password() {
    openssl rand -base64 32
}

# Function to base64 encode a string
base64_encode() {
    echo -n "$1" | base64 | tr -d '\n'
}

# Function to generate random string
generate_random_string() {
    local length=$1
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${length} | head -n 1
}

# Function to URL encode a string
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

# Function to generate Shadowsocks URI and QR code
generate_ss_uri() {
    local method="$1"
    local password="$2"
    local server_ip="$3"
    local port="$4"
    local shadowtls_version="$5"
    local shadowtls_host="$6"
    local shadowtls_password="$7"
    
    local user_info_with_server="${method}:${password}@${server_ip}:${port}"
    local user_info_base64=$(base64_encode "$user_info_with_server")
    
    local shadowtls_json="{\"version\":\"${shadowtls_version}\",\"host\":\"${shadowtls_host}\",\"password\":\"${shadowtls_password}\"}"
    local shadowtls_base64=$(base64_encode "$shadowtls_json")
    
    local random_string=$(generate_random_string 6)
    local node_name="${random_string} @ OwO"
    local encoded_node_name=$(url_encode "$node_name")
    
    local ss_uri="ss://${user_info_base64}?shadow-tls=${shadowtls_base64}#${encoded_node_name}"
    
    echo "$ss_uri"
}

# Function to display the connection info and QR code
display_connection_info() {
    local title="$1"
    local server_ip="$2"
    local port="$3"
    local shadowtls_password="$4"
    local shadowtls_host="$5"
    local internal_port="$6"
    local protocol_info="$7"
    local ss_uri="$8"
    
    print_header "$title has been set up successfully!"
    echo -e "${BOLD}Server Address:${NC} ${BOLD}$server_ip${NC}"
    echo -e "${BOLD}ShadowTLS Port:${NC} ${BOLD}$port${NC}"
    echo -e "${BOLD}ShadowTLS Password:${NC} ${BOLD}$shadowtls_password${NC}"
    echo -e "${BOLD}ShadowTLS TLS Server:${NC} ${BOLD}$shadowtls_host${NC}"
    echo -e "${BOLD}$protocol_info${NC}"
    print_header "Connection URI"
    echo -e "${BOLD}$ss_uri${NC}"
    print_header "QR Code"
    qrencode -t UTF8 "$ss_uri"
    echo -e "${BLUE}===========================================================${NC}"
}

# Function to verify config file password
verify_config_password() {
    local file="$1"
    local pattern="$2"
    local expected="$3"
    local label="$4"
    
    print_info "Verifying $label password in $file..."
    local found=$(grep -o "$pattern.*" "$file" | head -1)
    echo -e "${CYAN}Expected: $expected${NC}"
    echo -e "${CYAN}Found in config: $found${NC}"
    
    if [[ "$found" == *"$expected"* ]]; then
        print_success "Password verified successfully!"
    else
        print_error "WARNING: Password mismatch detected!"
    fi
    echo ""
}

# Function to setup Snell + ShadowTLS
setup_snell_shadowtls() {
    local port=$1
    
    print_header "Setting up Snell + ShadowTLS on port $port"
    
    # Create directory
    mkdir -p shadowtls-snell
    cd shadowtls-snell
    
    # Download compose file
    print_info "Downloading configuration files..."
    wget -O compose.yaml https://raw.githubusercontent.com/missuo/snell-server-docker/refs/heads/master/compose-snell.yaml
    
    # Generate passwords
    local snell_password=$(generate_password)
    local shadowtls_password=$(generate_password)
    
    print_info "Generated Snell password: ${BOLD}$snell_password${NC}"
    print_info "Generated ShadowTLS password: ${BOLD}$shadowtls_password${NC}"
    
    # Update compose file with passwords and custom port
    print_info "Updating configuration files..."
    # Changed delimiter from / to # to avoid conflicts with password
    sed -i "s#PSK=CHANGE_ME#PSK=$snell_password#g" compose.yaml
    sed -i "s#PASSWORD=CHANGE_ME#PASSWORD=$shadowtls_password#g" compose.yaml
    sed -i "s#LISTEN=0.0.0.0:8443#LISTEN=0.0.0.0:$port#g" compose.yaml
    
    # Verify passwords in config file
    verify_config_password "compose.yaml" "PSK=" "$snell_password" "Snell"
    verify_config_password "compose.yaml" "PASSWORD=" "$shadowtls_password" "ShadowTLS"
    
    # Start containers
    print_info "Starting containers..."
    docker compose up -d
    print_success "Containers started successfully!"
    
    # Display connection information
    print_header "Snell + ShadowTLS has been set up successfully!"
    echo -e "${BOLD}Server Address:${NC} ${BOLD}$(get_ipv4)${NC}"
    echo -e "${BOLD}ShadowTLS Port:${NC} ${BOLD}$port${NC}"
    echo -e "${BOLD}ShadowTLS Password:${NC} ${BOLD}$shadowtls_password${NC}"
    echo -e "${BOLD}ShadowTLS TLS Server:${NC} ${BOLD}weather-data.apple.com:443${NC}"
    echo -e "${BOLD}Snell Port:${NC} ${BOLD}24000${NC} (internal)"
    echo -e "${BOLD}Snell PSK:${NC} ${BOLD}$snell_password${NC}"
    echo -e "${BLUE}===========================================================${NC}"
    
    cd ..
}

# Function to setup Shadowsocks + ShadowTLS
setup_shadowsocks_shadowtls() {
    local port=$1
    
    print_header "Setting up Shadowsocks + ShadowTLS on port $port"
    
    # Create directory
    mkdir -p shadowtls-shadowsocks
    cd shadowtls-shadowsocks
    
    # Download compose file
    print_info "Downloading configuration files..."
    wget -O compose.yaml https://raw.githubusercontent.com/missuo/snell-server-docker/refs/heads/master/compose-shadowsocks.yaml
    
    # Generate passwords
    local ss_password=$(generate_password)
    local shadowtls_password=$(generate_password)
    
    print_info "Generated Shadowsocks password: ${BOLD}$ss_password${NC}"
    print_info "Generated ShadowTLS password: ${BOLD}$shadowtls_password${NC}"
    
    # Update compose file with passwords and custom port
    print_info "Updating configuration files..."
    # Replace first occurrence for shadowsocks password
    sed -i "0,/PASSWORD=CHANGE_ME/s|PASSWORD=CHANGE_ME|PASSWORD=$ss_password|" compose.yaml

    # Replace second occurrence for shadowtls password (find next occurrence)
    sed -i "/PASSWORD=CHANGE_ME/s|PASSWORD=CHANGE_ME|PASSWORD=$shadowtls_password|" compose.yaml
    # Update port
    sed -i "s#LISTEN=0.0.0.0:8443#LISTEN=0.0.0.0:$port#g" compose.yaml
    
    # Verify passwords in config file
    print_info "Verifying Shadowsocks password in compose.yaml..."
    local found_ss=$(grep -m 1 "PASSWORD=" compose.yaml)
    echo -e "${CYAN}Expected: PASSWORD=$ss_password${NC}"
    echo -e "${CYAN}Found in config: $found_ss${NC}"
    
    print_info "Verifying ShadowTLS password in compose.yaml..."
    local found_shadowtls=$(grep -m 2 "PASSWORD=" compose.yaml | tail -1)
    echo -e "${CYAN}Expected: PASSWORD=$shadowtls_password${NC}"
    echo -e "${CYAN}Found in config: $found_shadowtls${NC}"
    
    if [[ "$found_ss" == *"$ss_password"* ]]; then
        print_success "Shadowsocks password verified successfully!"
    else
        print_error "WARNING: Shadowsocks password mismatch detected!"
    fi
    
    if [[ "$found_shadowtls" == *"$shadowtls_password"* ]]; then
        print_success "ShadowTLS password verified successfully!"
    else
        print_error "WARNING: ShadowTLS password mismatch detected!"
    fi
    
    # Start containers
    print_info "Starting containers..."
    docker compose up -d
    print_success "Containers started successfully!"
    
    # Get server IP
    local server_ip=$(get_ipv4)
    local shadowtls_host="weather-data.apple.com"
    local ss_method="chacha20-ietf-poly1305"
    local internal_port="24000"
    
    # Generate SS URI
    local ss_uri=$(generate_ss_uri "$ss_method" "$ss_password" "$server_ip" "$port" "3" "$shadowtls_host" "$shadowtls_password")
    
    # Display connection information with URI and QR code
    local protocol_info="Shadowsocks Port: ${BOLD}$internal_port${NC} (internal)
Shadowsocks Password: ${BOLD}$ss_password${NC}
Shadowsocks Method: ${BOLD}$ss_method${NC}"
    
    display_connection_info "Shadowsocks + ShadowTLS" "$server_ip" "$port" "$shadowtls_password" "$shadowtls_host" "$internal_port" "$protocol_info" "$ss_uri"
    
    cd ..
}

# Function to setup Xray (Shadowsocks 2022) + ShadowTLS
setup_xray_shadowtls() {
    local port=$1
    
    print_header "Setting up Xray (Shadowsocks 2022) + ShadowTLS on port $port"
    
    # Create directory
    mkdir -p shadowtls-xray
    cd shadowtls-xray
    
    # Download compose file and config
    print_info "Downloading configuration files..."
    wget -O compose.yaml https://raw.githubusercontent.com/missuo/snell-server-docker/refs/heads/master/compose-shadowsocks2022.yaml
    wget -O config.json https://raw.githubusercontent.com/missuo/snell-server-docker/refs/heads/master/config-shadowsocks2022.json
    
    # Generate passwords
    local ss_password=$(generate_password)
    local shadowtls_password=$(generate_password)
    
    print_info "Generated Shadowsocks 2022 password: ${BOLD}$ss_password${NC}"
    print_info "Generated ShadowTLS password: ${BOLD}$shadowtls_password${NC}"
    
    # Update config.json with password - changed delimiter to # to avoid conflicts
    print_info "Updating configuration files..."
    sed -i "s#\"password\": \"CHANGE_ME\"#\"password\": \"$ss_password\"#g" config.json
    
    # Update compose file with shadowtls password and custom port
    sed -i "s#PASSWORD=CHANGE_ME#PASSWORD=$shadowtls_password#g" compose.yaml
    sed -i "s#LISTEN=0.0.0.0:8443#LISTEN=0.0.0.0:$port#g" compose.yaml
    
    # Verify passwords in config files
    verify_config_password "config.json" "\"password\": " "\"$ss_password\"" "Shadowsocks 2022"
    verify_config_password "compose.yaml" "PASSWORD=" "$shadowtls_password" "ShadowTLS"
    
    # Start containers
    print_info "Starting containers..."
    docker compose up -d
    print_success "Containers started successfully!"
    
    # Get server IP
    local server_ip=$(get_ipv4)
    local shadowtls_host="weather-data.apple.com"
    local ss_method="2022-blake3-chacha20-poly1305"
    local internal_port="24000"
    
    # Generate SS URI
    local ss_uri=$(generate_ss_uri "$ss_method" "$ss_password" "$server_ip" "$port" "3" "$shadowtls_host" "$shadowtls_password")
    
    # Display connection information with URI and QR code
    local protocol_info="Shadowsocks 2022 Port: ${BOLD}$internal_port${NC} (internal)
Shadowsocks 2022 Password: ${BOLD}$ss_password${NC}
Shadowsocks 2022 Method: ${BOLD}$ss_method${NC}"
    
    display_connection_info "Xray (Shadowsocks 2022) + ShadowTLS" "$server_ip" "$port" "$shadowtls_password" "$shadowtls_host" "$internal_port" "$protocol_info" "$ss_uri"
    
    cd ..
}

# Function to uninstall any ShadowTLS setup
uninstall_shadowtls() {
    print_header "Uninstalling ShadowTLS setups"
    
    # Check and uninstall Snell + ShadowTLS
    if [ -d "shadowtls-snell" ]; then
        print_info "Removing Snell + ShadowTLS..."
        cd shadowtls-snell
        docker compose down
        cd ..
        rm -rf shadowtls-snell
        print_success "Snell + ShadowTLS removed successfully!"
    fi
    
    # Check and uninstall Shadowsocks + ShadowTLS
    if [ -d "shadowtls-shadowsocks" ]; then
        print_info "Removing Shadowsocks + ShadowTLS..."
        cd shadowtls-shadowsocks
        docker compose down
        cd ..
        rm -rf shadowtls-shadowsocks
        print_success "Shadowsocks + ShadowTLS removed successfully!"
    fi
    
    # Check and uninstall Xray + ShadowTLS
    if [ -d "shadowtls-xray" ]; then
        print_info "Removing Xray (Shadowsocks 2022) + ShadowTLS..."
        cd shadowtls-xray
        docker compose down
        cd ..
        rm -rf shadowtls-xray
        print_success "Xray (Shadowsocks 2022) + ShadowTLS removed successfully!"
    fi
    
    # Clean up unused Docker resources
    print_header "Cleaning up Docker resources"
    print_warning "This Action Will Remove All Unused Docker Resources"
    print_warning "Are You Sure You Want To Continue? (y/n)"
    read -p "$(echo -e "${YELLOW}Enter your choice (y/n): ${NC}")" confirm
    
    if [ "$confirm" = "y" ]; then
        docker system prune -af
        print_success "Docker resources cleaned up successfully!"
    else
        print_info "Cleanup cancelled. No changes were made."
    fi
    print_success "Uninstallation completed successfully!"
}

# Main function
main() {
    # Do NOT clear screen to keep all output visible
    # clear  <-- Removed this line
    
    # Check if running as root
    check_root
    
    # Display welcome message
    echo -e "${BOLD}${MAGENTA}=====================================================${NC}"
    echo -e "${BOLD}${MAGENTA}       ShadowTLS Proxy Installation Script           ${NC}"
    echo -e "${BOLD}${MAGENTA}=====================================================${NC}"
    echo ""
    echo -e "${BOLD}GitHub: ${BLUE}https://github.com/missuo/snell-server-docker${NC}"
    echo ""
    echo -e "${BOLD}Please select an option:${NC}"
    echo -e "${GREEN}1)${NC} Install Snell + ShadowTLS ${YELLOW}(Recommended)${NC}"
    echo -e "${GREEN}2)${NC} Install Shadowsocks + ShadowTLS"
    echo -e "${GREEN}3)${NC} Install Xray (Shadowsocks 2022) + ShadowTLS ${YELLOW}(Recommended)${NC}"
    echo -e "${RED}4)${NC} Uninstall All ShadowTLS Setups"
    echo -e "${BLUE}5)${NC} Exit"
    echo ""
    
    # Get user choice
    read -p "$(echo -e "${CYAN}Enter your choice (1-5): ${NC}")" choice
    
    # Process user choice
    case $choice in
        1|2|3)
            # Check and install Docker if needed (only for installation options)
            check_docker
            
            # Check and install required tools
            check_required_tools
            
            # Default port
            default_port=8443
            
            # Ask for custom port
            read -p "$(echo -e "${CYAN}Enter ShadowTLS port (default: $default_port): ${NC}")" custom_port
            port=${custom_port:-$default_port}
            
            # Call appropriate setup function
            if [ "$choice" -eq "1" ]; then
                setup_snell_shadowtls $port
            elif [ "$choice" -eq "2" ]; then
                setup_shadowsocks_shadowtls $port
            elif [ "$choice" -eq "3" ]; then
                setup_xray_shadowtls $port
            fi
            ;;
        4)
            uninstall_shadowtls
            ;;
        5)
            print_info "Exiting. No changes were made."
            exit 0
            ;;
        *)
            print_error "Invalid option. Please run the script again and select a valid option."
            exit 1
            ;;
    esac
    
    echo ""
    print_success "Operation completed successfully!"
}

# Run main function
main