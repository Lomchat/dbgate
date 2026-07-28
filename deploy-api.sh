#!/bin/bash
# Recopie les fichiers de packages/api/src/ modifies dans ce fork vers le runtime npm.
#
# dbgate-api est publie avec ses sources en clair (pas de bundle), on peut donc les corriger
# directement. deploy.sh ne construit que le front et ne couvre pas ce cas.
#
# Usage : /srv/dbgate/deploy-api.sh
set -e

REPO=/srv/dbgate
SRC=$REPO/packages/api/src
DST=$REPO/runtime/node_modules/dbgate-api/src
BAK=$REPO/backup/api

# Fichiers corriges par ce fork. Ajouter ici toute nouvelle correction.
FILES=(
  proc/databaseConnectionProcess.js
  proc/serverConnectionProcess.js
)

mkdir -p "$BAK"
for f in "${FILES[@]}"; do
  [ -f "$SRC/$f" ] || { echo "ERREUR : $SRC/$f introuvable" >&2; exit 1; }
  [ -f "$DST/$f" ] || { echo "ERREUR : $DST/$f introuvable" >&2; exit 1; }

  mkdir -p "$BAK/$(dirname "$f")"
  [ -f "$BAK/$f" ] || cp "$DST/$f" "$BAK/$f"   # original conserve une seule fois

  # 'command cp' contourne l'alias interactif de cp, qui sinon sort avec succes
  # sans avoir rien copie.
  command cp -f "$SRC/$f" "$DST/$f"

  if [ "$(md5sum "$SRC/$f" | cut -d' ' -f1)" != "$(md5sum "$DST/$f" | cut -d' ' -f1)" ]; then
    echo "ERREUR : copie de $f non aboutie" >&2
    exit 1
  fi
  echo "  ok  $f"
done

echo "==> Redemarrage"
systemctl restart dbgate.service
systemctl is-active dbgate.service
echo "==> OK. Rollback : command cp -f $BAK/<fichier> $DST/<fichier> && systemctl restart dbgate.service"
