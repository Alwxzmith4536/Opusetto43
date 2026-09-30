"""
Export saitama_vs_cosmic_garou.blend for the WebGL player in web/.

    blender --background saitama_vs_cosmic_garou.blend --python export_web.py

Writes web/scene.json (objects, meshes, bones, materials, curve index) and
web/scene.bin.txt (float32 mesh + keyframe data, gzipped and base64-encoded). Keyframes are exported as-is
(with Bezier handles), so the browser evaluates the exact same animation curves.
"""
import bpy
import json
import os
import struct
import gzip
import base64

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get('WEB_OUT') or os.path.join(HERE, 'web')
INTERP = {'CONSTANT': 0, 'LINEAR': 1, 'BEZIER': 2}

buf = bytearray()


def put_f32(values):
    off = len(buf) // 4
    buf.extend(struct.pack('<%df' % len(values), *values))
    return off


def put_u32(values):
    off = len(buf) // 4
    buf.extend(struct.pack('<%dI' % len(values), *values))
    return off


def fcurves_of(id_):
    ad = getattr(id_, 'animation_data', None)
    if not ad or not ad.action:
        return []
    act = ad.action
    try:
        from bpy_extras import anim_utils
        cb = anim_utils.action_get_channelbag_for_slot(act, ad.action_slot)
        if cb is not None:
            return list(cb.fcurves)
    except Exception:
        pass
    return list(getattr(act, 'fcurves', []))


def curve(fc):
    kps = fc.keyframe_points
    n = len(kps)
    xs, ys, it, hs = [], [], [], []
    bez = False
    for kp in kps:
        xs.append(kp.co.x)
        ys.append(kp.co.y)
        it.append(INTERP.get(kp.interpolation, 2))
        hs += [kp.handle_left.x, kp.handle_left.y, kp.handle_right.x, kp.handle_right.y]
        bez = bez or kp.interpolation == 'BEZIER'
    c = {'p': fc.data_path, 'i': fc.array_index, 'n': n, 'x': put_f32(xs), 'y': put_f32(ys), 't': put_f32(it)}
    if bez:
        c['h'] = put_f32(hs)
    return c


def flat(m):
    return [round(m[r][c], 6) for c in range(4) for r in range(4)]  # column-major, like three.js


def mat_info(mat):
    if mat is None:
        return {'kind': 'toon', 'color': [0.8, 0.8, 0.8], 'shade': [0.6, 0.6, 0.6]}
    nodes = mat.node_tree.nodes if mat.node_tree else []
    types = {n.bl_idname for n in nodes}
    if 'ShaderNodeObjectInfo' in types:
        em = next(n for n in nodes if n.bl_idname == 'ShaderNodeEmission')
        return {'kind': 'fx', 'strength': em.inputs['Strength'].default_value}
    if 'ShaderNodeTexVoronoi' in types:
        return {'kind': 'cosmic'}
    if 'ShaderNodeShaderToRGB' in types:
        vm = next(n for n in nodes if n.bl_idname == 'ShaderNodeVectorMath')
        ramp = next(n for n in nodes if n.bl_idname == 'ShaderNodeValToRGB')
        return {'kind': 'toon', 'color': list(vm.inputs[0].default_value)[:3],
                'shade': list(ramp.color_ramp.elements[0].color)[:3]}
    em = next((n for n in nodes if n.bl_idname == 'ShaderNodeEmission'), None)
    if em:
        c = list(em.inputs['Color'].default_value)[:3]
        s = em.inputs['Strength'].default_value
        return {'kind': 'glow', 'color': c, 'strength': s}
    return {'kind': 'toon', 'color': list(mat.diffuse_color)[:3], 'shade': [0.6] * 3}


