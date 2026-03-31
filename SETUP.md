# Secure Plex Home Server Setup

This guide covers setting up a secure, optimized Plex server with AMD GPU hardware transcoding and Tailscale VPN for remote access.

## Hardware Requirements
- AMD GPU (detected: Radeon HD 7850)
- Ubuntu Linux host
- Network-attached storage (NAS)

## Security Features
✅ No privileged containers
✅ Credentials stored in `.env` file (not in git)
✅ Tailscale VPN for secure remote access (no port forwarding)
✅ Minimal container permissions
✅ Hardware device access via group permissions

## Initial Setup

### 1. Add your user to GPU groups
This is required for hardware transcoding to work properly:
```bash
sudo usermod -a -G render,video jacob
```
**Important:** Log out and log back in for this to take effect.

### 2. Create your environment file
Copy the example and fill in your credentials:
```bash
cp .env.example .env
nano .env
```

Fill in:
- `NAS_PASSWORD`: Your NAS password
- `TAILSCALE_AUTHKEY`: Get from https://login.tailscale.com/admin/settings/keys
  - Create a new auth key
  - Check "Reusable" and set "Expiration: Never" for this server
  - Add tag: `tag:server` (create this tag in Tailscale admin if needed)

### 3. Create Tailscale state directory
```bash
sudo mkdir -p /var/lib/tailscale
sudo chown root:root /var/lib/tailscale
sudo chmod 700 /var/lib/tailscale
```

### 4. Run the setup script
```bash
chmod +x docker-up.sh
./docker-up.sh
```

## Usage

### Starting the server
```bash
./docker-up.sh
```

This script will:
1. Install Docker if needed
2. Create required directories
3. Wake up the NAS
4. Mount network shares
5. Start Tailscale and Plex containers

### Stopping the server
```bash
./docker-down.sh
```

### Checking status
```bash
docker ps
docker logs plex
docker logs tailscale
```

### Get your Tailscale IP
```bash
docker exec tailscale tailscale ip -4
```

## OpenShift Deployment

An alternative to the Docker Compose setup, the OpenShift manifests in `openshift/` deploy Plex and Tidal to a local OpenShift cluster.

### Starting the cluster workloads
```bash
oc login <your-cluster>
./openshift-up.sh
```

This script will:
1. Wake the NAS and mount the CIFS share
2. Apply all OpenShift manifests (namespace, service accounts, SCCs, PVs, PVCs, secrets)
3. Build the tidal-dl image via the OpenShift internal registry
4. Deploy the Plex and Tidal pods

### Stopping the cluster workloads
```bash
./openshift-down.sh
```

### Checking status
```bash
oc get pods -n home-server
oc logs deployment/plex -n home-server
oc logs deployment/tidal -n home-server
```

### Using tidal-dl

The tidal container runs as a long-lived pod that you exec into to download music.

**1. Open a shell in the tidal pod:**
```bash
oc exec -it deployment/tidal -n home-server -- sh
```

**2. First-time setup — log in to Tidal:**
```bash
tidal-dl
```
Follow the prompts to authenticate. Your token is persisted in the `tidal-config-pvc` volume at `/root/.config/tidal`, so you only need to do this once.

**3. Download an album or track:**
```bash
tidal-dl -l <tidal-url-or-id>
```
For example:
```bash
tidal-dl -l https://tidal.com/browse/album/12345678
```

Downloads land in `/root/downloads` inside the pod (backed by `tidal-downloads-pvc`).

**4. Move downloads into the Plex library:**

The Plex media volume is mounted at `/data/Plex` inside the tidal pod. Copy or move your downloads there so Plex can pick them up:
```bash
mv /root/downloads/ArtistName /data/Plex/Music/
```

After moving files, trigger a library scan in Plex (Settings → Libraries → Scan Library Files) or wait for the scheduled scan.

**5. Exit the pod:**
```bash
exit
```

**Tip:** You can run a one-off download without an interactive shell:
```bash
oc exec deployment/tidal -n home-server -- tidal-dl -l <tidal-url-or-id>
```

