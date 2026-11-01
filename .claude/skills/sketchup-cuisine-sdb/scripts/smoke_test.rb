# Test de fumée hors SketchUp : simule le strict minimum de l'API Ruby SketchUp pour vérifier
# que cuisine_sdb.rb s'exécute de bout en bout (noms de méthodes, arités, flux). Il ne valide pas
# le rendu géométrique réel — seul SketchUp le fait.
#   ruby smoke_test.rb
module Geom
  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      @x, @y, @z = x.to_f, y.to_f, z.to_f
    end
    def to_a; [x, y, z]; end
    def -(o); Vector3d.new(x - o.x, y - o.y, z - o.z); end
  end
  class Vector3d < Point3d
    def cross(v); Vector3d.new(y * v.z - z * v.y, z * v.x - x * v.z, x * v.y - y * v.x); end
    def length; Math.sqrt(x * x + y * y + z * z); end
    def normalize; l = length; l.zero? ? self : Vector3d.new(x / l, y / l, z / l); end
  end
  class Transformation
    attr_reader :origin, :rot
    def initialize(pt = nil); @origin = pt || Point3d.new; @rot = 0.0; end
    def self.rotation(_o, _axis, angle); t = new; t.instance_variable_set(:@rot, angle); t; end
    def *(o); t = Transformation.new(@origin); t.instance_variable_set(:@rot, @rot + o.rot); t; end
  end
end
ORIGIN = Geom::Point3d.new
Z_AXIS = Geom::Vector3d.new(0, 0, 1)
class Numeric; def degrees; self * Math::PI / 180.0; end; end

module Sketchup
  class Color; def initialize(r, g, b); @rgb = [r, g, b]; end; end
  class Material
    attr_reader :name; attr_accessor :color, :alpha
    def initialize(n); @name = n; end
  end
  class Materials
    def initialize; @list = {}; end
    def [](n); @list[n]; end
    def add(n); @list[n] = Material.new(n); end
    def count; @list.size; end
  end
  class Face
    attr_reader :points, :pushed; attr_accessor :material, :back_material
    def initialize(points)
      raise "face: #{points.size} points" if points.size < 3
      @points = points; @pushed = nil
      a = points[1] - points[0]; b = points[2] - points[0]
      @normal = a.cross(b).normalize
      raise "face dégénérée" if @normal.length.zero?
    end
    def normal; @normal; end
    def reverse!; @normal = Geom::Vector3d.new(-@normal.x, -@normal.y, -@normal.z); self; end
    def pushpull(d); raise "pushpull nul" if d.zero?; @pushed = d; nil; end
  end
  class Edge; end
  class Entities
    attr_reader :items
    def initialize(model); @model = model; @items = []; end
    def add_group; g = Group.new(@model); @items << g; g; end
    def add_face(*args)
      pts = (args.size == 1 && args[0].is_a?(Array) && args[0][0].is_a?(Array)) ? args[0] : args
      pts = pts.map { |p| p.is_a?(Geom::Point3d) ? p : Geom::Point3d.new(*p) }
      f = Face.new(pts); @items << f; f
    end
    def add_instance(defn, tr); raise "instance sans définition" unless defn; i = [defn, tr]; @items << i; i; end
    def grep(k); @items.select { |i| i.is_a?(k) }; end
  end
  class Group
    attr_reader :entities; attr_accessor :name, :transformation, :material
    def initialize(model); @entities = Entities.new(model); end
  end
  class ComponentDefinition
    attr_reader :entities, :name
    def initialize(model, n); @entities = Entities.new(model); @name = n; end
  end
  class DefinitionList
    def initialize(model); @model = model; @list = {}; end
    def [](n); @list[n]; end
    def add(n); @list[n] = ComponentDefinition.new(@model, n); end
  end
  class Camera
    attr_reader :fov
    def initialize(eye, target, up, persp, fov)
      raise "caméra" unless eye.is_a?(Geom::Point3d) && target.is_a?(Geom::Point3d) && persp
      @fov = fov
    end
  end
  class View; attr_accessor :camera; def invalidate; end; def zoom_extents; end; end
  class Model
    attr_reader :entities, :materials, :definitions, :rendering_options, :shadow_info, :active_view, :ops
    def initialize
      @entities = Entities.new(self); @materials = Materials.new; @definitions = DefinitionList.new(self)
      @rendering_options = {}; @shadow_info = {}; @active_view = View.new; @ops = []
    end
    def start_operation(n, _d = false); @ops << [:start, n]; end
    def commit_operation; @ops << [:commit]; end
    def abort_operation; @ops << [:abort]; end
    def save(path, *_v); @ops << [:save, path]; true; end
  end
  def self.active_model; @m ||= Model.new; end
  def self.reset!; @m = Model.new; end
  def self.version; "19.0.685"; end
