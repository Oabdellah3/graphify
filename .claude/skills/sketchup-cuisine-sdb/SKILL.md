---
name: sketchup-cuisine-sdb
description: Conception et modélisation 3D de cuisines et de salles de bain dans SketchUp, via le connecteur Trimble SketchUp (build_model / save_model). À utiliser dès que l'utilisateur parle de cuisine, salle de bain, salle d'eau, meubles de cuisine, caissons, plan de travail, îlot, évier, plaque, hotte, frigo, colonne, meuble vasque, lavabo, douche, baignoire, WC, sèche-serviettes, implantation, agencement ou aménagement d'une pièce d'eau — même s'il ne dit ni "SketchUp" ni "3D", même pour un simple plan, une variante ("et si on mettait l'évier sous la fenêtre ?") ou une question de cotes ("à quelle hauteur le plan de travail ?"). Fournit les cotes standard (hauteurs, profondeurs, dégagements), une boîte à outils Python testée (pièce avec portes et fenêtres, lignes de meubles, îlot, sanitaires) et la finition (style, caméra, fichier .skp téléchargeable). Also use for any kitchen or bathroom design / layout / 3D model request in English.
---

# Cuisines et salles de bain dans SketchUp

Cette skill transforme un brief ("ma cuisine fait 3,60 × 3 m, fenêtre au fond, je veux un L avec
l'évier sous la fenêtre") en un modèle SketchUp propre, coté en centimètres, livré en `.skp` avec une
vue 3D lisible. Elle s'appuie sur le connecteur **Trimble SketchUp** (outils `list_skills`,
`read_skill`, `build_model`, `save_model`) et sur sa propre boîte à outils Python
(`references/toolkit.md`), validée en conditions réelles (voir `references/exemples.md`).

Le résultat attendu, à chaque fois :

1. un **plan d'implantation** écrit (liste des modules avec largeurs, cotes en cm, hypothèses) ;
2. le **modèle 3D** construit par étapes, vérifié dans les `model_snapshot` ;
3. un **fichier .skp** sauvegardé avec style et caméra, et une réponse qui récapitule la
   nomenclature, les cotes clés et ce qui peut être ajusté.

---

## Étape 0 — Préparer le connecteur (obligatoire, une fois par conversation)

Le connecteur refuse de produire du code fiable sans ses skills de base. Avant le premier
`build_model` :

1. `list_skills` (sans argument).
2. `read_skill` sur **chaque** skill `baseline` : `sketchup-sdk`, `sketchup-clean-geometry`,
   `sketchup-components`, `sketchup-assembly-structure`, `sketchup-camera`, `sketchup-styles`,
   `sketchup-solid-cleanup`. Les skills contextuelles (`sketchup-rounded-corners`,
   `sketchup-part-boundaries`, `sketchup-scenes`) ne sont utiles que si l'utilisateur demande des
   arrondis spécifiques, une assemblage de charpente, ou plusieurs scènes/variantes dans un fichier.
3. Lire `references/toolkit.md` de **cette** skill : c'est le code que tu colleras en tête de chaque
   appel `build_model`.

Règles du bac à sable à garder en tête (détail dans `sketchup-sdk`) : aucun `import`, unités en
**pouces** (le toolkit convertit depuis les cm avec `cm()`), l'état Python **ne persiste pas** entre
appels (recoller le toolkit à chaque fois), `clean: true` sur le premier `build_model` d'une
nouvelle tâche, et `build_model` n'est pas transactionnel (après une erreur, inspecter le snapshot
avant de continuer).

Si le connecteur Trimble SketchUp n'est pas disponible dans la session, voir
`references/sans-connecteur.md` (script Ruby pour la console de SketchUp Desktop).

---

## Étape 1 — Le brief

Récupère ou déduis ces informations. Ne bloque pas la tâche pour des détails : quand une donnée
manque, prends la valeur par défaut ci-dessous, **dis-le explicitement** dans la réponse, et
construis. Ne pose une question avant de construire que si la réponse change radicalement le modèle
(dimensions de la pièce totalement inconnues et aucun indice, ou demande contradictoire).

| Donnée                                   | Par défaut si absente                                  |
| ---------------------------------------- | ------------------------------------------------------ |
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
  (`("filler", n)`) ou en changeant un module (largeurs standard : 30, 40, 45, 50, 60, 80, 90, 100,
  120 cm).
- **Dans un angle, une seule ligne va jusqu'au mur** ; l'autre s'arrête à 65 cm du coin (la
  profondeur du plan) — donc `start=65` si l'angle est à sa gauche, ou longueur − 65 s'il est à sa
  droite. Le plan de travail de la ligne qui possède l'angle couvre le coin.
