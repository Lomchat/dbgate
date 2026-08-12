# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

# ⚠️ Fork local — à lire en premier

Ce dépôt est un **fork de DbGate figé sur le tag `v7.1.6`**, utilisé pour personnaliser l'interface
d'une instance DbGate qui tourne sur ce serveur. Tout ce qui suit est spécifique à cette installation
et ne vient pas du projet amont.

## Les emplacements à ne pas confondre

Il n'existe que **deux** emplacements DbGate sur ce serveur : ce dépôt, et les données.

| Chemin | Rôle | Versionné ? |
|---|---|---|
| `/srv/dbgate` | **Ce dépôt.** Les sources modifiables, c'est ici qu'on code. | oui |
| `/srv/dbgate/runtime/` | **L'instance qui tourne** : paquet npm `dbgate-serve@7.1.6`. Lancée par le service systemd `dbgate.service` sur le port 9999. | non (gitignore) |
| `/srv/dbgate/backup/` | Sauvegardes horodatées du front, déposées par `deploy.sh` | non (gitignore) |
| `/root/.dbgate` | **Les données** : connexions, mots de passe, historique, thèmes. Jamais dans le dépôt. | non |

⚠️ **`Restart=always`, et pas `on-failure`.** Le 12/08/2026 à 00:28:06, un signal extérieur a
éteint DbGate **proprement** (code de sortie 0). `on-failure` ne redémarre pas sur une sortie 0 :
le service est resté mort **19 heures**, Apache renvoyant `503 Service Unavailable`. `siege.service`
est tombé à la même seconde et a été relancé 20 s plus tard par une automatisation qui ne couvrait
pas DbGate. L'origine exacte du signal n'a pas été identifiée — ce serveur héberge plusieurs agents
qui ouvrent des sessions SSH root en continu.

Vérifier après toute modification de l'unité :
```sh
kill -TERM $(systemctl show -p MainPID --value dbgate.service)
sleep 10 && systemctl is-active dbgate.service   # doit afficher 'active'
```

Le service pointe directement dans ce dépôt :
```ini
WorkingDirectory=/srv/dbgate/runtime
EnvironmentFile=/srv/dbgate/runtime/.env     # PORT=9999, LOGIN_PASSWORD_admin
ExecStart=<node20> /srv/dbgate/runtime/node_modules/dbgate-serve/bin/dbgate-serve.js
```

> Pourquoi un runtime npm plutôt qu'un lancement direct depuis les sources ? Parce que l'API résout le
> front via `path.join(__dirname, '../../dbgate-web/public')` et les plugins via le dossier parent du
> paquet `dbgate-api` — deux chemins relatifs à la structure **npm**, pas à celle du monorepo. Les
> reproduire à coups de liens symboliques marcherait, mais casserait de façon obscure à la première
> mise à jour. Le runtime npm reste la voie testée par l'amont.

Accès public : `https://<DOMAINE>` → Apache (`/etc/httpd/conf.d/<DOMAINE>.conf`) → `localhost:9999`.

> Les valeurs réelles (domaine, IP, accès) sont dans `CLAUDE.local.md`, non versionné.

## La boucle de travail

```sh
# 1. Editer les sources du front
vim /srv/dbgate/packages/web/src/<composant>.svelte

# 2. Deployer  (~20 s de build + ~2 s de redemarrage)
/srv/dbgate/deploy.sh

# 3. Ctrl+Shift+R dans le navigateur
```

Trois pièges dans cette boucle, tous rencontrés en vrai :

**Le cache navigateur.** Sans **Ctrl+Shift+R**, l'ancien `bundle.js` reste servi et on conclut à tort
que la modification n'est pas passée. C'est de loin la fausse alerte la plus fréquente.

**Le 503 juste après le déploiement.** DbGate met ~2 secondes à écouter après un `systemctl restart`.
Pendant ce laps de temps Apache répond `503`. Ce n'est pas une panne : il faut simplement attendre.

**`deploy.sh` ne construit que le front** (`yarn build:web`). Une modification dans `packages/api/`
n'est pas prise en compte : le back exécuté est celui de `runtime/node_modules/dbgate-api/`, un paquet
npm. Pour les **plugins**, utiliser :

```sh
/srv/dbgate/deploy-plugin.sh dbgate-plugin-mongo
```

