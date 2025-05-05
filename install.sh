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

# Function to generate random passwords
generate_password() {
    openssl rand -base64 32
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
    
    # Update compose file with passwords and custom port
    sed -i "s/PSK=CHANGE_ME/PSK=$snell_password/" compose.yaml
    sed -i "s/PASSWORD=CHANGE_ME/PASSWORD=$shadowtls_password/" compose.yaml
    sed -i "s/LISTEN=0.0.0.0:8443/LISTEN=0.0.0.0:$port/" compose.yaml
    
    # Start containers
    docker compose up -d
    
    # Display connection information
    echo "=============================================="
    echo "Snell + ShadowTLS has been set up successfully!"
    echo "=============================================="
    echo "Server Address: $(curl -s ifconfig.me)"
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
    
    # Update compose file with passwords and custom port
    sed -i "s/PASSWORD=CHANGE_ME/PASSWORD=$ss_password/" compose.yaml
    sed -i "0,/PASSWORD=CHANGE_ME/s//PASSWORD=$shadowtls_password/" compose.yaml
    sed -i "s/LISTEN=0.0.0.0:8443/LISTEN=0.0.0.0:$port/" compose.yaml
    
    # Start containers
    docker compose up -d
    
    # Display connection information
    echo "=============================================="
    echo "Shadowsocks + ShadowTLS has been set up successfully!"
    echo "=============================================="
    echo "Server Address: $(curl -s ifconfig.me)"
    echo "ShadowTLS Port: $port"
    echo "ShadowTLS Password: $shadowtls_password"
    echo "ShadowTLS TLS Server: weather-data.apple.com:443"
    echo "Shadowsocks Port: 24000 (internal)"
    echo "Shadowsocks Password: $ss_password"
    echo "Shadowsocks Method: chacha20-ietf-poly1305"
    echo "=============================================="
    
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
    
    # Update config.json with password
    sed -i "s/\"password\": \"CHANGE_ME\"/\"password\": \"$ss_password\"/" config.json
    
    # Update compose file with shadowtls password and custom port
    sed -i "s/PASSWORD=CHANGE_ME/PASSWORD=$shadowtls_password/" compose.yaml
    sed -i "s/LISTEN=0.0.0.0:8443/LISTEN=0.0.0.0:$port/" compose.yaml
    
    # Start containers
    docker compose up -d
    
    # Display connection information
    echo "=============================================="
    echo "Xray (Shadowsocks 2022) + ShadowTLS has been set up successfully!"
    echo "=============================================="
    echo "Server Address: $(curl -s ifconfig.me)"
    echo "ShadowTLS Port: $port"
    echo "ShadowTLS Password: $shadowtls_password"
    echo "ShadowTLS TLS Server: weather-data.apple.com:443"
    echo "Shadowsocks 2022 Port: 24000 (internal)"
    echo "Shadowsocks 2022 Password: $ss_password"
    echo "Shadowsocks 2022 Method: 2022-blake3-chacha20-poly1305"
    echo "=============================================="
    
    cd ..
}

# Main function
main() {
    # Clear screen
    clear
    
    # Check if running as root
    check_root
    
    # Check and install Docker if needed
    check_docker
    
    # Display welcome message
    echo "====================================================="
    echo "       ShadowTLS Proxy Installation Script           "
    echo "====================================================="
    echo ""
    echo "Please select an installation option:"
    echo "1) Snell + ShadowTLS"
    echo "2) Shadowsocks + ShadowTLS"
    echo "3) Xray (Shadowsocks 2022) + ShadowTLS"
    echo "4) Exit"
    echo ""
    
    # Get user choice
    read -p "Enter your choice (1-4): " choice
    
    # Default port
    default_port=8443
    
    # Ask for custom port
    read -p "Enter ShadowTLS port (default: $default_port): " custom_port
    port=${custom_port:-$default_port}
    
    # Process user choice
    case $choice in
        1)
            setup_snell_shadowtls $port
            ;;
        2)
            setup_shadowsocks_shadowtls $port
            ;;
        3)
            setup_xray_shadowtls $port
            ;;
        4)
            echo "Exiting installation. No changes were made."
            exit 0
            ;;
        *)
            echo "Invalid option. Please run the script again and select a valid option."
            exit 1
            ;;
    esac
    
    echo ""
    echo "Installation completed successfully!"
    echo "To check logs, navigate to the installation directory and run: docker compose logs"
}

# Run main function
main