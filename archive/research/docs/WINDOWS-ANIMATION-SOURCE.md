# Animation-source mapping qualification

The earlier root delta was `Unit.delta_pose`, which describes movement already
applied to a node. Agreement with consecutive actual matrices is therefore not
proof that this value drives the rotation. The
[AnimationBlenderComponent reference](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_AnimationBlenderComponent.html)
documents a separate `delta_transform(component, entity)` getter for requested
animation motion. It requires an entity that owns that component; a legacy Unit
handle cannot be substituted for the entity.

The read-only mapper first tries to establish a complete unique chain from a
qualified 107-node Helldiver Unit through UnitComponent to an entity and then
to exactly one animation-blender component. It checks at most 4096 world
entities, eight per update with a 2 ms target and 8 ms stop limit. Incomplete,
ambiguous, unsupported or retired mappings never reach the animation getter.
Instance IDs and unit association are rechecked at each existing capture
sample; only copied scalar matrices survive callbacks. No time, physics,
animation, transform or visibility setter is called.

The mapping scan is enabled only by the existing explicit Freeze-observer
marker. It runs before that capture's baseline. A completed or unsupported
lookup stays idle. The root trace continues if no mapping exists, recording
that limitation without claiming a source. This is qualification work; live
animation-source access is not established by the offline fixtures.

Live generation `c656ed0987cd4d4fa6022748965a290d` completed the lookup at
20:01:06 on 2026-10-26: 313 entities, zero linked target units, zero qualified
animation blenders, maximum mapping step 1 ms, no writes. The subsequent
read-only Freeze capture completed with zero errors and a maximum step of 2 ms.
This inventory did not expose the required Unit-to-entity association, so the
requested-animation getter was not reached. This does not prove that no other
game API exposes the source. Repeating this same inventory is not a fix.