- **Cuisine, triangle d'activité** : évier, plaque et frigo sur deux ou trois lignes, aucune
  distance > 2,5 m ; lave-vaisselle collé à l'évier ; plaque à ≥ 30 cm d'un mur latéral et jamais
  dans un angle ; hotte centrée sur la plaque ; colonnes (frigo, four) en bout de ligne, jamais au
  milieu d'un plan ; évier sous la fenêtre si l'allège est ≥ 100 cm ; pas de meuble haut devant une
  fenêtre ; 90 cm minimum de passage (110–120 autour d'un îlot).
- **Salle de bain, dégagements** : 60 cm devant le WC et 35–40 cm de part et d'autre de son axe
  (donc un emplacement de 70–80 cm de large), 70 cm devant le lavabo, 60 cm devant la douche ou la
  baignoire ; la porte ne doit pas balayer le WC ; le lave-linge (60 × 60) a besoin de 60 cm
  devant ; la douche se met dans un angle (deux murs porteurs des parois) ; baignoire contre le mur
  le plus long.
- **Fenêtres** : rien d'opaque devant (ni colonne, ni meuble haut, ni miroir) ; un plan de travail
  sous fenêtre impose une allège ≥ 100 cm.
- **Chiralité** : "à gauche en entrant" se lit depuis la porte. Pose explicitement l'orientation dans
  la réponse ("mur du fond = face à la porte") pour que l'utilisateur puisse te corriger.

Garde le plan en tête sous forme d'arbre d'assemblage (`sketchup-assembly-structure`) : la pièce,
puis une ligne de meubles par mur, l'îlot, chaque sanitaire — chacun est un groupe parent qui
contient ses parties, pour que l'Outliner de SketchUp reste lisible.

---

## Étape 3 — Construire avec le toolkit

Chaque appel `build_model` = toolkit collé en tête + quelques lignes de scénario. Découpe en appels
courts (pièce, puis chaque ligne, puis finition) : un échec ne ruine alors qu'une étape, et chaque
`model_snapshot` te permet de vérifier les boîtes englobantes (en pouces : 1 cm = 0,3937 in).

### Conventions du toolkit

- Pièce : origine au coin **avant-gauche intérieur**, `W` selon +X, `D` selon +Y, sol en Z = 0.
  Murs `back` (y = D), `front` (y = 0), `left` (x = 0), `right` (x = W).
- Par défaut seuls `back` et `left` sont construits en pleine hauteur ; `front` et `right` sont des
  murets de 10 cm (maquette ouverte, lisible en vue 3/4). Choisis `full=` selon les murs qui portent
  des meubles : `("back", "left")`, `("back", "right")` ou `("back", "left", "right")` pour un U. Une
  porte sur un muret est quand même représentée (le muret est interrompu).
- Tout objet se place avec `pos = on_wall(wall, a, W, D)` : `a` = distance en cm entre le coin gauche
  du mur (vu depuis la pièce) et le bord gauche de l'objet. Plus besoin de calculer les rotations.
- Les ouvertures de `room()` se donnent par mur : `("door", a0, a1, z0, z1)` ou `("window", ...)`,
  avec `a` mesuré le long du mur depuis le coin d'origine (x = 0 pour back/front, y = 0 pour
  left/right), hauteurs en cm (porte : z0 = 1, z1 = 210 ; fenêtre : allège, allège + hauteur).

### Scénario type : cuisine en L (testé, voir `references/exemples.md`)

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

### Scénario type : salle de bain (testé)

```python
W, D, H = 300, 220, 250
room(model, W, D, H, full=("back", "left"),
     openings={"left": [("window", 40, 130, 120, 200)], "front": [("door", 20, 103, 1, 210)]})
bathtub(model, "Baignoire", on_wall("left", 0, W, D))
toilet(model, "WC", on_wall("back", 90, W, D))
vanity(model, "Meuble_Vasque", on_wall("back", 140, W, D), w=60)
shower(model, "Douche", on_wall("back", 210, W, D), W=90, D=90, paroi="left")
radiator(model, "Seche_Serviettes", on_wall("left", 175, W, D), w=40)
washer(model, "Lave_Linge", on_wall("front", 0, W, D))
style_interieur(True)
cam = camera_maquette(bb_room(W, D, H), azimut=45)
```

### Fonctions disponibles (toutes en cm, détail et code dans `references/toolkit.md`)

| Fonction | Rôle | Paramètres utiles |
| --- | --- | --- |
| `room(parent, W, D, H, full, openings, t, sol, mur)` | pièce : sol, murs pleins avec portes/fenêtres vitrées, murets | `sol="sol_parquet"/"sol_carrelage"` |
| `on_wall(wall, a, W, D)` | triplet de placement contre un mur | `wall` ∈ back/left/right/front |
| `kitchen_run(parent, nom, pos, modules, hauts, start, facade, plan, H)` | ligne de meubles bas (+ hauts), plan de travail percé pour l'évier, crédence, poignées | modules : `door, drawers, sink, hob, oven, dishwasher, fridge, tall, filler` ; hauts : `door, hood, open` |
| `island(parent, nom, pos, L, P, hob)` | îlot central | `pos=(x, y, 0)` = coin arrière-gauche, s'étend vers −Y |
| `vanity(parent, nom, pos, w, d, h_plan, miroir)` | meuble vasque suspendu, vasque encastrée, mitigeur, miroir | `w=60…140` (double vasque : `w=120`, deux appels `tap`) |
| `toilet(parent, nom, pos)` | WC à poser (40 × 66) | — |
| `shower(parent, nom, pos, W, D, paroi, porte)` | douche d'angle : receveur, paroi, porte vitrée, colonne | `paroi="right"/"left"` = côté libre |
| `bathtub(parent, nom, pos, L, W, H)` | baignoire droite, grand côté contre le mur | 170 × 75 par défaut |
| `radiator`, `washer`, `shelf` | sèche-serviettes, lave-linge, tablette | — |
| `box`, `hollow`, `slab`, `rounded` | primitives (boîte, cuve ouverte, plan percé, boîte arrondie) pour un objet non prévu | `yw` = distance au mur |
| `KIT` | cotes de la cuisine (socle, caisson, plan, hauts, colonnes) | copier et modifier pour un plan à 92 cm, etc. |
| `style_interieur(ombres)` | préréglage "Interior Room" | — |
| `camera_maquette(bb, azimut)` / `camera_interieure(bb, coin)` | vue 3/4 plongeante / vue à hauteur d'œil | `bb = bb_room(W, D, H)` |

