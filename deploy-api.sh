#!/bin/bash
# Recopie les fichiers de packages/api/src/ modifies dans ce fork vers le runtime npm (prod par defaut).
#
# dbgate-api est publie avec ses sources en clair (pas de bundle), on peut donc les corriger
# directement. deploy.sh ne construit que le front et ne couvre pas ce cas.
#
# Usage : /srv/dbgate/deploy-api.sh
# Cible et service reglables par variables, voir deploy-env.sh (ex. instance de test).
set -e
. "$(dirname "$0")/deploy-env.sh"

SRC=$REPO/packages/api/src
DST=$RUNTIME/node_modules/dbgate-api/src
API_VERSION=$(grep -m1 '"version"' "$RUNTIME/node_modules/dbgate-api/package.json" | cut -d'"' -f4)
# Originaux conserves par version : ceux de 7.1.6 ne valent rien pour restaurer une 7.3.4.
BAK=$BACKUP_DIR/api-$API_VERSION

# Fichiers corriges par ce fork. Ajouter ici toute nouvelle correction.
FILES=(
  main.js   # LISTEN_HOST : n'ecouter que sur 127.0.0.1 (Caddy relaie db.chalco.website)
  proc/databaseConnectionProcess.js
  proc/serverConnectionProcess.js
  controllers/auth.js        # anti brute force de auth/login (10 echecs / 15 min / IP, 429)
  auth/authProvider.js       # comparaison des mots de passe en temps constant
)

# Les sources doivent etre celles de la version installee, sinon on melange deux versions.
SRC_VERSION=$(grep -m1 '"version"' "$REPO/package.json" | cut -d'"' -f4)
if [ "$SRC_VERSION" != "$API_VERSION" ]; then
  echo "ERREUR : sources en $SRC_VERSION, dbgate-api du runtime en $API_VERSION. Abandon." >&2
  exit 1
fi

mkdir -p "$BAK"
for f in "${FILES[@]}"; do
  [ -f "$SRC/$f" ] || { echo "ERREUR : $SRC/$f introuvable" >&2; exit 1; }
  [ -f "$DST/$f" ] || { echo "ERREUR : $DST/$f introuvable" >&2; exit 1; }

  mkdir -p "$BAK/$(dirname "$f")"
  [ -f "$BAK/$f" ] || command cp "$DST/$f" "$BAK/$f"   # original conserve une seule fois

  # 'command cp' contourne l'alias interactif de cp, qui sinon sort avec succes
  # sans avoir rien copie.
  command cp -f "$SRC/$f" "$DST/$f"

  if [ "$(md5sum "$SRC/$f" | cut -d' ' -f1)" != "$(md5sum "$DST/$f" | cut -d' ' -f1)" ]; then
    echo "ERREUR : copie de $f non aboutie" >&2
    exit 1
  fi
  echo "  ok  $f"
done

restart_service
echo "==> OK. Rollback : command cp -f $BAK/<fichier> $DST/<fichier> && systemctl restart $SERVICE"
