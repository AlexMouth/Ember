<div align="center">

<img src="assets/icon-1024.png" width="128" alt="Logo Ember">

# Ember

**Ce que te coûtent vraiment tes IA de développement, dans la barre des menus de ton Mac.**

Claude Code · Codex · Gemini CLI · Kiro CLI · Cursor

[![Dernière version](https://img.shields.io/github/v/release/AlexMouth/Ember?label=version&color=F97316)](https://github.com/AlexMouth/Ember/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Universel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universel-555555)
![100 % local](https://img.shields.io/badge/donn%C3%A9es-100%20%25%20locales-22C55E)

[**Télécharger**](https://github.com/AlexMouth/Ember/releases/latest) · [Fonctionnalités](#fonctionnalités) · [Installation](#installation) · [Prix des modèles](#prix-des-modèles) · [Développement](#développement)

</div>

---

Ember lit les journaux que tes agents laissent déjà sur ton disque et en tire trois réponses, sans compte ni serveur :

- **Combien il me reste ?** Le quota de ton abonnement (fenêtre de 5 h, hebdomadaire), en pourcentage, avec l'heure du prochain reset.
- **Combien ça m'aurait coûté ?** La dépense en équivalent API, par jour, par modèle, par projet.
- **Est-ce que je tiens le rythme ?** Une courbe de consommation comparée au rythme idéal, et une projection jusqu'au reset.

## Fonctionnalités

### 🔥 Dans la barre des menus

- **Une flamme qui change de couleur :** verte tant que le quota va bien, orange dès 80 % utilisés, rouge dès 95 %. Elle peut être accompagnée d'une mini-jauge.
- **Le chiffre qui compte :** quota restant ou dépense du jour, au choix.
- **Le popover :**
  - une carte par quota, avec le pourcentage restant en grand et les barres 5 h et hebdomadaire ;
  - la session Claude Code en cours (projet, durée, coût, modèle) ;
  - la dépense du jour et des 30 jours, et les sources les plus utilisées.
- **Raccourcis :** <kbd>⌘R</kbd> actualiser · <kbd>⌘,</kbd> réglages · <kbd>⌘D</kbd> tableau de bord · <kbd>⌘Q</kbd> quitter.

### 📊 Tableau de bord

- **Aperçu :** dépense, tokens, rythme et projection du mois.
- **Graphique de dépense** par jour, par semaine ou par mois, ventilé par source.
- **Courbes de « burn-down » des quotas :**
  - zones d'avance et de retard ;
  - projection au rythme actuel ;
  - infobulle au survol, y compris sur les valeurs à venir.
- **Répartition par modèle et par projet,** et une page par agent (modèles, projets, types de tokens).

### 🔑 Quota Claude en direct

- **Ce qu'Ember lit :** le vrai pourcentage de ton abonnement, lu sur `api.anthropic.com` avec le jeton de Claude Code. Ember lit ce jeton dans le trousseau, en **lecture seule**, et ne le renouvelle ni ne l'écrit jamais.
- **Si le jeton a expiré :** Ember le signale. Relancer `claude` suffit à le renouveler ; en attendant, le quota est estimé à partir de ta consommation.

### 🔔 Alertes

- **Budget mensuel :** notification à 80 % puis à 100 %.
- **Quota :** notification quand il reste 30, 20, 10 ou 5 %, et quand la limite est atteinte.

### ⚙️ Réglages

- **Une fenêtre façon Réglages Système,** avec un aperçu en direct de l'icône de la barre des menus.
- **Page « Données et prix » :** pour chaque modèle utilisé, le prix appliqué, le coût et l'origine du prix.
- **Fichiers :** export CSV de toute la consommation, et dossier de données accessible en un clic.

### 🔍 Détection automatique

- **Nouvelles IA :** une IA installée ou lancée sur le Mac (Copilot, ChatGPT, Kimi…) apparaît dans les Sources, même si elle ne laisse aucun compteur lisible.

### ⬇️ Mises à jour intégrées

- **Source :** les nouvelles versions viennent des Releases GitHub.
- **Vérification :** chaque archive a une **signature Ed25519**, vérifiée avant l'installation.
- **Retour arrière :** si l'installation échoue, Ember restaure l'ancienne version.

## Confidentialité

> **Tout est calculé sur ton Mac.** Ember ne collecte rien, n'a pas de serveur et n'envoie aucune statistique d'usage.

Une seule requête réseau sort d'Ember : la lecture du quota Claude en direct, envoyée à `api.anthropic.com` avec ton propre jeton. Elle se coupe dans Réglages › Compte Claude. La vérification des mises à jour interroge en plus l'API publique de GitHub.

| Agent | Ce qu'Ember lit |
| --- | --- |
| Claude Code | `~/.claude/projects/**/*.jsonl` |
| Codex | `~/.codex/sessions/**/*.jsonl` |
| Gemini CLI | `~/.gemini/tmp/*/chats/*.json` |
| Kiro CLI | base SQLite locale de Kiro |
| Cursor | `state.vscdb` (quand il contient des compteurs) |

Tous ces fichiers sont ouverts en lecture seule. Ember garde son cache et son historique de quota (35 jours) dans `~/Library/Application Support/Ember`.

## Installation

1. Télécharge **`Ember-x.y.z.dmg`** depuis la [dernière release](https://github.com/AlexMouth/Ember/releases/latest).
2. Ouvre le `.dmg` et glisse **Ember** dans **Applications**.
3. Lance Ember : une flamme apparaît dans la barre des menus.

> [!NOTE]
> Ember est signé en ad-hoc mais pas notarisé par Apple. Au premier lancement, fais un clic droit sur Ember, puis **Ouvrir** et encore **Ouvrir**. Si macOS bloque toujours l'app :
> ```bash
> xattr -dr com.apple.quarantine /Applications/Ember.app
> ```

**Configuration requise :** macOS 14 Sonoma ou plus récent, Apple Silicon ou Intel. Sur macOS 26, l'interface utilise Liquid Glass.

## Prix des modèles

Les coûts sont calculés en **équivalent API** : ce que tu aurais payé à l'usage pour les mêmes tokens. Ember cherche le prix de chaque modèle dans quatre sources, par ordre de priorité :

| Priorité | Source | Fichier |
| :---: | --- | --- |
| 1 | **Tes prix personnalisés** | `~/Library/Application Support/Ember/pricing-overrides.json` |
| 2 | **[models.dev](https://models.dev)**, une copie intégrée à l'app | `Sources/Ember/Resources/pricing.json` |
| 3 | **Prix intégrés** pour les modèles absents de models.dev | `Sources/Ember/Resources/pricing-fallbacks.json` |
| 4 | **Même famille (≈)** : un nouveau modèle hérite du prix de sa famille (`opus`, `sonnet`, `gpt-5`…) | `Sources/Ember/Resources/pricing-fallbacks.json` |

Un modèle introuvable dans toutes ces sources est compté **0 $** et signalé en rouge dans **Réglages › Données et prix**. Cette page montre le prix appliqué à chaque modèle et son origine.

Pour corriger un prix, clique sur **Ouvrir…** dans cette page, modifie le fichier, puis clique sur **Recharger**. Le format est en USD par million de tokens, et le nom du modèle est insensible à la casse :

```json
{
  "mon-modele": [3.0, 15.0, 0.30, 3.75]
}
```

Les quatre valeurs sont, dans l'ordre : entrée, sortie, lecture du cache et écriture du cache.

## Développement

**Prérequis :** macOS 14 ou plus récent, et Xcode ou les Command Line Tools (Swift 6).

```bash
./scripts/build_app.sh
```

```bash
open build/Ember.app
```

```bash
./scripts/test.sh
```

`build_app.sh` compile en release (`-Osize`, binaire nettoyé) et signe l'app en ad-hoc. `test.sh` lance la suite swift-testing, qui couvre :

- les prix ;
- les projections de quota ;
- la lecture des journaux de chaque agent ;
- le cache ;
- l'export CSV ;
- la vérification des mises à jour.

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
VERSION=0.5.2 ./scripts/release.sh
```

Le script produit quatre fichiers dans `dist/`, et **les quatre doivent être joints à la Release GitHub** :

- `Ember-<version>.dmg` ;
- `Ember-<version>.zip` ;
- `Ember-<version>.zip.sig` ;
- `Ember-<version>.zip.sha256`.

La mise à jour intégrée refuse tout ZIP dont la signature Ed25519 (le `.zip.sig`) est absente ou invalide. Le `.sha256` ne sert plus qu'aux versions 0.4.2 et antérieures.

La clé privée de signature ne quitte jamais la machine : elle est dans `~/.config/ember/update-signing.key`, ou à l'emplacement donné par `$EMBER_SIGNING_KEY`. La clé publique correspondante est intégrée dans `Updater.swift`.

- **Création de la clé** (une seule fois) : `swift scripts/sign_update.swift genkey`.
- **Sauvegarde-la :** sans elle, les copies déjà installées ne peuvent plus se mettre à jour.

**Notarisation** (facultative, nécessite un compte Developer ID) :

1. Crée une fois un profil :
   ```bash
   xcrun notarytool store-credentials <profil> --apple-id <id> --team-id <équipe>
   ```
2. Puis, à chaque version :
   ```bash
   SIGN_IDENTITY="Developer ID Application: Nom (TEAMID)" NOTARY_PROFILE=<profil> VERSION=0.5.2 ./scripts/release.sh
   ```

</details>

<details>
<summary><b>Options de débogage</b></summary>

<br>

| Commande | Effet |
| --- | --- |
| `Ember --dump` | affiche les totaux lus pour chaque agent |
| `Ember --snapshot <dossier>` | rend les écrans principaux en PNG |
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
| `Sources/Ember/Screens.swift` | popover, tableau de bord, pages par agent |
| `Sources/Ember/SettingsView.swift` | fenêtre des Réglages |
| `Sources/Ember/Pricing.swift` | résolution des prix (personnalisé, models.dev, intégré, famille) |
| `Sources/Ember/Updater.swift` | mise à jour intégrée (signature Ed25519, retour arrière) |
| `Sources/Ember/Debug.swift` | `--dump` et `--snapshot` |
| `Tests/EmberTests/` | tests swift-testing |

</details>

## Crédits

- **Prix des modèles :** [models.dev](https://models.dev).
- **Projet :** Ember est un projet indépendant, sans lien avec Anthropic, OpenAI, Google, Amazon ou Anysphere. Les noms des agents appartiennent à leurs propriétaires respectifs.
