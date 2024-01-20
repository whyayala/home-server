# Install tools and a bunch of docker shit.
sudo apt update -y
sudo apt install -y ca-certificates curl gnupg cifs-utils

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y

sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

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
sudo docker-compose up -d