def main():
    sc = bpy.context.scene
    sc.frame_set(0)
    objs = [o for o in sc.objects if o.type in ('MESH', 'ARMATURE', 'EMPTY', 'CAMERA', 'LIGHT')]
    index = {o.name: i for i, o in enumerate(objs)}
    inked = set()
    for ls in sc.view_layers[0].freestyle_settings.linesets:
        if ls.collection:
            inked |= {o.name for o in ls.collection.objects}
    meshes, mesh_index, materials, mat_index = [], {}, [], {}

    def mat_id(mat):
        key = mat.name if mat else '__none__'
        if key not in mat_index:
            mat_index[key] = len(materials)
            info = mat_info(mat)
            info['name'] = key
            materials.append(info)
        return mat_index[key]

    def mesh_id(me):
        if me.name in mesh_index:
            return mesh_index[me.name]
        me.calc_loop_triangles()
        co = [c for v in me.vertices for c in v.co]
        tris = [i for t in me.loop_triangles for i in t.vertices]
        smooth = any(p.use_smooth for p in me.polygons)
        mesh_index[me.name] = len(meshes)
        meshes.append({'name': me.name, 'nv': len(me.vertices), 'nt': len(tris) // 3,
                       'v': put_f32(co), 'f': put_u32(tris), 'smooth': smooth})
        return mesh_index[me.name]

    out_objs = []
    for o in objs:
        d = {'name': o.name, 'type': o.type,
             'parent': index.get(o.parent.name, -1) if o.parent else -1,
             'ptype': o.parent_type, 'pbone': o.parent_bone,
             'pinv': flat(o.matrix_parent_inverse),
             'loc': list(o.location), 'rot': list(o.rotation_euler), 'scale': list(o.scale),
             'rmode': o.rotation_mode, 'color': list(o.color),
             'hide': bool(o.hide_render), 'coll': o.users_collection[0].name if o.users_collection else '',
             'ink': o.name in inked, 'curves': [curve(fc) for fc in fcurves_of(o)]}
        if o.type == 'MESH':
            d['mesh'] = mesh_id(o.data)
            d['mat'] = mat_id(o.data.materials[0] if len(o.data.materials) else None)
            arm = next((m for m in o.modifiers if m.type == 'ARMATURE' and m.object), None)
            if arm:
                names = [g.name for g in o.vertex_groups]
                ws = []
                for v in o.data.vertices:
                    row = [0.0] * len(names)
                    for g in v.groups:
                        row[g.group] = g.weight
                    ws += row
                d['skin'] = {'arm': index[arm.object.name], 'bones': names, 'w': put_f32(ws)}
        elif o.type == 'ARMATURE':
            bones = []
            for b in o.data.bones:
                bones.append({'name': b.name, 'parent': b.parent.name if b.parent else None,
                              'rest': flat(b.matrix_local), 'len': b.length})
            d['bones'] = bones
            d['poseDefaults'] = {pb.name: {'rot': list(pb.rotation_euler), 'loc': list(pb.location)}
                                 for pb in o.pose.bones}
        elif o.type == 'CAMERA':
            d['lens'] = o.data.lens
            d['sensor'] = o.data.sensor_width
            d['lensCurves'] = [curve(fc) for fc in fcurves_of(o.data)]
            tt = next((c for c in o.constraints if c.type == 'TRACK_TO'), None)
            d['track'] = index[tt.target.name] if tt else -1
        elif o.type == 'LIGHT':
            d['energy'] = o.data.energy
        out_objs.append(d)

    world = sc.world
    world_curves = [curve(fc) for fc in fcurves_of(world.node_tree)] if world and world.node_tree else []
    glow_curves = []
    gm = bpy.data.materials.get('G_Cosmic')
    if gm:
        glow_curves = [curve(fc) for fc in fcurves_of(gm.node_tree)]
    header = {
        'fps': sc.render.fps, 'start': sc.frame_start, 'end': sc.frame_end,
        'objects': out_objs, 'meshes': meshes, 'materials': materials,
        'camera': index[sc.camera.name], 'world': world_curves, 'glow': glow_curves,
    }
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, 'scene.json'), 'w') as f:
        json.dump(header, f, separators=(',', ':'))
    # gzip + base64 in a .txt so any static host (and claude.ai artifacts) will serve it
    with open(os.path.join(OUT, 'scene.bin.txt'), 'wb') as f:
        f.write(base64.b64encode(gzip.compress(bytes(buf), 9)))
    nkeys = sum(c['n'] for o in out_objs for c in o['curves'])
    print('objects %d meshes %d materials %d keys %d bin %.1f MB' %
          (len(out_objs), len(meshes), len(materials), nkeys, len(buf) / 1e6))


main()
