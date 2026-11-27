<div align="center">

<img src="assets/icon-1024.png" width="112" alt="Logo Ember">

# Ember

**Le coût réel de tes IA de développement, dans la barre des menus de ton Mac.**

Quotas en direct · dépense en équivalent API · projections · 100 % local

[![Dernière version](https://img.shields.io/github/v/release/AlexMouth/Ember?label=version&color=F97316)](https://github.com/AlexMouth/Ember/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)
![Universel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universel-555555)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![100 % local](https://img.shields.io/badge/donn%C3%A9es-100%20%25%20locales-22C55E)

### [⬇︎ Télécharger Ember](https://github.com/AlexMouth/Ember/releases/latest)

[Pourquoi Ember](#pourquoi-ember) · [Fonctionnalités](#fonctionnalités) · [Agents pris en charge](#agents-pris-en-charge) · [Installation](#installation) · [Confidentialité](#confidentialité) · [Prix des modèles](#prix-des-modèles) · [Développement](#développement)

</div>

---

## Pourquoi Ember

Tes agents de code laissent déjà des journaux détaillés sur ton disque. Ember les lit et répond à trois questions, sans compte, sans serveur et sans configuration :

| | Question | Réponse d'Ember |
| :---: | --- | --- |
| 🔋 | **Combien il me reste ?** | Le quota de ton abonnement (fenêtre de 5 h et hebdomadaire), avec l'heure du prochain reset. |
| 💸 | **Combien ça m'aurait coûté ?** | La dépense en équivalent API, par jour, par modèle et par projet. |
| 📈 | **Est-ce que je tiens le rythme ?** | Ta consommation comparée au rythme idéal, et une projection jusqu'au reset. |

## Fonctionnalités

### Barre des menus

Une flamme discrète, **verte** tant que tout va bien, **orange** à partir de 80 % du quota, **rouge** à partir de 95 %. À côté, le chiffre qui t'intéresse : quota restant ou dépense du jour, avec une mini-jauge en option.

Un clic ouvre le popover :

- une carte par quota, avec le pourcentage restant et les barres 5 h et hebdomadaire ;
- la session Claude Code en cours : projet, durée, coût et modèle ;
- la dépense du jour et des 30 derniers jours, et les sources les plus actives.

<kbd>⌘R</kbd> actualiser · <kbd>⌘D</kbd> tableau de bord · <kbd>⌘,</kbd> réglages · <kbd>⌘Q</kbd> quitter

### Tableau de bord

- **Vue d'ensemble :** dépense, tokens, rythme et projection du mois.
- **Courbes de quota :** consommation réelle face au rythme idéal, zones d'avance et de retard, projection au rythme actuel et infobulle au survol.
- **Classements :** modèles et projets triés par coût, avec barre proportionnelle et part du total.
- **Répartition des tokens :** entrée, sortie, lecture et écriture du cache, sur une échelle logarithmique pour que les petites catégories restent lisibles.
- **Une page par agent,** avec ses propres modèles, projets et tokens.

Le graphique de dépense existe en **quatre styles**, au choix dans *Réglages › Général › Tableau de bord* :

| Style | Ce qu'il montre |
| --- | --- |
| **Barres et moyenne** | Barres empilées par source ou par modèle, avec la moyenne. Par jour, semaine ou mois. |
| **Cumul du mois** | Courbe cumulée, projection de fin de mois et comparaison avec le mois dernier. |
| **Calendrier** | Un carré par jour, coloré selon la dépense. |
| **Période en cours** | Barres fines, période en cours mise en avant, sans les jours vides. |

### Quota Claude en direct

Ember affiche le **vrai pourcentage** de ton abonnement Claude, lu sur `api.anthropic.com` avec le jeton de Claude Code. Ce jeton est lu dans le trousseau **en lecture seule** : Ember ne le renouvelle et ne l'écrit jamais.

Si le jeton a expiré, Ember le signale et estime le quota à partir de ta consommation. Relancer `claude` suffit à le renouveler.

### Alertes

- **Budget mensuel :** notification à 80 % puis à 100 %.
- **Quota :** notification quand il reste 30, 20, 10 ou 5 %, puis quand la limite est atteinte.

### Réglages

- Une fenêtre dans l'esprit de Réglages Système, avec un aperçu en direct de l'icône de la barre des menus.
- **Données et prix :** pour chaque modèle utilisé, le prix appliqué, le coût total et l'origine du prix.
- **Export CSV** de toute la consommation, et accès en un clic au dossier de données.
- **Zone de danger :** effacement des données d'Ember, protégé par une confirmation par saisie.

### Mises à jour intégrées

Ember se met à jour depuis les Releases GitHub. Chaque archive porte une **signature Ed25519**, vérifiée avant l'installation ; en cas d'échec, l'ancienne version est restaurée.

## Agents pris en charge

| Agent | Dépense et tokens | Quota | Source lue |
| --- | :---: | :---: | --- |
| **Claude Code** | ✓ | ✓ en direct | `~/.claude/projects/**/*.jsonl` |
| **Codex** | ✓ | ✓ | `~/.codex/sessions/**/*.jsonl` |
| **Gemini CLI** | ✓ | — | `~/.gemini/tmp/*/chats/*.json` |
| **Kiro CLI** | ✓ | — | base SQLite locale de Kiro |
| **Cursor** | ✓ si disponible | — | `state.vscdb` |

Ember repère aussi les autres IA installées ou lancées sur le Mac (Copilot, ChatGPT, Kimi…) et les liste dans les Sources, même lorsqu'elles ne laissent aucun compteur lisible.

## Installation

1. Télécharge **`Ember-x.y.z.dmg`** depuis la [dernière release](https://github.com/AlexMouth/Ember/releases/latest).
2. Ouvre le `.dmg` et glisse **Ember** dans **Applications**.
3. Lance Ember : la flamme apparaît dans la barre des menus.

> [!NOTE]
> Ember est signé en ad-hoc mais n'est pas notarisé par Apple. Au premier lancement, fais un clic droit sur Ember, puis **Ouvrir**, et confirme avec **Ouvrir**. Si macOS bloque toujours l'app :
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Ember.app
> ```

**Configuration requise :** macOS 14 Sonoma ou plus récent, sur Apple Silicon ou Intel. Sur macOS 26, l'interface adopte Liquid Glass.

## Confidentialité

> [!IMPORTANT]
> **Tout est calculé sur ton Mac.** Ember n'a ni compte ni serveur, ne collecte rien et n'envoie aucune statistique d'usage.

- **Fichiers :** les journaux des agents sont ouverts en lecture seule. Le cache et l'historique de quota (35 jours) restent dans `~/Library/Application Support/Ember`.
- **Réseau :** deux appels seulement.
  - La lecture du quota Claude sur `api.anthropic.com`, avec ton propre jeton. Elle se désactive dans *Réglages › Compte Claude*.
  - La vérification des mises à jour, via l'API publique de GitHub.

## Prix des modèles

Les coûts sont exprimés en **équivalent API** : ce que tu aurais payé à l'usage pour les mêmes tokens. Pour chaque modèle, Ember retient le premier prix trouvé dans cet ordre :

| # | Source | Emplacement |
| :---: | --- | --- |
| 1 | **Tes prix personnalisés** | `~/Library/Application Support/Ember/pricing-overrides.json` |
| 2 | **[models.dev](https://models.dev)**, copie intégrée à l'app | `Sources/Ember/Resources/pricing.json` |
| 3 | **Prix intégrés** pour les modèles absents de models.dev | `Sources/Ember/Resources/pricing-fallbacks.json` |
| 4 | **Même famille (≈)** : un nouveau modèle hérite du prix de sa famille (`opus`, `sonnet`, `gpt-5`…) | `Sources/Ember/Resources/pricing-fallbacks.json` |

Un modèle sans prix connu est compté **0 $** et signalé en rouge dans *Réglages › Données et prix*.

Pour corriger un prix, clique sur **Ouvrir…** dans cette page, modifie le fichier, puis clique sur **Recharger** : pas besoin de relancer Ember. Les valeurs sont en USD par million de tokens, et le nom du modèle est insensible à la casse :

```json
{
  "mon-modele": [3.0, 15.0, 0.30, 3.75]
}
```

Dans l'ordre : entrée, sortie, lecture du cache, écriture du cache.

## Développement

**Prérequis :** macOS 14 ou plus récent, avec Xcode ou les Command Line Tools (Swift 6).

Compiler l'app :

```bash
./scripts/build_app.sh
```

La lancer :

```bash
open build/Ember.app
```

Lancer les tests :

```bash
./scripts/test.sh
```

`build_app.sh` compile en release (`-Osize`, binaire nettoyé) et signe l'app en ad-hoc. `test.sh` lance la suite swift-testing : prix, projections de quota, lecture des journaux de chaque agent, cache, export CSV et vérification des mises à jour.

<details>
<summary><b>Variables de compilation</b></summary>

<br>

Ces variables s'appliquent à `build_app.sh`, et donc aussi à `release.sh`.

| Variable | Défaut | Rôle |
| --- | --- | --- |
| `VERSION` | dernier tag git (sans `v`) | `CFBundleShortVersionString` |
| `BUILD_NUMBER` | nombre de commits | `CFBundleVersion` |
| `BUNDLE_ID` | `local.ember.app` | identifiant du bundle |
| `SIGN_IDENTITY` | `-` (ad-hoc) | identité de signature, ex. `Developer ID Application: …` (active le runtime durci) |
| `ARCHS` | architecture de la machine | ex. `"arm64 x86_64"` pour un binaire universel |

</details>

<details>
<summary><b>Publier une version</b></summary>

<br>

```bash
VERSION=0.6.0 ./scripts/release.sh
```

Le script produit quatre fichiers dans `dist/`. **Les quatre doivent être joints à la Release GitHub :**

| Fichier | Rôle |
| --- | --- |
| `Ember-<version>.dmg` | installation manuelle |
| `Ember-<version>.zip` | archive de la mise à jour intégrée |
| `Ember-<version>.zip.sig` | signature Ed25519 du ZIP, obligatoire |
| `Ember-<version>.zip.sha256` | empreinte, utilisée seulement par les versions 0.4.2 et antérieures |

La mise à jour intégrée refuse tout ZIP dont la signature est absente ou invalide.

**Clé de signature :** elle ne quitte jamais la machine. Elle se trouve dans `~/.config/ember/update-signing.key`, ou à l'emplacement donné par `$EMBER_SIGNING_KEY`. La clé publique correspondante est intégrée dans `Updater.swift`.

- Pour la créer, une seule fois : `swift scripts/sign_update.swift genkey`.
- Sauvegarde-la : sans elle, les copies déjà installées ne peuvent plus se mettre à jour.

**Notarisation** (facultative, nécessite un compte Developer ID) :

1. Crée une fois un profil :
   ```bash
   xcrun notarytool store-credentials <profil> --apple-id <id> --team-id <équipe>
   ```
2. Puis, à chaque version :
   ```bash
   SIGN_IDENTITY="Developer ID Application: Nom (TEAMID)" NOTARY_PROFILE=<profil> VERSION=0.6.0 ./scripts/release.sh
   ```

</details>

<details>
<summary><b>Options de débogage</b></summary>

<br>

| Commande | Effet |
| --- | --- |
| `Ember --dump` | affiche les totaux lus pour chaque agent |
| `Ember --snapshot <dossier>` | rend les écrans principaux et les 4 styles de graphique en PNG |
| `Ember --open-settings --settings-pane data` | ouvre directement une page des Réglages |

Le logo se régénère avec `swift scripts/make_icon.swift && ./scripts/make_icns.sh`.

</details>

<details>
<summary><b>Structure du projet</b></summary>

<br>

| Chemin | Rôle |
| --- | --- |
| `Sources/Ember/Providers/` | lecteurs par agent et découverte automatique |
| `Sources/Ember/Store.swift` | état, rafraîchissement, alertes |
| `Sources/Ember/Quota.swift` | modèle et calculs de quota (rythme, projection) |
| `Sources/Ember/QuotaViews.swift` | courbes, cartes, infobulles |
| `Sources/Ember/SpendViews.swift` | graphique de dépense (4 styles), classements, répartition des tokens |
| `Sources/Ember/Screens.swift` | popover, tableau de bord, pages par agent |
| `Sources/Ember/SettingsView.swift` | fenêtre des Réglages |
| `Sources/Ember/Pricing.swift` | résolution des prix (personnalisé, models.dev, intégré, famille) |
| `Sources/Ember/Updater.swift` | mise à jour intégrée (signature Ed25519, retour arrière) |
| `Sources/Ember/Debug.swift` | `--dump` et `--snapshot` |
| `Tests/EmberTests/` | tests swift-testing |

</details>

## Crédits

Prix des modèles fournis par [models.dev](https://models.dev).

Ember est un projet indépendant, sans lien avec Anthropic, OpenAI, Google, Amazon ou Anysphere. Les noms des agents appartiennent à leurs propriétaires respectifs.
