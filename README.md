# Ember 🔥

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
- **Popover** dans la barre des menus, avec onglets par agent.
- **Alertes** : budget mensuel (80 % / 100 %) et seuil de quota restant, via notifications macOS.
- **Export CSV**, prix des modèles modifiables (`pricing-overrides.json`), lancement à l'ouverture de session.

Tout est calculé sur ton Mac. Aucune donnée n'est envoyée, hormis l'appel Anthropic du quota Claude en direct (désactivable dans les Réglages).

## Prérequis

- macOS 14 ou plus récent
- Toolchain Swift (Xcode ou Command Line Tools)

## Compiler et lancer

```bash
./scripts/build_app.sh
open "$PWD/build/Ember.app"
```

Le script compile en release et signe l'app en ad-hoc. Au premier lancement, macOS peut demander l'accès au trousseau (quota Claude) et aux notifications.

Options de débogage : `Ember --dump` (affiche les données lues) et `Ember --snapshot <dossier>` (rend des PNG des vues).

## Structure

| Chemin | Rôle |
| --- | --- |
| `Sources/Ember/Providers/` | lecteurs par agent + découverte automatique |
| `Sources/Ember/Quota.swift` | modèle et calculs de quota (rythme, projection) |
| `Sources/Ember/QuotaViews.swift` | courbes, cartes, infobulles |
| `Sources/Ember/Screens.swift` | popover, tableau de bord, pages |
| `Sources/Ember/Store.swift` | état, rafraîchissement, alertes |
| `Sources/Ember/Resources/pricing.json` | prix des modèles (USD / million de tokens) |

## Licence et crédits

Voir [NOTICE.md](NOTICE.md) pour l'attribution des données de prix.
