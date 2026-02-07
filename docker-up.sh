#!/bin/bash
set -e

# Load environment variables from .env file
if [ -f .env ]; then
    # Use set -a to export all variables automatically
    set -a
    source .env
    set +a
else
    echo "ERROR: .env file not found. Please create one from .env.example"
    exit 1
fi

# Create CIFS credentials file for secure mounting
CREDS_FILE="/tmp/.nas_credentials_$$"
cat > "$CREDS_FILE" <<EOF
username=${NAS_USERNAME}
password=${NAS_PASSWORD}
EOF
chmod 600 "$CREDS_FILE"

# Cleanup function to remove credentials file
cleanup() {
    rm -f "$CREDS_FILE"
}
trap cleanup EXIT

# Install tools and docker dependencies
sudo apt update -y
sudo apt install -y ca-certificates curl gnupg cifs-utils netcat-openbsd

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y

sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Function to wait for NAS to be ready
wait_for_nas() {
    local host="${NAS_HOST}"
    local max_attempts=10
    local attempt=0
    
    echo "Waking up NAS at $host..."
    
    # Initial ping to wake the drive (use correct syntax)
    ping -c 3 "$host" > /dev/null 2>&1
    
    # Wait for SMB port (445) to be available
    while [ $attempt -lt $max_attempts ]; do
        if nc -z -w 2 "$host" 445 2>/dev/null; then
            echo "NAS is awake and SMB service is ready!"
            # Give it a moment for shares to fully initialize
            sleep 2
            return 0
        fi
        
        echo "Waiting for NAS to wake up... (attempt $((attempt + 1))/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "ERROR: NAS did not wake up within expected time"
    return 1
}


# Create plex directories
mkdir -p /media/Plex \
	/media/volume/plex/data/temp \
	/media/volume/plex/config \
	/media/volume/plex/transcode \
	/media/Downloads \
	/media/Sonarr

# Create emby directories
mkdir -p /media/Emby \
	/media/volume/emby/data/temp \
	/media/volume/emby/config \
	/media/volume/emby/transcode

# Wake NAS and wait for it to be ready
if ! wait_for_nas; then
    echo "Failed to wake NAS. Exiting."
    exit 1
fi

# Mount network drives using credentials file
sudo mount -t cifs -o uid=${PLEX_UID},credentials="$CREDS_FILE" //${NAS_HOST}/Plex /media/Plex/ || {
    echo "Failed to mount Plex share"
    echo "Check that:"
    echo "  1. NAS is accessible: ping ${NAS_HOST}"
    echo "  2. Credentials are correct in .env file"
    echo "  3. Share name is correct: //${NAS_HOST}/Plex"
    exit 1
}

echo "Mounts successful!"

# Start Docker daemon
sudo systemctl start docker

# Start container
docker compose up -d
