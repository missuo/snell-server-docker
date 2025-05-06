#!/bin/bash

# Function to check if script is running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root"
        exit 1
    fi
}

# Function to check if Docker is installed and install if needed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker is not installed. Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
        
        # Check if Docker Compose plugin is available
        if ! docker compose version &> /dev/null; then
            echo "Installing Docker Compose plugin..."
            apt-get update && apt-get install -y docker-compose-plugin
        fi
        
        echo "Docker installation completed."
    else
        echo "Docker is already installed."
        
        # Ensure Docker Compose plugin is available
        if ! docker compose version &> /dev/null; then
            echo "Installing Docker Compose plugin..."
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
        echo "Installing required tools: ${missing_tools[*]}"
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
    
    echo "=============================================="
    echo "$title has been set up successfully!"
    echo "=============================================="
    echo "Server Address: $server_ip"
    echo "ShadowTLS Port: $port"
    echo "ShadowTLS Password: $shadowtls_password"
    echo "ShadowTLS TLS Server: $shadowtls_host"
    echo "$protocol_info"
    echo "=============================================="
    echo "Connection URI:"
    echo "$ss_uri"
    echo "=============================================="
    echo "QR Code:"
    qrencode -t UTF8 "$ss_uri"
    echo "=============================================="
}

# Function to verify config file password
verify_config_password() {
    local file="$1"
    local pattern="$2"
    local expected="$3"
    local label="$4"
    
    echo "Verifying $label password in $file..."
    local found=$(grep -o "$pattern.*" "$file" | head -1)
    echo "Expected: $expected"
    echo "Found in config: $found"
    
    if [[ "$found" == *"$expected"* ]]; then
        echo "✅ Password verified successfully!"
    else
        echo "❌ WARNING: Password mismatch detected!"
    fi
    echo ""
}

# Function to setup Snell + ShadowTLS
setup_snell_shadowtls() {
    local port=$1
    
    echo "Setting up Snell + ShadowTLS on port $port..."
    
    # Create directory
    mkdir -p shadowtls-snell
    cd shadowtls-snell
    
    # Download compose file
    wget -O compose.yaml https://raw.githubusercontent.com/missuo/snell-server-docker/refs/heads/master/compose-snell.yaml
    
    # Generate passwords
    local snell_password=$(generate_password)
    local shadowtls_password=$(generate_password)
    
    echo "Generated Snell password: $snell_password"
    echo "Generated ShadowTLS password: $shadowtls_password"
    
    # Update compose file with passwords and custom port
    # Changed delimiter from / to # to avoid conflicts with password
    sed -i "s#PSK=CHANGE_ME#PSK=$snell_password#g" compose.yaml
    sed -i "s#PASSWORD=CHANGE_ME#PASSWORD=$shadowtls_password#g" compose.yaml
    sed -i "s#LISTEN=0.0.0.0:8443#LISTEN=0.0.0.0:$port#g" compose.yaml
    
    # Verify passwords in config file
    verify_config_password "compose.yaml" "PSK=" "$snell_password" "Snell"
    verify_config_password "compose.yaml" "PASSWORD=" "$shadowtls_password" "ShadowTLS"
    
    # Start containers
    docker compose up -d
    
    # Display connection information
    echo "=============================================="
    echo "Snell + ShadowTLS has been set up successfully!"
    echo "=============================================="
    echo "Server Address: $(get_ipv4)"
    echo "ShadowTLS Port: $port"
    echo "ShadowTLS Password: $shadowtls_password"
    echo "ShadowTLS TLS Server: weather-data.apple.com:443"
    echo "Snell Port: 24000 (internal)"
    echo "Snell PSK: $snell_password"
    echo "=============================================="
    
    cd ..
}

