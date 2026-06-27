Phase 1 Fresh Ubuntu install
--------------------------------------------------------------------------------------------------------------------------
1 Install Ubuntu 24.04 LTS — same version
    Boot from USB. Use same hostname: vinothserver. Create user vinoth with same password.
2 First update
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git unzip net-tools
3 Disable IPv6 immediately (same fix as before)
    echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
==========================================================================================================================
Phase 2 Install Rclone and pull backup from Google Drive
--------------------------------------------------------------------------------------------------------------------------
4 Install Rclone
    curl https://rclone.org/install.sh | sudo bash
5 Configure Google Drive remote (same as before)
    rclone config
    # n → gdrive → drive → scope 1 → n (headless) → paste auth URL in browser → q
    This is the only manual step that needs a browser
6 List available backups — pick the latest
    rclone lsd gdrive:vinothserver-backups/
    # Shows all dated folders e.g. 20260627_0200/
7 Download latest backup archive
    mkdir -p ~/restore
    rclone copy gdrive:vinothserver-backups/20260627_0200/ ~/restore/ --progress
    ls -lh ~/restore/
    # Should show: vinothserver-full-backup-20260627_0200.tar.gz
8 Extract the archive
    cd ~/restore
    tar xzf vinothserver-full-backup-*.tar.gz
    ls full-server-backup-*/
    # Shows: server/ k8s/ jenkins/ docker/ databases/ apps/ meta/
==========================================================================================================================
Phase 3 Restore system configs and packages
--------------------------------------------------------------------------------------------------------------------------
9 Restore /etc (all system config)
    sudo tar xzf ~/restore/full-server-backup-*/server/etc.tar.gz -C /
    sudo systemctl daemon-reload
    This restores nginx, ssh, cloudflared, samba, ufw — everything in /etc
10 Restore home directory
    tar xzf ~/restore/full-server-backup-*/users/home-vinoth.tar.gz -C /
11 Reinstall all packages from saved list
    sudo dpkg --set-selections < ~/restore/full-server-backup-*/system/dpkg-packages.txt
    sudo apt-get dselect-upgrade -y
12 Restore crontabs
    crontab ~/restore/full-server-backup-*/users/crontab-vinoth.txt
    sudo crontab ~/restore/full-server-backup-*/users/crontab-root.txt
==========================================================================================================================
Phase 4 Restore services — Cloudflare, Nginx, Jenkins
--------------------------------------------------------------------------------------------------------------------------
13 Install and restore Cloudflare Tunnel
    sudo apt install -y cloudflared
    sudo tar xzf ~/restore/full-server-backup-*/services/cloudflared.tar.gz -C /
    sudo systemctl enable cloudflared
    sudo systemctl start cloudflared
    # ideanow.info should come back online
14 Install and restore Nginx
    sudo apt install -y nginx
    sudo tar xzf ~/restore/full-server-backup-*/services/nginx.tar.gz -C /
    sudo nginx -t && sudo systemctl restart nginx
15 Install and restore Jenkins
# Install Java + Jenkins
    sudo apt install -y openjdk-17-jdk
    curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list
    sudo apt update && sudo apt install -y jenkins

# Stop Jenkins before restoring data
    sudo systemctl stop jenkins
    sudo tar xzf ~/restore/full-server-backup-*/services/jenkins.tar.gz -C /
    sudo chown -R jenkins:jenkins /var/lib/jenkins
    sudo systemctl start jenkins
    All jobs, credentials, pipeline configs restored automatically
16 Copy Rclone config to Jenkins user
    sudo mkdir -p /var/lib/jenkins/.config/rclone
    sudo cp ~/.config/rclone/rclone.conf /var/lib/jenkins/.config/rclone/
    sudo chown -R jenkins:jenkins /var/lib/jenkins/.config/rclone
==========================================================================================================================
Phase 5 Restore Docker and Kubernetes
--------------------------------------------------------------------------------------------------------------------------
17 Install Docker
    curl -fsSL https://get.docker.com | sudo bash
    sudo usermod -aG docker vinoth
    sudo systemctl enable docker
18 Restore Docker volumes
    ls ~/restore/full-server-backup-*/docker/volumes/
    # Restore each volume:
    for VOL_FILE in ~/restore/full-server-backup-*/docker/volumes/*.tar.gz; do
      VOL_NAME=$(basename $VOL_FILE .tar.gz)
      docker volume create $VOL_NAME
      docker run --rm \
        -v ${VOL_NAME}:/data \
        -v $(dirname $VOL_FILE):/backup \
        alpine tar xzf /backup/${VOL_NAME}.tar.gz -C /data
    done
19 Reinstall kubeadm cluster
    sudo apt install -y kubelet kubeadm kubectl
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16
    mkdir -p ~/.kube
    sudo cp /etc/kubernetes/admin.conf ~/.kube/config
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
20 Restore all Kubernetes resources from YAML
    for NS in hrms-dev hrms-stage hrms-prod default; do
      kubectl create namespace $NS 2>/dev/null || true
      kubectl apply -f ~/restore/full-server-backup-*/k8s/namespaces/$NS/configmaps.yaml
      kubectl apply -f ~/restore/full-server-backup-*/k8s/namespaces/$NS/secrets.yaml
      kubectl apply -f ~/restore/full-server-backup-*/k8s/namespaces/$NS/deployments.yaml
      kubectl apply -f ~/restore/full-server-backup-*/k8s/namespaces/$NS/services.yaml
      kubectl apply -f ~/restore/full-server-backup-*/k8s/namespaces/$NS/pvcs.yaml
    done
    All HRMS namespaces restored — dev, stage, prod
==========================================================================================================================
Phase 6 Verify everything is back
--------------------------------------------------------------------------------------------------------------------------
21 Check all services running
    sudo systemctl status cloudflared nginx jenkins docker kubelet
    kubectl get nodes
    kubectl get pods --all-namespaces
22 Confirm ideanow.info is reachable
    Open https://ideanow.info and https://monitor.ideanow.info in browser — both should load.
23 Trigger Jenkins backup build to confirm pipeline works
    Go to Jenkins → vinothserver-full-backup → Build Now. You should get a Telegram success message within ~10 minutes.
==========================================================================================================================


Total recovery time is roughly 40 minutes from a completely dead server to fully operational.
The key insight is that your backup already contains everything needed to rebuild — the only manual step that requires human interaction is 
step 5 (rclone OAuth, needs a browser on your phone/laptop). Everything else is just commands.
The order matters:

/etc restore must happen before starting services — it has all the config files
Jenkins must be stopped before restoring its data directory
K8s cluster must be initialized fresh before applying the YAML exports

One thing to prepare now — save the recovery commands somewhere offline (notes app on your phone, printed paper) so you can access them 
even if vinothserver and your browser history are both gone. The rclone OAuth URL in step 5 is the most time-sensitive part — 
open it immediately after it appears, it expires in a few minutes.