# Sans connecteur Trimble SketchUp : script Ruby pour SketchUp Desktop

Si la session n'a pas accès aux outils `mcp__Trimble_SketchUp__*`, livre à l'utilisateur un script
Ruby à coller dans **Fenêtre → Console Ruby** de SketchUp (Make ou Pro, 2017+). Les conventions
sont les mêmes que le toolkit Python (cm, pièce W × D, murs back/left/right/front, modules de
gauche à droite), seule la mécanique change : ici l'API Ruby fait les extrusions (`pushpull`) et les
découpes se font en dessinant la face de l'ouverture sur le mur.

```ruby
# ---- helpers (cm → pouces, SketchUp travaille en pouces en interne)
def cm(v) v.to_f / 2.54 end
MODEL = Sketchup.active_model
MATS = {}
def mat(name, rgb)
  MATS[name] ||= begin
    m = MODEL.materials.add(name); m.color = Sketchup::Color.new(*rgb); m
  end
end
# boîte w×d×h (cm) dans le groupe parent, coin arrière-gauche en (x, yw, z) exprimé dans le repère
# "mur" (yw = distance au mur, l'objet s'étend vers -Y)
def box(parent, name, x, yw, z, w, d, h, material = nil)
  g = parent.entities.add_group; g.name = name
  pts = [[cm(x), -cm(yw + d), cm(z)], [cm(x + w), -cm(yw + d), cm(z)],
         [cm(x + w), -cm(yw), cm(z)], [cm(x), -cm(yw), cm(z)]]
  f = g.entities.add_face(pts); f.reverse! if f.normal.z < 0
  f.pushpull(cm(h))
  g.material = material if material
  g
end
def assembly(parent, name, x, y, rot)
  g = parent.entities.add_group; g.name = name
  tr = Geom::Transformation.new([cm(x), cm(y), 0]) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, rot.degrees)
  g.transformation = tr
  g
end
def on_wall(wall, a, w_room, d_room)
  case wall
  when "back"  then [a, d_room, 0]
  when "left"  then [0, a, 90]
  when "right" then [w_room, d_room - a, 270]
  when "front" then [w_room - a, 0, 180]
  end
end

# ---- ligne de meubles bas (socle, caisson, façades) + plan de travail
KIT = {socle: 10, retrait: 5, caisson_h: 76, caisson_p: 58, facade: 2, plan_ep: 4, plan_p: 65}
def kitchen_run(parent, name, pos, modules, facade_rgb = [246, 246, 243], plan_rgb = [236, 234, 229])
  a = assembly(parent, name, *pos)
  fm = mat("facade_#{name}", facade_rgb); pm = mat("plan_#{name}", plan_rgb)
  cur = 0
  modules.each_with_index do |(kind, w), i|
    nm = "#{name}_#{'%02d' % (i + 1)}_#{kind}"
    if %w[fridge tall].include?(kind)
      box(a, nm, cur, 0, 0, w, 60, 220, fm)
    else
      box(a, "#{nm}_Socle", cur, 0, 0, w, KIT[:caisson_p] - KIT[:retrait], KIT[:socle], mat("socle", [45, 45, 48]))
      box(a, "#{nm}_Caisson", cur, 0, KIT[:socle], w, KIT[:caisson_p], KIT[:caisson_h], fm)
      box(a, "#{nm}_Facade", cur + 0.3, KIT[:caisson_p], KIT[:socle] + 0.3, w - 0.6, KIT[:facade], KIT[:caisson_h] - 0.6, fm)
    end
    cur += w
  end
  # plan de travail d'un seul tenant (à découper à la main sous les colonnes)
  box(a, "#{name}_Plan", 0, 0, KIT[:socle] + KIT[:caisson_h], cur, KIT[:plan_p], KIT[:plan_ep], pm)
  a
end

# ---- pièce : sol + murs pleins back/left (ouvertures à dessiner ensuite avec l'outil Rectangle)
def room(w, d, h = 250, t = 12)
  r = MODEL.entities.add_group; r.name = "Piece"
  box(r, "Sol", -t, -t, -2, w + 2 * t, d + 2 * t, 2, mat("sol", [190, 190, 186]))
  box(r, "Mur_back", -t, -(d + t), 0, w + 2 * t, t, h, mat("mur", [240, 238, 232]))   # yw négatif = au-delà de y=D
  box(r, "Mur_left", -t, -d, 0, t, d, h, mat("mur", [240, 238, 232]))
  r
end

MODEL.start_operation("Cuisine", true)
W, D, H = 360, 300, 250
room(W, D, H)
kitchen_run(MODEL, "Ligne_Fond", on_wall("back", 0, W, D),
            [["door", 60], ["hob", 60], ["drawers", 60], ["sink", 80], ["dishwasher", 60], ["door", 40]])
kitchen_run(MODEL, "Ligne_Gauche", on_wall("left", 0, W, D),
            [["fridge", 60], ["tall", 60], ["oven", 60], ["drawers", 55]], [205, 175, 130])
MODEL.commit_operation
MODEL.active_view.zoom_extents
```

Limites de cette version Ruby : les ouvertures (porte, fenêtre), l'évier encastré et les sanitaires
ne sont pas générés — explique à l'utilisateur comment les ajouter (Rectangle sur la face du mur +
Pousser/Tirer pour une ouverture ; composants 3D Warehouse pour les sanitaires), ou ajoute des
fonctions `box` supplémentaires sur le même modèle que `kitchen_run`. Propose aussi, si possible,
de reprendre la conversation dans une session qui dispose du connecteur Trimble SketchUp.
