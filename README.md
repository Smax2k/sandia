# Dvsk

Application personnelle de barre des menus pour macOS : elle réchauffe l'écran le soir en agissant sur les tables gamma, comme f.lux. Elle remplace f.lux sur nos Mac.

## Origine

Fork personnel de [fabianwgl/dvsk](https://github.com/fabianwgl/dvsk) (MIT), repris au commit `86f149a` après relecture complète du code : aucune dépendance externe, aucun appel réseau, aucun sous-processus, la seule API privée étant `CoreBrightness` pour le rétroéclairage clavier.

**On ne suit pas les mises à jour de l'amont.** Un mainteneur peut modifier son dépôt à tout moment ; une mise à jour automatique importerait du code non relu. Si une correction amont nous intéresse, elle est relue et réappliquée à la main.

Le fichier `LICENSE` d'origine est conservé : le code dérive d'un projet MIT.

## Construire

Le projet Xcode est généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen) depuis `project.yml`, et le `.xcodeproj` produit est versionné : Xcode s'ouvre directement, sans rien installer.

```sh
open Dvsk.xcodeproj      # puis ⌘R
```

Après une régénération (`brew install xcodegen`) :

```sh
xcodegen generate
xcodebuild -project Dvsk.xcodeproj -scheme Dvsk -configuration Release build
```

Tests (49) :

```sh
swift test
xcodebuild test -project Dvsk.xcodeproj -scheme Dvsk -destination 'platform=macOS'
```

## Installer

```sh
xcodebuild -project Dvsk.xcodeproj -scheme Dvsk -configuration Release -derivedDataPath .build/xcode build
ditto .build/xcode/Build/Products/Release/Dvsk.app /Applications/Dvsk.app
open /Applications/Dvsk.app
```

L'app vit dans `/Applications` : c'est de là que « Lancer à l'ouverture » fonctionne. Depuis un dossier de build, la ligne est volontairement grisée.

Rien n'est publié, rien n'est distribué. Il n'y a donc ni Homebrew, ni DMG de release.

## Signature

Développement local : certificat **Apple Development** de la team, signature automatique par Xcode.

Installation sur un autre Mac sans avertissement de Gatekeeper : il faut un certificat **Developer ID Application** puis une notarisation.

```sh
xcrun notarytool store-credentials dvsk-notary --apple-id … --team-id 5PC4RUY4PJ
xcrun notarytool submit Dvsk.zip --keychain-profile dvsk-notary --wait
xcrun stapler staple Dvsk.app
```

Faute de Developer ID, un `.app` copié par `scp`/`rsync` ou téléchargé par `curl` s'ouvre quand même : ces voies ne posent pas l'attribut de quarantaine. Un fichier reçu par AirDrop ou récupéré dans un navigateur sera, lui, bloqué.

## Organisation

- `Sources/DvskCore/` — logique pure, sans AppKit : couleur, horaire, calcul solaire. C'est là que vont les tests.
- `Sources/Dvsk/` — interface : icône de barre des menus, popover, gamma, rétroéclairage.
- `Tests/DvskCoreTests/` — tests unitaires de `DvskCore`.
- `project.yml` — source du projet Xcode. Ne pas éditer `Dvsk.xcodeproj` à la main : il est régénéré.

## Si l'écran reste teinté

Après un plantage ou un `kill -9`, les couleurs peuvent rester chaudes :

```sh
/Applications/Dvsk.app/Contents/MacOS/Dvsk --reset
```

## Limites connues

- Ne pas faire tourner f.lux en même temps : les deux réécrivent les mêmes tables gamma et la teinte clignote.
- Désactiver Night Shift et True Tone (Réglages Système → Écrans), qui se cumulent.
- Le rétroéclairage clavier passe par une API privée (`CoreBrightness`) : chaque sélecteur est testé et la section disparaît si macOS ne l'expose plus.
