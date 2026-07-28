const { DatabaseAnalyser } = global.DBGATE_PACKAGES['dbgate-tools'];

class Analyser extends DatabaseAnalyser {
  constructor(dbhan, driver, version) {
    super(dbhan, driver, version);
  }

  // Nombre de $collStats simultanes. Au-dela, sur un serveur distant, les requetes se mettent
  // en file d'attente et finissent par expirer au lieu d'aller plus vite.
  static STATS_CONCURRENCY = 4;
  // Budget total accorde aux statistiques. Depasse, on rend la structure sans elles :
  // mieux vaut un arbre immediat sans compteurs qu'un arbre qui se fait attendre.
  static STATS_BUDGET_MS = 1200;

  async _collectStats(collections) {
    const deadline = Date.now() + Analyser.STATS_BUDGET_MS;
    const byName = {};
    let index = 0;

    const worker = async () => {
      while (index < collections.length && Date.now() < deadline) {
        const current = collections[index++];
        try {
          const resp = await this.dbhan
            .getDatabase()
            .collection(current.name)
            .aggregate([{ $collStats: { count: {}, storageStats: {} } }], {
              maxTimeMS: Math.max(200, deadline - Date.now()),
            })
            .toArray();
          byName[current.name] = { count: resp[0]?.count, size: resp[0]?.storageStats?.size };
        } catch (e) {
          // $collStats non supporte, vue, collection distribuee, delai depasse :
          // cette collection sera simplement affichee sans compteur.
        }
      }
    };

    const work = Promise.all(
      Array.from({ length: Math.min(Analyser.STATS_CONCURRENCY, collections.length) }, worker)
    );

    // Le budget doit etre tenu meme si une requete deja partie ne repond jamais : la verifier
    // en tete de boucle ne suffit pas, et maxTimeMS ne borne que l'execution serveur, pas
    // l'attente reseau ni l'acquisition d'une connexion du pool. D'ou cette course explicite.
    // Les requetes en retard continuent sans nuire : elles ecrivent dans un objet plus lu.
    await Promise.race([
      work,
      new Promise((resolve) => setTimeout(resolve, Analyser.STATS_BUDGET_MS)),
    ]);
    work.catch(() => {});

    return byName;
  }

  async _runAnalysis() {
    const collectionsAndViews = await this.dbhan.getDatabase().listCollections().toArray();
    const collections = collectionsAndViews.filter((x) => x.type == 'collection');
    const views = collectionsAndViews.filter((x) => x.type == 'view');

    // Les compteurs et tailles ne servent qu'a decorer l'arbre : la liste des collections,
    // elle, est deja complete. On ne laisse donc jamais ces statistiques bloquer l'affichage.
    //
    // L'implementation d'origine lancait un $collStats par collection, toutes en parallele via
    // Promise.all. Sur un serveur distant cela sature le pool de connexions et les requetes
    // s'empilent jusqu'a expirer : mesure a plus de 30 s sur une base de 9 collections, alors
    // que les memes requetes en sequentiel prennent 237 ms au total.
    const stats = await this._collectStats(collections);


    const res = this.mergeAnalyseResult({
      collections: [
        // Indexation par nom : l'ancien code indexait par position, ce qui associait les
        // statistiques a la mauvaise collection des qu'une seule requete echouait.
        ...collections.map((x) => ({
          pureName: x.name,
          tableRowCount: stats[x.name]?.count,
          sizeBytes: stats[x.name]?.size,
          uniqueKey: [{ columnName: '_id' }],
          partitionKey: [{ columnName: '_id' }],
          clusterKey: [{ columnName: '_id' }],
        })),
        ...views.map((x, index) => ({
          pureName: x.name,
          uniqueKey: [{ columnName: '_id' }],
          partitionKey: [{ columnName: '_id' }],
          clusterKey: [{ columnName: '_id' }],
        })),
      ],
    });
    // console.log('MERGED', res);
    return res;
  }
}

module.exports = Analyser;
