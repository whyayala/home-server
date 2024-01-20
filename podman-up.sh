# Install tools
sudo apt install podman cifs-utils containernetworking-plugins -y
sudo apt update
sudo curl -o /usr/local/bin/podman-compose https://raw.githubusercontent.com/containers/podman-compose/devel/podman_compose.py \
	&& sudo chmod +x /usr/local/bin/podman-compose

# Create plex directories
sudo mkdir -p /media/Plex \
	/media/volume/plex/data/temp \
	/media/volume/plex/config \
	/media/volume/plex/transcode \
	/media/Downloads \
	/media/Sonarr

# Create emby directories
sudo mkdir -p /media/Emby \
	/media/volume/emby/data/temp \
	/media/volume/emby/config \
	/media/volume/emby/transcode

# Mount network drive
sudo mount -t cifs -o username=a4d,password=$1 //net-store.local/Plex /media/Plex/
sudo mount -t cifs -o username=a4d,password=$1 //net-store.local/Emby /media/Emby/

# Start container
sudo podman-compose up -d
