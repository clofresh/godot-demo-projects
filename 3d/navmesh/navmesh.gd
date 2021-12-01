extends Navigation

const Cylinder = preload('res://cylinder.tscn')

const SPEED = 10.0

var camrot = 0.0
var m = SpatialMaterial.new()

var show_path = true
var navmesh_dirty = false
export var navmesh_bake_delay = 0.1
var navmesh_bake_delay_timer = 0.0
var bake_ready = true
var bake_start_time = 0.0

onready var robot  = get_node("RobotBase")
onready var camera = get_node("CameraBase/Camera")
onready var navagent = get_node("RobotBase/NavigationAgent")
onready var navmesh = get_node("NavigationMeshInstance_Level")

func _ready():
	set_process_input(true)
	m.flags_unshaded = true
	m.flags_use_point_size = true
	m.albedo_color = Color.white
	navagent.connect("path_changed", self, "on_path_changed")
	navmesh.connect("bake_finished", self, "on_bake_finished")

func _process(delta):
	if navmesh_dirty:
		navmesh_bake_delay_timer += delta
		if navmesh_bake_delay_timer > navmesh_bake_delay:
			if bake_ready:
				bake_ready = false
				bake_start_time = OS.get_ticks_msec()
				navmesh.bake_navigation_mesh()
				navmesh_dirty = false
				navmesh_bake_delay_timer = 0.0

func _physics_process(delta):
	if navagent.is_navigation_finished():
		return
	var direction = Vector3()

	# We need to scale the movement speed by how much delta has passed,
	# otherwise the motion won't be smooth.
	var step_size = delta * SPEED
	var destination = navagent.get_next_location()
	# Direction is the difference between where we are now
	# and where we want to go.
	direction = destination - robot.translation
	# Move the robot towards the path node, by how far we want to travel.
	# Note: For a KinematicBody, we would instead use move_and_slide
	# so collisions work properly.
	var vel = direction.normalized() * step_size
	navagent.set_velocity(vel)

	# Lastly let's make sure we're looking in the direction we're traveling.
	# Clamp y to 0 so the robot only looks left and right, not up/down.
	direction.y = 0
	if direction:
		# Direction is relative, so apply it to the robot's location to
		# get a point we can actually look at.
		var look_at_point = robot.translation + direction.normalized()
		# Make the robot look at the point.
		robot.look_at(look_at_point, Vector3.UP)

func _on_NavigationAgent_velocity_computed(vel):
	robot.translation += vel


func _unhandled_input(event):
	if event is InputEventMouseButton:
		var from = camera.project_ray_origin(event.position)
		var to = from + camera.project_ray_normal(event.position) * 1000
		var target_point = get_closest_point_to_segment(from, to)
		if event.button_index == BUTTON_LEFT and event.pressed:
			# Set the path between the robots current location and our target.
			navagent.set_target_location(target_point)
			get_tree().set_input_as_handled()
		elif event.button_index == BUTTON_RIGHT and event.pressed:
			var space_state = get_world().direct_space_state

			var result = space_state.intersect_ray(from, to)
			if result:
				remove_cylinder(result.collider.get_parent())
			else:
				add_cylinder(target_point)
			get_tree().set_input_as_handled()

	if event is InputEventMouseMotion:
		if event.button_mask & BUTTON_MASK_MIDDLE:
			camrot += event.relative.x * 0.005
			get_node("CameraBase").set_rotation(Vector3(0, camrot, 0))
			print("Camera Rotation: ", camrot)
			get_tree().set_input_as_handled()


func add_cylinder(pos):
	var cylinder = Cylinder.instance()
	print("adding cylinder %s" % cylinder.name)
	cylinder.transform.origin = pos
	navmesh.add_child(cylinder)
	navmesh_bake_delay_timer = 0.0
	navmesh_dirty = true

func remove_cylinder(cylinder):
	print("removing cylinder %s" % [cylinder.name])
	navmesh.remove_child(cylinder)
	navmesh_bake_delay_timer = 0.0
	navmesh_dirty = true

func on_path_changed():
	var path_array = navagent.get_nav_path()
	if path_array.size() == 0:
		return
	var im = get_node("Draw")
	im.set_material_override(m)
	im.clear()
	im.begin(Mesh.PRIMITIVE_POINTS, null)
	im.add_vertex(path_array[0])
	im.add_vertex(path_array[path_array.size() - 1])
	im.end()
	im.begin(Mesh.PRIMITIVE_LINE_STRIP, null)
	for x in path_array:
		im.add_vertex(x)
	im.end()

func on_bake_finished():
	bake_ready = true
	print('Navmesh baked in %.2fms' % (OS.get_ticks_msec() - bake_start_time))
