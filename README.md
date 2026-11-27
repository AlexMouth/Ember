<p align="center"><img src="assets/icon-1024.png" width="128" alt="Logo Ember"></p>

# Ember

Application macOS de barre des menus (SwiftUI) qui suit, **en local**, la consommation de tes IA de développement : dépense équivalente API, tokens, et quotas d'abonnement avec courbes de « burn-down ».

## Ce que fait Ember

- **Suivi multi-agents** : Claude Code, Codex, Gemini CLI, Kiro CLI et Cursor, lus directement depuis leurs journaux/bases locales.
- **Détection automatique** de nouvelles IA installées ou lancées (ex. Kimi) : elles apparaissent dans « Autres IA détectées » avec leur état (ouvert / installé), même sans compteur lisible.
- **Quotas d'abonnement** (fenêtres 5 h, 7 j, 30 j) avec :
  - courbe de consommation réelle vs rythme attendu, zones d'avance / de retard colorées ;
  - projection au rythme actuel jusqu'au reset ;
  - infobulle au survol, y compris dans le futur (valeurs projetées) ;
  - historique conservé 35 jours (`~/Library/Application Support/Ember/quota-history.json`).
- **Quota Claude en direct** (activé par défaut) : lecture seule du jeton de Claude Code dans le trousseau, appel à `api.anthropic.com`. Le jeton n'est jamais renouvelé ni écrit. L'historique du début de la fenêtre en cours est reconstitué à partir de ta consommation.
- **Tableau de bord** : aperçu (dépense, tokens, rythme, projection du mois), graphique de dépense jour/semaine/mois par source, pages par agent (modèles, projets, répartition des tokens).
- **Session en cours** (Claude Code) : projet, durée, coût, tokens et modèle de la conversation active, dans le popover.
- **Répartition par modèle et par projet** dans l'aperçu du tableau de bord (top 8, toutes sources confondues).
- **Popover** dans la barre des menus : une carte par quota (gros pourcentage restant + barres 5 h / hebdo), session en cours, dépense du jour et des 30 jours, top des sources. Si le jeton Claude Code a expiré, la carte l'indique (« Estimation ») et un clic lance `claude`, ce qui suffit à le renouveler ; `claude /login` n'est proposé que si le compte est vraiment déconnecté.
- **Réglages** façon Réglages Système : barre latérale (Général, Barre des menus, Notifications, Compte Claude, Données, Sources, À propos) avec aperçu en direct de l'icône de la barre des menus et état du jeton Claude (date d'expiration).
- **Mise à jour intégrée** depuis les Releases GitHub, avec progression du téléchargement.
- **Alertes** : budget mensuel (80 % / 100 %), seuil de quota restant au choix et notification quand une limite est atteinte (100 %), via notifications macOS.
- **Export CSV**, prix des modèles modifiables (`pricing-overrides.json`), lancement à l'ouverture de session.

Tout est calculé sur ton Mac. Aucune donnée n'est envoyée, hormis l'appel Anthropic du quota Claude en direct (désactivable dans les Réglages).

## Installation (sans compiler)

