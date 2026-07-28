#!/bin/bash
# Deploie le front DbGate modifie vers le runtime npm embarque dans ce depot.
# Usage : /srv/dbgate/deploy.sh
set -e

export NVM_DIR="/root/.nvm"
. "$NVM_DIR/nvm.sh" >/dev/null 2>&1
nvm use 20 >/dev/null 2>&1
unset PORT API_URL

REPO=/srv/dbgate
SRC=$REPO/packages/web/public/
DST=$REPO/runtime/node_modules/dbgate-web/public/
BAK=$REPO/backup/public.$(date +%Y%m%d-%H%M%S)

echo "==> Build de production du front..."
cd "$REPO"
yarn build:web 2>&1 | grep -vE "A11y:|Unused CSS|svelte plugin" | tail -5

echo "==> Garde-fou : pas d'URL de dev dans le bundle"
if grep -q "localhost:3000" "${SRC}build/bundle.js"; then
  echo "ERREUR : build de dev detecte (localhost:3000). Abandon." >&2
  exit 1
fi

echo "==> Sauvegarde de l'existant dans $BAK"
mkdir -p "$REPO/backup"
cp -a "$DST" "$BAK"

echo "==> Bascule"
rsync -a --delete "$SRC" "$DST"

echo "==> Redemarrage"
systemctl restart dbgate.service
systemctl is-active dbgate.service

echo "==> OK. Pense au rafraichissement force du navigateur (Ctrl+Shift+R)"
echo "    Rollback : rsync -a --delete $BAK/ $DST && systemctl restart dbgate.service"
