#!/bin/ash

set -e

BIN="/usr/bin/snell-server"
CONF="/etc/snell-server.conf"

# reuse existing config when the container restarts

run_bin() {
    echo "Running snell-server with config:"
    echo ""
    cat ${CONF}

    ${BIN} --version
    ${BIN} -c ${CONF}
}

if [ -f ${CONF} ]; then
    echo "Found existing config, rm it."
    rm ${CONF}
fi

if [ -z "${PSK}" ]; then
    PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    echo "Using generated PSK: ${PSK}"
else
    echo "Using predefined PSK: ${PSK}"
fi

# Set default LISTEN if not provided
if [ -z "${LISTEN}" ]; then
    LISTEN="127.0.0.1:9102"
    echo "Using default LISTEN: ${LISTEN}"
else
    echo "Using provided LISTEN: ${LISTEN}"
fi

# Set default IPV6 if not provided
if [ -z "${IPV6}" ]; then
    IPV6="true"
    echo "Using default IPV6: ${IPV6}"
else
    echo "Using provided IPV6: ${IPV6}"
fi

echo "Generating new config..."
echo "[snell-server]" >> ${CONF}
echo "listen = ${LISTEN}" >> ${CONF}
echo "psk = ${PSK}" >> ${CONF}
echo "ipv6 = ${IPV6}" >> ${CONF}
run_bin