Pour un objet qui n'existe pas dans le toolkit (lave-vaisselle apparent, machine à laver sous plan,
WC suspendu, vasque à poser, niche…), compose-le avec `box` / `hollow` / `rounded` dans un
`assembly(parent, nom, pos)` — c'est ce que font déjà `toilet` ou `vanity`. Reste sur des boîtes et
des cuves : à cette échelle, c'est ce qui se lit le mieux et ce que le SDK produit le plus
proprement.

### Vérifications dans le snapshot

- La boîte englobante d'une ligne contre le mur `back` doit avoir `max.y ≈ D` (en pouces), et une
  profondeur ≈ 25,6 in (65 cm). Une ligne qui "sort" de la pièce = mauvais `on_wall`.
- Deux groupes dont les boîtes se chevauchent (hors sanitaires volontairement encastrés) = deux
  objets au même endroit : reprendre les abscisses `a`.
- `Mur_*` avec ouvertures : 6 faces + 4 par ouverture. Un mur à 6 faces alors qu'une fenêtre était
  prévue = ouverture ignorée (mur en muret, ou `a` hors du mur).
- `materials` doit lister chaque matériau une seule fois.

---

## Étape 4 — Finir et livrer

1. Dans le dernier `build_model` : `style_interieur(True)` puis `camera_maquette(bb_room(W, D, H),
   azimut)` — azimut 45 pour des meubles sur `back`+`left`, 135 pour `back`+`right`, 90 (de face)
   pour un U. Ajoute `camera_interieure` à la place si l'utilisateur veut "se projeter dans la
   pièce". Le retour de la fonction (`persp: True`, `fov`) confirme que la caméra est posée.
2. `save_model` avec un nom parlant : `cuisine_L_360x300.skp`, `sdb_240x200_v2.skp`. Garde la
   session ouverte (`keep_session` par défaut) tant que l'utilisateur peut demander une variante.
3. Réponds en français, en centimètres, avec :
   - le lien de téléchargement du `.skp` et, si disponible, la vignette ;
   - la **nomenclature** par mur (tableau : position, module, largeur) et les cotes clés (hauteur de
     plan, hauteur sous meubles hauts, dégagements obtenus) ;
   - les **hypothèses** prises (dimensions par défaut, position de porte, etc.) ;
   - deux ou trois **ajustements possibles** (variante îlot, évier sous fenêtre, double vasque…).

Pour une variante demandée ensuite ("mets le frigo de l'autre côté"), ne repars pas de zéro :
reconstruis seulement la ligne concernée (`clean: false`), ou utilise `clean: true` si le changement
touche la pièce elle-même. Pour présenter deux options dans un même fichier, lis la skill
`sketchup-scenes` du connecteur (calques + scènes).

---

## Pièges connus

- Oublier de recoller le toolkit → `NameError` sur `room`/`kitchen_run`. Le toolkit est long mais
  c'est le prix de la fiabilité ; ne le résume pas.
- Donner des cm aux fonctions `*_geom` ou aux caméras (elles attendent des pouces) — `bb_room` et
  les fonctions métier gèrent la conversion.
- Lister des modules de droite à gauche. Toujours de gauche à droite **vu depuis la pièce**.
- Placer un meuble haut ou une colonne devant la fenêtre ; placer la plaque dans l'angle.
- Une porte sur un mur plein : `z0` doit être ≥ 0,5 cm (le toolkit l'impose) pour rester une
  découpe propre (boucle interne) ; le seuil d'1 cm est invisible.
- Les trous d'un plan (`slab`) ne doivent pas toucher le bord du plan ; `kitchen_run` centre
  automatiquement la cuve avec 5 cm de marge.
- Les matériaux intégrés de SketchUp (`.skm`) n'existent pas dans le bac à sable : la palette
  `PAL` du toolkit est en couleurs unies ; ajoute-y une entrée plutôt que de chercher une texture.
- `save_model` est limité en nombre de sauvegardes par session : sauvegarde aux étapes utiles
  (fin de construction, après chaque variante validée), pas après chaque ligne.