## Remote Access Setup

### On this server
The Tailscale container automatically connects your server to your Tailscale network.

### On remote devices (phone, laptop, etc.)
1. Install Tailscale: https://tailscale.com/download
2. Log in with the same account you used to create the auth key
3. Find your Plex server's Tailscale IP:
   ```bash
   docker exec tailscale tailscale status
   ```
4. Access Plex at: `http://<tailscale-ip>:32400/web`

## Hardware Transcoding

Your AMD Radeon HD 7850 is configured for hardware transcoding:
- Uses VAAPI (Video Acceleration API)
- Driver: `radeonsi`
- Device: `/dev/dri/renderD128`

### Enable in Plex
1. Go to Settings → Transcoder
2. Enable "Use hardware acceleration when available"
3. Hardware transcoding requires Plex Pass

### Verify it's working
```bash
# Check if Plex can access the GPU
docker exec plex ls -l /dev/dri/

# Monitor GPU usage during transcoding
intel_gpu_top  # or radeontop for AMD
```

## Security Best Practices

### Network Security
- ✅ No ports forwarded on your router
- ✅ All remote access via encrypted Tailscale VPN
- ✅ Only authenticated devices can connect
- ✅ Containers run as non-root user (UID 1000)

### Credential Security
- ✅ Sensitive data in `.env` (excluded from git)
- ✅ No hardcoded passwords
- ✅ Tailscale auth key can be rotated

### Container Security
- ✅ No privileged mode
- ✅ Minimal capabilities (only NET_ADMIN/NET_RAW for Tailscale)
- ✅ Read-only root filesystem where possible
- ✅ Resource limits can be added if needed

### Optional: Add resource limits
Edit `docker-compose.yml` and add under each service:
```yaml
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 4G
```

### Optional: Enable Ubuntu firewall
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 100.64.0.0/10  # Allow Tailscale network
sudo ufw enable
```

## Performance Tuning

### Transcoding Directory
The transcode directory is on local storage (`/media/volume/plex/transcode`) for best performance. Ensure this is on an SSD if possible.

### Network Mount Performance
The media files are on a NAS. For best performance:
- Use gigabit or faster network
- Consider SMB3 multi-channel if your NAS supports it
- Keep the server close to the NAS (same switch/router)

### GPU Driver Updates
Keep your AMD drivers updated for best transcoding performance:
```bash
sudo apt update
sudo apt install mesa-va-drivers
```

## Troubleshooting

### GPU not accessible
```bash
# Check groups
id jacob

# Should include: video(44) render(110)
# If not, run: sudo usermod -a -G render,video jacob
# Then log out and back in
```

### NAS won't mount
```bash
# Test connection
ping net-store.local
nc -zv net-store.local 445

# Manual mount test
sudo mount -t cifs -o username=a4d //net-store.local/Plex /media/Plex/
```

### Tailscale not connecting
```bash
# Check logs
docker logs tailscale

# Verify auth key is correct in .env
cat .env | grep TAILSCALE

# Manually authenticate (alternative to auth key)
docker exec -it tailscale tailscale up
```

### Plex remote access not working
- Don't enable Plex's built-in "Remote Access" feature
- Use Tailscale IP instead: `http://<tailscale-ip>:32400/web`
- Check Tailscale status: `docker exec tailscale tailscale status`

## Maintenance

### Update containers
```bash
docker compose pull
docker compose up -d
```

### View logs
```bash
docker logs -f plex
docker logs -f tailscale
```

### Backup configuration
Important directories to backup:
- `/media/volume/plex/config` - Plex database and settings
- `/var/lib/tailscale` - Tailscale connection state
- `.env` - Your credentials (keep secure!)

## Additional Resources
- Plex documentation: https://support.plex.tv
- Tailscale documentation: https://tailscale.com/kb
- AMD GPU transcoding: https://www.plex.tv/blog/introducing-hardware-accelerated-transcoding
