# Notchy

Une app de notch native pour macOS (Swift + SwiftUI), dans l'esprit d'Alcove et NotchNook.

## Fonctions

- **Musique** : morceau en cours, pochette, visualiseur, paroles synchronisées (LRCLIB), contrôles et barre de lecture. Seules les applis audio et les sites autorisés (YouTube, Spotify web, Deezer, SoundCloud…) s'affichent ; les sites de niche sont ignorés. Les deux listes se modifient dans les réglages.
- **Calendrier** : bande des jours et agenda du jour, bouton « Rejoindre » pour Meet/Zoom/Teams, alerte 5 min avant une réunion.
- **Live activities** : charge et batterie faible, écouteurs et appareils Bluetooth (batterie des AirPods), verrouillage majuscules, caméra et micro utilisés, conversion de fichiers.
- **HUD volume et luminosité** qui remplacent ceux de macOS.
- **Écran verrouillé** : le notch reste visible avec la musique.
- **Gestes** : survol pour ouvrir, glisser vers le bas ou le haut pour ouvrir ou fermer, glisser à gauche ou à droite pour changer de morceau, retour haptique.
- **Pomodoro** et **minuteur**, **météo** (Open-Meteo), **miroir** (caméra).
- **Étagère** : glisse des fichiers sur le notch, **AirDrop** et **conversion** (images PNG/JPEG/HEIC/TIFF, vidéo MP4/MOV, audio M4A).
- 3 styles : noir, semi-transparent, transparent (Liquid Glass sur macOS 26+).
- Interface en français (par défaut) et en anglais.

## Compiler

Prérequis : macOS 15+, Xcode (licence acceptée).

```bash
scripts/build.sh          # → build/Notchy.app
open build/Notchy.app
```

L'app est signée avec le certificat local « Todoux Developer » s'il existe (sinon ad hoc), ce qui garde les autorisations macOS d'une mise à jour à l'autre.

Publier une version : mettre à jour `VERSION`, puis `scripts/release.sh "notes"`.

## Installer depuis une release

L'app n'est pas notarisée par Apple. Après l'avoir copiée dans Applications :

```bash
xattr -dr com.apple.quarantine /Applications/Notchy.app
```
