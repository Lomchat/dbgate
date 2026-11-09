#!/bin/bash
# Deploie le BACKEND d'un plugin vers le runtime (prod par defaut).
#
# deploy.sh ne construit que le front (yarn build:web) : le back execute vient des paquets npm
# du runtime. Ce script comble ce trou pour les plugins.
#
# Usage : /srv/dbgate/deploy-plugin.sh dbgate-plugin-mongo
# Cible et service reglables par variables, voir deploy-env.sh (ex. instance de test).
set -e
. "$(dirname "$0")/deploy-env.sh"
use_build_node

PLUGIN=${1:?usage: deploy-plugin.sh <nom-du-plugin>}
SRC=$REPO/plugins/$PLUGIN
DST=$RUNTIME/node_modules/$PLUGIN/dist
BAK=$BACKUP_DIR/plugins

[ -d "$SRC" ] || { echo "ERREUR : $SRC introuvable" >&2; exit 1; }
[ -d "$DST" ] || { echo "ERREUR : $DST introuvable (plugin non installe dans le runtime)" >&2; exit 1; }
PLUGIN_VERSION=$(grep -m1 '"version"' "$RUNTIME/node_modules/$PLUGIN/package.json" | cut -d'"' -f4)

echo "==> Build backend de $PLUGIN (node $(node -v))"
cd "$SRC"
yarn build:backend 2>&1 | tail -2

echo "==> Sauvegarde de l'original $PLUGIN_VERSION (une seule fois)"
mkdir -p "$BAK"
ORIG=$BAK/$PLUGIN-$PLUGIN_VERSION-backend.origine.js
[ -f "$ORIG" ] || command cp "$DST/backend.js" "$ORIG"

echo "==> Bascule vers $DST"
# 'command cp' contourne l'alias interactif de cp, qui sinon demande une confirmation
# impossible a donner en script et laisse silencieusement l'ancien fichier en place.
command cp -f "$SRC/dist/backend.js" "$DST/backend.js"

if [ "$(md5sum "$SRC/dist/backend.js" | cut -d' ' -f1)" != "$(md5sum "$DST/backend.js" | cut -d' ' -f1)" ]; then
  echo "ERREUR : la copie n'a pas abouti" >&2
  exit 1
fi

restart_service

echo "==> OK. Rollback : command cp -f $ORIG $DST/backend.js && systemctl restart $SERVICE"
