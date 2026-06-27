# 1. Pull from GDrive
rclone copy gdrive:vinothserver-backups/YYYYMMDD_HHMM/ ~/restore/

# 2. Extract
tar xzf ~/restore/vinothserver-backup-*.tar.gz -C ~/restore/

# 3. Restore K8s (after new cluster is up)
for NS in hrms-dev hrms-stage hrms-prod; do
  kubectl create namespace $NS 2>/dev/null || true
  kubectl apply -f ~/restore/k8s/$NS/configmaps.yaml
  kubectl apply -f ~/restore/k8s/$NS/secrets.yaml
  kubectl apply -f ~/restore/k8s/$NS/all-resources.yaml
done

# 4. Restore server configs
sudo tar xzf ~/restore/server/etc.tar.gz -C /
tar xzf ~/restore/server/home.tar.gz -C /
sudo tar xzf ~/restore/server/jenkins-jobs.tar.gz -C /