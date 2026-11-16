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
 * Prerequis : Playwright, installe dans tools/ (cd tools && npm install). Le Chromium
 * vient du cache commun de Playwright (~/.cache/ms-playwright).
 *
 *   navig timeout 120 node tools/check-ui.js [data-testid]
 */
const { chromium } = require('playwright');
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

async function main(browser) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });

  const errors = [];
  page.on('console', m => {
    if (m.type() === 'error') errors.push(m.text().slice(0, 140));
  });

  await page.goto('http://127.0.0.1:9999/', { waitUntil: 'networkidle', timeout: 30000 });

  if (await page.$('input[type=password]')) {
    const user = await page.$('input[type=text]');
    if (user) await user.fill('admin');
    await page.fill('input[type=password]', PW);
    await page.keyboard.press('Enter');
    // La connexion recharge la page : on attend le rail d'icones de la nouvelle page.
    await page.waitForSelector('[data-testid^=WidgetIconPanel_]', { timeout: 30000 }).catch(() => {});
    await new Promise(r => setTimeout(r, 3000));
  }

  const button = await page.$(`[data-testid=${TARGET}]`);
  if (!button) {
    console.log(`ECHEC : bouton [data-testid=${TARGET}] introuvable`);
    await page.screenshot({ path: OUT });
    return 1;
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

  return tip && !tip.recouvertePar ? 0 : 1;
}

(async () => {
  const browser = await chromium.launch({
    args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
  });
  try {
    process.exitCode = await main(browser);
  } finally {
    await browser.close();
  }
})().catch(e => {
  console.error('ECHEC :', e.message);
  process.exitCode = 1;
});
