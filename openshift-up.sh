#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Load environment variables from .env
# ---------------------------------------------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
else
    echo "ERROR: .env file not found. Please create one from .env.example"
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify oc CLI is available
# ---------------------------------------------------------------------------
if ! command -v oc &>/dev/null; then
    echo "ERROR: 'oc' CLI not found. Install it from https://mirror.openshift.com/pub/openshift-v4/clients/oc/"
    exit 1
fi

# Quick cluster health check
if ! oc whoami &>/dev/null; then
    echo "ERROR: Not logged in to an OpenShift cluster. Run 'oc login' first."
    exit 1
fi

echo "Logged in as $(oc whoami) on $(oc whoami --show-server)"

# ---------------------------------------------------------------------------
# Create CIFS credentials file for secure mounting
# ---------------------------------------------------------------------------
CREDS_FILE="/tmp/.nas_credentials_$$"
cat > "$CREDS_FILE" <<EOF
username=${NAS_USERNAME}
password=${NAS_PASSWORD}
EOF
chmod 600 "$CREDS_FILE"

cleanup() {
    rm -f "$CREDS_FILE"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Wake NAS and mount CIFS share (same logic as docker-up.sh)
# ---------------------------------------------------------------------------
wait_for_nas() {
    local host="${NAS_HOST}"
    local max_attempts=10
    local attempt=0

    echo "Waking up NAS at $host..."
    ping -c 3 "$host" > /dev/null 2>&1 || true

    while [ $attempt -lt $max_attempts ]; do
        if nc -z -w 2 "$host" 445 2>/dev/null; then
            echo "NAS is awake and SMB service is ready!"
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

# Create required directories
sudo mkdir -p /media/Plex \
    /media/volume/plex/data/temp \
    /media/volume/plex/config \
    /media/volume/plex/transcode \
    /media/volume/tidal/downloads \
    /media/volume/tidal/config

# Wake NAS and wait for it
if ! wait_for_nas; then
    echo "Failed to wake NAS. Exiting."
    exit 1
fi

# Mount NAS share (skip if already mounted)
if mountpoint -q /media/Plex; then
    echo "NAS share already mounted at /media/Plex"
else
    sudo mount -t cifs -o "uid=${PLEX_UID},credentials=$CREDS_FILE" \
        "//${NAS_HOST}/Plex" /media/Plex/ || {
        echo "Failed to mount Plex share"
        echo "Check that:"
        echo "  1. NAS is accessible: ping ${NAS_HOST}"
        echo "  2. Credentials are correct in .env file"
        echo "  3. Share name is correct: //${NAS_HOST}/Plex"
        exit 1
    }
    echo "NAS share mounted."
fi

# ---------------------------------------------------------------------------
# Apply OpenShift manifests (order matters)
# ---------------------------------------------------------------------------
MANIFESTS="$SCRIPT_DIR/openshift"

echo ""
echo "Applying OpenShift manifests..."

# 1. Namespace
oc apply -f "$MANIFESTS/namespace.yml"

# 2. Service accounts (must exist before SCCs reference them)
oc apply -f "$MANIFESTS/plex-sa.yml"
oc apply -f "$MANIFESTS/tidal-sa.yml"

# 3. Security Context Constraints (cluster-scoped, needs cluster-admin)
oc apply -f "$MANIFESTS/plex-scc.yml"
oc apply -f "$MANIFESTS/tidal-scc.yml"

# 4. Secret — substitute env vars into the template
envsubst < "$MANIFESTS/plex-secret.yml" | oc apply -f -

# 5. Persistent Volumes (cluster-scoped) and PVCs (namespaced)
oc apply -f "$MANIFESTS/plex-pv.yml"
oc apply -f "$MANIFESTS/tidal-pv.yml"
oc apply -f "$MANIFESTS/plex-pvc.yml"
oc apply -f "$MANIFESTS/tidal-pvc.yml"

# 6. Build tidal image (ImageStream + BuildConfig, then trigger build)
oc apply -f "$MANIFESTS/tidal-buildconfig.yml"
echo ""
echo "Building tidal image..."
oc start-build tidal -n home-server --from-dir="$SCRIPT_DIR" --follow || {
    echo "WARNING: tidal image build failed. The tidal deployment may not start."
    echo "You can retry with: oc start-build tidal -n home-server --from-dir=$SCRIPT_DIR --follow"
}

# 7. Deployments
oc apply -f "$MANIFESTS/plex-deployment.yml"
oc apply -f "$MANIFESTS/tidal-deployment.yml"

# ---------------------------------------------------------------------------
# Wait for rollouts
# ---------------------------------------------------------------------------
echo ""
echo "Waiting for Plex deployment to roll out..."
oc rollout status deployment/plex -n home-server --timeout=120s

echo "Waiting for Tidal deployment to roll out..."
oc rollout status deployment/tidal -n home-server --timeout=120s

echo ""
echo "All pods:"
oc get pods -n home-server
