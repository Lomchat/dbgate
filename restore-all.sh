#!/bin/bash
# Remet en place TOUTES les personnalisations de ce fork sur le runtime npm (prod par defaut).
#
# A lancer apres un `npm install` dans runtime/, une montee de version de dbgate-serve,
# ou tout evenement qui a rendu l'interface a son etat d'origine.
# Deja arrive le 19/08/2026 : front, correctif API, plugin Mongo et /etc/hosts remis a zero.
#
# Usage : /srv/dbgate/restore-all.sh
# Instance de test : DBGATE_RUNTIME=... DBGATE_SERVICE=none DBGATE_PORT=9998 (voir deploy-env.sh).
# Avec DBGATE_SERVICE=none, l'instance doit etre (re)lancee a la main AVANT la verification
# finale ; DBGATE_RESTART_CMD peut fournir la commande qui le fait.
set -e
. "$(dirname "$0")/deploy-env.sh"
D=$RUNTIME/node_modules

echo "===== 1/4  Front (2e colonne, infobulles, bouton upgrade deplace) ====="
"$REPO/deploy.sh" 2>&1 | grep -iE "ERREUR|Bascule|active|Pas de redemarrage" || true

echo "===== 2/4  packages/api (delai d'inactivite 600 s, LISTEN_HOST) ====="
"$REPO/deploy-api.sh" 2>&1 | grep -E "^  ok|ERREUR|active" || true

echo "===== 3/4  Plugin Mongo (stats bornees, connectTimeout) ====="
"$REPO/deploy-plugin.sh" dbgate-plugin-mongo 2>&1 | grep -iE "ERREUR|Bascule|active" || true

echo "===== 4/4  Blocage de api.dbgate.io (hors depot, voir CLAUDE.md) ====="
if grep -q "api.dbgate.io" /etc/hosts; then
  echo "  deja present dans /etc/hosts"
else
  echo "0.0.0.0 api.dbgate.io" >> /etc/hosts
  echo "  ligne ajoutee a /etc/hosts"
fi

if [ "$SERVICE" != "none" ]; then
  systemctl restart "$SERVICE"
elif [ -n "$DBGATE_RESTART_CMD" ]; then
  bash -c "$DBGATE_RESTART_CMD"
fi
for i in $(seq 1 30); do
  curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$CHECK_PORT/" 2>/dev/null | grep -q "200" && break
  sleep 2
done

echo
echo "===== VERIFICATION ($RUNTIME, port $CHECK_PORT) ====="
fail=0
check() { # nom, valeur obtenue, valeur attendue
  if [ "$2" = "$3" ]; then printf "  OK    %-34s %s\n" "$1" "$2"
  else printf "  ECHEC %-34s obtenu=%s attendu=%s\n" "$1" "$2" "$3"; fail=1; fi
}
WEB=$D/dbgate-web/public/build
check "2e colonne detachable"  "$(grep -c secondleftpanel $WEB/bundle.js)" 1
check "bouton d'en-tete"       "$(grep -c WidgetTitle_action $WEB/bundle.js)" 1
check "infobulles du rail"     "$(grep -c sidebar-tooltip $WEB/bundle.js)" 1
check "bouton upgrade retire"  "$(grep -c TabsPanel_buttonUpgrade $WEB/bundle.js)" 0
check "upgrade dans reglages"  "$(grep -c settings-upgrade $WEB/bundle.js)" 1
check "raccourcis navigateur"  "$(grep -c "ctrl+shift+i" $WEB/bundle.js)" 1
check "workers ace livres"     "$(ls $WEB/worker-*.js 2>/dev/null | wc -l | grep -qv '^0$' && echo oui || echo non)" oui
check "api delai d'inactivite" "$(grep -c 'const IDLE_TIMEOUT_MS' $D/dbgate-api/src/proc/databaseConnectionProcess.js)" 1
check "api LISTEN_HOST"        "$(grep -c 'process.env.LISTEN_HOST' $D/dbgate-api/src/main.js)" 1
check "plugin mongo"           "$(grep -c _collectStats $D/dbgate-plugin-mongo/dist/backend.js)" 1
check "blocage api.dbgate.io"  "$(grep -c 'api.dbgate.io' /etc/hosts)" 1
if [ "$SERVICE" != "none" ]; then
  check "service"              "$(systemctl is-active "$SERVICE")" active
fi
check "repond sur $CHECK_PORT" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$CHECK_PORT/")" 200

echo
[ $fail -eq 0 ] && echo "Tout est en place. Pense au Ctrl+Shift+R dans le navigateur." || {
  echo "Au moins une verification a echoue, voir ci-dessus." >&2; exit 1; }
