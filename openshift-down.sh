#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/openshift"

# ---------------------------------------------------------------------------
# Verify oc CLI is available and logged in
# ---------------------------------------------------------------------------
if ! command -v oc &>/dev/null; then
    echo "ERROR: 'oc' CLI not found."
    exit 1
fi

if ! oc whoami &>/dev/null; then
    echo "ERROR: Not logged in to an OpenShift cluster. Run 'oc login' first."
    exit 1
fi

echo "Tearing down home-server resources..."

# ---------------------------------------------------------------------------
# Delete namespaced resources (deployments, PVCs, secrets, service accounts)
# ---------------------------------------------------------------------------
oc delete -f "$MANIFESTS/plex-deployment.yml" --ignore-not-found
oc delete -f "$MANIFESTS/tidal-deployment.yml" --ignore-not-found
oc delete -f "$MANIFESTS/tidal-buildconfig.yml" --ignore-not-found
oc delete -f "$MANIFESTS/plex-pvc.yml" --ignore-not-found
oc delete -f "$MANIFESTS/tidal-pvc.yml" --ignore-not-found
oc delete -f "$MANIFESTS/plex-secret.yml" --ignore-not-found 2>/dev/null || true
oc delete -f "$MANIFESTS/plex-sa.yml" --ignore-not-found
oc delete -f "$MANIFESTS/tidal-sa.yml" --ignore-not-found

# ---------------------------------------------------------------------------
# Delete cluster-scoped resources
# ---------------------------------------------------------------------------
oc delete -f "$MANIFESTS/plex-pv.yml" --ignore-not-found
oc delete -f "$MANIFESTS/tidal-pv.yml" --ignore-not-found
oc delete -f "$MANIFESTS/plex-scc.yml" --ignore-not-found
oc delete -f "$MANIFESTS/tidal-scc.yml" --ignore-not-found

# ---------------------------------------------------------------------------
# Delete namespace (catches anything left over)
# ---------------------------------------------------------------------------
oc delete -f "$MANIFESTS/namespace.yml" --ignore-not-found

echo "OpenShift resources deleted."

# ---------------------------------------------------------------------------
# Unmount NAS share
# ---------------------------------------------------------------------------
if mountpoint -q /media/Plex; then
    sudo umount /media/Plex
    echo "NAS share unmounted."
else
    echo "NAS share was not mounted."
fi

echo "Done."
