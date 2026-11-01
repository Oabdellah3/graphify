# ============================================================================
# cuisine_sdb.rb — Boîte à outils Ruby pour dessiner cuisines et salles de bain
# dans SketchUp Desktop (Ruby 2.5+, SketchUp 2017 → 2019 et suivants).
#
# Utilisation dans SketchUp : Fenêtre → Console Ruby, puis
#     load "C:/chemin/vers/mon_projet.rb"      (barres obliques /, même sous Windows)
# où mon_projet.rb = ce fichier suivi du scénario (voir SKILL.md).
#
# Conventions (identiques au toolkit Python du connecteur) :
#   - toutes les fonctions métier prennent des CENTIMÈTRES ; SketchUp travaille en pouces
#     en interne, cm() convertit.
#   - pièce : origine au coin avant-gauche intérieur, W selon +X, D selon +Y, sol en Z = 0 ;
#     murs "back" (y = D), "front" (y = 0), "left" (x = 0), "right" (x = W).
#   - un objet adossé à un mur est placé par pos = on_wall(mur, a, W, D) : son dos est sur
#     le mur, il s'étend vers la pièce, ses modules vont de gauche à droite vu depuis la pièce.
#   - yw = distance entre le mur et la face arrière de l'objet.
# ============================================================================
module CuisineSdb
  module_function

  PAL = {
    "mur" => [240, 238, 232], "sol_parquet" => [196, 166, 120], "sol_carrelage" => [190, 190, 186],
    "sol_carrelage_fonce" => [120, 120, 118], "facade_blanc" => [246, 246, 243],
    "facade_chene" => [205, 175, 130], "facade_noir" => [45, 45, 48], "facade_vert" => [92, 112, 96],
    "facade_bleu" => [70, 90, 120], "plan_quartz" => [236, 234, 229], "plan_bois" => [188, 148, 98],
    "plan_noir" => [40, 40, 42], "inox" => [196, 198, 200], "noir_appareil" => [30, 30, 32],
    "credence" => [226, 224, 220], "faience" => [242, 244, 246], "ceramique" => [250, 250, 250],
    "verre" => [185, 215, 232, 70], "chrome" => [205, 210, 215], "miroir" => [200, 220, 235]
  }

  KIT = {
    socle: 10, retrait: 5, caisson_h: 76, caisson_p: 58, facade: 2, plan_ep: 4, plan_p: 65,
    haut_h: 72, haut_p: 35, haut_z: 145, colonne_h: 220, colonne_p: 60, credence_h: 55,
    jeu: 0.3, hotte_z: 155
  }

  # ------------------------------------------------------------ bases
  def cm(v)
    v.to_f / 2.54
  end

  def model
    Sketchup.active_model
  end

  # Matériau par clé de PAL (créé une seule fois) ; "verre" est semi-transparent.
  def mat(key)
    key = key.to_s
    existing = model.materials[key]
    return existing if existing
    r, g, b, a = PAL.fetch(key) { raise "Matériau inconnu : #{key}" }
    m = model.materials.add(key)
    m.color = Sketchup::Color.new(r, g, b)
    m.alpha = a / 255.0 if a && a < 255
    m
  end

  def paint(g, m)
    return g unless m
    g.entities.grep(Sketchup::Face).each do |f|
      f.material = m
      f.back_material = m
    end
    g
  end

  # Rotation autour de Z (degrés) puis translation (pouces).
  def tr(x, y, z, rot)
    t = Geom::Transformation.new(Geom::Point3d.new(x, y, z))
    r = Geom::Transformation.rotation(ORIGIN, Z_AXIS, rot.degrees)
    t * r
  end

  def new_group(parent, name)
    g = parent.entities.add_group
    g.name = name
    g
  end

  def axis_aligned?(n)
    [n.x, n.y, n.z].any? { |c| (c.abs - 1).abs < 0.01 }
  end

  # ------------------------------------------------------------ géométrie (pouces, dans un groupe)
  # Face horizontale w×d à z = z0, normale +Z.
  def top_face(ents, x0, y0, x1, y1, z)
    f = ents.add_face([x0, y0, z], [x1, y0, z], [x1, y1, z], [x0, y1, z])
    f.reverse! if f.normal.z < 0
    f
  end

  def box_geom(g, w, d, h)
    top_face(g.entities, 0, 0, w, d, 0).pushpull(h)
    g
  end

  # Boîte creuse ouverte sur le dessus (évier, vasque, baignoire, receveur).
  def hollow_geom(g, w, d, h, t, depth)
    box_geom(g, w, d, h)
    top_face(g.entities, t, t, w - t, d - t, h).pushpull(-depth)
    g
  end

  # Plan w×d×t percé de trous traversants [[x0, y0, x1, y1], ...].
  def slab_geom(g, w, d, t, holes)
    box_geom(g, w, d, t)
    holes.each do |x0, y0, x1, y1|
      top_face(g.entities, x0, y0, x1, y1, t).pushpull(-t)
    end
    g
  end

  # Mur le long de +X (longueur len, épaisseur t selon +Y, hauteur h), ouvertures [[x0, x1, z0, z1]].
  def wall_geom(g, len, t, h, openings)
    box_geom(g, len, t, h)
    openings.each do |x0, x1, z0, z1|
      f = g.entities.add_face([x0, 0, z0], [x1, 0, z0], [x1, 0, z1], [x0, 0, z1])
      f.reverse! if f.normal.y > 0
      f.pushpull(-t)
    end
    g
  end

  # Boîte à arêtes verticales arrondies (cuvette WC, vasque à poser).
  def rounded_geom(g, w, d, h, r, n = 3)
    r = [r, w / 2.0 - 0.01, d / 2.0 - 0.01].min
    centers = [[r, r], [w - r, r], [w - r, d - r], [r, d - r]]
    starts = [Math::PI, 1.5 * Math::PI, 0.0, 0.5 * Math::PI]
    pts = []
    4.times do |ci|
      cx, cy = centers[ci]
      n.times do |j|
        a = starts[ci] + (Math::PI / 2) * j / n
        pts << [cx + r * Math.cos(a), cy + r * Math.sin(a), 0]
      end
    end
    f = g.entities.add_face(pts)
    f.reverse! if f.normal.z < 0
    f.pushpull(h)
    g.entities.grep(Sketchup::Edge).each do |e|
      next unless e.faces.length == 2
      next if (e.start.position.z - e.end.position.z).abs < 0.001
      next if e.faces.any? { |fc| axis_aligned?(fc.normal) }
      e.soft = true
      e.smooth = true
    end
    g
  end

  # ------------------------------------------------------------ placement (cm)
  # Groupe placé en pouces dans le repère du parent ; le bloc construit la géométrie.
  def grp(parent, name, x, y, z, rot, m = nil)
    g = new_group(parent, name)
    yield g
    g.transformation = tr(x, y, z, rot)
    paint(g, m)
  end

  # Groupe vide servant de parent (assemblage), pos = [x_cm, y_cm, rot].
  def assembly(parent, name, pos = [0, 0, 0])
    g = new_group(parent, name)
    g.transformation = tr(cm(pos[0]), cm(pos[1]), 0, pos[2])
    g
  end

  def on_wall(wall, a, w_room, d_room)
    case wall.to_s
    when "back" then [a, d_room, 0]
    when "left" then [0, a, 90]
    when "right" then [w_room, d_room - a, 270]
    when "front" then [w_room - a, 0, 180]
    else raise "Mur inconnu : #{wall}"
    end
  end

  # x = bord gauche (cm), yw = distance mur → face arrière (cm), z = base (cm), d = profondeur (cm)
  def place(parent, name, x, yw, z, d, m = nil, &blk)
    grp(parent, name, cm(x), -cm(yw + d), cm(z), 0, m, &blk)
  end

  def box(parent, name, x, yw, z, w, d, h, m = nil)
    place(parent, name, x, yw, z, d, m) { |g| box_geom(g, cm(w), cm(d), cm(h)) }
  end

  def hollow(parent, name, x, yw, z, w, d, h, t, depth, m = nil)
    place(parent, name, x, yw, z, d, m) { |g| hollow_geom(g, cm(w), cm(d), cm(h), cm(t), cm(depth)) }
  end

  def rounded(parent, name, x, yw, z, w, d, h, r, m = nil, n = 3)
    place(parent, name, x, yw, z, d, m) { |g| rounded_geom(g, cm(w), cm(d), cm(h), cm(r), n) }
  end

  # Trous : [[hx, hyw, hw, hd], ...] — hx depuis le bord gauche du plan, hyw = distance mur → bord arrière.
  def slab(parent, name, x, yw, z, w, d, t, holes = [], m = nil)
    hl = holes.map { |hx, hyw, hw, hd| [cm(hx), cm(d - hyw - hd), cm(hx + hw), cm(d - hyw)] }
    place(parent, name, x, yw, z, d, m) { |g| slab_geom(g, cm(w), cm(d), cm(t), hl) }
  end

  # ------------------------------------------------------------ pièce
  # full = murs pleine hauteur (les autres sont des murets de low_h cm, maquette ouverte).
  # openings = { "back" => [["door", a0, a1, z0, z1], ["window", a0, a1, z0, z1]], ... }
  def room(parent, w_room, d_room, h_room = 250, full: ["back", "left"], openings: {}, t: 12,
           sol: "sol_carrelage", mur: "mur", low_h: 10)
    full = full.map(&:to_s)
    r = assembly(parent, "Piece")
    grp(r, "Sol", cm(-t), cm(-t), cm(-2), 0, mat(sol)) { |g| box_geom(g, cm(w_room + 2 * t), cm(d_room + 2 * t), cm(2)) }
    l_ref = { "back" => w_room, "front" => w_room, "left" => d_room, "right" => d_room }
    spec = {
      "back" => [w_room + 2 * t, -t, d_room, 0, t],
      "front" => [w_room + 2 * t, -t, -t, 0, t],
      "left" => [d_room, 0, 0, 90, 0],
      "right" => [d_room, w_room + t, 0, 90, 0]
    }
    %w[back front left right].each do |side|
      len, x, y, rot, off = spec[side]
      ops = (openings[side] || openings[side.to_sym] || []).map { |o| o.map { |v| v.is_a?(Symbol) ? v.to_s : v } }
      unless full.include?(side)
        cuts = ops.select { |o| o[0] == "door" }.map { |o| [o[1], o[2]] }.sort_by(&:first)
        a = -off
        segs = []
        cuts.each do |a0, a1|
          segs << [a, a0]
          a = a1
        end
        segs << [a, l_ref[side] + (off > 0 ? t : 0)]
        segs.each_with_index do |(s0, s1), i|
          next if s1 - s0 < 0.5
          lx = cm(s0 + off)
          wx = cm(x) + Math.cos(rot.degrees) * lx
          wy = cm(y) + Math.sin(rot.degrees) * lx
          grp(r, "Muret_#{side}_#{i + 1}", wx, wy, 0, rot, mat(mur)) { |g| box_geom(g, cm(s1 - s0), cm(t), cm(low_h)) }
        end
        next
      end
      cut = ops.map { |_k, a0, a1, z0, z1| [cm(a0 + off), cm(a1 + off), cm([z0, 0.5].max), cm([z1, h_room - 0.5].min)] }
      grp(r, "Mur_#{side}", cm(x), cm(y), 0, rot, mat(mur)) { |g| wall_geom(g, cm(len), cm(t), cm(h_room), cut) }
      ops.each do |kind, a0, a1, z0, z1|
        next unless kind == "window"
        lx = cm(a0 + off)
        ly = cm(t / 2.0 - 0.5)
        wx = cm(x) + Math.cos(rot.degrees) * lx - Math.sin(rot.degrees) * ly
        wy = cm(y) + Math.sin(rot.degrees) * lx + Math.cos(rot.degrees) * ly
        grp(r, "Vitrage_#{side}", wx, wy, cm(z0), rot, mat("verre")) { |g| box_geom(g, cm(a1 - a0), cm(1), cm(z1 - z0)) }
      end
    end
    r
  end

  # ------------------------------------------------------------ accessoires
  def tap(parent, x, yw, z)
    box(parent, "Mitigeur", x - 1.25, yw, z, 2.5, 2.5, 20, mat("chrome"))
    box(parent, "Bec", x - 1, yw, z + 17, 2, 14, 2.5, mat("chrome"))
  end

  # Poignée barre 15 cm (composant partagé) ; x, z = milieu de la barre, yw = face avant.
  def handle(parent, x, yw, z)
    defn = model.definitions["Poignee"]
    unless defn
      defn = model.definitions.add("Poignee")
      top_face(defn.entities, 0, 0, cm(15), cm(2.5), 0).pushpull(cm(1.2))
      defn.entities.grep(Sketchup::Face).each do |f|
        f.material = mat("chrome")
        f.back_material = mat("chrome")
      end
    end
    parent.entities.add_instance(defn, tr(cm(x - 7.5), -cm(yw + 2.5), cm(z - 0.6), 0))
  end

  # ------------------------------------------------------------ cuisine
  # modules : [[:door, 60], [:drawers, 60], [:sink, 80], [:hob, 60], [:oven, 60], [:dishwasher, 60],
  #            [:fridge, 60], [:tall, 60], [:filler, 5]] de gauche à droite vu depuis la pièce.
  # hauts : [[:door, 60], [:hood, 60], [:open, 100]]
  def kitchen_run(parent, name, pos, modules, hauts: nil, start: 0, hauts_start: nil, credence: true,
                  facade: "facade_blanc", plan: "plan_quartz", h_room: 250, poignees: true, k: KIT)
    a = assembly(parent, name, pos)
    fm = mat(facade)
    pm = mat(plan)
    z_plan = k[:socle] + k[:caisson_h]
    z_top = z_plan + k[:plan_ep]
    cur = start
    seg_start = start
    holes = []
    seg = 0

    facade_box = lambda do |nm, fx, fz, fw, fh|
      box(a, nm, fx + k[:jeu], k[:caisson_p], fz + k[:jeu], fw - 2 * k[:jeu], k[:facade], fh - 2 * k[:jeu], fm)
      handle(a, fx + fw / 2.0, k[:caisson_p] + k[:facade], fh > 30 ? fz + fh - 5 : fz + fh / 2.0) if poignees
    end

    close_segment = lambda do |fin|
      if fin - seg_start >= 1
        seg += 1
        hl = holes.map { |hx, hyw, hw, hd| [hx - seg_start, hyw, hw, hd] }
        slab(a, "#{name}_Plan_#{seg}", seg_start, 0, z_plan, fin - seg_start, k[:plan_p], k[:plan_ep], hl, pm)
        box(a, "#{name}_Credence_#{seg}", seg_start, 0, z_top, fin - seg_start, 1, k[:credence_h], mat("credence")) if credence
      end
      holes = []
    end

    modules.each_with_index do |(kind, w), i|
      kind = kind.to_s
      nm = format("%s_%02d_%s", name, i + 1, kind)
      if kind == "filler"
        box(a, nm, cur, k[:caisson_p] - 2, k[:socle], w, k[:facade] + 2, k[:caisson_h], fm)
        cur += w
        next
      end
      if kind == "fridge" || kind == "tall"
        close_segment.call(cur)
        box(a, "#{nm}_Caisson", cur, 0, 0, w, k[:colonne_p] - k[:facade], k[:colonne_h], fm)
        top_h = k[:colonne_h] * 0.62
        box(a, "#{nm}_Porte_Haute", cur + k[:jeu], k[:colonne_p] - k[:facade], k[:colonne_h] - top_h + k[:jeu],
            w - 2 * k[:jeu], k[:facade], top_h - 2 * k[:jeu], fm)
        box(a, "#{nm}_Porte_Basse", cur + k[:jeu], k[:colonne_p] - k[:facade], k[:jeu],
            w - 2 * k[:jeu], k[:facade], k[:colonne_h] - top_h - 2 * k[:jeu], fm)
        if poignees
          handle(a, cur + w / 2.0, k[:colonne_p], k[:colonne_h] - top_h + 6)
          handle(a, cur + w / 2.0, k[:colonne_p], k[:colonne_h] - top_h - 6)
        end
        cur += w
        seg_start = cur
        next
      end
      box(a, "#{nm}_Socle", cur, 0, 0, w, k[:caisson_p] - k[:retrait], k[:socle], mat("facade_noir"))
      box(a, "#{nm}_Caisson", cur, 0, k[:socle], w, k[:caisson_p], k[:caisson_h], fm)
      case kind
      when "drawers"
        fz = k[:socle]
        [0.22, 0.39, 0.39].each do |frac|
          fh = k[:caisson_h] * frac
          facade_box.call("#{nm}_Tiroir", cur, fz, w, fh)
          fz += fh
        end
      when "oven"
        fh_drawer = k[:caisson_h] - 60
        facade_box.call("#{nm}_Tiroir", cur, k[:socle], w, fh_drawer)
        box(a, "#{nm}_Four", cur + k[:jeu], k[:caisson_p], k[:socle] + fh_drawer + k[:jeu],
            w - 2 * k[:jeu], k[:facade], 60 - 2 * k[:jeu], mat("noir_appareil"))
        box(a, "#{nm}_Four_Poignee", cur + 4, k[:caisson_p] + k[:facade], k[:socle] + k[:caisson_h] - 8,
            w - 8, 2.5, 1.5, mat("chrome"))
      when "dishwasher"
        box(a, "#{nm}_Facade", cur + k[:jeu], k[:caisson_p], k[:socle] + k[:jeu],
            w - 2 * k[:jeu], k[:facade], k[:caisson_h] - 2 * k[:jeu], fm)
        handle(a, cur + w / 2.0, k[:caisson_p] + k[:facade], k[:socle] + k[:caisson_h] - 5) if poignees
      else
        if w > 65
          facade_box.call("#{nm}_Porte_G", cur, k[:socle], w / 2.0, k[:caisson_h])
          facade_box.call("#{nm}_Porte_D", cur + w / 2.0, k[:socle], w / 2.0, k[:caisson_h])
        else
          facade_box.call("#{nm}_Porte", cur, k[:socle], w, k[:caisson_h])
        end
      end
      if kind == "sink"
        bw = [w - 10, 80].min
        bd = 40
        hx0 = cur + (w - bw) / 2.0
        holes << [hx0, 10, bw, bd]
        hollow(a, "#{nm}_Cuve", hx0, 10, z_top - 18, bw, bd, 18, 1, 17, mat("inox"))
        tap(a, cur + w / 2.0, 3, z_top)
      end
      if kind == "hob"
        box(a, "#{nm}_Plaque", cur + (w - 58) / 2.0, 7, z_top, 58, 51, 0.6, mat("noir_appareil"))
      end
      cur += w
    end
    fin = cur
    close_segment.call(fin)

    if hauts
      hc = hauts_start || start
      hauts.each_with_index do |(kind, w), i|
        kind = kind.to_s
        nm = format("%s_Haut_%02d_%s", name, i + 1, kind)
        case kind
        when "door"
          box(a, "#{nm}_Caisson", hc, 0, k[:haut_z], w, k[:haut_p], k[:haut_h], fm)
          box(a, "#{nm}_Porte", hc + k[:jeu], k[:haut_p], k[:haut_z] + k[:jeu],
              w - 2 * k[:jeu], k[:facade], k[:haut_h] - 2 * k[:jeu], fm)
          handle(a, hc + w / 2.0, k[:haut_p] + k[:facade], k[:haut_z] + 5) if poignees
        when "hood"
          box(a, "#{nm}_Corps", hc + (w - 60) / 2.0, 0, k[:hotte_z], 60, 50, 8, mat("inox"))
          box(a, "#{nm}_Cheminee", hc + w / 2.0 - 12.5, 0, k[:hotte_z] + 8, 25, 30, h_room - k[:hotte_z] - 8, mat("inox"))
        end
        hc += w
      end
    end
    [a, fin]
  end

  # Îlot : pos = [x, y, rot] de son coin arrière-gauche, il s'étend vers -Y local.
  def island(parent, name, pos, l: 200, p: 100, facade: "facade_chene", plan: "plan_quartz", k: KIT, hob: false)
    a = assembly(parent, name, pos)
    z_plan = k[:socle] + k[:caisson_h]
    box(a, "#{name}_Socle", 5, 5, 0, l - 10, p - 10, k[:socle], mat("facade_noir"))
    box(a, "#{name}_Caisson", 2.5, 2.5, k[:socle], l - 5, p - 5, k[:caisson_h], mat(facade))
    box(a, "#{name}_Plan", 0, 0, z_plan, l, p, k[:plan_ep], mat(plan))
    box(a, "#{name}_Plaque", l / 2.0 - 29, p / 2.0 - 25, z_plan + k[:plan_ep], 58, 51, 0.6, mat("noir_appareil")) if hob
    a
  end

  # ------------------------------------------------------------ salle de bain
  def vanity(parent, name, pos, w: 80, d: 48, h_plan: 85, facade: "facade_chene", plan: "plan_quartz", miroir: true)
    a = assembly(parent, name, pos)
    zc = h_plan - 3 - 50
    box(a, "#{name}_Caisson", 0, 0, zc, w, d - 4, 50, mat(facade))
    box(a, "#{name}_Facade_Haut", 0.3, d - 4, zc + 25.3, w - 0.6, 2, 24.4, mat(facade))
    box(a, "#{name}_Facade_Bas", 0.3, d - 4, zc + 0.3, w - 0.6, 2, 24.4, mat(facade))
    bw = [50, w - 16].min
    bd = [38, d - 10].min
    x0 = (w - bw) / 2.0
    y0 = (d - bd) / 2.0
    slab(a, "#{name}_Plan", 0, 0, h_plan - 3, w, d, 3, [[x0, y0, bw, bd]], mat(plan))
    hollow(a, "#{name}_Vasque", x0, y0, h_plan - 15, bw, bd, 15, 1, 14, mat("ceramique"))
    tap(a, w / 2.0, 3, h_plan)
    box(a, "#{name}_Miroir", 5, 0, h_plan + 15, w - 10, 1, 80, mat("miroir")) if miroir
    a
  end

  # WC à poser : encombrement 40 × 66 cm.
  def toilet(parent, name, pos)
    a = assembly(parent, name, pos)
    box(a, "#{name}_Reservoir", 1, 0, 40, 38, 18, 40, mat("ceramique"))
    box(a, "#{name}_Bouton", 17, 18, 72, 6, 0.8, 4, mat("chrome"))
    rounded(a, "#{name}_Cuvette", 2, 14, 0, 36, 52, 40, 15, mat("ceramique"))
    rounded(a, "#{name}_Abattant", 2, 18, 40, 36, 46, 3, 15, mat("ceramique"))
    a
  end

  def bathtub(parent, name, pos, l: 170, w: 75, h: 58)
    a = assembly(parent, name, pos)
    hollow(a, "#{name}_Cuve", 0, 0, 0, l, w, h, 5, 45, mat("ceramique"))
    box(a, "#{name}_Mitigeur", l - 40, 0, 72, 22, 8, 7, mat("chrome"))
    box(a, "#{name}_Bec", l - 31, 8, 74, 4, 14, 3, mat("chrome"))
    a
  end

  # Douche d'angle : paroi = côté libre ("right" ou "left", vu depuis la pièce).
  def shower(parent, name, pos, w: 90, d: 90, paroi: "right", porte: true)
    a = assembly(parent, name, pos)
    hollow(a, "#{name}_Receveur", 0, 0, 0, w, d, 4, 3, 2.5, mat("ceramique"))
    px = paroi.to_s == "right" ? w - 0.8 : 0
    box(a, "#{name}_Paroi", px, 0, 4, 0.8, d, 196, mat("verre"))
    box(a, "#{name}_Porte", 2, d - 0.8, 4, w - 4, 0.8, 196, mat("verre")) if porte
    box(a, "#{name}_Barre", w / 2.0 - 1.25, 2, 90, 2.5, 2.5, 110, mat("chrome"))
    box(a, "#{name}_Mitigeur", w / 2.0 - 10, 0, 100, 20, 6, 6, mat("chrome"))
    box(a, "#{name}_Pommeau", w / 2.0 - 10, 2, 198, 20, 20, 2, mat("chrome"))
    a
  end

  def radiator(parent, name, pos, w: 50, h: 120, z: 25)
    a = assembly(parent, name, pos)
    box(a, "#{name}_Corps", 0, 3, z, w, 5, h, mat("ceramique"))
    a
  end

  def washer(parent, name, pos)
    a = assembly(parent, name, pos)
    box(a, "#{name}_Corps", 0, 0, 0, 60, 60, 85, mat("ceramique"))
    box(a, "#{name}_Hublot", 12.5, 60, 20, 35, 1, 35, mat("noir_appareil"))
    box(a, "#{name}_Bandeau", 2, 60, 72, 56, 0.6, 10, mat("inox"))
    a
  end

  def shelf(parent, name, pos, z: 120, w: 60, d: 25, h: 1.8, m: "facade_chene")
    a = assembly(parent, name, pos)
    box(a, "#{name}_Tablette", 0, 0, z, w, d, h, mat(m))
    a
  end

  # ------------------------------------------------------------ style et caméra
  def style_interieur(ombres = true)
    ro = model.rendering_options
    ro["BackgroundColor"] = Sketchup::Color.new(255, 255, 255)
    ro["FaceFrontColor"] = Sketchup::Color.new(240, 238, 232)
    ro["FaceBackColor"] = Sketchup::Color.new(150, 155, 165)
    ro["ForegroundColor"] = Sketchup::Color.new(60, 58, 55)
    ro["EdgeDisplayMode"] = 1
    ro["RenderMode"] = 2
    ro["ModelTransparency"] = false
    ro["DrawDepthQue"] = false
    ro["DrawSilhouettes"] = true
    ro["SilhouetteWidth"] = 2
    ro["DrawHorizon"] = false
    ro["DrawGround"] = false
    ro["DisplaySketchAxes"] = false
    si = model.shadow_info
    si["DisplayShadows"] = ombres
    if ombres
      si["Light"] = 75
      si["Dark"] = 55
    end
    true
  end

  # Boîte englobante (pouces) d'une pièce créée par room(), pour les caméras.
  def bb_room(w_room, d_room, h_room = 250, t = 12)
    [cm(-t), cm(-t), cm(-2), cm(w_room + t), cm(d_room + t), cm(h_room)]
  end

  def set_cam(eye, target, fov)
    cam = Sketchup::Camera.new(Geom::Point3d.new(*eye), Geom::Point3d.new(*target), Z_AXIS, true, fov)
    model.active_view.camera = cam
    cam
  end

  # Vue 3/4 plongeante "maquette ouverte". azimut 45 → regarde vers back+left, 135 → back+right, 90 → de face.
  def camera_maquette(bb, azimut: 45, elevation: 35, fov: 45, aspect: 1.6, marge: 1.15)
    xmin, ymin, zmin, xmax, ymax, zmax = bb
    cx = (xmin + xmax) / 2.0
    cy = (ymin + ymax) / 2.0
    cz = (zmin + zmax) / 2.0
    w = xmax - xmin
    d = ymax - ymin
    h = zmax - zmin
    az = azimut.degrees
    el = elevation.degrees
    dx = Math.cos(az) * Math.cos(el)
    dy = -Math.sin(az) * Math.cos(el)
    dz = Math.sin(el)
    rl = Math.sqrt(dx * dx + dy * dy)
    rx = -dy / rl
    ry = dx / rl
    rz = 0.0
    ux = dy * rz - dz * ry
    uy = dz * rx - dx * rz
    uz = dx * ry - dy * rx
    hext = rx.abs * w + ry.abs * d + rz.abs * h
    vext = ux.abs * w + uy.abs * d + uz.abs * h
    hv = (fov / 2.0).degrees
    hh = Math.atan(aspect * Math.tan(hv))
    dist = [vext / 2.0 / Math.tan(hv), hext / 2.0 / Math.tan(hh)].max * marge
    set_cam([cx + dist * dx, cy + dist * dy, cz + dist * dz], [cx, cy, zmin + h * 0.3], fov)
  end

  # Vue intérieure à hauteur d'œil depuis un coin ("front-right", "front-left", "back-right", "back-left").
  def camera_interieure(bb, coin: "front-right", fov: 62, oeil: 160)
    xmin, ymin, zmin, xmax, ymax, _zmax = bb
    w = xmax - xmin
    d = ymax - ymin
    fx = coin.include?("left") ? 0.12 : 0.88
    fy = coin.include?("front") ? 0.12 : 0.88
    set_cam([xmin + w * fx, ymin + d * fy, zmin + cm(oeil)],
            [xmin + w * (1 - fx), ymin + d * (1 - fy), zmin + cm(110)], fov)
  end

  # Enregistre au format de la version de SketchUp en cours (2019 → fichier 2019).
  def save_as(path)
    model.save(path)
  end

  # Exécute un scénario dans une opération annulable d'un seul Ctrl+Z ; en cas d'erreur, tout est annulé.
  def run(nom = "Cuisine / salle de bain")
    model.start_operation(nom, true)
    begin
      yield
      model.commit_operation
    rescue StandardError => e
      model.abort_operation
      raise e
    end
    model.active_view.invalidate
    true
  end
end

include CuisineSdb

# ============================ SCÉNARIO : salle de bain 300 × 220 ============================
run("Salle de bain") do
  w, d, h = 300, 220, 250
  room(model, w, d, h, full: ["back", "left"],
       openings: { "left" => [["window", 40, 130, 120, 200]], "front" => [["door", 20, 103, 1, 210]] })
  bathtub(model, "Baignoire", on_wall("left", 0, w, d))
  toilet(model, "WC", on_wall("back", 90, w, d))
  vanity(model, "Meuble_Vasque", on_wall("back", 140, w, d), w: 60)
  shower(model, "Douche", on_wall("back", 210, w, d), w: 90, d: 90, paroi: "left")
  radiator(model, "Seche_Serviettes", on_wall("left", 175, w, d), w: 40)
  washer(model, "Lave_Linge", on_wall("front", 0, w, d))
  style_interieur(true)
  camera_maquette(bb_room(w, d, h), azimut: 45)
end
