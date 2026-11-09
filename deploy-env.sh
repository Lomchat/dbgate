#!/bin/bash
# Parametres communs aux scripts deploy*.sh et restore-all.sh (source, pas execute).
#
# Par defaut tout vise la PROD : runtime /srv/dbgate/runtime, service dbgate.service, port 9999.
# Pour une instance de test, surcharger par variables d'environnement, par exemple :
#
#   DBGATE_RUNTIME=/srv/dbgate-test/runtime DBGATE_SERVICE=none \
#   DBGATE_BACKUP=/srv/dbgate-test/backup DBGATE_PORT=9998 /srv/dbgate/restore-all.sh
#
#   DBGATE_REPO     sources a construire          (defaut : dossier de ce script)
#   DBGATE_RUNTIME  runtime npm a modifier         (defaut : $DBGATE_REPO/runtime)
#   DBGATE_BACKUP   dossier des sauvegardes        (defaut : $DBGATE_REPO/backup)
#   DBGATE_SERVICE  unite systemd a redemarrer     (defaut : dbgate.service ; 'none' = pas de redemarrage)
#   DBGATE_PORT     port de verification (restore-all.sh) (defaut : 9999)
#   DBGATE_NODE_DIR dossier bin du Node de BUILD   (defaut : Node 24, exige par l'amont depuis 7.2)

REPO=${DBGATE_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
RUNTIME=${DBGATE_RUNTIME:-$REPO/runtime}
BACKUP_DIR=${DBGATE_BACKUP:-$REPO/backup}
SERVICE=${DBGATE_SERVICE:-dbgate.service}
CHECK_PORT=${DBGATE_PORT:-9999}
NODE_DIR=${DBGATE_NODE_DIR:-/opt/node-v24.22.1-linux-x64/bin}

# Node de build : yarn 1 vient de nvm (Node 20), le Node lui-meme de NODE_DIR (>= 24 pour 7.3.x).
use_build_node() {
  export NVM_DIR="/root/.nvm"
  . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
  nvm use 20 >/dev/null 2>&1
  [ -x "$NODE_DIR/node" ] && export PATH="$NODE_DIR:$PATH"
  unset PORT API_URL
}

restart_service() {
  if [ "$SERVICE" = "none" ]; then
    echo "==> Pas de redemarrage (DBGATE_SERVICE=none) : relancer l'instance a la main"
    return 0
  fi
  echo "==> Redemarrage de $SERVICE"
  systemctl restart "$SERVICE"
  systemctl is-active "$SERVICE"
}