qui construit le backend du plugin, sauvegarde l'original une fois pour toutes dans
`backup/plugins/`, bascule et redémarre. `packages/api/` lui-même reste non déployable par script.

⚠️ Ce script utilise `command cp -f`. Sur ce serveur `cp` est aliasé en mode interactif : un `cp`
nu demande une confirmation qu'un script ne peut pas donner, **sort avec succès et laisse
silencieusement l'ancien fichier en place**. Le script vérifie donc l'empreinte après copie.

### Où se trouve quoi dans le front

Tout est sous `packages/web/src/` :

| Chemin | Contenu |
|---|---|
| `widgets/WidgetIconPanel.svelte` | La bande d'icônes verticale à gauche |
| `widgets/WidgetColumnBar.svelte` | Les sections repliables de la sidebar |
| `widgets/DatabaseWidget.svelte`, `ConnectionList.svelte` | Arbre des bases, liste des connexions |
| `widgets/SqlObjectList.svelte` | Tables, vues, procédures |
| `tabpanel/TabsPanel.svelte` | La barre d'onglets et ses boutons en haut à droite |
| `tabs/SettingsTab.svelte` | Le menu des réglages (y enregistrer tout nouvel écran) |
| `settings/*.svelte` | Un fichier par écran de réglages |
| `Screen.svelte` | Le layout global, largeurs des panneaux |

Les fichiers `packages/web/public/*.css` (`global.css`, `tokens.css`, `dimensions.css`, `tailwind-colors.css`)
sont versionnés, en clair et non minifiés. Les modifier ne demande **aucune compilation** — mais il faut
quand même `deploy.sh` pour les recopier vers `runtime/`. Pour un essai jetable, on peut les éditer
directement dans `runtime/node_modules/dbgate-web/public/` : effet immédiat au rafraîchissement, mais
hors du dépôt, donc à reporter dans les sources si on veut le garder.

### Vérifier qu'un déploiement a bien atterri

Plutôt que de se fier à l'œil, on interroge le bundle réellement servi :

```sh
curl -s https://<DOMAINE>/build/bundle.js | grep -c "<un-identifiant-de-ta-modif>"
```

Les attributs `data-testid` du code sont parfaits pour ça — ils survivent à la minification.

Le script refuse de déployer s'il détecte un build de dev (présence de `localhost:3000` dans le bundle)
et sauvegarde l'existant dans `backup/public.<horodatage>` avant chaque bascule.

Rollback :
```sh
rsync -a --delete /srv/dbgate/backup/public.<horodatage>/ \
                  /srv/dbgate/runtime/node_modules/dbgate-web/public/
systemctl restart dbgate.service
```

`backup/public-origine-npm` contient le front npm d'origine, jamais modifié : c'est le filet de secours
ultime pour revenir à une interface DbGate vierge.

## ⚠️ Fragilité principale

Le front déployé vit dans `runtime/node_modules/dbgate-web/public/`. **Un `npm install` lancé dans
`runtime/`, ou une montée de version de `dbgate-serve`, l'écrasera sans prévenir** et les
personnalisations disparaîtront.

Ce n'est pas une perte : les sources sont ici, il suffit de relancer `deploy.sh`. Mais il ne faut pas
s'étonner de voir l'interface revenir à son état d'origine après une mise à jour.

## ⚠️ Ne jamais utiliser le bouton « Sync fork » de GitHub sur `custom-ui`

Le modèle de branches est le suivant :

| Branche | Rôle |
|---|---|
| `master` | Miroir intact de l'amont. On n'y travaille jamais. |
| `custom-ui` | **Tout le travail local**, basé sur le commit du tag `v7.1.6`. |

Le bouton « Sync fork » de GitHub, appliqué à `custom-ui`, y **fusionne le master amont** : la branche
saute alors de `7.1.6` à la dernière version de développement (une beta), et ne correspond plus au
`dbgate-serve` installé dans `runtime/`. C'est déjà arrivé une fois — la sauvegarde de cet état est
conservée sous l'étiquette `backup/sync-merge-20260728`.

Pour regarder ce qui a changé en amont sans rien casser :
```sh
git fetch upstream
git log --oneline v7.1.6..upstream/master
```

## Contraintes à respecter

- **Rester sur `v7.1.6`.** Le front déployé doit correspondre à la version de `dbgate-serve` installée.
  Une montée de version du fork sans montée équivalente de l'instance casse le contrat d'API.
