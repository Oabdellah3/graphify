---
name: sketchup-cuisine-sdb
description: Conception et modélisation 3D de cuisines et de salles de bain dans SketchUp. Livre soit un script Ruby à charger dans SketchUp Desktop (2017 → 2019 et suivants ; l'utilisateur de ce dépôt travaille sur SketchUp Pro 2019), soit un fichier .skp via le connecteur Trimble SketchUp (uniquement lisible par SketchUp 2021+ ou SketchUp Web). À utiliser dès que l'utilisateur parle de cuisine, salle de bain, salle d'eau, meubles de cuisine, caissons, plan de travail, îlot, évier, plaque, hotte, frigo, colonne, meuble vasque, lavabo, douche, baignoire, WC, sèche-serviettes, implantation, agencement ou aménagement d'une pièce d'eau — même s'il ne dit ni "SketchUp" ni "3D", même pour un simple plan, une variante ("et si on mettait l'évier sous la fenêtre ?") ou une question de cotes ("à quelle hauteur le plan de travail ?"). Fournit les cotes standard (hauteurs, profondeurs, dégagements), une boîte à outils testée (pièce avec portes et fenêtres, lignes de meubles, îlot, sanitaires) en Ruby et en Python, et la finition (style, caméra). Also use for any kitchen or bathroom design / layout / 3D model request in English.
---

# Cuisines et salles de bain dans SketchUp

Cette skill transforme un brief ("ma cuisine fait 3,60 × 3 m, fenêtre au fond, je veux un L avec
l'évier sous la fenêtre") en un modèle SketchUp propre, coté en centimètres, avec une vue 3D
lisible. Deux chemins de livraison existent, avec **les mêmes fonctions et les mêmes conventions** :

| Mode | Quand | Outil | Résultat |
| --- | --- | --- | --- |
| **A — Script Ruby** (par défaut) | SketchUp Desktop 2017 à 2020, **et en particulier SketchUp Pro 2019 qu'utilise l'utilisateur de ce dépôt** ; ou pas de connecteur dans la session | `scripts/cuisine_sdb.rb` + scénario, validé avec `scripts/smoke_test.rb` | un fichier `.rb` à charger dans Fenêtre → Console Ruby ; le modèle se construit nativement, l'utilisateur enregistre en `.skp` 2019 |
| **B — Connecteur Trimble SketchUp** | SketchUp 2021+ ou SketchUp Web, ou pour produire un **aperçu image** avant d'ouvrir SketchUp | `list_skills` / `read_skill` / `build_model` / `save_model` + `references/toolkit.md` | un `.skp` téléchargeable au format 2021+ et sa vignette |

Pourquoi ce choix compte : le connecteur enregistre avec le SDK 2026, sans option de version, et
SketchUp 2019 refuse d'ouvrir ces fichiers ("créé dans une version plus récente"). Les conversions
par 3D Warehouse ou SketchUp Web ne sont pas fiables. Demande la version de SketchUp si elle est
inconnue ; en cas de doute, livre le script Ruby (il marche partout) et propose l'aperçu par le
connecteur en bonus.

Le résultat attendu, à chaque fois :

1. un **plan d'implantation** écrit (liste des modules avec largeurs, cotes en cm, hypothèses) ;
2. le **modèle 3D** construit par étapes et vérifié (snapshot du connecteur, ou simulateur Ruby) ;
3. le **livrable** (`.rb` ou `.skp`) avec style et caméra, et une réponse qui récapitule la
   nomenclature, les cotes clés, la marche à suivre et ce qui peut être ajusté.

---

## Étape 0 — Préparer les outils

**Mode A (Ruby).** Lire `references/ruby.md` (différences de syntaxe, mécanique SketchUp, livraison)
et parcourir `scripts/cuisine_sdb.rb` pour connaître les signatures. Vérifier que `ruby` est
disponible (`ruby --version`) pour la vérification de syntaxe et le simulateur ; sinon, relire le
scénario avec soin et le dire dans la réponse.

**Mode B (connecteur).** Le connecteur refuse de produire du code fiable sans ses skills de base.
Avant le premier `build_model` : `list_skills`, puis `read_skill` sur **chaque** skill `baseline`
(`sketchup-sdk`, `sketchup-clean-geometry`, `sketchup-components`, `sketchup-assembly-structure`,
`sketchup-camera`, `sketchup-styles`, `sketchup-solid-cleanup`), puis lire `references/toolkit.md`
de cette skill : c'est le code à coller en tête de chaque appel `build_model`. Règles du bac à
sable : aucun `import`, unités en pouces (le toolkit convertit depuis les cm), l'état Python ne
persiste pas entre appels, `clean: true` sur le premier appel d'une nouvelle tâche, `build_model`
n'est pas transactionnel.

---

## Étape 1 — Le brief

Récupère ou déduis ces informations. Ne bloque pas la tâche pour des détails : quand une donnée
manque, prends la valeur par défaut ci-dessous, **dis-le explicitement** dans la réponse, et
construis. Ne pose une question avant de construire que si la réponse change radicalement le modèle
(dimensions de la pièce totalement inconnues et aucun indice, version de SketchUp inconnue alors
qu'un `.skp` est demandé, ou demande contradictoire).

| Donnée                                   | Par défaut si absente                                  |
| ---------------------------------------- | ------------------------------------------------------ |
| Version de SketchUp                      | SketchUp Pro 2019 → mode A (script Ruby)               |
| Dimensions de la pièce (L × l × H)       | cuisine 360 × 300 × 250 cm ; salle de bain 240 × 200 × 250 cm |
| Position de la porte                     | mur avant (`front`), largeur 83 cm, près d'un coin     |
| Fenêtre                                  | cuisine : mur du fond, allège 110 cm ; SdB : aucune    |
| Type d'implantation cuisine              | L si deux murs libres, sinon linéaire ; îlot si ≥ 4 m de large |
| Hauteur du plan de travail               | 90 cm (socle 10 + caisson 76 + plan 4)                  |
| Électroménager cuisine                   | frigo 60, four 60, plaque 60, hotte 60, lave-vaisselle 60, évier 80 |
| Équipement salle de bain                 | douche 90 × 90, meuble vasque 80, WC, sèche-serviettes  |
| Finitions                                | façades blanches, plan quartz clair, sol carrelage      |

Les cotes normalisées (modules, hauteurs, dégagements, ergonomie) sont dans `references/cotes.md` :
consulte-le pour toute question de dimension ou pour vérifier un agencement.

---

## Étape 2 — L'implantation sur papier (avant tout code)

Écris l'implantation sous forme de listes de modules, mur par mur, **de gauche à droite en regardant
le mur depuis la pièce**. C'est exactement le format consommé par `kitchen_run` et `on_wall`, donc
ce travail n'est jamais perdu.

```
Mur du fond (back, 360 cm) : porte 60 | plaque 60 | tiroirs 60 | évier 80 | lave-vaisselle 60 | porte 40  = 360 ✓
Mur gauche (left, 300 cm)  : frigo 60 | colonne four 60 | four 60 | tiroirs 55 = 235 = 300 − 65 (angle occupé par la ligne du fond) ✓
Hauts (fond)               : porte 60 | hotte 60 | porte 80 | vide 100 (fenêtre) | porte 60 = 360 ✓
```

Vérifie, et corrige avant de construire :

- **La somme des largeurs = longueur disponible du mur.** Absorbe l'écart avec un fileur
  (`filler`) ou en changeant un module (largeurs standard : 30, 40, 45, 50, 60, 80, 90, 100, 120).
- **Dans un angle, une seule ligne va jusqu'au mur** ; l'autre s'arrête à 65 cm du coin (la
  profondeur du plan) — donc `start: 65` si l'angle est à sa gauche, ou longueur − 65 s'il est à sa
  droite. Le plan de travail de la ligne qui possède l'angle couvre le coin.
- **Cuisine, triangle d'activité** : évier, plaque et frigo sur deux ou trois lignes, aucune
  distance > 2,5 m ; lave-vaisselle collé à l'évier ; plaque à ≥ 30 cm d'un mur latéral et jamais
  dans un angle ; hotte centrée sur la plaque ; colonnes (frigo, four) en bout de ligne, jamais au
  milieu d'un plan ; évier sous la fenêtre si l'allège est ≥ 100 cm ; pas de meuble haut devant une
  fenêtre ; 90 cm minimum de passage (110–120 autour d'un îlot).
- **Salle de bain, dégagements** : 60 cm devant le WC et 35–40 cm de part et d'autre de son axe
  (donc un emplacement de 70–80 cm de large), 70 cm devant le lavabo, 60 cm devant la douche ou la
  baignoire ; la porte ne doit pas balayer le WC ; le lave-linge (60 × 60) a besoin de 60 cm
  devant ; la douche se met dans un angle ; baignoire contre le mur le plus long.
- **Fenêtres** : rien d'opaque devant (ni colonne, ni meuble haut, ni miroir) ; un plan de travail
  sous fenêtre impose une allège ≥ 100 cm.
- **Chiralité** : "à gauche en entrant" se lit depuis la porte. Pose explicitement l'orientation dans
  la réponse ("mur du fond = face à la porte") pour que l'utilisateur puisse te corriger.

Garde le plan en tête sous forme d'arbre d'assemblage : la pièce, puis une ligne de meubles par
mur, l'îlot, chaque sanitaire — chacun est un groupe parent qui contient ses parties, pour que
l'Outliner de SketchUp reste lisible.

---

## Étape 3 — Construire

### Conventions communes aux deux modes

- Pièce : origine au coin **avant-gauche intérieur**, `W` selon +X, `D` selon +Y, sol en Z = 0.
  Murs `back` (y = D), `front` (y = 0), `left` (x = 0), `right` (x = W).
- Par défaut seuls `back` et `left` sont construits en pleine hauteur ; `front` et `right` sont des
  murets de 10 cm (maquette ouverte, lisible en vue 3/4). Choisis `full` selon les murs qui portent
  des meubles : `back + left`, `back + right`, ou les trois pour un U. Une porte sur un muret est
  quand même représentée (le muret est interrompu).
- Tout objet se place avec `pos = on_wall(wall, a, W, D)` : `a` = distance en cm entre le coin gauche
  du mur (vu depuis la pièce) et le bord gauche de l'objet. Plus besoin de calculer les rotations.
- Les ouvertures de `room` se donnent par mur : `("door", a0, a1, z0, z1)` ou `("window", ...)`,
  avec `a` mesuré le long du mur depuis le coin d'origine (x = 0 pour back/front, y = 0 pour
  left/right), hauteurs en cm (porte : z0 = 1, z1 = 210 ; fenêtre : allège, allège + hauteur).

### Mode A — scénario Ruby (testé avec le simulateur)

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

Salle de bain : `bathtub(model, "Baignoire", on_wall("left", 0, w, d))`,
`toilet(model, "WC", on_wall("back", 90, w, d))`, `vanity(model, "Meuble_Vasque", on_wall("back", 140, w, d), w: 60)`,
`shower(model, "Douche", on_wall("back", 210, w, d), w: 90, d: 90, paroi: "left")`,
`radiator(...)`, `washer(...)` — l'exemple complet est `scripts/exemple_salle_de_bain.rb`.

Puis : fichier livrable = `scripts/cuisine_sdb.rb` + scénario concaténés (`cat`), `ruby -c` dessus,
et passage dans `scripts/smoke_test.rb` (il charge le toolkit et exécute les scénarios de référence ;
pour un scénario nouveau, exécute-le de la même manière). Détails dans `references/ruby.md`.

### Mode B — scénario Python (testé sur le connecteur, voir `references/exemples.md`)

```python
W, D, H = 360, 300, 250
room(model, W, D, H, full=("back", "left"),
     openings={"back": [("window", 200, 300, 110, 210)], "front": [("door", 250, 333, 1, 210)]},
     sol="sol_parquet")
kitchen_run(model, "Ligne_Fond", on_wall("back", 0, W, D),
    [("door", 60), ("hob", 60), ("drawers", 60), ("sink", 80), ("dishwasher", 60), ("door", 40)],
    hauts=[("door", 60), ("hood", 60), ("door", 80), ("open", 100), ("door", 60)], H=H)
kitchen_run(model, "Ligne_Gauche", on_wall("left", 0, W, D),
    [("fridge", 60), ("tall", 60), ("oven", 60), ("drawers", 55)], facade="facade_chene", H=H)
style_interieur(True)
cam = camera_maquette(bb_room(W, D, H), azimut=45)
result = {"cam": cam}
```

Chaque appel `build_model` = toolkit collé en tête + quelques lignes de scénario. Découpe en appels
courts (pièce, puis chaque ligne, puis finition) et vérifie les boîtes englobantes du
`model_snapshot` (en pouces : 1 cm = 0,3937 in) : une ligne contre `back` doit avoir `max.y ≈ D`
et ≈ 25,6 in de profondeur ; un `Mur_*` avec ouverture a 6 + 4 faces par ouverture ; deux boîtes qui
se chevauchent = deux objets au même endroit ; `materials` sans doublon.

### Fonctions disponibles (toutes en cm)

| Fonction | Rôle | Paramètres utiles |
| --- | --- | --- |
| `room(parent, W, D, H, full, openings, t, sol, mur)` | pièce : sol, murs pleins avec portes/fenêtres vitrées, murets | `sol="sol_parquet"/"sol_carrelage"` |
| `on_wall(wall, a, W, D)` | triplet de placement contre un mur | `wall` ∈ back/left/right/front |
| `kitchen_run(parent, nom, pos, modules, hauts, start, facade, plan, H/h_room, K/k)` | ligne de meubles bas (+ hauts), plan percé pour l'évier, crédence, poignées | modules : `door, drawers, sink, hob, oven, dishwasher, fridge, tall, filler` ; hauts : `door, hood, open` |
| `island(parent, nom, pos, L/l, P/p, hob)` | îlot central | `pos=(x, y, 0)` = coin arrière-gauche, s'étend vers −Y |
| `vanity(parent, nom, pos, w, d, h_plan, miroir)` | meuble vasque suspendu, vasque encastrée, mitigeur, miroir | `w=60…140` (double vasque : `w=120` + deux `tap`) |
| `toilet(parent, nom, pos)` | WC à poser (40 × 66) | — |
| `shower(parent, nom, pos, W/w, D/d, paroi, porte)` | douche d'angle : receveur, paroi, porte vitrée, colonne | `paroi="right"/"left"` = côté libre |
| `bathtub(parent, nom, pos, L/l, W/w, H/h)` | baignoire droite, grand côté contre le mur | 170 × 75 par défaut |
| `radiator`, `washer`, `shelf` | sèche-serviettes, lave-linge, tablette | — |
| `box`, `hollow`, `slab`, `rounded` | primitives (boîte, cuve ouverte, plan percé, boîte arrondie) pour un objet non prévu | `yw` = distance au mur |
| `KIT` | cotes de la cuisine (socle, caisson, plan, hauts, colonnes) | copier et modifier pour un plan à 92 cm |
| `style_interieur(ombres)` | fond blanc, profils, ombres (AO en plus sur le connecteur) | — |
| `camera_maquette(bb, azimut)` / `camera_interieure(bb, coin)` | vue 3/4 plongeante / vue à hauteur d'œil | `bb = bb_room(W, D, H)` |

En Ruby les paramètres optionnels sont nommés (`w:`, `hauts:`, `h_room:`), en minuscules. Pour un
objet absent (lave-vaisselle apparent, WC suspendu, vasque à poser, niche…), compose-le avec
`box` / `hollow` / `rounded` dans un `assembly(parent, nom, pos)`, comme le font `toilet` ou
`vanity`. Reste sur des boîtes et des cuves : à cette échelle c'est ce qui se lit le mieux.

---

## Étape 4 — Finir et livrer

1. Finition dans le scénario : `style_interieur(true)` puis `camera_maquette(bb_room(W, D, H),
   azimut)` — azimut 45 pour des meubles sur `back`+`left`, 135 pour `back`+`right`, 90 (de face)
   pour un U. `camera_interieure` à la place si l'utilisateur veut "se projeter dans la pièce".
2. **Mode A** : écrire `<projet>.rb` (toolkit + scénario) dans le répertoire de travail, nom parlant
   (`cuisine_L_360x300.rb`), le vérifier (`ruby -c`, simulateur), l'envoyer à l'utilisateur, et
   donner la marche à suivre en une phrase : nouveau fichier SketchUp, Fenêtre → Console Ruby,
   `load "C:/chemin/vers/cuisine_L_360x300.rb"`, puis Fichier → Enregistrer. Un Ctrl+Z annule tout.
   **Mode B** : `save_model` avec un nom parlant, session gardée ouverte pour les variantes ; si
   l'utilisateur est sur SketchUp ≤ 2020, le dire et fournir aussi le `.rb`.
3. Réponds en français, en centimètres, avec :
   - le livrable (fichier `.rb` ou lien `.skp` + vignette) et la marche à suivre ;
   - la **nomenclature** par mur (tableau : position, module, largeur) et les cotes clés (hauteur de
     plan, hauteur sous meubles hauts, dégagements obtenus) ;
   - les **hypothèses** prises (dimensions par défaut, position de porte, version de SketchUp) ;
   - deux ou trois **ajustements possibles** (variante îlot, évier sous fenêtre, double vasque…).

Pour une variante ("mets le frigo de l'autre côté"), modifie le scénario et relivre un fichier
complet (mode A : un nouveau `load` dans un nouveau fichier vide, ou Ctrl+Z puis `load`) ; en mode
B, reconstruis seulement la ligne concernée (`clean: false`) ou tout (`clean: true`).

---

## Pièges connus

- **Format de fichier** : un `.skp` du connecteur ne s'ouvre pas dans SketchUp 2019 ; ne le
  propose jamais comme seul livrable à un utilisateur en version ≤ 2020.
- Oublier de recoller le toolkit Python → `NameError` sur `room`/`kitchen_run`. Ne le résume pas.
- Donner des cm aux fonctions `*_geom` ou aux caméras (elles attendent des pouces) — `bb_room` et
  les fonctions métier gèrent la conversion, dans les deux langages.
- Lister des modules de droite à gauche. Toujours de gauche à droite **vu depuis la pièce**.
- Placer un meuble haut ou une colonne devant la fenêtre ; placer la plaque dans l'angle.
- Ruby : `L`, `P`, `W` majuscules seraient des constantes — les paramètres sont `l:`, `p:`, `w:` ;
  charger le script dans un **fichier vide** ; chemins avec `/` dans `load`.
- Une porte sur un mur plein : `z0` ≥ 0,5 cm (imposé par le toolkit) pour rester une découpe
  propre ; le seuil d'1 cm est invisible.
- Les trous d'un plan (`slab`) ne doivent pas toucher le bord du plan ; `kitchen_run` centre la
  cuve avec 5 cm de marge.
- Pas de textures : la palette `PAL` est en couleurs unies dans les deux modes ; ajoute-y une entrée
  plutôt que de chercher un matériau `.skm`.
- `save_model` (mode B) est limité en sauvegardes par session : sauvegarde aux étapes utiles.
