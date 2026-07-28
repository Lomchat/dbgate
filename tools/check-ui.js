/*
 * Verification visuelle de l'interface, sans passer par le navigateur de l'utilisateur.
 *
 * Charge l'instance locale, se connecte, survole un bouton du rail d'icones et rapporte
 * si l'infobulle est reellement PEINTE (pas seulement presente dans le DOM). Une capture
 * est ecrite pour inspection.
 *
 * Motivation : une infobulle peut etre dans le DOM, avec visibility:visible et opacity:1,
 * tout en etant invisible parce qu'un autre panneau la recouvre. Seul le rendu le montre.
 *
 * Prerequis : puppeteer + un binaire chromium. Adapter les deux constantes ci-dessous.
 *
 *   nvm use 20 && node tools/check-ui.js
 */
const PUPPETEER = '/srv/school/frontend/node_modules/puppeteer';
const CHROME = '/root/.cache/ms-playwright/chromium-1228/chrome-linux64/chrome';

const puppeteer = require(PUPPETEER);
const fs = require('fs');

const TARGET = process.argv[2] || 'WidgetIconPanel_database';
const OUT = '/tmp/dbgate-check-ui.png';

const PW = fs
  .readFileSync('/srv/dbgate/runtime/.env', 'utf8')
  .split('\n')
  .find(l => l.startsWith('LOGIN_PASSWORD_admin='))
  .split('=')[1]
  .trim()
  .replace(/^'|'$/g, '');

(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1400, height: 900 });

  const errors = [];
  page.on('console', m => {
    if (m.type() === 'error') errors.push(m.text().slice(0, 140));
  });

  await page.goto('http://127.0.0.1:9999/', { waitUntil: 'networkidle2', timeout: 30000 });

  if (await page.$('input[type=password]')) {
    const user = await page.$('input[type=text]');
    if (user) await user.type('admin');
    await page.type('input[type=password]', PW);
    await Promise.all([
      page.keyboard.press('Enter'),
      page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 30000 }).catch(() => {}),
    ]);
    await new Promise(r => setTimeout(r, 3000));
  }

  const button = await page.$(`[data-testid=${TARGET}]`);
  if (!button) {
    console.log(`ECHEC : bouton [data-testid=${TARGET}] introuvable`);
    await page.screenshot({ path: OUT });
    await browser.close();
    process.exit(1);
  }

  await button.hover();
  await new Promise(r => setTimeout(r, 600));

  const tip = await page.evaluate(() => {
    const el = document.querySelector('.sidebar-tooltip');
    if (!el) return null;
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    // Test decisif : quel element occupe reellement le centre de l'infobulle ?
    // L'infobulle porte pointer-events:none, donc elementFromPoint la traverserait et
    // signalerait a tort un recouvrement. On le neutralise le temps du test de hit-test.
    const savedPointerEvents = el.style.pointerEvents;
    el.style.pointerEvents = 'auto';
    const onTop = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
    el.style.pointerEvents = savedPointerEvents;
    return {
      texte: el.textContent,
      rect: { x: r.x, y: r.y, w: r.width, h: r.height },
      visibility: cs.visibility,
      opacity: cs.opacity,
      zIndex: cs.zIndex,
      recouvertePar: onTop === el ? null : onTop?.className || onTop?.tagName,
    };
  });

  if (!tip) {
    console.log('ECHEC : aucune infobulle dans le DOM au survol');
  } else if (tip.recouvertePar) {
    console.log(`ECHEC : infobulle presente mais RECOUVERTE par "${tip.recouvertePar}"`);
    console.log(JSON.stringify(tip, null, 2));
  } else {
    console.log(`OK : infobulle "${tip.texte}" visible et au premier plan`);
    console.log(`     position ${Math.round(tip.rect.x)},${Math.round(tip.rect.y)} ` + `taille ${Math.round(tip.rect.w)}x${Math.round(tip.rect.h)}`);
  }

  await page.screenshot({ path: OUT });
  console.log('capture   :', OUT);
  console.log('erreurs console :', errors.length ? errors : 'aucune');

  await browser.close();
  process.exit(tip && !tip.recouvertePar ? 0 : 1);
})().catch(e => {
  console.error('ECHEC :', e.message);
  process.exit(1);
});
