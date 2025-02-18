#!/bin/bash

# Variables
INSTALL_DIR="/usr/local/bin"
DATA_DIR="~/.expanse"
SERVICE_FILE="/etc/systemd/system/gexp.service"
LOG_FILE="/var/log/gexp.log"
JSON_URL="https://raw.githubusercontent.com/expanse-org/mist/refs/heads/master/clientBinaries.json"

# Detect system architecture and OS
ARCH=$(uname -m)
OS=$(uname | tr '[:upper:]' '[:lower:]')

case "$ARCH" in
    x86_64)
        ARCH="x64"
        ;;
    i386|i686)
        ARCH="ia32"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Fetch the clientBinaries.json
echo "Fetching client binaries information..."
CLIENT_BINARIES=$(curl -sSL "$JSON_URL")

if [[ -z "$CLIENT_BINARIES" ]]; then
    echo "Failed to fetch client binaries information."
    exit 1
fi

# Parse JSON to get the download URL, file type, MD5 checksum, and binary path
DOWNLOAD_URL=$(echo "$CLIENT_BINARIES" | grep -oP '"url":\s*"\K[^"]+(?=")' | grep "$OS" | grep "$ARCH")
FILE_TYPE=$(echo "$CLIENT_BINARIES" | grep -oP '"type":\s*"\K[^"]+(?=")' | grep "$OS" | grep "$ARCH")
MD5_CHECKSUM=$(echo "$CLIENT_BINARIES" | grep -oP '"md5":\s*"\K[^"]+(?=")' | grep "$OS" | grep "$ARCH")
BIN_PATH=$(echo "$CLIENT_BINARIES" | grep -oP '"bin":\s*"\K[^"]+(?=")' | grep "$OS" | grep "$ARCH")

if [[ -z "$DOWNLOAD_URL" || -z "$FILE_TYPE" || -z "$MD5_CHECKSUM" || -z "$BIN_PATH" ]]; then
    echo "Failed to parse client binaries information."
    exit 1
fi

# Download the GEXP binary
echo "Downloading GEXP from $DOWNLOAD_URL..."
curl -L -o gexp_download "$DOWNLOAD_URL"

if [[ $? -ne 0 ]]; then
    echo "Failed to download GEXP. Check the URL and network connection."
    exit 1
fi

# Verify MD5 checksum
echo "Verifying download integrity..."
DOWNLOADED_MD5=$(md5sum gexp_download | awk '{ print $1 }')

if [[ "$DOWNLOADED_MD5" != "$MD5_CHECKSUM" ]]; then
    echo "MD5 checksum verification failed."
    rm gexp_download
    exit 1
fi

# Extract the binary
echo "Extracting GEXP..."
case "$FILE_TYPE" in
    tar)
        tar -xzf gexp_download
        ;;
    zip)
        unzip gexp_download
        ;;
    *)
        echo "Unsupported file type: $FILE_TYPE"
        rm gexp_download
        exit 1
        ;;
esac

rm gexp_download

# Move the binary to the installation directory
echo "Installing GEXP to $INSTALL_DIR..."
chmod +x "$BIN_PATH"
mv "$BIN_PATH" "$INSTALL_DIR/gexp"

# Create the data directory if it doesn't exist
mkdir -p "$DATA_DIR"

# Create systemd service
echo "Creating systemd service..."
cat <<EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=GEXP Node Service
After=network.target

[Service]
User=$(whoami)
ExecStart=/bin/bash -c '$INSTALL_DIR/gexp --gcmode=archive --syncmode=full --http --http.addr "0.0.0.0" --http.vhosts="*" --ws --ws.addr="0.0.0.0" --ws.origins "*" --datadir="$DATA_DIR" --http.api "web3,eth,txpool,net,exp" --ws.api="web3,eth,txpool,net,exp" --snapshot=false --http.corsdomain "*" console'
Restart=always
RestartSec=10
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and start the service
echo "Enabling and starting GEXP service..."
sudo systemctl daemon-reload
sudo systemctl enable gexp
sudo systemctl start gexp

echo "Installation complete! Check service status with:"
echo "sudo systemctl status gexp"