# Function to setup Shadowsocks + ShadowTLS
setup_shadowsocks_shadowtls() {
    local port=$1
    
    echo "Setting up Shadowsocks + ShadowTLS on port $port..."
    
    # Create directory
    mkdir -p shadowtls-shadowsocks
    cd shadowtls-shadowsocks
    
    # Download compose file
    wget -O compose.yaml https://raw.githubusercontent.com/missuo/snell-server-docker/refs/heads/master/compose-shadowsocks.yaml
    
    # Generate passwords
    local ss_password=$(generate_password)
    local shadowtls_password=$(generate_password)
    
    echo "Generated Shadowsocks password: $ss_password"
    echo "Generated ShadowTLS password: $shadowtls_password"
    
    # Replace first occurrence for shadowsocks password
    sed -i "0,/PASSWORD=CHANGE_ME/s|PASSWORD=CHANGE_ME|PASSWORD=$ss_password|" compose.yaml

    # Replace second occurrence for shadowtls password (find next occurrence)
    sed -i "/PASSWORD=CHANGE_ME/s|PASSWORD=CHANGE_ME|PASSWORD=$shadowtls_password|" compose.yaml
    # Update port
    sed -i "s#LISTEN=0.0.0.0:8443#LISTEN=0.0.0.0:$port#g" compose.yaml
    
    # Verify passwords in config file
    echo "Verifying Shadowsocks password in compose.yaml..."
    local found_ss=$(grep -m 1 "PASSWORD=" compose.yaml)
    echo "Expected: PASSWORD=$ss_password"
    echo "Found in config: $found_ss"
    
    echo "Verifying ShadowTLS password in compose.yaml..."
    local found_shadowtls=$(grep -m 2 "PASSWORD=" compose.yaml | tail -1)
    echo "Expected: PASSWORD=$shadowtls_password"
    echo "Found in config: $found_shadowtls"
    
    if [[ "$found_ss" == *"$ss_password"* ]]; then
        echo "✅ Shadowsocks password verified successfully!"
    else
        echo "❌ WARNING: Shadowsocks password mismatch detected!"
    fi
    
    if [[ "$found_shadowtls" == *"$shadowtls_password"* ]]; then
        echo "✅ ShadowTLS password verified successfully!"
    else
        echo "❌ WARNING: ShadowTLS password mismatch detected!"
    fi
    
    # Start containers
    docker compose up -d
    
    # Get server IP
    local server_ip=$(get_ipv4)
    local shadowtls_host="weather-data.apple.com"
    local ss_method="chacha20-ietf-poly1305"
    local internal_port="24000"
    
    # Generate SS URI
    local ss_uri=$(generate_ss_uri "$ss_method" "$ss_password" "$server_ip" "$port" "3" "$shadowtls_host" "$shadowtls_password")
    
    # Display connection information with URI and QR code
    local protocol_info="Shadowsocks Port: $internal_port (internal)
Shadowsocks Password: $ss_password
Shadowsocks Method: $ss_method"
    
    display_connection_info "Shadowsocks + ShadowTLS" "$server_ip" "$port" "$shadowtls_password" "$shadowtls_host" "$internal_port" "$protocol_info" "$ss_uri"
    
    cd ..
}

