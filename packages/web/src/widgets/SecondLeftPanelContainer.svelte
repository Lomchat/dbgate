<script lang="ts">
  // Deuxieme colonne de la sidebar : accueille "Tables, vues, fonctions" et les sections
  // voisines quand l'utilisateur les detache du panneau de gauche.
  //
  // DatabaseWidgetDetailContent n'emet que des <WidgetColumnBarItem>, qui exigent le contexte
  // pose par <WidgetColumnBar>. Il faut donc lui fournir sa propre barre ici, avec un
  // storageName distinct pour que les hauteurs de sections ne se marchent pas dessus.
  import WidgetColumnBar from './WidgetColumnBar.svelte';
  import DatabaseWidgetDetailContent from './DatabaseWidgetDetailContent.svelte';

  let domSqlObjectList = null;
</script>

<WidgetColumnBar storageName="databaseWidgetDetached">
  <DatabaseWidgetDetailContent bind:domSqlObjectList showCloudConnection={false} />
</WidgetColumnBar>
