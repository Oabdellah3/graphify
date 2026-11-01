# Boîte à outils Python — cuisines et salles de bain (connecteur Trimble SketchUp)

Coller **l'intégralité** du bloc ci-dessous en tête de **chaque** appel `build_model` (l'état Python
ne persiste pas d'un appel à l'autre). Toutes les fonctions "métier" (`room`, `kitchen_run`,
`vanity`, `toilet`, `shower`, `bathtub`, …) prennent des **centimètres** ; seules les fonctions
`*_geom` et les caméras travaillent en pouces (l'unité du SDK, celle du `model_snapshot`).

Conventions :

- Pièce : origine au coin intérieur avant-gauche, largeur `W` selon +X, profondeur `D` selon +Y,
  `Z=0` = dessus du sol. Mur `back` en `y = D`, `front` en `y = 0`, `left` en `x = 0`, `right` en
  `x = W`.
- Chaque ligne de meubles / chaque équipement est un groupe placé par un triplet `pos = (x, y, rot)`
  (cm, cm, degrés) : son dos est sur le mur (local `y = 0`), il s'étend **vers la pièce en local
  `−Y`**, et ses modules se succèdent en local `+X` = **de gauche à droite pour quelqu'un qui
  regarde le mur depuis la pièce**. `on_wall(wall, a, W, D)` calcule ce triplet pour un objet dont
  le bord gauche est à `a` cm du coin gauche du mur (vu depuis la pièce) : plus besoin de réfléchir
  aux rotations.
- Dans les helpers, le paramètre `yw` = distance entre le mur et la face arrière de l'objet (cm).

```python
# ======================= TOOLKIT CUISINE / SALLE DE BAIN =======================
# Unités SDK = pouces. Les fonctions métier prennent des CENTIMÈTRES et convertissent.
def cm(v):
    return v / 2.54


def T(x=0, y=0, z=0, rot=0):
    """Rotation autour de Z (degrés, sens trigo vu de dessus) puis translation (pouces)."""
    c = math.cos(math.radians(rot))
    s = math.sin(math.radians(rot))
    return SUTransformation([c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, x, y, z, 1])


def _loc(x, y, rot, lx, ly):
    """Coordonnées monde (pouces) d'un point local (lx, ly) d'un repère placé en (x, y, rot)."""
    c = math.cos(math.radians(rot))
    s = math.sin(math.radians(rot))
    return (x + c * lx - s * ly, y + s * lx + c * ly)


# ---------------------------------------------------------------- matériaux
PAL = {
    "mur": (240, 238, 232),
    "sol_parquet": (196, 166, 120),
    "sol_carrelage": (190, 190, 186),
    "sol_carrelage_fonce": (120, 120, 118),
    "facade_blanc": (246, 246, 243),
    "facade_chene": (205, 175, 130),
    "facade_noir": (45, 45, 48),
    "facade_vert": (92, 112, 96),
    "facade_bleu": (70, 90, 120),
    "plan_quartz": (236, 234, 229),
    "plan_bois": (188, 148, 98),
    "plan_noir": (40, 40, 42),
    "inox": (196, 198, 200),
    "noir_appareil": (30, 30, 32),
    "credence": (226, 224, 220),
    "faience": (242, 244, 246),
    "ceramique": (250, 250, 250),
    "verre": (185, 215, 232, 70),
    "chrome": (205, 210, 215),
    "miroir": (200, 220, 235),
}


def mat(name, r, g, b, a=255):
    for m in model.get_materials():
        if m.get_name() == name:
            return m
    m = Material()
    m.set_name(name)
    m.set_color(SUColor(r, g, b, a))
    model.add_materials([m])
    return m


def M(key):
    v = PAL[key]
    return mat(key, v[0], v[1], v[2], v[3] if len(v) > 3 else 255)


def paint(g, m):
    for f in g.get_entities().get_faces():
        f.set_front_material(m)
        f.set_back_material(m)


# ---------------------------------------------------------------- géométrie (pouces)
def _faces(geom, faces):
    for fv in faces:
        lp = LoopInput()
        for i in fv:
            lp.add_vertex_index(i)
        _, geom = geom.add_face(lp)
    return geom


BOX_FACES = [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [0, 3, 2, 1]]


def _box_verts(w, d, h):
    return [
        SUPoint3D(0, 0, 0), SUPoint3D(w, 0, 0), SUPoint3D(w, d, 0), SUPoint3D(0, d, 0),
        SUPoint3D(0, 0, h), SUPoint3D(w, 0, h), SUPoint3D(w, d, h), SUPoint3D(0, d, h),
    ]


def box_geom(w, d, h):
    """Boîte 6 quads, origine (0,0,0) → (w,d,h)."""
    g = GeometryInput()
    g.set_vertices(_box_verts(w, d, h))
    return _faces(g, BOX_FACES)


def hollow_geom(w, d, h, t, depth):
    """Boîte creuse ouverte sur le dessus (évier, vasque, baignoire, receveur).
    t = épaisseur des parois, depth = profondeur de la cuve (< h)."""
    zf = h - depth
    g = GeometryInput()
    g.set_vertices(
        _box_verts(w, d, h)
        + [SUPoint3D(t, t, h), SUPoint3D(w - t, t, h), SUPoint3D(w - t, d - t, h), SUPoint3D(t, d - t, h)]
        + [SUPoint3D(t, t, zf), SUPoint3D(w - t, t, zf), SUPoint3D(w - t, d - t, zf), SUPoint3D(t, d - t, zf)]
    )
    g = _faces(g, [[0, 3, 2, 1], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]])
    top = LoopInput()
    for i in [4, 5, 6, 7]:
        top.add_vertex_index(i)
    fi, g = g.add_face(top)
    inner = LoopInput()
    for i in [8, 11, 10, 9]:
        inner.add_vertex_index(i)
    g = g.face_add_inner_loop(fi, inner)
    return _faces(g, [[8, 9, 13, 12], [9, 10, 14, 13], [10, 11, 15, 14], [11, 8, 12, 15], [12, 13, 14, 15]])


def slab_geom(w, d, t, holes=()):
    """Plan horizontal w×d×t percé de trous traversants (x0, y0, x1, y1) : plan de travail avec
    évier, plan vasque. Les trous ne doivent pas toucher le bord."""
    verts = _box_verts(w, d, t)
    for (x0, y0, x1, y1) in holes:
        verts += [
            SUPoint3D(x0, y0, 0), SUPoint3D(x1, y0, 0), SUPoint3D(x1, y1, 0), SUPoint3D(x0, y1, 0),
            SUPoint3D(x0, y0, t), SUPoint3D(x1, y0, t), SUPoint3D(x1, y1, t), SUPoint3D(x0, y1, t),
        ]
    g = GeometryInput()
    g.set_vertices(verts)
    g = _faces(g, [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]])
    top = LoopInput()
    for i in [4, 5, 6, 7]:
        top.add_vertex_index(i)
    ti, g = g.add_face(top)
    bot = LoopInput()
    for i in [0, 3, 2, 1]:
        bot.add_vertex_index(i)
    bi, g = g.add_face(bot)
    for k in range(len(holes)):
        b = 8 + 8 * k
        lp = LoopInput()
        for i in [b + 4, b + 7, b + 6, b + 5]:
            lp.add_vertex_index(i)
        g = g.face_add_inner_loop(ti, lp)
        lp = LoopInput()
        for i in [b, b + 1, b + 2, b + 3]:
            lp.add_vertex_index(i)
        g = g.face_add_inner_loop(bi, lp)
        g = _faces(g, [[b, b + 4, b + 5, b + 1], [b + 1, b + 5, b + 6, b + 2],
                       [b + 2, b + 6, b + 7, b + 3], [b + 3, b + 7, b + 4, b]])
    return g


def wall_geom(L, t, h, openings=()):
    """Mur le long de +X (longueur L, épaisseur t selon +Y, hauteur h) avec ouvertures
    (x0, x1, z0, z1) découpées par boucles internes + tableaux. z0 doit être > 0."""
    verts = _box_verts(L, t, h)
    for (x0, x1, z0, z1) in openings:
        verts += [
            SUPoint3D(x0, 0, z0), SUPoint3D(x1, 0, z0), SUPoint3D(x1, 0, z1), SUPoint3D(x0, 0, z1),
            SUPoint3D(x0, t, z0), SUPoint3D(x1, t, z0), SUPoint3D(x1, t, z1), SUPoint3D(x0, t, z1),
        ]
    g = GeometryInput()
    g.set_vertices(verts)
    outer = LoopInput()
    for i in [0, 1, 5, 4]:
        outer.add_vertex_index(i)
    fi, g = g.add_face(outer)
    for k in range(len(openings)):
        b = 8 + k * 8
        inner = LoopInput()
        for i in [b, b + 3, b + 2, b + 1]:
            inner.add_vertex_index(i)
        g = g.face_add_inner_loop(fi, inner)
    outer = LoopInput()
    for i in [2, 3, 7, 6]:
        outer.add_vertex_index(i)
    bi, g = g.add_face(outer)
    for k in range(len(openings)):
        b = 8 + k * 8 + 4
        inner = LoopInput()
        for i in [b, b + 3, b + 2, b + 1]:
            inner.add_vertex_index(i)
        g = g.face_add_inner_loop(bi, inner)
    g = _faces(g, [[1, 2, 6, 5], [3, 0, 4, 7], [4, 5, 6, 7], [0, 3, 2, 1]])
    for k in range(len(openings)):
        b = 8 + k * 8
        g = _faces(g, [[b, b + 4, b + 7, b + 3], [b + 5, b + 1, b + 2, b + 6],
                       [b, b + 1, b + 5, b + 4], [b + 7, b + 6, b + 2, b + 3]])
    return g


def rounded_geom(w, d, h, r, n=3):
    """Boîte à arêtes verticales arrondies (cuvette WC, vasque à poser, îlot). Retourne geom."""
    r = min(r, w / 2 - 0.01, d / 2 - 0.01)
    centers = [(r, r), (w - r, r), (w - r, d - r), (r, d - r)]
    starts = [math.pi, 1.5 * math.pi, 0, 0.5 * math.pi]

    def ring(z):
        pts = []
        for ci in range(4):
            cx, cy = centers[ci]
            for j in range(n):
                a = starts[ci] + (math.pi / 2) * j / n
                pts.append(SUPoint3D(cx + r * math.cos(a), cy + r * math.sin(a), z))
        return pts

    bot = ring(0)
    top = ring(h)
    vn = len(bot)
    g = GeometryInput()
    g.set_vertices(bot + top)
    lp = LoopInput()
    for i in range(vn - 1, -1, -1):
        lp.add_vertex_index(i)
    _, g = g.add_face(lp)
    lp = LoopInput()
    for i in range(vn, 2 * vn):
        lp.add_vertex_index(i)
    _, g = g.add_face(lp)
    for i in range(vn):
        i2 = (i + 1) % vn
        g = _faces(g, [[i, i2, i2 + vn, i + vn]])
    return g


def soften_rounded(g):
    """Adoucit les arêtes verticales des coins arrondis (à appeler après fill)."""
    for e in g.get_entities().get_edges():
        faces = e.get_faces()
        if len(faces) != 2:
            continue
        sv = e.get_start_vertex().get_position()
        ev = e.get_end_vertex().get_position()
        if abs(sv.z - ev.z) < 0.001:
            continue
        n0 = faces[0].get_normal()
        n1 = faces[1].get_normal()

        def axis(nv):
            return abs(abs(nv.x) - 1) < 0.01 or abs(abs(nv.y) - 1) < 0.01 or abs(abs(nv.z) - 1) < 0.01

        if axis(n0) or axis(n1):
            continue
        e.set_soft(True)
        e.set_smooth(True)


# ---------------------------------------------------------------- placement
def grp(parent, name, geom, x=0, y=0, z=0, rot=0, m=None):
    """Crée un groupe nommé dans `parent` (Group ou model), le remplit, le place (POUCES)."""
    g = Group()
    parent.get_entities().add_group(g)
    g.set_name(name)
    g.get_entities().fill(geom, weld_vertices=True)
    g.set_transform(T(x, y, z, rot))
    if m is not None:
        paint(g, m)
    return g


def assembly(parent, name, pos=(0, 0, 0)):
    """Groupe vide servant de parent (assemblage), placé par pos = (x_cm, y_cm, rot)."""
    g = Group()
    parent.get_entities().add_group(g)
    g.set_name(name)
    g.set_transform(T(cm(pos[0]), cm(pos[1]), 0, pos[2]))
    return g


def on_wall(wall, a, W, D):
    """pos = (x, y, rot) d'un objet adossé au mur `wall` ("back", "left", "right", "front") d'une
    pièce W×D, dont le bord gauche (vu depuis la pièce) est à `a` cm du coin gauche du mur."""
    if wall == "back":
        return (a, D, 0)
    if wall == "left":
        return (0, a, 90)
    if wall == "right":
        return (W, D - a, 270)
    if wall == "front":
        return (W - a, 0, 180)
    raise Exception("wall inconnu: " + wall)


def place(parent, name, geom, x, yw, z, d, m=None):
    """Place une géométrie (pouces, profondeur d cm) dans le repère local d'un assemblage :
    x = abscisse du bord gauche (cm), yw = distance mur→face arrière (cm), z = hauteur (cm)."""
    return grp(parent, name, geom, cm(x), -cm(yw + d), cm(z), 0, m)


def box(parent, name, x, yw, z, w, d, h, m=None):
    """Boîte w×d×h (cm) : bord gauche en x, face arrière à yw du mur, base en z."""
    return place(parent, name, box_geom(cm(w), cm(d), cm(h)), x, yw, z, d, m)


def hollow(parent, name, x, yw, z, w, d, h, t, depth, m=None):
    return place(parent, name, hollow_geom(cm(w), cm(d), cm(h), cm(t), cm(depth)), x, yw, z, d, m)


def rounded(parent, name, x, yw, z, w, d, h, r, m=None, n=3):
    g = place(parent, name, rounded_geom(cm(w), cm(d), cm(h), cm(r), n), x, yw, z, d, m)
    soften_rounded(g)
    return g


def slab(parent, name, x, yw, z, w, d, t, holes=(), m=None):
    """Plan w×d×t (cm) percé de trous (hx, hyw, hw, hd) : hx depuis le bord gauche du plan,
    hyw = distance mur→bord arrière du trou, hw×hd = dimensions du trou."""
    hl = [(cm(hx), cm(d - hyw - hd), cm(hx + hw), cm(d - hyw)) for (hx, hyw, hw, hd) in holes]
    return place(parent, name, slab_geom(cm(w), cm(d), cm(t), hl), x, yw, z, d, m)


def bb_room(W, D, H=250, t=12):
    """Boîte englobante (POUCES) d'une pièce créée par room(), pour les caméras."""
    return (cm(-t), cm(-t), cm(-2), cm(W + t), cm(D + t), cm(H))


# ---------------------------------------------------------------- pièce
def room(parent, W, D, H=250, full=("back", "left"), openings=None, t=12, sol="sol_carrelage", mur="mur", low_h=10):
    """Pièce W×D×H (cm). `full` = murs pleine hauteur ; les autres sont des murets de `low_h` cm
    (maquette ouverte, lisible en vue 3/4). `openings` = {"back": [(kind, a0, a1, z0, z1), ...]}
    avec kind "door" ou "window", a = abscisse le long du mur depuis le coin x=0 (murs back/front)
    ou y=0 (murs left/right), z0/z1 = hauteurs (cm). Une porte commence à z0=1 (seuil)."""
    openings = openings or {}
    R = assembly(parent, "Piece")
    grp(R, "Sol", box_geom(cm(W + 2 * t), cm(D + 2 * t), cm(2)), cm(-t), cm(-t), cm(-2), 0, M(sol))
    L_ref = {"back": W, "front": W, "left": D, "right": D}
    spec = {
        "back": (W + 2 * t, -t, D, 0, t),
        "front": (W + 2 * t, -t, -t, 0, t),
        "left": (D, 0, 0, 90, 0),
        "right": (D, W + t, 0, 90, 0),
    }
    for side in ["back", "front", "left", "right"]:
        L, x, y, rot, off = spec[side]
        if side not in full:
            # muret bas, interrompu au droit des portes
            cuts = [(a0, a1) for (kind, a0, a1, z0, z1) in openings.get(side, []) if kind == "door"]
            for i in range(len(cuts)):
                for j in range(len(cuts) - 1 - i):
                    if cuts[j][0] > cuts[j + 1][0]:
                        cuts[j], cuts[j + 1] = cuts[j + 1], cuts[j]
            a = -off
            segs = []
            for (a0, a1) in cuts:
                segs.append((a, a0))
                a = a1
            segs.append((a, L_ref[side] + (t if off else 0)))
            for i, (s0, s1) in enumerate(segs):
                if s1 - s0 < 0.5:
                    continue
                wx, wy = _loc(cm(x), cm(y), rot, cm(s0 + off), 0)
                grp(R, "Muret_%s_%d" % (side, i + 1), box_geom(cm(s1 - s0), cm(t), cm(low_h)), wx, wy, 0, rot, M(mur))
            continue
        ops = []
        for (kind, a0, a1, z0, z1) in openings.get(side, []):
            ops.append((cm(a0 + off), cm(a1 + off), cm(max(z0, 0.5)), cm(min(z1, H - 0.5))))
        grp(R, "Mur_" + side, wall_geom(cm(L), cm(t), cm(H), ops), cm(x), cm(y), 0, rot, M(mur))
        for (kind, a0, a1, z0, z1) in openings.get(side, []):
            if kind == "window":
                wx, wy = _loc(cm(x), cm(y), rot, cm(a0 + off), cm(t / 2 - 0.5))
                grp(R, "Vitrage_" + side, box_geom(cm(a1 - a0), cm(1), cm(z1 - z0)), wx, wy, cm(z0), rot, M("verre"))
    return R


# ---------------------------------------------------------------- petits accessoires
def tap(parent, x, yw, z, m=None):
    """Mitigeur (cm) : corps vertical à yw du mur + bec de 14 cm vers la pièce."""
    m = m or M("chrome")
    box(parent, "Mitigeur", x - 1.25, yw, z, 2.5, 2.5, 20, m)
    box(parent, "Bec", x - 1, yw, z + 17, 2, 14, 2.5, m)


HANDLE_DEF = [None]


def handle(parent, x, yw, z):
    """Poignée barre 15 cm (composant partagé). x,z (cm) = milieu de la barre ; yw = face avant."""
    if HANDLE_DEF[0] is None:
        cd = None
        for d in model.get_component_definitions():
            if d.get_name() == "Poignee":
                cd = d
        if cd is None:
            cd = ComponentDefinition()
            cd.set_name("Poignee")
            model.add_component_definitions([cd])
            cd.get_entities().fill(box_geom(cm(15), cm(2.5), cm(1.2)), weld_vertices=True)
            for f in cd.get_entities().get_faces():
                f.set_front_material(M("chrome"))
                f.set_back_material(M("chrome"))
        HANDLE_DEF[0] = cd
    inst = HANDLE_DEF[0].create_instance()
    inst.set_name("Poignee")
    inst.set_transform(T(cm(x - 7.5), -cm(yw + 2.5), cm(z - 0.6), 0))
    parent.get_entities().add_instance(inst)
    return inst


# ---------------------------------------------------------------- cuisine
KIT = {"socle": 10, "retrait": 5, "caisson_h": 76, "caisson_p": 58, "facade": 2, "plan_ep": 4,
       "plan_p": 65, "haut_h": 72, "haut_p": 35, "haut_z": 145, "colonne_h": 220, "colonne_p": 60,
       "credence_h": 55, "jeu": 0.3, "hotte_z": 155}


def kitchen_run(parent, name, pos, modules, hauts=None, start=0, hauts_start=None,
                credence=True, facade="facade_blanc", plan="plan_quartz", H=250, poignees=True, K=None):
    """Ligne de meubles le long d'un mur (cm). pos = on_wall(...) ou (x, y, rot).
    `modules` = [(kind, largeur), ...] posés de gauche à droite (vu depuis la pièce) à partir de
    `start` : door, drawers, sink, hob, oven, dishwasher, fridge, tall, filler.
    `hauts` = [(kind, largeur), ...] : door, hood, open. Le plan de travail et la crédence couvrent
    les meubles bas et s'interrompent aux colonnes. Retourne (groupe, abscisse_fin_cm)."""
    K = K or KIT
    A = assembly(parent, name, pos)
    fm = M(facade)
    pm = M(plan)
    z_plan = K["socle"] + K["caisson_h"]
    z_top = z_plan + K["plan_ep"]
    cur = start
    st = {"seg_start": start, "holes": [], "seg": 0}

    def facade_box(nm, fx, fz, fw, fh):
        box(A, nm, fx + K["jeu"], K["caisson_p"], fz + K["jeu"], fw - 2 * K["jeu"], K["facade"], fh - 2 * K["jeu"], fm)
        if poignees:
            handle(A, fx + fw / 2, K["caisson_p"] + K["facade"], fz + fh - 5 if fh > 30 else fz + fh / 2)

    def close_segment(end):
        s0 = st["seg_start"]
        if end - s0 < 1:
            st["holes"] = []
            return
        st["seg"] += 1
        hl = [(hx - s0, hyw, hw, hd) for (hx, hyw, hw, hd) in st["holes"]]
        slab(A, name + "_Plan_%d" % st["seg"], s0, 0, z_plan, end - s0, K["plan_p"], K["plan_ep"], hl, pm)
        if credence:
            box(A, name + "_Credence_%d" % st["seg"], s0, 0, z_top, end - s0, 1, K["credence_h"], M("credence"))
        st["holes"] = []

    for i, (kind, w) in enumerate(modules):
        nm = "%s_%02d_%s" % (name, i + 1, kind)
        if kind == "filler":
            box(A, nm, cur, K["caisson_p"] - 2, K["socle"], w, K["facade"] + 2, K["caisson_h"], fm)
            cur += w
            continue
        if kind in ("fridge", "tall"):
            close_segment(cur)
            box(A, nm + "_Caisson", cur, 0, 0, w, K["colonne_p"] - K["facade"], K["colonne_h"], fm)
            top_h = K["colonne_h"] * 0.62
            box(A, nm + "_Porte_Haute", cur + K["jeu"], K["colonne_p"] - K["facade"], K["colonne_h"] - top_h + K["jeu"],
                w - 2 * K["jeu"], K["facade"], top_h - 2 * K["jeu"], fm)
            box(A, nm + "_Porte_Basse", cur + K["jeu"], K["colonne_p"] - K["facade"], K["jeu"],
                w - 2 * K["jeu"], K["facade"], K["colonne_h"] - top_h - 2 * K["jeu"], fm)
            if poignees:
                handle(A, cur + w / 2, K["colonne_p"], K["colonne_h"] - top_h + 6)
                handle(A, cur + w / 2, K["colonne_p"], K["colonne_h"] - top_h - 6)
            cur += w
            st["seg_start"] = cur
            continue
        # --- meuble bas générique
        box(A, nm + "_Socle", cur, 0, 0, w, K["caisson_p"] - K["retrait"], K["socle"], M("facade_noir"))
        box(A, nm + "_Caisson", cur, 0, K["socle"], w, K["caisson_p"], K["caisson_h"], fm)
        if kind == "drawers":
            hs = [0.22, 0.39, 0.39]
            fz = K["socle"]
            for hfrac in hs:
                fh = K["caisson_h"] * hfrac
                facade_box(nm + "_Tiroir", cur, fz, w, fh)
                fz += fh
        elif kind == "oven":
            fh_drawer = K["caisson_h"] - 60
            facade_box(nm + "_Tiroir", cur, K["socle"], w, fh_drawer)
            box(A, nm + "_Four", cur + K["jeu"], K["caisson_p"], K["socle"] + fh_drawer + K["jeu"],
                w - 2 * K["jeu"], K["facade"], 60 - 2 * K["jeu"], M("noir_appareil"))
            box(A, nm + "_Four_Poignee", cur + 4, K["caisson_p"] + K["facade"], K["socle"] + K["caisson_h"] - 8,
                w - 8, 2.5, 1.5, M("chrome"))
        elif kind == "dishwasher":
            box(A, nm + "_Facade", cur + K["jeu"], K["caisson_p"], K["socle"] + K["jeu"],
                w - 2 * K["jeu"], K["facade"], K["caisson_h"] - 2 * K["jeu"], fm)
            if poignees:
                handle(A, cur + w / 2, K["caisson_p"] + K["facade"], K["socle"] + K["caisson_h"] - 5)
        else:  # door, sink, hob
            if w > 65:
                facade_box(nm + "_Porte_G", cur, K["socle"], w / 2, K["caisson_h"])
                facade_box(nm + "_Porte_D", cur + w / 2, K["socle"], w / 2, K["caisson_h"])
            else:
                facade_box(nm + "_Porte", cur, K["socle"], w, K["caisson_h"])
        if kind == "sink":
            bw = min(w - 10, 80)
            bd = 40
            hx0 = cur + (w - bw) / 2
            st["holes"].append((hx0, 10, bw, bd))
            hollow(A, nm + "_Cuve", hx0, 10, z_top - 18, bw, bd, 18, 1, 17, M("inox"))
            tap(A, cur + w / 2, 3, z_top)
        if kind == "hob":
            box(A, nm + "_Plaque", cur + (w - 58) / 2, 7, z_top, 58, 51, 0.6, M("noir_appareil"))
        cur += w
    end = cur
    close_segment(end)

    if hauts:
        hc = start if hauts_start is None else hauts_start
        for i, (kind, w) in enumerate(hauts):
            nm = "%s_Haut_%02d_%s" % (name, i + 1, kind)
            if kind == "door":
                box(A, nm + "_Caisson", hc, 0, K["haut_z"], w, K["haut_p"], K["haut_h"], fm)
                box(A, nm + "_Porte", hc + K["jeu"], K["haut_p"], K["haut_z"] + K["jeu"],
                    w - 2 * K["jeu"], K["facade"], K["haut_h"] - 2 * K["jeu"], fm)
                if poignees:
                    handle(A, hc + w / 2, K["haut_p"] + K["facade"], K["haut_z"] + 5)
            elif kind == "hood":
                box(A, nm + "_Corps", hc + (w - 60) / 2, 0, K["hotte_z"], 60, 50, 8, M("inox"))
                box(A, nm + "_Cheminee", hc + w / 2 - 12.5, 0, K["hotte_z"] + 8, 25, 30, H - K["hotte_z"] - 8, M("inox"))
            hc += w
    return A, end


def island(parent, name, pos, L=200, P=100, facade="facade_chene", plan="plan_quartz", K=None, hob=False):
    """Îlot central (cm) : pos = (x, y, rot) de son coin arrière-gauche, il s'étend vers local −Y."""
    K = K or KIT
    A = assembly(parent, name, pos)
    z_plan = K["socle"] + K["caisson_h"]
    box(A, name + "_Socle", 5, 5, 0, L - 10, P - 10, K["socle"], M("facade_noir"))
    box(A, name + "_Caisson", 2.5, 2.5, K["socle"], L - 5, P - 5, K["caisson_h"], M(facade))
    box(A, name + "_Plan", 0, 0, z_plan, L, P, K["plan_ep"], M(plan))
    if hob:
        box(A, name + "_Plaque", L / 2 - 29, P / 2 - 25, z_plan + K["plan_ep"], 58, 51, 0.6, M("noir_appareil"))
    return A


# ---------------------------------------------------------------- salle de bain
def vanity(parent, name, pos, w=80, d=48, h_plan=85, facade="facade_chene", plan="plan_quartz", miroir=True):
    """Meuble vasque suspendu (cm) : plan percé + vasque encastrée + mitigeur + miroir."""
    A = assembly(parent, name, pos)
    zc = h_plan - 3 - 50
    box(A, name + "_Caisson", 0, 0, zc, w, d - 4, 50, M(facade))
    box(A, name + "_Facade_Haut", 0.3, d - 4, zc + 25.3, w - 0.6, 2, 24.4, M(facade))
    box(A, name + "_Facade_Bas", 0.3, d - 4, zc + 0.3, w - 0.6, 2, 24.4, M(facade))
    bw = min(50, w - 16)
    bd = min(38, d - 10)
    x0 = (w - bw) / 2
    y0 = (d - bd) / 2
    slab(A, name + "_Plan", 0, 0, h_plan - 3, w, d, 3, [(x0, y0, bw, bd)], M(plan))
    hollow(A, name + "_Vasque", x0, y0, h_plan - 15, bw, bd, 15, 1, 14, M("ceramique"))
    tap(A, w / 2, 3, h_plan)
    if miroir:
        box(A, name + "_Miroir", 5, 0, h_plan + 15, w - 10, 1, 80, M("miroir"))
    return A


def toilet(parent, name, pos):
    """WC à poser (cm) : réservoir contre le mur, cuvette arrondie, abattant. Encombrement 40×66."""
    A = assembly(parent, name, pos)
    box(A, name + "_Reservoir", 1, 0, 40, 38, 18, 40, M("ceramique"))
    box(A, name + "_Bouton", 17, 18, 72, 6, 0.8, 4, M("chrome"))
    rounded(A, name + "_Cuvette", 2, 14, 0, 36, 52, 40, 15, M("ceramique"))
    rounded(A, name + "_Abattant", 2, 18, 40, 36, 46, 3, 15, M("ceramique"))
    return A


def bathtub(parent, name, pos, L=170, W=75, H=58):
    """Baignoire droite (cm), dos au mur (grand côté en local X)."""
    A = assembly(parent, name, pos)
    hollow(A, name + "_Cuve", 0, 0, 0, L, W, H, 5, 45, M("ceramique"))
    box(A, name + "_Mitigeur", L - 40, 0, 72, 22, 8, 7, M("chrome"))
    box(A, name + "_Bec", L - 31, 8, 74, 4, 14, 3, M("chrome"))
    return A


def shower(parent, name, pos, W=90, D=90, paroi="right", porte=True):
    """Douche d'angle (cm) : receveur, paroi vitrée latérale (`paroi` = côté local "right" ou
    "left"), porte vitrée en façade, colonne de douche sur le mur du fond."""
    A = assembly(parent, name, pos)
    hollow(A, name + "_Receveur", 0, 0, 0, W, D, 4, 3, 2.5, M("ceramique"))
    px = W - 0.8 if paroi == "right" else 0
    box(A, name + "_Paroi", px, 0, 4, 0.8, D, 196, M("verre"))
    if porte:
        box(A, name + "_Porte", 2, D - 0.8, 4, W - 4, 0.8, 196, M("verre"))
    box(A, name + "_Barre", W / 2 - 1.25, 2, 90, 2.5, 2.5, 110, M("chrome"))
    box(A, name + "_Mitigeur", W / 2 - 10, 0, 100, 20, 6, 6, M("chrome"))
    box(A, name + "_Pommeau", W / 2 - 10, 2, 198, 20, 20, 2, M("chrome"))
    return A


def radiator(parent, name, pos, w=50, h=120, z=25):
    """Sèche-serviettes (cm) plaqué au mur."""
    A = assembly(parent, name, pos)
    box(A, name + "_Corps", 0, 3, z, w, 5, h, M("ceramique"))
    return A


def washer(parent, name, pos):
    """Lave-linge 60×60×85 (cm)."""
    A = assembly(parent, name, pos)
    box(A, name + "_Corps", 0, 0, 0, 60, 60, 85, M("ceramique"))
    box(A, name + "_Hublot", 12.5, 60, 20, 35, 1, 35, M("noir_appareil"))
    box(A, name + "_Bandeau", 2, 60, 72, 56, 0.6, 10, M("inox"))
    return A


def shelf(parent, name, pos, z=120, w=60, d=25, h=1.8, m="facade_chene"):
    """Étagère / tablette murale (cm)."""
    A = assembly(parent, name, pos)
    return box(A, name + "_Tablette", 0, 0, z, w, d, h, M(m))


# ---------------------------------------------------------------- style et caméra
def style_interieur(ombres=True):
    """Préréglage 'Interior Room' (fond blanc, profils, AO) ; ombres au choix."""
    ro = model.get_rendering_options()

    def s(k, v):
        ro[RenderingOptionKey[k]] = v

    s("BACKGROUND_COLOR", TypedValue(color_value=SUColor(255, 255, 255, 255)))
    s("FACE_FRONT_COLOR", TypedValue(color_value=SUColor(240, 238, 232, 255)))
    s("FACE_BACK_COLOR", TypedValue(color_value=SUColor(150, 155, 165, 255)))
    s("FOREGROUND_COLOR", TypedValue(color_value=SUColor(60, 58, 55, 255)))
    s("EDGE_DISPLAY_MODE", TypedValue(int_value=1))
    s("EDGE_COLOR_MODE", TypedValue(int_value=0))
    s("RENDER_MODE", TypedValue(int_value=2))
    s("MODEL_TRANSPARENCY", TypedValue(bool_value=False))
    s("MATERIAL_TRANSPARENCY", TypedValue(bool_value=True))
    s("DRAW_DEPTH_QUE", TypedValue(bool_value=False))
    s("DRAW_SILHOUETTES", TypedValue(bool_value=True))
    s("SILHOUETTE_WIDTH", TypedValue(int_value=2))
    s("DRAW_HORIZON", TypedValue(bool_value=False))
    s("DRAW_GROUND", TypedValue(bool_value=False))
    s("DISPLAY_SKETCH_AXES", TypedValue(bool_value=False))
    s("HIGHLIGHT_COLOR", TypedValue(color_value=SUColor(0, 1, 255, 255)))
    s("LOCKED_COLOR", TypedValue(color_value=SUColor(255, 0, 0, 255)))
    s("AMBIENT_OCCLUSION", TypedValue(bool_value=True))
    s("AMBIENT_OCCLUSION_DISTANCE", TypedValue(float_value=10.0))
    s("AMBIENT_OCCLUSION_INTENSITY", TypedValue(float_value=0.45))
    s("AMBIENT_OCCLUSION_MULTIPLIER", TypedValue(float_value=1.0))
    si = model.get_shadow_info()
    si[ShadowInfoKey["DISPLAY_SHADOWS"]] = TypedValue(bool_value=ombres)
    if ombres:
        si[ShadowInfoKey["LIGHT"]] = TypedValue(int_value=75)
        si[ShadowInfoKey["DARK"]] = TypedValue(int_value=55)


def _set_cam(eye, target, fov):
    cam = Camera()
    cam.set_orientation(eye, target, SUVector3D(0, 0, 1))
    cam.enable_perspective()
    cam.set_perspective_frustum_fov(fov)
    model.set_camera(cam)
    chk = model.get_camera()
    o = chk.get_orientation()
    return {"eye": [round(o[0].x, 1), round(o[0].y, 1), round(o[0].z, 1)],
            "fov": chk.get_perspective_frustum_fov(), "persp": chk.is_perspective()}


def camera_maquette(bb, azimut=45, elevation=35, fov=45, aspect=1.6, marge=1.15):
    """Vue 3/4 plongeante 'maquette ouverte'. bb = (xmin, ymin, zmin, xmax, ymax, zmax) en POUCES,
    repris du model_snapshot. azimut 45 regarde vers les murs back+left, 135 vers back+right,
    90 de face (cuisine en U)."""
    xmin, ymin, zmin, xmax, ymax, zmax = bb
    cx, cy, cz = (xmin + xmax) / 2, (ymin + ymax) / 2, (zmin + zmax) / 2
    w, d, h = xmax - xmin, ymax - ymin, zmax - zmin
    az, el = math.radians(azimut), math.radians(elevation)
    dx, dy, dz = math.cos(az) * math.cos(el), -math.sin(az) * math.cos(el), math.sin(el)
    rl = math.sqrt(dx * dx + dy * dy)
    rx, ry, rz = -dy / rl, dx / rl, 0.0
    ux, uy, uz = dy * rz - dz * ry, dz * rx - dx * rz, dx * ry - dy * rx
    hext = abs(rx) * w + abs(ry) * d + abs(rz) * h
    vext = abs(ux) * w + abs(uy) * d + abs(uz) * h
    hv = math.radians(fov / 2)
    hh = math.atan(aspect * math.tan(hv))
    dist = max(vext / 2 / math.tan(hv), hext / 2 / math.tan(hh)) * marge
    eye = SUPoint3D(cx + dist * dx, cy + dist * dy, cz + dist * dz)
    target = SUPoint3D(cx, cy, zmin + h * 0.3)
    return _set_cam(eye, target, fov)


def camera_interieure(bb, coin="front-right", fov=62, oeil=160):
    """Vue intérieure à hauteur d'œil (cm) depuis un coin de la pièce vers le coin opposé."""
    xmin, ymin, zmin, xmax, ymax, zmax = bb
    w, d = xmax - xmin, ymax - ymin
    fx = 0.12 if "left" in coin else 0.88
    fy = 0.12 if "front" in coin else 0.88
    eye = SUPoint3D(xmin + w * fx, ymin + d * fy, zmin + cm(oeil))
    target = SUPoint3D(xmin + w * (1 - fx), ymin + d * (1 - fy), zmin + cm(110))
    return _set_cam(eye, target, fov)
# ===================== FIN TOOLKIT =====================
```