- **Node 20 obligatoire** (`nvm use 20`). Le shell par défaut est en Node 16, qui ne sait pas builder ce projet.
- **`packages/api/.env` contient `WORKSPACE_DIR=/srv/dbgate-data`.** Ce garde-fou empêche le serveur de dev
  (`yarn start`) d'écrire dans les vraies données. Le dossier est recréé vide au besoin. Ne jamais le
  faire pointer vers `/root/.dbgate`.
- **`/root/.dbgate/.key`** chiffre les mots de passe des connexions. Le perdre les rend définitivement illisibles.
  Sauvegarde : `tar czf backup.tar.gz /root/.dbgate /srv/dbgate/runtime/.env`
- **Licence GPL-3.0.** Modifier et utiliser en interne n'impose rien. Publier ou redistribuer une version modifiée
  oblige à en publier les sources sous GPL. Conserver `LICENSE` et les en-têtes de copyright.

## Modifications appliquées par rapport à l'amont

- `packages/web/src/tabpanel/TabsPanel.svelte` — suppression du bouton « Upgrade » en haut à droite
  (bloc, classe de layout `.tabs-upgrade-button`, CSS associé et import devenu orphelin)
- `packages/web/src/settings/UpgradeSettings.svelte` — **nouveau** : écran d'upgrade déplacé dans les réglages
- `packages/web/src/tabs/SettingsTab.svelte` — ajout de l'entrée « Upgrade to Premium » sous « Keyboard shortcuts »
- `packages/web/src/widgets/WidgetIconPanel.svelte` — infobulles sur le rail d'icônes de gauche
  (voir ci-dessous)
- **Deuxième colonne de sidebar détachable** — voir la section dédiée plus bas
- `deploy.sh` — **nouveau** : script de build et de déploiement

### Infobulles du rail d'icônes

Le `title` natif était posé par `FontIcon` sur le `<span>` de la glyphe (~20pt) alors que la zone
cliquable fait 50px de haut : il ne se déclenchait donc pas de façon fiable. Trois boutons (menu,
compte cloud, réglages) n'avaient même aucun libellé.

Remplacé par une infobulle maison dans `WidgetIconPanel.svelte` : `on:mouseenter` sur le `.wrapper`
complet, position `fixed` calée sur `--dim-widget-icon-size` pour ne pas être rognée par le rail,
couleurs issues des variables `--theme-modal-*` (donc correctes en thème clair comme sombre).
Le `title` natif a été retiré des `FontIcon` du rail pour éviter la double infobulle, et remplacé
par un `aria-label` sur le wrapper.

⚠️ En Svelte, `{@const}` n'est valide que comme enfant direct d'un bloc (`{#if}`, `{#each}`…).
Les libellés des boutons hors bloc sont donc déclarés dans le `<script>`.

