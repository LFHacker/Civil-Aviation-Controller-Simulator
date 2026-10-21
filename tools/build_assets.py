"""Blender 无头建模脚本：生成低多边形客机并导出 .glb。

用法（不需要打开 Blender 界面）：
    blender.exe --background --python tools/build_assets.py

输出：
    assets/models/airliner_lowpoly.glb
    assets/models/airliner_lowpoly.blend
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
OUT_DIR = os.path.join(PROJECT, "assets", "models")


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def make_material(name, rgba, rough=0.5, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metallic
    return mat


def add_box(name, size, loc, rot=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat:
        obj.data.materials.append(mat)
    return obj


def add_cyl(name, radius, depth, loc, rot=(0, 0, 0), verts=10, mat=None):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot
    )
    obj = bpy.context.active_object
    obj.name = name
    if mat:
        obj.data.materials.append(mat)
    return obj


def build_airliner():
    """机身沿 -Y 为机头方向（与 Godot 的 -Z 前向对应时再旋转）。"""
    body = make_material("Body", (0.90, 0.91, 0.92, 1.0), rough=0.35)
    stripe = make_material("Stripe", (0.12, 0.40, 0.64, 1.0), rough=0.35)
    dark = make_material("Dark", (0.07, 0.08, 0.09, 1.0), rough=0.55)
    glass = make_material("Glass", (0.05, 0.07, 0.09, 1.0), rough=0.10, metallic=0.6)

    # 机身：沿 Y 轴
    fuselage = add_cyl("Fuselage", 1.92, 34.0, (0, 0, 0), rot=(math.radians(90), 0, 0),
                       verts=10, mat=body)
    # 机头锥
    add_cyl("Nose", 1.92, 4.6, (0, -19.3, 0), rot=(math.radians(90), 0, 0),
            verts=10, mat=body)

    # 主翼
    add_box("Wing", (36.0, 5.1, 0.55), (0, -2.2, -0.45), mat=body)
    add_box("Stab", (13.2, 3.3, 0.42), (0, 13.4, 0.15), mat=body)
    add_box("Fin", (0.45, 5.6, 7.0), (0, 12.9, 3.6), rot=(math.radians(-14), 0, 0), mat=body)

    # 发动机
    for side in (-1.0, 1.0):
        add_cyl("Engine", 1.30, 5.2, (side * 5.2, -2.8, -1.75),
                rot=(math.radians(90), 0, 0), verts=8, mat=dark)

    # 涂装带
    for side in (-1.0, 1.0):
        add_box("Stripe", (0.12, 26.0, 0.75), (side * 1.92, 0.0, -0.55), mat=stripe)

    # 舷窗带
    for side in (-1.0, 1.0):
        add_box("Windows", (0.10, 21.0, 0.42), (side * 1.90, -1.0, 0.62), mat=glass)

    return fuselage


def export_glb(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    clear_scene()
    build_airliner()

    glb = os.path.join(OUT_DIR, "airliner_lowpoly.glb")
    blend = os.path.join(OUT_DIR, "airliner_lowpoly.blend")

    export_glb(glb)
    bpy.ops.wm.save_as_mainfile(filepath=blend)

    size = os.path.getsize(glb) if os.path.exists(glb) else -1
    print("[build_assets] GLB: %s (%d bytes)" % (glb, size))
    print("[build_assets] BLEND: %s" % blend)
    if size <= 0:
        sys.exit(2)


if __name__ == "__main__":
    main()
