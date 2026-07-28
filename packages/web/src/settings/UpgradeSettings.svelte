<script lang="ts">
  import FormStyledButton from '../buttons/FormStyledButton.svelte';
  import { isElectronAvailable } from '../utility/getElectron';
  import { openWebLink } from '../utility/simpleTools';
  import { _t } from '../translations';

  function handleUpgrade() {
    openWebLink(
      `https://www.dbgate.io/purchase/${isElectronAvailable() ? 'premium' : 'team-premium'}/?utm_campaign=premiumUpgradeButton`
    );
  }
</script>

<div class="wrapper">
  <div class="heading">{_t('settings.upgrade', { defaultMessage: 'Upgrade to Premium' })}</div>
  <div class="text">
    {_t('settings.upgrade.description', {
      defaultMessage:
        'DbGate Premium adds an administration console, OAuth and LDAP login, role based permissions and additional database drivers.',
    })}
  </div>
  <div class="button-row">
    <FormStyledButton
      type="button"
      value={_t('settings.upgrade.button', { defaultMessage: 'Upgrade to Premium' })}
      on:click={handleUpgrade}
    />
  </div>
</div>

<style>
  .heading {
    font-size: 20px;
    margin: 5px;
    margin-left: var(--dim-large-form-margin);
    margin-top: var(--dim-large-form-margin);
  }

  .text {
    margin: 5px;
    margin-left: var(--dim-large-form-margin);
    max-width: 600px;
  }

  .button-row {
    margin: 5px;
    margin-left: var(--dim-large-form-margin);
    margin-top: 15px;
  }
</style>