⚠️ **Piège d'empilement, résolu dans `Screen.svelte`.** `position: fixed` **crée un contexte
d'empilement**. `.iconbar` étant en `position: fixed` sans `z-index`, le `z-index: 1000` de
l'infobulle restait confiné au rail, et tout le rail était peint avant `.leftpanel` (même `z-index:
auto`, départage par l'ordre DOM). Résultat : infobulle présente dans le DOM, `visibility: visible`,
`opacity: 1`, et pourtant **invisible**. Corrigé par `z-index: 10` sur `.iconbar`.

Toute infobulle ou menu qui doit déborder d'un panneau `position: fixed` rencontrera le même
problème. Vérifier le rendu, pas seulement le DOM.

### Vérifier le rendu sans passer par son navigateur

```sh
nvm use 20 && node tools/check-ui.js [data-testid]     # defaut : WidgetIconPanel_database
```

Charge l'instance locale, se connecte, survole le bouton et rapporte si l'infobulle est réellement
**peinte au premier plan** — pas seulement présente. Capture écrite dans `/tmp/dbgate-check-ui.png`.

C'est cet outil qui a tranché le bug d'empilement ci-dessus, après plusieurs allers-retours où le DOM
paraissait correct. Les styles calculés ne suffisent pas : il faut le rendu.

> Détail à connaître : l'infobulle porte `pointer-events: none`, donc `elementFromPoint()` la
> traverse et signale un faux recouvrement. Le script neutralise temporairement cette propriété
> pendant le test.

### Deuxième colonne de sidebar détachable

Le bouton dans l'en-tête des sections de contenu (« Tables, vues, fonctions », « Database content »…)
bascule ce bloc entre deux dispositions : empilé sous les connexions, ou en **colonne autonome pleine
hauteur** à droite du panneau de gauche, avec son propre splitter.

| Fichier | Rôle |
|---|---|
| `stores.ts` | `detachedDbObjects`, `secondLeftPanelWidth` (persistés), `visibleSecondLeftPanel` (dérivé) |
| `public/dimensions.css` | `--dim-second-left-panel-width`, `--dim-visible-second-left-panel`, intégrées à `--dim-content-left` |
| `Screen.svelte` | `.secondleftpanel` + `.second-left-splitter` |
| `widgets/SecondLeftPanelContainer.svelte` | **nouveau** : réenveloppe le contenu dans son propre `WidgetColumnBar` |
| `widgets/WidgetTitle.svelte` | `onAction` / `actionIcon` / `actionTitle` — bouton générique dans l'en-tête |
| `widgets/DatabaseWidget.svelte` | rendu conditionnel + `{#key}` |

Le décalage du contenu est **automatique** : `--dim-content-left` intègre la largeur de la deuxième
colonne, et tout le layout en dépend déjà. Aucun composant n'a eu besoin d'être modifié pour ça.

⚠️ **`WidgetColumnBar` n'oublie jamais ses sections.** `pushWidgetItemDefinition` empile les
définitions au montage et rien ne les retire au démontage. Les sections parties dans l'autre colonne
continuaient donc d'y réserver leur hauteur — la liste des connexions restait à 412px dans un panneau
de 878px, avec un grand vide dessous. D'où le `{#key $detachedDbObjects}` qui force la reconstruction
de la barre. Toute manipulation dynamique de sections rencontrera ce piège.

⚠️ `DatabaseWidgetDetailContent` n'émet que des `<WidgetColumnBarItem>`, qui exigent le contexte
d'un `<WidgetColumnBar>` parent. Il ne peut donc pas être monté seul : d'où le composant d'enveloppe,
avec un `storageName` distinct pour que les hauteurs des deux dispositions ne se mélangent pas.

> Le bouton est posé sur **toutes** les sections de contenu, pas seulement « Tables, vues, fonctions ».
> Sans base sélectionnée, seule la section d'attente s'affiche : sans cela, impossible de revenir en arrière.

### ⚠️ Lenteur d'ouverture des bases — la vraie cause

Symptôme : plusieurs secondes avant de voir les tables, **quel que soit le moteur**. Décomposition
mesurée en pilotant un navigateur :

| Appel | Coût |
|---|---|
| `/database-connections/structure` (tables, vues, fonctions) | **~30 ms** — jamais en cause |
| `/database-connections/schema-list` à froid | **16 122 ms** |
| le même, une fois la cause corrigée | **611 ms** |

Trois faits qui s'emboîtent :

1. **DbGate tue ses processus de connexion après 40 s d'inactivité** (`databaseConnectionProcess.js`,
   `serverConnectionProcess.js`). Chaque retour sur une base paie un démarrage à froid : fork Node,
   chargement de `dbgate-api` et du plugin, reconnexion au SGBD.
2. **Ce démarrage à froid contacte `api.dbgate.io`.** Depuis ce serveur, l'hôte **accepte la connexion
   TCP en ~1 s puis ne répond jamais** — pas d'échec franc, juste une attente.
3. **`cloudIntf.js` ne pose aucun timeout** sur ses appels axios. L'attente va donc jusqu'au délai TCP
   du système, ~15 s, à **chaque ouverture de base**.

**Correctifs en place :**

- `0.0.0.0 api.dbgate.io` dans **`/etc/hosts`** — l'appel échoue instantanément. ⚠️ C'est un remède
  **système, hors du dépôt** : invisible pour qui ne lit que ce fichier. Il coupe DbGate Cloud, qui
  ne fonctionnait déjà plus puisque l'hôte ne répond pas. Pour annuler : retirer la ligne.
- Délai d'inactivité porté de 40 s à **600 s**, réglable par `CONNECTION_IDLE_SECONDS` dans
  `runtime/.env`. Déployé par `deploy-api.sh`.

> Piège de diagnostic : cette attente de ~15 s contaminait toutes les autres mesures. Les valeurs
> à 15 000 et 30 000 ms rencontrées pendant l'enquête sur Mongo en venaient en partie. Devant un
> chiffre suspicieusement rond, chercher une expiration réseau avant d'optimiser du code.