end

load File.join(__dir__, "cuisine_sdb.rb")

def stats(ents, acc = Hash.new(0))
  ents.items.each do |i|
    case i
    when Sketchup::Group then acc[:groups] += 1; stats(i.entities, acc)
    when Sketchup::Face then acc[:faces] += 1; acc[:pushpulls] += 1 if i.pushed
    when Array then acc[:instances] += 1
    end
  end
  acc
end

# --- scénario 1 : cuisine en L
Sketchup.reset!
run("Cuisine L") do
  w, d, h = 360, 300, 250
  room(model, w, d, h, full: ["back", "left"],
       openings: { "back" => [["window", 200, 300, 110, 210]], "front" => [["door", 250, 333, 1, 210]] },
       sol: "sol_parquet")
  _a, fin_a = kitchen_run(model, "Ligne_Fond", on_wall("back", 0, w, d),
                          [[:door, 60], [:hob, 60], [:drawers, 60], [:sink, 80], [:dishwasher, 60], [:door, 40]],
                          hauts: [[:door, 60], [:hood, 60], [:door, 80], [:open, 100], [:door, 60]], h_room: h)
  _b, fin_b = kitchen_run(model, "Ligne_Gauche", on_wall("left", 0, w, d),
                          [[:fridge, 60], [:tall, 60], [:oven, 60], [:drawers, 55]], facade: "facade_chene", h_room: h)
  island(model, "Ilot", [100, 150, 0], l: 180, p: 90, hob: false)
  raise "fin_a" unless fin_a == 360
  raise "fin_b" unless fin_b == 235
  style_interieur(true)
  camera_maquette(bb_room(w, d, h), azimut: 45)
end
s = stats(model.entities)
puts "cuisine : #{s.inspect}, matériaux=#{model.materials.count}, ops=#{model.ops.map(&:first).inspect}, fov=#{model.active_view.camera.fov}"
raise "pas de commit" unless model.ops.last == [:commit]
top = model.entities.items.grep(Sketchup::Group).map(&:name)
puts "  racine : #{top.inspect}"
piece = model.entities.items.grep(Sketchup::Group).find { |g| g.name == "Piece" }
puts "  pièce  : #{piece.entities.items.grep(Sketchup::Group).map(&:name).inspect}"

# --- scénario 2 : salle de bain
Sketchup.reset!
run("SdB") do
  w, d, h = 300, 220, 250
  room(model, w, d, h, openings: { left: [[:window, 40, 130, 120, 200]], front: [[:door, 20, 103, 1, 210]] })
  bathtub(model, "Baignoire", on_wall("left", 0, w, d))
  toilet(model, "WC", on_wall("back", 90, w, d))
  vanity(model, "Meuble_Vasque", on_wall("back", 140, w, d), w: 60)
  shower(model, "Douche", on_wall("back", 210, w, d), w: 90, d: 90, paroi: "left")
  radiator(model, "Seche_Serviettes", on_wall("left", 175, w, d), w: 40)
  washer(model, "Lave_Linge", on_wall("front", 0, w, d))
  shelf(model, "Tablette", on_wall("right", 50, w, d))
  style_interieur(false)
  camera_interieure(bb_room(w, d, h), coin: "front-right")
  save_as("C:/tmp/sdb.skp")
end
s = stats(model.entities)
puts "sdb     : #{s.inspect}, matériaux=#{model.materials.count}, ops=#{model.ops.map(&:first).inspect}"
raise "pas de commit" unless model.ops.last == [:commit]

# --- scénario 3 : une erreur annule l'opération
Sketchup.reset!
begin
  run("Erreur") { box(model, "X", 0, 0, 0, 10, 10, 0) }
rescue StandardError => e
  puts "erreur attendue : #{e.message} → ops=#{model.ops.map(&:first).inspect}"
end
raise "pas d'abort" unless model.ops.last == [:abort]
puts "SMOKE TEST OK"
