<script lang="ts">
  import { useCloudContentList, useConfig, useConnectionInfo } from '../utility/metadataLoaders';

  import ConnectionList from './ConnectionList.svelte';

  import WidgetColumnBar from './WidgetColumnBar.svelte';
  import WidgetColumnBarItem from './WidgetColumnBarItem.svelte';
  import SingleConnectionDatabaseList from './SingleConnectionDatabaseList.svelte';
  import _ from 'lodash';
  import { _t } from '../translations';
  import DatabaseWidgetDetailContent from './DatabaseWidgetDetailContent.svelte';
  import { detachedDbObjects } from '../stores';

  export let hidden = false;
  let domSqlObjectList = null;

  $: config = useConfig();
  $: cloudContentList = useCloudContentList();
</script>

<!-- WidgetColumnBar accumule les definitions de sections au montage et ne les retire jamais.
     Sans remontage, les sections parties dans la deuxieme colonne continueraient d'y reserver
     leur hauteur, laissant un vide sous les connexions. -->
{#key $detachedDbObjects}
  <WidgetColumnBar {hidden} storageName="databaseWidget">
  {#if $config?.singleConnection}
    <WidgetColumnBarItem title={_t('widget.databases', { defaultMessage: 'Databases' })} name="databases" height="35%">
      <SingleConnectionDatabaseList connection={$config?.singleConnection} />
    </WidgetColumnBarItem>
  {:else if !$config?.singleDbConnection}
    <WidgetColumnBarItem
      title={_t('common.connections', { defaultMessage: 'Connections' })}
      name="connections"
      height={$detachedDbObjects ? null : '35%'}
      storeHeight
    >
      <ConnectionList
        passProps={{
          onFocusSqlObjectList: () => domSqlObjectList.focus(),
          cloudContentList: $cloudContentList,
        }}
      />
    </WidgetColumnBarItem>
  {/if}

    {#if !$detachedDbObjects}
      <DatabaseWidgetDetailContent bind:domSqlObjectList showCloudConnection={false} />
    {/if}
  </WidgetColumnBar>
{/key}
