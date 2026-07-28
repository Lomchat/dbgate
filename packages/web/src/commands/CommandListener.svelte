<script lang="ts" context="module">
  import { commandsCustomized, visibleCommandPalette } from '../stores';
  import { get } from 'svelte/store';
  import { runGroupCommand } from './runCommand';
  import { getKeyTextFromEvent, isMac, resolveKeyText } from '../utility/common';
  import getElectron from '../utility/getElectron';

  // Raccourcis laisses au navigateur quand DbGate tourne dans un onglet.
  //
  // Sans cette liste, DbGate fait preventDefault() sur ses propres raccourcis et confisque
  // le rechargement, les devtools, la barre d'adresse et le zoom : l'onglet devient
  // difficilement utilisable. En Electron il n'y a pas de navigateur autour, donc la liste
  // ne s'applique pas et toutes les commandes DbGate restent disponibles.
  //
  // Pour rendre un raccourci a DbGate, retirer la ligne correspondante.
  const BROWSER_RESERVED_KEYS = [
    // Rechargement et outils de developpement
    'ctrl+shift+r',
    'ctrl+shift+i',
    'ctrl+shift+j',
    'ctrl+shift+c',
    'f12',
    // Navigation et onglets
    'ctrl+l',
    'ctrl+t',
    'ctrl+shift+t',
    'ctrl+n',
    'ctrl+w',
    // Zoom
    'ctrl+0',
    'ctrl+-',
    'ctrl+=',
    'ctrl++',
    // Plein ecran
    'f11',
  ];

  function isBrowserReservedKey(keyText: string) {
    // getKeyTextFromEvent produit 'Ctrl+' ou 'Command+' selon la plateforme
    const normalized = keyText.toLowerCase().replace('command+', 'ctrl+');
    return BROWSER_RESERVED_KEYS.includes(normalized);
  }

  export function handleCommandKeyDown(e) {
    const keyText = getKeyTextFromEvent(e);

    if (!getElectron() && isBrowserReservedKey(keyText)) {
      return;
    }

    // console.log('keyText', keyText);

    const commandsValue = get(commandsCustomized);
    let commandsFiltered: any = Object.values(commandsValue).filter(
      (x: any) =>
        x.keyText &&
        resolveKeyText(x.keyText)
          .toLowerCase()
          .split('|')
          .map(x => x.trim())
          .includes(keyText.toLowerCase()) &&
        (x.disableHandleKeyText == null ||
          !resolveKeyText(x.disableHandleKeyText)
            .toLowerCase()
            .split('|')
            .map(x => x.trim())
            .includes(keyText.toLowerCase()))
    );

    if (commandsFiltered.length > 0 && commandsFiltered.find(x => !x.systemCommand)) {
      e.preventDefault();
      e.stopPropagation();
    }

    if (
      commandsFiltered.length > 1 &&
      commandsFiltered.find(x => x.systemCommand) &&
      commandsFiltered.find(x => !x.systemCommand)
    ) {
      commandsFiltered = commandsFiltered.filter(x => !x.systemCommand);
    }

    if (commandsFiltered.every(x => x.systemCommand)) {
      return;
    }

    const notGroup = commandsFiltered.filter(x => x.enabled && !x.isGroupCommand);

    if (notGroup.length > 1) {
      console.log('Warning, multiple commands mapped to', keyText, notGroup);
    }

    if (notGroup.length == 1) {
      const command = notGroup[0];
      if (command.onClick) command.onClick();
      else if (command.getSubCommands) visibleCommandPalette.set(command);
      return;
    }

    const group = commandsFiltered.filter(x => x.enabled && x.isGroupCommand);

    if (group.length > 1) {
      console.log('Warning, multiple commands mapped to', keyText, group);
    }

    if (group.length == 1) {
      const command = group[0];
      runGroupCommand(command.group);
    }
  }
</script>

<svelte:window on:keydown={handleCommandKeyDown} />