### Déployer un correctif dans `packages/api/`

```sh
/srv/dbgate/deploy-api.sh
```

`dbgate-api` est publié **avec ses sources en clair**, pas en bundle : on peut donc les corriger
directement dans le runtime. Le script recopie la liste de fichiers déclarée en tête, conserve
l'original une seule fois dans `backup/api/` et redémarre. Ajouter tout nouveau fichier corrigé à
la liste `FILES`.

### ⚠️⚠️ Le réseau sortant du serveur perd des paquets

**À vérifier avant toute optimisation de DbGate.** Mesuré ici, 12 tentatives d'ouverture TCP
espacées de 2 s :

| Destination | Réussite |
|---|---|
| `127.0.0.1:9999` (témoin) | **12/12** |
| Cloudflare `1.1.1.1:443` | 5/12 |
| Google DNS `8.8.8.8:53` | 2/12 |
| Base distante | 3/12 |

**60 à 80 % des connexions sortantes échouent, quelle que soit la destination.** Le témoin local est
parfait, la charge et conntrack sont bas : la machine va bien, c'est le réseau du fournisseur.

Conséquences, toutes vérifiées pendant l'enquête :

- Une connexion qui aboutit prend ~22 ms ; une qui échoue **pend jusqu'au timeout** du client.
- Toute mesure de performance devient ininterprétable. Deux hypothèses ont été retenues puis
  **infirmées** faute d'échantillon : `directConnection=true` pour Mongo (rapide une fois, lent la
  suivante) et une limitation ciblée sur les ports base de données (démentie dès que SSH a échoué
  aussi). **Ne jamais conclure sur moins d'une dizaine de tentatives.**
- Les chiffres ronds — 15 s, 30 s — sont des expirations, jamais du calcul.

