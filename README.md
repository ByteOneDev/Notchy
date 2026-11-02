<p align="center"><img src="docs/logo.png" width="128" alt="Notchy"></p>

# Notchy

Une app de notch native pour macOS (Swift + SwiftUI), dans l'esprit d'Alcove et NotchNook Pro.

## Panneaux

Sous le notch ouvert, une barre flottante donne accès aux panneaux : **Nook** (vue d'ensemble), **Musique**, **Calendrier**, **Étagère**, **Prompteur**, **Agents IA**, **Minuteur** et **Miroir**. Chacun s'active ou se désactive dans les réglages.

- **Musique** : tous les sons de l'ordinateur, contrôlables depuis le notch. Les applis et sites listés (Spotify, YouTube, Deezer…) s'affichent en entier (pochette, paroles synchronisées, visualiseur) ; les autres seulement avec leur nom et leur logo. Un contour lumineux de la couleur de la pochette entoure le notch pendant la lecture. Choix de la sortie audio.
- **Calendrier** : agenda des prochains jours et grille du mois, bouton « Rejoindre » pour Meet/Zoom/Teams, glisser à deux doigts pour changer de jour.
- **Étagère** : dépose des fichiers sur le notch, **AirDrop** et **conversion** (PNG/JPEG/HEIC/TIFF, MP4/MOV, M4A).
- **Prompteur** : le texte défile sous la caméra, à vitesse fixe ou **en suivant ta voix** (reconnaissance vocale sur le Mac).
- **Agents IA** : ce que fait Claude Code (étapes, messages), **accepter ou refuser ses demandes d'autorisation** depuis le notch, limites d'usage (5 h / semaine) avec **alerte à 80 %**. Codex en partie, et tout autre outil via `POST http://127.0.0.1:47812/agent`.
- **Minuteur et pomodoro**, **miroir** (qui s'ouvre tout seul avant un appel vidéo), **météo**.

## Live activities

Charge (avec temps restant) et batterie faible, écouteurs Bluetooth, batterie faible des souris, claviers et AirPods, écran externe, mode Concentration, alerte pluie, réunion imminente, caméra et micro, verrouillage majuscules, conversion, agents IA. Plus les **HUD volume et luminosité** et l'affichage sur l'**écran verrouillé**.

## Réglages

Toutes les fonctions s'activent ou se désactivent depuis **Réglages → Fonctionnalités**. 4 styles (noir, semi-transparent, transparent, **Liquid Glass**), largeur et hauteur du notch, raccourcis clavier globaux, sons discrets et retour haptique, masquage dans les captures et partages d'écran, notch caché en plein écran, interface en français (par défaut) et en anglais.

## Compiler

Prérequis : macOS 15+, Xcode (licence acceptée).

```bash
scripts/build.sh          # → build/Notchy.app
open build/Notchy.app
```

L'app est signée avec le certificat local « Todoux Developer » s'il existe (sinon ad hoc), ce qui garde les autorisations macOS d'une mise à jour à l'autre. Le logo se régénère avec `swift scripts/make-icon.swift`.

Publier une version : mettre à jour `VERSION`, puis `scripts/release.sh "notes"`.

## Installer

Télécharger **la dernière version** : [Notchy (DMG)](https://github.com/ByteOneDev/Notchy/releases/latest). Ouvrir le DMG et glisser Notchy dans Applications.

Ensuite, Notchy se met à jour tout seul (Réglages → À propos).

L'app n'est pas notarisée par Apple. Après l'avoir copiée dans Applications :

```bash
xattr -dr com.apple.quarantine /Applications/Notchy.app
```
