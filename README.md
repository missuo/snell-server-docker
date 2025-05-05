# Snell-Server-Docker

This repository packages [Snell Server](https://manual.nssurge.com/others/snell.html) into a Docker image for easy deployment and integration with ShadowTLS. It also supports Shadowsocks + ShadowTLS deployment.

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Basic understanding of proxy servers
- Server with open ports (recommended: 443)

## Deployment Options

### Option 1: Snell + ShadowTLS

```bash
# Create directory and navigate to it
mkdir shadowtls-snell
cd shadowtls-snell

# Download compose file
wget -O compose.yaml https://raw.githubusercontent.com/missuo/snell-server-docker/refs/heads/master/compose-snell.yaml

# Generate random password for enhanced security
PASSWORD=$(openssl rand -base64 32)
echo "Generated password: $PASSWORD"

# Edit the compose file with your configuration
nano compose.yaml

# Start the containers
docker compose up -d

# Check logs
docker compose logs
```

### Option 2: Shadowsocks + ShadowTLS

```bash
# Create directory and navigate to it
mkdir shadowtls-shadowsocks
cd shadowtls-shadowsocks

# Download compose file
wget -O compose.yaml https://raw.githubusercontent.com/missuo/snell-server-docker/refs/heads/master/compose-shadowsocks.yaml

# Generate random password for enhanced security
PASSWORD=$(openssl rand -base64 32)
echo "Generated password: $PASSWORD"

# Edit the compose file with your configuration
nano compose.yaml

# Start the containers
docker compose up -d

# Check logs
docker compose logs
```

## Client Configuration

### Surge for iOS/macOS

Add the following to your Surge configuration:

#### For Snell + ShadowTLS:

```
[Proxy]
my-snell = snell, your-server-ip, 8888, psk=your-snell-password, version=4, tfo=true, reuse=true, shadow-tls-password=shadowtls-pass, shadow-tls-version=3, shadow-tls-sni=weather-data.apple.com
```

#### For Shadowsocks + ShadowTLS:

```
[Proxy]
my-shadowsocks = ss, your-server-ip, 8443, encrypt-method=chacha20-ietf-poly1305, password=shadowsocks-pass, reuse=true, shadow-tls-password=shadowtls-pass, shadow-tls-version=3, shadow-tls-sni=weather-data.apple.com
```
