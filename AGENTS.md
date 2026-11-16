# Sandia — consignes pour les agents

## Après chaque modification de code (test local)

Sans demander d'autorisation, pour que Jonathan puisse tester tout de suite :

1. Lancer les tests : `swift test`.
2. Construire l'app : `xcodebuild -project Sandia.xcodeproj -scheme Sandia -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`.
3. Quitter Sandia s'il tourne (`pkill -x Sandia`), ce qui restaure le gamma de l'écran.
4. Remplacer `/Applications/Sandia.app` par l'app construite (`ditto <build>/Sandia.app /Applications/Sandia.app`), puis la relancer avec `open /Applications/Sandia.app`.
5. Dire à Jonathan que l'app est remplacée, avec la version et l'heure.

Le remplacement de l'app dans `/Applications` est autorisé en permanence ; ne pas redemander. Aucune notarisation, aucun DMG, aucune release pour un simple test.

## Livraison (release)

Seulement sur demande explicite de Jonathan :

- `./scripts/release.sh` : build Release, signature Developer ID, notarisation via `asc`, agrafage et DMG dans `dist/`.
- Publier le DMG en release GitHub.
- Mettre à jour la version (`project.yml`) et les deux README si nécessaire.

## Unités

- L'interface parle en **réduction du bleu** : 0 % = écran neutre (6 504 K, D65), 100 % = filtre maximal (1 000 K). Le curseur va de 100 % à gauche à 0 % à droite.
- Le kelvin reste l'unité interne (`Preferences`, `Schedule`, `ColorTemperature`), borné à 1 000–6 504 K pour ce filtre. La fraction 0–1 de `BlueLightReduction` est l'unité du noyau ; les vues affichent des pourcentages.
- C'est la force du filtre logiciel le long de la plage chaude (échelle mired), pas une mesure de la quantité de bleu retirée ni de la lumière.

## Règles

- Hors remplacement dans `/Applications`, ne pas lancer l'app pour des essais automatisés : elle modifie le gamma de l'écran de Jonathan.
- Tests automatisés toujours en headless.
- Aucun secret manipulé : la notarisation passe par le profil `asc` déjà présent.
