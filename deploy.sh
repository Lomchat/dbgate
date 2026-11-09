#!/bin/bash
# Deploie le front DbGate modifie vers le runtime npm (prod par defaut).
# Usage : /srv/dbgate/deploy.sh
# Cible et service reglables par variables, voir deploy-env.sh (ex. instance de test).
set -e
. "$(dirname "$0")/deploy-env.sh"
use_build_node

SRC=$REPO/packages/web/public/
DST=$RUNTIME/node_modules/dbgate-web/public/
BAK=$BACKUP_DIR/public.$(date +%Y%m%d-%H%M%S)

[ -d "$DST" ] || { echo "ERREUR : $DST introuvable" >&2; exit 1; }

echo "==> Build de production du front ($REPO, node $(node -v))..."
cd "$REPO"
yarn build:web 2>&1 | grep -vE "A11y:|Unused CSS|svelte plugin" | tail -5

echo "==> Garde-fou : pas d'URL de dev dans le bundle"
if grep -q "localhost:3000" "${SRC}build/bundle.js"; then
  echo "ERREUR : build de dev detecte (localhost:3000). Abandon." >&2
  exit 1
fi

echo "==> Garde-fou : version du front = version du runtime"
WANT=$(node -p "require('$RUNTIME/node_modules/dbgate-web/package.json').version")
HAVE_ROOT=$(node -p "require('$REPO/package.json').version")
if [ "$WANT" != "$HAVE_ROOT" ]; then
  echo "ERREUR : sources en $HAVE_ROOT, runtime en $WANT. Abandon (voir CLAUDE.md, contrainte de version)." >&2
  exit 1
fi

echo "==> Sauvegarde de l'existant dans $BAK"
mkdir -p "$BACKUP_DIR"
cp -a "$DST" "$BAK"

echo "==> Bascule vers $DST"
rsync -a --delete "$SRC" "$DST"

restart_service

echo "==> OK. Pense au rafraichissement force du navigateur (Ctrl+Shift+R)"
echo "    Rollback : rsync -a --delete $BAK/ $DST puis redemarrer ($SERVICE)"
