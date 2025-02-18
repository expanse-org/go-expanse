#!/bin/bash

set -e  # Exit on any error

# Variables
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/gexp.service"
LOG_FILE="/var/log/gexp.log"
JSON_URL="https://raw.githubusercontent.com/expanse-org/mist/refs/heads/master/clientBinaries.json"

# Install dependencies
echo "Installing required dependencies..."
sudo apt update && sudo apt install -y jq curl tar unzip

# Fetch and parse clientBinaries.json
echo "Fetching client binaries information..."
CLIENT_BINARIES=$(curl -sSL "$JSON_URL")

if [[ -z "$CLIENT_BINARIES" ]]; then
    echo "Failed to fetch client binaries information."
    exit 1
fi

# Detect system architecture and OS
ARCH=$(uname -m)
OS=$(uname | tr '[:upper:]' '[:lower:]')

case "$ARCH" in
    x86_64) ARCH="x64" ;;
    i386|i686) ARCH="ia32" ;;
    aarch64) ARCH="arm64" ;;  # Not present in JSON but included for completeness
    armv7l) ARCH="arm" ;;      # Not present in JSON but included for completeness
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Extract relevant values using jq
DOWNLOAD_URL=$(echo "$CLIENT_BINARIES" | jq -r --arg OS "$OS" --arg ARCH "$ARCH" '.clients.Gexp.platforms[$OS][$ARCH].download.url')
FILE_TYPE=$(echo "$CLIENT_BINARIES" | jq -r --arg OS "$OS" --arg ARCH "$ARCH" '.clients.Gexp.platforms[$OS][$ARCH].download.type')
MD5_CHECKSUM=$(echo "$CLIENT_BINARIES" | jq -r --arg OS "$OS" --arg ARCH "$ARCH" '.clients.Gexp.platforms[$OS][$ARCH].download.md5')
BIN_NAME=$(echo "$CLIENT_BINARIES" | jq -r --arg OS "$OS" --arg ARCH "$ARCH" '.clients.Gexp.platforms[$OS][$ARCH].download.bin')

# Validate extracted values
if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then echo "Error: Failed to extract download URL."; exit 1; fi
if [[ -z "$FILE_TYPE" || "$FILE_TYPE" == "null" ]]; then echo "Error: Failed to extract file type."; exit 1; fi
if [[ -z "$MD5_CHECKSUM" || "$MD5_CHECKSUM" == "null" ]]; then echo "Error: Failed to extract MD5 checksum."; exit 1; fi
if [[ -z "$BIN_NAME" || "$BIN_NAME" == "null" ]]; then echo "Error: Failed to extract binary name."; exit 1; fi

# Define binary path
BIN_PATH="$INSTALL_DIR/gexp"

# Download the binary
echo "Downloading gexp binary from $DOWNLOAD_URL..."
curl -sSL -o /tmp/gexp_download "$DOWNLOAD_URL"

# Verify the download (MD5 checksum)
echo "Verifying checksum..."
DOWNLOADED_MD5=$(md5sum /tmp/gexp_download | awk '{print $1}')
if [[ "$DOWNLOADED_MD5" != "$MD5_CHECKSUM" ]]; then
    echo "Error: MD5 checksum mismatch!"
    exit 1
fi

# Extract the binary based on the file type
echo "Extracting binary..."
case "$FILE_TYPE" in
    tar) tar -xzf /tmp/gexp_download -C /tmp ;;
    zip) unzip -o /tmp/gexp_download -d /tmp ;;
    *) echo "Error: Unknown file type $FILE_TYPE"; exit 1 ;;
esac

# Move the binary to the install directory
echo "Installing binary to $BIN_PATH..."
sudo mv "/tmp/$BIN_NAME" "$BIN_PATH"
sudo chmod +x "$BIN_PATH"

# Clean up
rm -f /tmp/gexp_download

# Create a systemd service file
echo "Creating systemd service..."
sudo bash -c "cat > $SERVICE_FILE" <<EOL
[Unit]
Description=GEXP Node
After=network.target

[Service]
ExecStart=$BIN_PATH --gcmode=archive --syncmode=full --http --http.addr "0.0.0.0" --http.vhosts="*" --ws --ws.addr="0.0.0.0" --ws.origins "*" --http.api "web3,eth,txpool,net,exp" --ws.api="web3,eth,txpool,net,exp" --snapshot=false --http.corsdomain "*"
Restart=always
User=root
Group=root
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOL

# Ensure log file exists and has correct permissions
sudo touch "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"

# Reload systemd and enable the service
echo "Starting and enabling gexp service..."
sudo systemctl daemon-reload
sudo systemctl enable gexp
sudo systemctl start gexp

echo "Installation complete. GEXP is now running as a systemd service."