1. Télécharge le dernier `Ember-x.y.z.dmg` depuis la page [Releases](https://github.com/AlexMouth/Ember/releases).
2. Ouvre le `.dmg` et glisse **Ember** dans **Applications**.
3. Au premier lancement, macOS peut bloquer l'app (elle est signée en ad-hoc, pas notarisée par Apple) : clic droit sur Ember → **Ouvrir** → **Ouvrir**. Si besoin :

```bash
xattr -dr com.apple.quarantine /Applications/Ember.app
```

L'app est universelle (Apple Silicon et Intel), macOS 14 ou plus récent. Elle vit dans la barre des menus.

## Compiler depuis les sources

### Prérequis

- macOS 14 ou plus récent
- Toolchain Swift (Xcode ou Command Line Tools)

```bash
./scripts/build_app.sh
open "$PWD/build/Ember.app"
```

Le script compile en release (`-Osize`, binaire nettoyé) et signe l'app en ad-hoc. Au premier lancement, macOS peut demander l'accès au trousseau (quota Claude) et aux notifications.

Variables d'environnement acceptées par `build_app.sh` (et donc par `release.sh`) :

| Variable | Défaut | Rôle |
| --- | --- | --- |
| `VERSION` | dernier tag git (sans `v`) | `CFBundleShortVersionString` |
| `BUILD_NUMBER` | nombre de commits | `CFBundleVersion` |
| `BUNDLE_ID` | `local.ember.app` | identifiant du bundle |
| `SIGN_IDENTITY` | `-` (ad-hoc) | identité de signature, ex. `Developer ID Application: …` (active le runtime durci) |
| `ARCHS` | architecture de la machine | ex. `"arm64 x86_64"` pour un binaire universel |

### Publier une version

```bash
VERSION=0.5.0 ./scripts/release.sh
```

Le script produit dans `dist/` : `Ember-<version>.dmg`, `Ember-<version>.zip`, `Ember-<version>.zip.sig` et `Ember-<version>.zip.sha256`. **Les quatre fichiers doivent être joints à la Release GitHub** : la mise à jour intégrée refuse tout ZIP dont la signature Ed25519 (`.zip.sig`) est absente ou invalide, vérifie la signature de l'app extraite, et restaure l'ancienne version si l'installation échoue. Le `.sha256` ne sert plus qu'aux versions ≤ 0.4.2.

La signature utilise une clé privée qui ne quitte jamais la machine (`~/.config/ember/update-signing.key`, ou `$EMBER_SIGNING_KEY`) ; la clé publique correspondante est intégrée dans `Updater.swift`. Création unique avec `swift scripts/sign_update.swift genkey`. **Sauvegarde cette clé** : sans elle, les copies installées ne peuvent plus se mettre à jour.

Notarisation (facultative, nécessite un compte Developer ID) : crée une fois un profil avec `xcrun notarytool store-credentials <profil> --apple-id <id> --team-id <équipe>`, puis :

```bash
SIGN_IDENTITY="Developer ID Application: Nom (TEAMID)" NOTARY_PROFILE=<profil> VERSION=0.5.0 ./scripts/release.sh
```

Le logo se régénère avec `swift scripts/make_icon.swift && ./scripts/make_icns.sh`.

### Tests

```bash
./scripts/test.sh
```

Le script lance `swift test` avec les options nécessaires à swift-testing quand seules les Command Line Tools sont installées. Il couvre les prix, les projections de quota, la lecture des journaux de chaque agent (Claude Code, Codex, Gemini, Kiro), le cache de fichiers, l'export CSV et la comparaison de versions / vérification SHA-256 du système de mise à jour.

Options de débogage : `Ember --dump` (affiche les données lues) et `Ember --snapshot <dossier>` (rend des PNG des vues).

### Prix des modèles

- `Sources/Ember/Resources/pricing.json` : table générée depuis models.dev (USD / million de tokens).
- `Sources/Ember/Resources/pricing-fallbacks.json` : prix intégrés pour les modèles absents de la table, et rapprochement par famille (`sonnet`, `opus`, `gpt-5`…) pour les nouvelles versions. Un prix obtenu par famille est signalé comme approché dans les Réglages.
- `~/Library/Application Support/Ember/pricing-overrides.json` : tes corrections, prioritaires sur tout le reste. Format : `{"nom-du-modele": [entrée, sortie, lecture cache, écriture cache]}` en USD par million de tokens (nom insensible à la casse).

## Structure

| Chemin | Rôle |
| --- | --- |
| `Sources/Ember/Providers/` | lecteurs par agent + découverte automatique |
| `Sources/Ember/Quota.swift` | modèle et calculs de quota (rythme, projection) |
| `Sources/Ember/QuotaViews.swift` | courbes, cartes, infobulles |
| `Sources/Ember/Screens.swift` | popover, tableau de bord, pages |
| `Sources/Ember/Store.swift` | état, rafraîchissement, alertes |
| `Sources/Ember/Resources/pricing.json` | prix des modèles (USD / million de tokens) |
| `Sources/Ember/Resources/pricing-fallbacks.json` | prix de secours et familles de modèles |
| `Sources/Ember/Updater.swift` | mise à jour intégrée (semver, SHA-256, retour arrière) |
| `Sources/Ember/Debug.swift` | `--dump` et `--snapshot` |
| `Tests/EmberTests/` | tests swift-testing |

## Licence et crédits

Voir [NOTICE.md](NOTICE.md) pour l'attribution des données de prix.