Atténuation côté DbGate (le réseau reste à corriger chez l'hébergeur) :

- `connectTimeoutMS: 4000` dans le driver Mongo, au lieu des 30 s par défaut. Une tentative perdue
  est abandonnée vite et le driver en relance une autre dans le budget de sélection de serveur, au
  lieu d'attendre une seule fois très longtemps. Mesuré : pire attente **30 016 ms → 4 578 ms**, à
  taux de réussite égal. Réglable par `MONGO_CONNECT_TIMEOUT_MS`.
- Connexions maintenues 10 min (voir plus haut) : moins de reconnexions, donc moins d'occasions de
  tomber sur une perte.

### Lenteur de chargement des collections Mongo

L'arbre mettait 15 à 31 secondes à apparaître sur certaines bases Mongo. Décomposition mesurée :

| Étape | Coût |
|---|---|
| `listCollections()` — la liste elle-même | **~15 ms**, constant |
| `$collStats` par collection, en séquentiel | ~26–37 ms |
| Les mêmes en parallèle sans limite (code d'origine) | **15 000 à 31 000 ms** |

`Analyser.js` lançait un `$collStats` par collection, toutes via un `Promise.all` unique. Sur un
serveur distant cela sature le pool de connexions et les requêtes expirent au lieu d'aller plus vite.
Or ces statistiques (nombre de documents, taille) ne servent qu'à **décorer** l'arbre.

Corrigé par : parallélisme borné (`STATS_CONCURRENCY = 4`) et budget de temps
(`STATS_BUDGET_MS = 1200`). Résultat : 15 238 ms → 1 218 ms, 15 339 ms → 112 ms.

⚠️ **Un budget vérifié en tête de boucle ne borne rien.** Une requête déjà partie n'est jamais
interrompue, et `maxTimeMS` ne limite que l'exécution serveur — ni l'attente réseau, ni l'acquisition
d'une connexion. Première version : budget de 2 500 ms, temps réel mesuré à 30 047 ms, soit **pire**
que l'original. Il a fallu un `Promise.race` explicite contre un minuteur pour que le budget existe
vraiment. Les compteurs en retard sont simplement absents de l'affichage.

⚠️ Les statistiques étaient indexées **par position** (`stats[index]`) alors que les requêtes
peuvent échouer indépendamment : un seul échec décalait tous les compteurs suivants sur les mauvaises
collections. Désormais indexées par nom.

> Piste non explorée : DbGate ne met aucun modèle en cache et refait une analyse complète à chaque
> besoin — 251 analyses complètes relevées dans les logs pour une seule base de 28 tables. Le driver
> Mongo n'implémente pas non plus `getModifications()`, donc jamais d'analyse incrémentale. Attention
> si on s'y attaque : renvoyer des `setTableRowCounts` sans détecter aussi les ajouts et suppressions
> ferait que **les nouvelles collections n'apparaîtraient plus jamais**. Et les collections Mongo
> n'ont pas d'`objectId`, qui est pourtant la clé de fusion des compteurs.

### Raccourcis clavier rendus au navigateur

`commands/CommandListener.svelte` écoute `window.keydown` et appelle `preventDefault()` dès qu'un
raccourci DbGate correspond. En version web, cela confisquait au navigateur **les trois moyens de
recharger** (`F5`, `Ctrl+R`, `Ctrl+Shift+R`), les devtools (`Ctrl+Shift+C`), la barre d'adresse
(`Ctrl+L`), les onglets (`Ctrl+T`, `Ctrl+Shift+T`) et le zoom (`Ctrl+0/-/=`).

Une liste `BROWSER_RESERVED_KEYS` en tête du fichier rend ces touches au navigateur, **uniquement
hors Electron** (dans l'application de bureau il n'y a pas de navigateur autour, toutes les commandes
DbGate restent actives). Pour rendre un raccourci à DbGate, retirer sa ligne de la liste.

Conflits laissés à DbGate par défaut, car ce sont des actions applicatives légitimes :
`F5`/`Ctrl+R` (exécuter la requête), `Ctrl+F5` (rafraîchir avec la structure), `Ctrl+F`, `Ctrl+S`,
`Ctrl+D`, `Ctrl+J`, `Ctrl+U`.

⚠️ Pour diagnostiquer un raccourci, chercher `keyText` dans **tout** `packages/web/src`, pas
seulement dans `commands/stdCommands.ts` : les onglets et la grille de données en enregistrent aussi
(`tabs/`, `datagrid/`).

### Erreurs console de l'éditeur Ace (corrigées)

Deux erreurs présentes dans DbGate 7.1.6 d'origine, indépendantes de ce fork :

**`worker-json.js` — NetworkError.** Ace charge ses workers dynamiquement depuis le dossier du
bundle, mais `rolldown.config.mjs` ne les copiait pas. Corrigé en ajoutant
`ace-builds/src-noconflict/worker-*.js` aux cibles du plugin `copy` (11 workers désormais livrés).

**`keybinding-null.js` — 401.** `AceEditor.svelte` construisait `'ace/keyboard/' + keyBindingMode`
dès que le mode n'était pas exactement `'default'`. Or le réglage vaut `null` tant que l'utilisateur
n'y a pas touché, d'où une requête vers `keybinding-null.js`. Corrigé par `resolveKeyboardHandler()`,
qui traite toute valeur absente comme `default`.

> Le 401 plutôt qu'un 404 vient de l'authentification de l'API, qui répond 401 sur les chemins
> statiques inconnus. Un 401 sur un fichier `/build/*` signifie donc « fichier absent », pas
> « problème de droits ».

## Serveur de dev séparé (optionnel, rarement utile)

La boucle `deploy.sh` prenant ~20 s, le serveur de dev n'apporte pas grand-chose ici. Il reste pertinent
pour expérimenter sans jamais toucher à l'instance publique :
```sh
cd /srv/dbgate && yarn start                  # API sur 3000, watch rolldown, données isolées
ssh -L 3000:127.0.0.1:3000 <USER>@<IP-SERVEUR>    # depuis le poste client, port 3000 fermé au pare-feu
```
Attention : ce mode produit un bundle avec `API_URL=http://localhost:3000` codé en dur — **ne jamais le déployer**.
C'est précisément ce que vérifie le garde-fou de `deploy.sh`.

---

## Project Overview

DbGate is a cross-platform (no)SQL database manager supporting MySQL, PostgreSQL, SQL Server, Oracle, MongoDB, Redis, SQLite, and more. It runs as a web app (Docker/NPM), an Electron desktop app, or in a browser. The monorepo uses Yarn workspaces.

## Development Commands

```sh
yarn          # install all packages (also builds TS libraries and plugins)
yarn start    # run API (port 3000) + web (port 5001) concurrently
```

For more control, run these 3 commands in separate terminals:
```sh
yarn start:api    # Express API on port 3000
yarn start:web    # Svelte frontend on port 5001
yarn lib          # watch-compile TS libraries and plugins
```

For Electron development:
```sh
yarn start:web     # web on port 5001
yarn lib           # watch TS libs/plugins
yarn start:app     # Electron app
```

### Building

```sh
yarn build:lib          # build all TS libraries (sqltree, tools, filterparser, datalib, rest)
yarn build:api          # build API
yarn build:web          # build web frontend
yarn ts                 # TypeScript type-check API and web
yarn prettier           # format all source files
```

### Testing

Unit tests (in packages like `dbgate-tools`):
```sh
yarn workspace dbgate-tools test
```

Integration tests (requires Docker for database containers):
```sh
cd integration-tests
yarn test:local                                              # run all tests
yarn test:local:path __tests__/alter-database.spec.js       # run a single test file
```

E2E tests (Cypress):
```sh
yarn cy:open                    # open Cypress UI
cd e2e-tests && yarn cy:run:browse-data   # run a specific spec headlessly
```

## Architecture

### Monorepo Structure

| Path | Package | Purpose |
|---|---|---|
| `packages/api` | `dbgate-api` | Express.js backend server |
| `packages/web` | `dbgate-web` | Svelte 4 frontend (built with Rolldown) |
| `packages/tools` | `dbgate-tools` | Shared TS utilities: SQL dumping, schema analysis, diffing, driver base classes |
| `packages/datalib` | `dbgate-datalib` | Grid display logic, changeset management, perspectives, chart definitions |
| `packages/sqltree` | `dbgate-sqltree` | SQL AST representation and dumping |
| `packages/filterparser` | `dbgate-filterparser` | Parses filter strings into SQL/Mongo conditions |
| `packages/rest` | `dbgate-rest` | REST connection support |
| `packages/types` | `dbgate-types` | TypeScript type definitions (`.d.ts` only) |
| `packages/aigwmock` | `dbgate-aigwmock` | Mock AI gateway server for E2E testing |
| `plugins/dbgate-plugin-*` | — | Database drivers and file format handlers |
| `app/` | — | Electron shell |
| `integration-tests/` | — | Jest-based DB integration tests (Docker) |
| `e2e-tests/` | — | Cypress E2E tests |

### API Backend (`packages/api`)

- Express.js server with controllers in `src/controllers/` — each file exposes REST endpoints via the `useController` utility
- Database connections run in child processes (`src/proc/`) to isolate crashes and long-running operations
- `src/shell/` contains stream-based data pipeline primitives (readers, writers, transforms) used for import/export and replication
- Plugin drivers are loaded dynamically via `requireEngineDriver`; each plugin in `plugins/` exports a driver conforming to `DriverBase` from `dbgate-tools`

### Frontend (`packages/web`)

- Svelte 4 components; builds with Rolldown (not Vite/Webpack)
- Global state in `src/stores.ts` using Svelte writable stores, with `writableWithStorage` / `writableWithForage` helpers for persistence
- API calls go through `src/utility/api.ts` (`apiCall`, `apiOff`, etc.) which handles auth, error display, and cache invalidation
- Tab system: each open editor/viewer is a "tab" tracked in `openedTabs` store; tab components live in `src/tabs/`
- Left-panel tree items are "AppObjects" in `src/appobj/`
- Metadata (table lists, column info) is loaded reactively via hooks in `src/utility/metadataLoaders.ts`
- Commands/keybindings are registered in `src/commands/`

### Plugin Architecture

Each `plugins/dbgate-plugin-*` package provides:
- **Frontend build** (`build:frontend`): bundled JS loaded by the web UI for query formatting, data rendering
- **Backend build** (`build:backend`): Node.js driver code loaded by the API for actual DB connections

Plugins are copied to `plugins/dist/` via `plugins:copydist` before building the app or Docker image.

### Key Conventions

- Error/message codes use `DBGM-00000` as placeholder — do not introduce new numbered `DBGM-NNNNN` codes
- Frontend uses **Svelte 4** (not Svelte 5)
- E2E test selectors use `data-testid` attribute with format `ComponentName_identifier`
- Prettier config: single quotes, 2-space indent, 120-char line width, trailing commas ES5
- Logging via `pinomin`; pipe through `pino-pretty` for human-readable output

### Translation System

```sh
yarn translations:extract        # extract new strings
yarn translations:add-missing    # add missing translations
yarn translations:check          # check for issues
```
