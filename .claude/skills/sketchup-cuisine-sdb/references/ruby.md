# Livraison en script Ruby (SketchUp Desktop 2017 → 2019 et suivants)

`scripts/cuisine_sdb.rb` est le portage Ruby du toolkit Python : mêmes fonctions, mêmes
conventions (cm, `on_wall`, `yw`, modules de gauche à droite), même palette `PAL` et mêmes cotes
`KIT`. Il construit le modèle **nativement** dans la version de SketchUp de l'utilisateur, donc
sans aucun problème de format de fichier — c'est la voie à prendre pour SketchUp 2019 (et toute
version antérieure à 2021), puisque le `.skp` du connecteur Trimble est au format 2021+.

## Produire le fichier à livrer

1. Écrire le scénario (quelques lignes, voir ci-dessous) dans un fichier temporaire.
2. Concaténer toolkit + scénario en un seul fichier autonome, nommé d'après le projet :

   ```bash
   cat .claude/skills/sketchup-cuisine-sdb/scripts/cuisine_sdb.rb scenario.rb > cuisine_L_360x300.rb
   ruby -c cuisine_L_360x300.rb          # vérification de syntaxe si Ruby est installé
   ```

3. Le vérifier avec le simulateur : copier `scripts/smoke_test.rb` n'est pas nécessaire, il suffit
   de lancer `ruby scripts/smoke_test.rb` pour valider le toolkit, puis, pour un scénario précis,
   l'exécuter de la même façon (le simulateur accepte n'importe quel scénario : remplacer la
   ligne `load ... cuisine_sdb.rb` par le chemin du fichier livré).
4. Déposer le fichier dans le répertoire de travail (ou l'envoyer à l'utilisateur) et donner la
   marche à suivre :

   > Dans SketchUp 2019 : **Fenêtre → Console Ruby**, puis taper
   > `load "C:/Users/moi/Documents/cuisine_L_360x300.rb"` (barres obliques `/`, même sous Windows)
   > et Entrée. Le modèle se construit en une seconde dans le fichier ouvert ; un seul Ctrl+Z
   > l'annule entièrement. Enregistrer ensuite normalement (Fichier → Enregistrer) : le `.skp`
   > est au format 2019.

Toujours partir d'un **nouveau fichier SketchUp vide** (modèle en centimètres ou en mètres, peu
importe : le script travaille en pouces internes) pour éviter de mélanger avec un modèle existant.

## Scénario type

```ruby
run("Cuisine en L") do
  w, d, h = 360, 300, 250
  room(model, w, d, h, full: ["back", "left"],
       openings: { "back" => [["window", 200, 300, 110, 210]], "front" => [["door", 250, 333, 1, 210]] },
       sol: "sol_parquet")
  kitchen_run(model, "Ligne_Fond", on_wall("back", 0, w, d),
              [[:door, 60], [:hob, 60], [:drawers, 60], [:sink, 80], [:dishwasher, 60], [:door, 40]],
              hauts: [[:door, 60], [:hood, 60], [:door, 80], [:open, 100], [:door, 60]], h_room: h)
  kitchen_run(model, "Ligne_Gauche", on_wall("left", 0, w, d),
              [[:fridge, 60], [:tall, 60], [:oven, 60], [:drawers, 55]], facade: "facade_chene", h_room: h)
  style_interieur(true)
  camera_maquette(bb_room(w, d, h), azimut: 45)
end
```

`run` enveloppe tout dans une opération unique (annulable d'un coup) et annule tout si une ligne
échoue. Les deux exemples complets, prêts à charger, sont `scripts/exemple_cuisine_L.rb` et
`scripts/exemple_salle_de_bain.rb`.

## Différences avec le toolkit Python

| Python (connecteur)                          | Ruby (SketchUp Desktop)                                   |
| -------------------------------------------- | --------------------------------------------------------- |
| `kitchen_run(model, nom, pos, modules, hauts=..., H=250)` | `kitchen_run(model, nom, pos, modules, hauts: ..., h_room: 250)` — arguments nommés |
| `("door", 60)`                               | `[:door, 60]` (symboles ou chaînes, au choix)             |
| `island(..., L=200, P=100)`                  | `island(..., l: 200, p: 100)` (minuscules : `L` serait une constante Ruby) |
| `vanity(..., w=80)` / `shower(..., W=90, D=90)` | `vanity(..., w: 80)` / `shower(..., w: 90, d: 90)`      |
| `room(..., full=("back","left"), openings={...})` | `room(..., full: ["back","left"], openings: {...})`  |
| `K = {**KIT, "caisson_h": 78}`               | `k = KIT.merge(caisson_h: 78)` puis `kitchen_run(..., k: k)` |
| `result = {...}` pour le snapshot            | rien : regarder le modèle dans SketchUp (Outliner)        |
| `save_model`                                 | `save_as("C:/.../fichier.skp")` ou Fichier → Enregistrer  |
| style avec occlusion ambiante                | pas d'AO avant SketchUp 2023 : le style se limite aux ombres et profils |

## Mécanique SketchUp utilisée (pour composer un objet absent du toolkit)

- `box_geom(g, w, d, h)` : face au sol + `pushpull(h)`. Une face dessinée à z = 0 est orientée
  vers le bas par SketchUp, d'où le `reverse! if normal.z < 0` avant chaque `pushpull`.
- `hollow_geom` : boîte, puis rectangle intérieur dessiné sur la face du dessus (il devient une
  sous-face) et `pushpull(-profondeur)`.
- `slab_geom` / `wall_geom` : même principe, le `pushpull` traverse toute l'épaisseur et SketchUp
  perce le trou (ouverture de porte, fenêtre, découpe d'évier).
- `rounded_geom` : polygone à coins arrondis + `pushpull`, puis adoucissement des arêtes
  verticales dont aucune face voisine n'est alignée sur un axe.
- Les groupes sont créés dans `parent.entities`, leur géométrie est construite à l'origine locale
  et la position est portée par `transformation=` (translation × rotation) : exactement la
  hiérarchie attendue dans l'Outliner.
- Les poignées sont des instances d'une définition de composant `Poignee` partagée.

## Contraintes Ruby de SketchUp 2019

Ruby 2.5 : pas de `&.`-chaînes exotiques, pas de paramètres numérotés (`_1`), pas de pattern
matching, pas de `endless methods`. Le toolkit n'utilise rien de plus récent que Ruby 2.3.
Le simulateur `scripts/smoke_test.rb` tourne avec n'importe quel Ruby ≥ 2.5.