# Function to setup Xray (Shadowsocks 2022) + ShadowTLS
setup_xray_shadowtls() {
    local port=$1
    
    echo "Setting up Xray (Shadowsocks 2022) + ShadowTLS on port $port..."
    
    # Create directory
    mkdir -p shadowtls-xray
    cd shadowtls-xray
    
    # Download compose file and config
    wget -O compose.yaml https://raw.githubusercontent.com/missuo/snell-server-docker/refs/heads/master/compose-shadowsocks2022.yaml
    wget -O config.json https://raw.githubusercontent.com/missuo/snell-server-docker/refs/heads/master/config-shadowsocks2022.json
    
    # Generate passwords
    local ss_password=$(generate_password)
    local shadowtls_password=$(generate_password)
    
    echo "Generated Shadowsocks 2022 password: $ss_password"
    echo "Generated ShadowTLS password: $shadowtls_password"
    
    # Update config.json with password - changed delimiter to # to avoid conflicts
    sed -i "s#\"password\": \"CHANGE_ME\"#\"password\": \"$ss_password\"#g" config.json
    
    # Update compose file with shadowtls password and custom port
    sed -i "s#PASSWORD=CHANGE_ME#PASSWORD=$shadowtls_password#g" compose.yaml
    sed -i "s#LISTEN=0.0.0.0:8443#LISTEN=0.0.0.0:$port#g" compose.yaml
    
    # Verify passwords in config files
    verify_config_password "config.json" "\"password\": " "\"$ss_password\"" "Shadowsocks 2022"
    verify_config_password "compose.yaml" "PASSWORD=" "$shadowtls_password" "ShadowTLS"
    
    # Start containers
    docker compose up -d
    
    # Get server IP
    local server_ip=$(get_ipv4)
    local shadowtls_host="weather-data.apple.com"
    local ss_method="2022-blake3-chacha20-poly1305"
    local internal_port="24000"
    
    # Generate SS URI
    local ss_uri=$(generate_ss_uri "$ss_method" "$ss_password" "$server_ip" "$port" "3" "$shadowtls_host" "$shadowtls_password")
    
    # Display connection information with URI and QR code
    local protocol_info="Shadowsocks 2022 Port: $internal_port (internal)
Shadowsocks 2022 Password: $ss_password
Shadowsocks 2022 Method: $ss_method"
    
    display_connection_info "Xray (Shadowsocks 2022) + ShadowTLS" "$server_ip" "$port" "$shadowtls_password" "$shadowtls_host" "$internal_port" "$protocol_info" "$ss_uri"
    
    cd ..
}

# Function to uninstall any ShadowTLS setup
uninstall_shadowtls() {
    echo "Uninstalling ShadowTLS setups..."
    
    # Check and uninstall Snell + ShadowTLS
    if [ -d "shadowtls-snell" ]; then
        echo "Removing Snell + ShadowTLS..."
        cd shadowtls-snell
        docker compose down
        cd ..
        rm -rf shadowtls-snell
    fi
    
    # Check and uninstall Shadowsocks + ShadowTLS
    if [ -d "shadowtls-shadowsocks" ]; then
        echo "Removing Shadowsocks + ShadowTLS..."
        cd shadowtls-shadowsocks
        docker compose down
        cd ..
        rm -rf shadowtls-shadowsocks
    fi
    
    # Check and uninstall Xray + ShadowTLS
    if [ -d "shadowtls-xray" ]; then
        echo "Removing Xray (Shadowsocks 2022) + ShadowTLS..."
        cd shadowtls-xray
        docker compose down
        cd ..
        rm -rf shadowtls-xray
    fi
    
    # Clean up unused Docker resources
    echo "Cleaning up Docker resources..."
    docker system prune -af
    
    echo "Uninstallation completed successfully!"
}

# Main function
main() {
    # Do NOT clear screen to keep all output visible
    # clear  <-- Removed this line
    
    # Check if running as root
    check_root
    
    # Display welcome message
    echo "====================================================="
    echo "       ShadowTLS Proxy Installation Script           "
    echo "====================================================="
    echo ""
    echo "Please select an option:"
    echo "1) Install Snell + ShadowTLS"
    echo "2) Install Shadowsocks + ShadowTLS"
    echo "3) Install Xray (Shadowsocks 2022) + ShadowTLS"
    echo "4) Uninstall All ShadowTLS Setups"
    echo "5) Exit"
    echo ""
    
    # Get user choice
    read -p "Enter your choice (1-5): " choice
    
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
            read -p "Enter ShadowTLS port (default: $default_port): " custom_port
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
            echo "Exiting. No changes were made."
            exit 0
            ;;
        *)
            echo "Invalid option. Please run the script again and select a valid option."
            exit 1
            ;;
    esac
    
    echo ""
    echo "Operation completed successfully!"
}

# Run main function
main