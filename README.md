# RadarMap (iOS + CarPlay)

Carte 3D des radars fixes français (≈3 300), avec filtres par type.  
Données : data.gouv.fr « Liste des radars fixes en France » (Licence Ouverte 2.0), embarquées dans `Resources/radars.csv`.

---

## Installer sur iPhone depuis Windows (sans Mac)

### Étape 1 — Récupérer le .ipa (GitHub Actions)

1. Push ce dépôt sur GitHub (compte gratuit suffit)
2. Va dans **Actions** > dernier build > **Artifacts** > télécharge `RadarMap-ipa`
3. Dézippe → tu obtiens `RadarMap-unsigned.ipa`

> Le build tourne sur un runner macOS gratuit fourni par GitHub (~5 min).

### Étape 2 — Installer sur ton iPhone

**Option A : Sideloadly** (le plus simple)
1. Télécharge [Sideloadly](https://sideloadly.io) (Windows)
2. Connecte ton iPhone en USB, fais confiance à l'ordinateur
3. Glisse `RadarMap-unsigned.ipa` dans Sideloadly
4. Connecte-toi avec ton Apple ID gratuit
5. Clique **Install**
6. Sur iPhone : Réglages > Général > VPN et gestion d'app > ton Apple ID > Faire confiance

> Limite compte gratuit : l'app expire au bout de **7 jours**, relance Sideloadly pour renouveler.

**Option B : AltStore** (renouvellement semi-automatique)
1. Installe [AltServer](https://altstore.io) sur Windows
2. Installe AltStore sur ton iPhone via AltServer
3. Ouvre AltStore > **My Apps** > **+** > sélectionne le `.ipa`

> AltServer doit tourner en arrière-plan sur ton PC pour le renouvellement automatique toutes les 7 jours (via Wi-Fi).

---

## CarPlay

Le code CarPlay est intégré (liste des radars proches + filtres sur l'écran de la voiture).

- **Compte gratuit** : CarPlay fonctionne en build de développement via Xcode sur Mac.  
  La CI retire automatiquement l'entitlement pour les builds GitHub Actions — l'app tourne sur iPhone uniquement dans ce cas.
- **Activer CarPlay** : nécessite un compte Apple Developer payant (99€/an) + demande sur [developer.apple.com/contact/carplay](https://developer.apple.com/contact/carplay/).  
  Une fois accordé : ajouter la ligne `com.apple.developer.carplay-driving-task: true` dans `project.yml`, reconfigurer la signature.

---

## Générer le projet (sur un Mac)

```bash
brew install xcodegen
cd RadarMap && xcodegen
open RadarMap.xcodeproj
```

Renseigne `DEVELOPMENT_TEAM` et `PRODUCT_BUNDLE_IDENTIFIER` dans `project.yml` (ou dans Xcode > Signing).

---

## Produire le .ipa manuellement (sur Mac)

```bash
xcodebuild -project RadarMap.xcodeproj -scheme RadarMap -configuration Release \
  -archivePath build/RadarMap.xcarchive archive
xcodebuild -exportArchive -archivePath build/RadarMap.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/ipa
```
