class_name StaticBatch
extends RefCounted
## Many static collision shapes in one physics body, without scene nodes.
## Used for thousands of tree trunks, rocks and bushes. Shapes are collected
## first and the body is added to the space once, in commit().

var body: RID
var shapes: Array[Shape3D] = []
var _layer: int
var _owner_id: int


func _init(layer: int, owner: Object) -> void:
	_layer = layer
	_owner_id = owner.get_instance_id()
	body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(body, layer)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_attach_object_instance_id(body, _owner_id)


func add(shape: Shape3D, xform: Transform3D) -> void:
	shapes.append(shape)
	PhysicsServer3D.body_add_shape(body, shape.get_rid(), xform)


func count() -> int:
	return shapes.size()


func commit(space: RID) -> void:
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	PhysicsServer3D.body_set_space(body, space)


func release() -> void:
	if body.is_valid():
		PhysicsServer3D.free_rid(body)
	body = RID()
	shapes.clear()
