#!/bin/bash
# Deploie le BACKEND d'un plugin vers le runtime.
#
# deploy.sh ne construit que le front (yarn build:web) : le back execute vient des paquets npm
# de runtime/node_modules/. Ce script comble ce trou pour les plugins.
#
# Usage : /srv/dbgate/deploy-plugin.sh dbgate-plugin-mongo
set -e

PLUGIN=${1:?usage: deploy-plugin.sh <nom-du-plugin>}
REPO=/srv/dbgate
SRC=$REPO/plugins/$PLUGIN
DST=$REPO/runtime/node_modules/$PLUGIN/dist
BAK=$REPO/backup/plugins

export NVM_DIR="/root/.nvm"
. "$NVM_DIR/nvm.sh" >/dev/null 2>&1
nvm use 20 >/dev/null 2>&1

[ -d "$SRC" ] || { echo "ERREUR : $SRC introuvable" >&2; exit 1; }
[ -d "$DST" ] || { echo "ERREUR : $DST introuvable (plugin non installe dans le runtime)" >&2; exit 1; }

echo "==> Build backend de $PLUGIN"
cd "$SRC"
yarn build:backend 2>&1 | tail -2

echo "==> Sauvegarde de l'original (une seule fois)"
mkdir -p "$BAK"
[ -f "$BAK/$PLUGIN-backend.origine.js" ] || cp "$DST/backend.js" "$BAK/$PLUGIN-backend.origine.js"

echo "==> Bascule"
# 'command cp' contourne l'alias interactif de cp, qui sinon demande une confirmation
# impossible a donner en script et laisse silencieusement l'ancien fichier en place.
command cp -f "$SRC/dist/backend.js" "$DST/backend.js"

if [ "$(md5sum "$SRC/dist/backend.js" | cut -d' ' -f1)" != "$(md5sum "$DST/backend.js" | cut -d' ' -f1)" ]; then
  echo "ERREUR : la copie n'a pas abouti" >&2
  exit 1
fi

echo "==> Redemarrage"
systemctl restart dbgate.service
systemctl is-active dbgate.service

echo "==> OK. Rollback : command cp -f $BAK/$PLUGIN-backend.origine.js $DST/backend.js && systemctl restart dbgate.service"
