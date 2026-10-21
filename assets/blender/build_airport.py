# -*- coding: utf-8 -*-
"""
程序化生成机场 3D 模型（单位：米），用于两条路线：
  1) 正射俯视渲染 -> 管制员场面显示底图（assets/textures/airport_top.png）
  2) 后续塔台/地面视角的 3D 场景基础

坐标系：X 向东，Y 向北，Z 向上。
地图可视范围 2600 x 1732 m，与 Godot 侧 MAP 1200x800 严格等比（1.5）。

自西向东：主楼 / 双指廊机坪 / 平行滑行道 A / 跑道 / 草地与围界道路
南北向：  远机位（北） / 北指廊 / 机坪通廊 / 南指廊 / 除冰坪·消防站（南）
"""

import bpy
import math
from mathutils import Euler

# ---------------------------------------------------------------- 地图范围
MAP_X0, MAP_X1 = -2132.0, 468.0
MAP_Y0, MAP_Y1 = -866.0, 866.0
CX = (MAP_X0 + MAP_X1) * 0.5
CY = (MAP_Y0 + MAP_Y1) * 0.5
MAP_W = MAP_X1 - MAP_X0
MAP_H = MAP_Y1 - MAP_Y0

# ---------------------------------------------------------------- 东西向
X_HEAD0, X_HEAD1 = -1730.0, -1400.0     # 主楼
X_PIER0, X_PIER1 = -1400.0, -670.0      # 双指廊
X_AP0, X_AP1 = -1420.0, -640.0          # 机坪
X_TWYA0, X_TWYA1 = -390.0, -345.0       # 平行滑行道 A
X_RWY0, X_RWY1 = 20.0, 65.0             # 跑道

# ---------------------------------------------------------------- 南北向
Y_NP0, Y_NP1 = 250.0, 320.0             # 北指廊
Y_SP0, Y_SP1 = -320.0, -250.0           # 南指廊
Y_NST = 140.0
Y_SST = -140.0
Y_TXN = 105.0
Y_TXS = -105.0
Y_HEAD0, Y_HEAD1 = -400.0, 400.0
Y_AP0, Y_AP1 = -370.0, 370.0
Y_RWY0, Y_RWY1 = -800.0, 800.0
Y_REM0, Y_REM1 = 620.0, 830.0           # 远机坪

Z_G = 0.02
Z_P = 0.10
Z_J = 0.118
Z_M = 0.18

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

_s = [20260401]


def rnd():
    _s[0] = (_s[0] * 1103515245 + 12345) & 0x7FFFFFFF
    return _s[0] / 2147483647.0


# ----------------------------------------------------------------------------
# 材质
# ----------------------------------------------------------------------------
def mk(name, color, rough=1.0, metal=0.0, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit > 0.0:
        try:
            b.inputs["Emission Color"].default_value = (color[0], color[1], color[2], 1.0)
            b.inputs["Emission Strength"].default_value = emit
        except Exception:
            pass
    return m


def mk_noise(name, c1, c2, scale, rough=1.0, detail=8.0, pos=(0.34, 0.66)):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nodes, links = nt.nodes, nt.links
    b = nodes["Principled BSDF"]
    tc = nodes.new("ShaderNodeTexCoord")
    nz = nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = detail
    try:
        nz.inputs["Roughness"].default_value = 0.55
    except Exception:
        pass
    rp = nodes.new("ShaderNodeValToRGB")
    el = rp.color_ramp.elements
    el[0].position = pos[0]
    el[0].color = (c1[0], c1[1], c1[2], 1.0)
    el[1].position = pos[1]
    el[1].color = (c2[0], c2[1], c2[2], 1.0)
    links.new(tc.outputs["Object"], nz.inputs["Vector"])
    links.new(nz.outputs["Fac"], rp.inputs["Fac"])
    links.new(rp.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    return m


MAT_DEFS = [
    ("grass", lambda: mk_noise("grass", (0.082, 0.098, 0.052), (0.112, 0.128, 0.068), 0.055, 1.0, 13.0, (0.24, 0.76))),
    ("grass_dry", lambda: mk_noise("grass_dry", (0.100, 0.108, 0.060), (0.122, 0.128, 0.072), 0.10, 1.0, 9.0)),
    ("tree", lambda: mk_noise("tree", (0.058, 0.086, 0.044), (0.086, 0.118, 0.058), 0.30, 0.95, 8.0)),
    ("asphalt_rwy", lambda: mk_noise("asphalt_rwy", (0.048, 0.050, 0.054), (0.070, 0.072, 0.076), 0.18, 0.88, 11.0)),
    ("asphalt_twy", lambda: mk_noise("asphalt_twy", (0.068, 0.071, 0.076), (0.092, 0.095, 0.100), 0.22, 0.88, 11.0)),
    ("asphalt_shoulder", lambda: mk_noise("asphalt_shoulder", (0.112, 0.114, 0.108), (0.134, 0.136, 0.128), 0.26, 0.93, 9.0)),
    ("concrete", lambda: mk_noise("concrete", (0.300, 0.292, 0.270), (0.348, 0.340, 0.314), 0.085, 0.94, 13.0)),
    ("concrete_dark", lambda: mk_noise("concrete_dark", (0.236, 0.231, 0.214), (0.272, 0.266, 0.246), 0.13, 0.94, 10.0)),
    ("joint", lambda: mk("joint", (0.190, 0.186, 0.172), 0.98)),
    ("rubber", lambda: mk_noise("rubber", (0.026, 0.027, 0.028), (0.044, 0.045, 0.047), 0.28, 0.90, 9.0)),
    ("road", lambda: mk_noise("road", (0.082, 0.084, 0.088), (0.104, 0.106, 0.110), 0.20, 0.92, 9.0)),
    ("white", lambda: mk("white", (0.740, 0.740, 0.720), 0.68, 0.0, 0.10)),
    ("yellow", lambda: mk("yellow", (0.730, 0.552, 0.062), 0.68, 0.0, 0.10)),
    ("red", lambda: mk("red", (0.430, 0.078, 0.062), 0.76, 0.0, 0.04)),
    ("roof", lambda: mk("roof", (0.212, 0.213, 0.205), 0.88)),
    ("roof_detail", lambda: mk("roof_detail", (0.160, 0.162, 0.156), 0.90)),
    ("roof_skylight", lambda: mk("roof_skylight", (0.170, 0.212, 0.242), 0.26, 0.25)),
    ("wall", lambda: mk("wall", (0.190, 0.189, 0.178), 0.90)),
    ("glass", lambda: mk("glass", (0.080, 0.115, 0.142), 0.16, 0.20)),
    ("metal", lambda: mk("metal", (0.170, 0.175, 0.180), 0.46, 0.40)),
    ("bridge", lambda: mk("bridge", (0.392, 0.410, 0.424), 0.76, 0.14)),
    ("pole", lambda: mk("pole", (0.322, 0.322, 0.320), 0.80)),
    ("veh_white", lambda: mk("veh_white", (0.560, 0.560, 0.548), 0.80)),
    ("veh_yellow", lambda: mk("veh_yellow", (0.540, 0.425, 0.070), 0.80)),
    ("veh_blue", lambda: mk("veh_blue", (0.072, 0.144, 0.284), 0.80)),
    ("veh_red", lambda: mk("veh_red", (0.420, 0.084, 0.062), 0.80)),
]

MATS = [(n, f()) for n, f in MAT_DEFS]
MI = {n: i for i, (n, _) in enumerate(MATS)}


# ----------------------------------------------------------------------------
# 几何构建
# ----------------------------------------------------------------------------
BOX_F = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]


class Builder:
    def __init__(self, name):
        self.name = name
        self.v = []
        self.f = []
        self.mi = []

    def box(self, x0, x1, y0, y1, z0, z1, mat):
        mi = MI[mat]
        if x0 > x1:
            x0, x1 = x1, x0
        if y0 > y1:
            y0, y1 = y1, y0
        if z0 > z1:
            z0, z1 = z1, z0
        b = len(self.v)
        self.v += [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                   (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        for f in BOX_F:
            self.f.append(tuple(b + i for i in f))
            self.mi.append(mi)

    def prism(self, pts, z0, z1, mat):
        mi = MI[mat]
        b = len(self.v)
        n = len(pts)
        for p in pts:
            self.v.append((p[0], p[1], z0))
        for p in pts:
            self.v.append((p[0], p[1], z1))
        self.f.append(tuple(b + i for i in range(n - 1, -1, -1)))
        self.mi.append(mi)
        self.f.append(tuple(b + n + i for i in range(n)))
        self.mi.append(mi)
        for i in range(n):
            j = (i + 1) % n
            self.f.append((b + i, b + j, b + n + j, b + n + i))
            self.mi.append(mi)

    def build(self):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.v, [], self.f)
        me.update()
        for _n, m in MATS:
            me.materials.append(m)
        for i, p in enumerate(me.polygons):
            p.material_index = self.mi[i]
        ob = bpy.data.objects.new(self.name, me)
        scene.collection.objects.link(ob)
        return ob


G = Builder("Ground")
B = Builder("Buildings")
D = Builder("Details")


def seg(bld, p0, p1, w, mat, z0=Z_M, z1=Z_M + 0.02):
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy)
    if L < 1e-6:
        return
    ux, uy = dx / L, dy / L
    nx, ny = -uy * w * 0.5, ux * w * 0.5
    ex, ey = ux * w * 0.5, uy * w * 0.5
    ax, ay = p0[0] - ex, p0[1] - ey
    bx, by = p1[0] + ex, p1[1] + ey
    bld.prism([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)],
              z0, z1, mat)


def path(bld, pts, w, mat, z0=Z_M, z1=Z_M + 0.02):
    for i in range(len(pts) - 1):
        seg(bld, pts[i], pts[i + 1], w, mat, z0, z1)


def rrect(bld, cx, cy, w, h, ang, z0, z1, mat):
    ca, sa = math.cos(ang), math.sin(ang)
    hw, hh = w * 0.5, h * 0.5
    pts = [(cx + p[0] * ca - p[1] * sa, cy + p[0] * sa + p[1] * ca)
           for p in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]]
    bld.prism(pts, z0, z1, mat)


def text(ob_name, body, x, y, size, rot_deg, mat, z=Z_M + 0.03):
    cu = bpy.data.curves.new(ob_name, type='FONT')
    cu.body = body
    cu.size = size
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    ob = bpy.data.objects.new(ob_name, cu)
    ob.location = (x, y, z)
    ob.rotation_euler = (0.0, 0.0, math.radians(rot_deg))
    cu.materials.append(bpy.data.materials[mat])
    scene.collection.objects.link(ob)
    return ob


def joints(x0, x1, y0, y1, step=62.0, width=1.4):
    x = x0
    while x <= x1:
        G.box(x - width * 0.5, x + width * 0.5, y0, y1, Z_P, Z_J, "joint")
        x += step
    y = y0
    while y <= y1:
        G.box(x0, x1, y - width * 0.5, y + width * 0.5, Z_P, Z_J, "joint")
        y += step


def vehicle(x, y, ang, mat, L=8.0, W=3.0, H=3.2):
    rrect(D, x, y, L, W, math.radians(ang), 0.0, H, mat)


def tree(x, y, r=5.0, h=9.0):
    B.box(x - 0.8, x + 0.8, y - 0.8, y + 0.8, 0.0, h * 0.55, "pole")
    B.box(x - r, x + r, y - r, y + r, h * 0.35, h, "tree")


# ----------------------------------------------------------------------------
# 1. 草皮底
# ----------------------------------------------------------------------------
G.box(MAP_X0 - 60, MAP_X1 + 60, MAP_Y0 - 60, MAP_Y1 + 60, 0.0, Z_G, "grass")
# 草地上的浅色草皮纹理带
for i in range(16):
    y0 = MAP_Y0 + i * 110.0
    if i % 2 == 0:
        G.box(-2120.0, X_HEAD0 - 6, y0, y0 + 110.0, Z_G, Z_G + 0.004, "grass_dry")
        G.box(X_RWY1 + 60, 330.0, y0, y0 + 110.0, Z_G, Z_G + 0.004, "grass_dry")


# ----------------------------------------------------------------------------
# 2. 铺筑面
# ----------------------------------------------------------------------------
# 主停机坪（双指廊之间）
G.box(X_AP0, X_AP1, Y_AP0, Y_AP1, 0.0, Z_P, "concrete")

# 除冰坪（南，紧贴机坪）
G.box(-1360.0, -1020.0, -620.0, Y_AP0, 0.0, Z_P, "concrete")
# 消防站出车坪（南，紧贴机坪）
G.box(-980.0, -660.0, -620.0, Y_AP0, 0.0, Z_P, "concrete")

# 远机坪（北）
G.box(-1400.0, -680.0, Y_REM0, Y_REM1, 0.0, Z_P, "concrete")
G.box(-700.0, -660.0, Y_AP1, Y_REM0, 0.0, Z_P, "concrete")   # 通廊 -> 远机坪

# 平行滑行道 A
G.box(X_TWYA0, X_TWYA1, -840.0, 840.0, 0.0, Z_P, "asphalt_twy")
# 机坪 -> 滑行道 A 连接滑行道（y=0）
G.box(X_AP1, X_TWYA0, -22.5, 22.5, 0.0, Z_P, "asphalt_twy")

# 跑道（含道肩、防吹坪）
G.box(X_RWY0 - 8, X_RWY1 + 8, Y_RWY0, Y_RWY1, 0.0, Z_P, "asphalt_shoulder")
G.box(X_RWY0 - 8, X_RWY1 + 8, Y_RWY0 - 55, Y_RWY0, 0.0, Z_P, "asphalt_shoulder")
G.box(X_RWY0 - 8, X_RWY1 + 8, Y_RWY1, Y_RWY1 + 55, 0.0, Z_P, "asphalt_shoulder")
G.box(X_RWY0, X_RWY1, Y_RWY0, Y_RWY1, 0.0, Z_P + 0.004, "asphalt_rwy")

# 联络道 B1..B4
CONN_Y = [600.0, 200.0, -200.0, -600.0]
for cy in CONN_Y:
    G.box(X_TWYA1, X_RWY0, cy - 22.5, cy + 22.5, 0.0, Z_P, "asphalt_twy")

# 围界道路
G.box(330.0, 342.0, MAP_Y0 + 20, MAP_Y1 - 20, 0.0, Z_P, "road")
G.box(-1800.0, -1788.0, MAP_Y0 + 20, MAP_Y1 - 20, 0.0, Z_P, "road")

# 橡胶沉积 & 轮胎痕
G.box(X_RWY0, X_RWY1, Y_RWY0, Y_RWY0 + 160.0, Z_P + 0.004, Z_P + 0.009, "rubber")
G.box(X_RWY0, X_RWY1, Y_RWY1 - 160.0, Y_RWY1, Z_P + 0.004, Z_P + 0.009, "rubber")
for cy in CONN_Y:
    G.box(X_TWYA1 + 26.0, X_RWY0 - 26.0, cy - 7.0, cy + 7.0, Z_P, Z_P + 0.006, "rubber")

# 道面接缝
joints(X_AP0, X_AP1, Y_AP0, Y_AP1, 62.0)
joints(-1400.0, -680.0, Y_REM0, Y_REM1, 62.0)


# ----------------------------------------------------------------------------
# 3. 滑行道标线（黄）
# ----------------------------------------------------------------------------
TWY_W = 1.6
path(G, [(X_AP0, 0), (X_TWYA0, 0)], TWY_W, "yellow")
path(G, [((X_TWYA0 + X_TWYA1) * 0.5, -840.0), ((X_TWYA0 + X_TWYA1) * 0.5, 840.0)], TWY_W, "yellow")
path(G, [(X_AP0, Y_TXN), (X_PIER1 - 20.0, Y_TXN)], TWY_W, "yellow")
path(G, [(X_AP0, Y_TXS), (X_PIER1 - 20.0, Y_TXS)], TWY_W, "yellow")
path(G, [(-650.0, 0), (-650.0, Y_TXN)], TWY_W, "yellow")
path(G, [(-650.0, 0), (-650.0, Y_TXS)], TWY_W, "yellow")
# 远机坪连接
path(G, [(-680.0, 0), (-680.0, 650.0), (-1360.0, 650.0)], TWY_W, "yellow")
# 除冰坪 / 消防站 进出
path(G, [(-1200.0, 0), (-1200.0, -440.0)], TWY_W, "yellow")
path(G, [(-820.0, 0), (-820.0, -440.0)], TWY_W, "yellow")

for cy in CONN_Y:
    path(G, [((X_TWYA0 + X_TWYA1) * 0.5, cy), ((X_RWY0 + X_RWY1) * 0.5, cy)], TWY_W, "yellow")
    for xo in (-1.2, -3.8):
        seg(G, (X_RWY0 - 38.0 + xo, cy - 16), (X_RWY0 - 38.0 + xo, cy + 16), 1.7, "yellow")
    for k in range(4):
        xo = X_RWY0 - 53.0 - k * 6.5
        seg(G, (xo, cy - 16), (xo, cy + 16), 1.7, "yellow")

seg(G, (X_TWYA0 + 1.5, -840.0), (X_TWYA0 + 1.5, 840.0), 0.9, "white")
seg(G, (X_TWYA1 - 1.5, -840.0), (X_TWYA1 - 1.5, 840.0), 0.9, "white")
seg(G, (X_AP0, Y_AP1 - 12), (X_AP1, Y_AP1 - 12), 0.9, "white")
seg(G, (X_AP0, Y_AP0 + 12), (X_AP1, Y_AP0 + 12), 0.9, "white")
seg(G, (X_AP1 - 12, Y_AP0), (X_AP1 - 12, Y_AP1), 0.9, "white")


# ----------------------------------------------------------------------------
# 4. 跑道标线
# ----------------------------------------------------------------------------
RXM = (X_RWY0 + X_RWY1) * 0.5
y = Y_RWY0 + 20.0
while y < Y_RWY1:
    G.box(RXM - 0.9, RXM + 0.9, y, min(y + 30.0, Y_RWY1), Z_M, Z_M + 0.02, "white")
    y += 50.0

seg(G, (X_RWY0 + 1.0, Y_RWY0), (X_RWY0 + 1.0, Y_RWY1), 0.9, "white")
seg(G, (X_RWY1 - 1.0, Y_RWY0), (X_RWY1 - 1.0, Y_RWY1), 0.9, "white")

for sign in (-1.0, 1.0):
    base = Y_RWY1 * sign
    inward = -sign
    for i in range(8):
        x0 = X_RWY0 + 5.0 + i * 5.0
        G.box(x0, x0 + 1.8, min(base, base + inward * 30.0), max(base, base + inward * 30.0),
              Z_M, Z_M + 0.02, "white")
    for xo in (X_RWY0 + 11.0, X_RWY0 + 28.0):
        y0 = base + inward * 300.0
        G.box(xo, xo + 6.0, min(y0, y0 + inward * 45.0), max(y0, y0 + inward * 45.0),
              Z_M, Z_M + 0.02, "white")
    for d in (150.0, 450.0, 600.0):
        y0 = base + inward * d
        for xo in (X_RWY0 + 9.0, X_RWY0 + 36.0):
            G.box(xo, xo + 3.6, min(y0, y0 + inward * 22.0), max(y0, y0 + inward * 22.0),
                  Z_M, Z_M + 0.02, "white")

text("Rwy36", "36", RXM, Y_RWY0 + 55.0, 28.0, 0.0, "white")
text("Rwy18", "18", RXM, Y_RWY1 - 55.0, 28.0, 180.0, "white")


# ----------------------------------------------------------------------------
# 5. 机位
# ----------------------------------------------------------------------------
STAND_X = [X_PIER0 + 39.0 + i * 78.0 for i in range(9)]


def stand(x, y_nose, y_tail, label, rot, ly):
    y0, y1 = min(y_nose, y_tail), max(y_nose, y_tail)
    G.box(x - 29, x + 29, y0 - 3, y1 + 3, Z_M, Z_M + 0.008, "red")
    G.box(x - 27, x + 27, y0 - 1, y1 + 1, Z_M + 0.008, Z_M + 0.010, "concrete")
    G.box(x - 26, x + 26, y0, y1, Z_M, Z_M + 0.012, "white")
    G.box(x - 24, x + 24, y0 + 2, y1 - 2, Z_M + 0.012, Z_M + 0.014, "concrete")
    text("ST_" + label, label, x, ly, 11.0, rot, "white")


for i, x in enumerate(STAND_X):
    path(G, [(x, Y_TXN), (x, Y_NP0 - 16.0)], 1.3, "white")
    seg(G, (x - 9, Y_NP0 - 11.0), (x + 9, Y_NP0 - 11.0), 1.6, "white")
    stand(x, Y_NP0, Y_NST, "A%02d" % (i + 1), 180.0, Y_NST - 17.0)

for i, x in enumerate(STAND_X):
    path(G, [(x, Y_TXS), (x, Y_SP0 + 16.0)], 1.3, "white")
    seg(G, (x - 9, Y_SP0 + 11.0), (x + 9, Y_SP0 + 11.0), 1.6, "white")
    stand(x, Y_SP0, Y_SST, "A%02d" % (i + 10), 0.0, Y_SST + 17.0)

R_STAND_X = [-1360.0, -1250.0, -1140.0, -1030.0, -920.0, -810.0]
for i, x in enumerate(R_STAND_X):
    path(G, [(x, 650.0), (x, 782.0)], 1.3, "white")
    seg(G, (x - 9, 788.0), (x + 9, 788.0), 1.6, "white")
    stand(x, 800.0, 700.0, "A%02d" % (i + 19), 180.0, 684.0)

# 除冰坪三处机位
for i, x in enumerate([-1310.0, -1220.0, -1130.0]):
    path(G, [(x, -440.0), (x, -500.0)], 1.3, "white")
    G.box(x - 24, x + 24, -590.0, -500.0, Z_M, Z_M + 0.012, "white")
    G.box(x - 22, x + 22, -588.0, -502.0, Z_M + 0.012, Z_M + 0.014, "concrete")
    text("DEI_%d" % i, "D%d" % (i + 1), x, -516.0, 11.0, 0.0, "white")


# ----------------------------------------------------------------------------
# 6. 航站楼 / 指廊 / 廊桥 / 塔台 / 消防站
# ----------------------------------------------------------------------------
B.box(X_HEAD0, X_HEAD1, Y_HEAD0, Y_HEAD1, 0.0, 26.0, "wall")
B.box(X_HEAD0 - 8, X_HEAD1 + 12, Y_HEAD0 - 10, Y_HEAD1 + 10, 26.0, 30.0, "roof")
# 屋顶天窗带 + 屋顶设备（比"条形码"式天窗真实得多）
B.box(X_HEAD0 + 40, X_HEAD1 - 34, 300.0, 316.0, 30.0, 30.9, "roof_skylight")
B.box(X_HEAD0 + 40, X_HEAD1 - 34, -316.0, -300.0, 30.0, 30.9, "roof_skylight")
for i in range(9):
    y0 = Y_HEAD0 + 34.0 + i * 84.0
    for j, xo in enumerate((26.0, 96.0, 166.0)):
        w = 34.0 + (i * 7 + j * 11) % 22
        d = 26.0 + (i * 5 + j * 13) % 16
        B.box(X_HEAD0 + xo, X_HEAD0 + xo + w, y0, y0 + d, 30.0, 32.4, "roof_detail")
B.box(X_HEAD0 + 30, X_HEAD0 + 118, Y_HEAD0 + 40, Y_HEAD0 + 120, 30.0, 35.2, "roof_detail")
B.box(X_HEAD0 + 30, X_HEAD0 + 118, Y_HEAD1 - 120, Y_HEAD1 - 40, 30.0, 35.2, "roof_detail")
B.box(X_HEAD1, X_HEAD1 + 16, Y_HEAD0 - 10, Y_HEAD1 + 10, 21.0, 25.0, "roof_detail")
B.box(X_HEAD0 + 10, X_HEAD1 - 10, Y_HEAD1 + 10, Y_HEAD1 + 32, 0.0, 17.0, "roof_detail")
B.box(X_HEAD0 + 10, X_HEAD1 - 10, Y_HEAD0 - 32, Y_HEAD0 - 10, 0.0, 17.0, "roof_detail")

B.box(X_PIER0 + 10, X_PIER1, Y_NP0, Y_NP1, 0.0, 15.0, "wall")
B.box(X_PIER0, X_PIER1 + 8, Y_NP0 - 8, Y_NP1 + 8, 15.0, 17.6, "roof")
for i in range(12):
    x0 = X_PIER0 + 20.0 + i * 60.0
    B.box(x0, x0 + 30.0, Y_NP0 + 8, Y_NP1 - 8, 17.6, 18.6, "roof_detail")
B.box(X_PIER1, X_PIER1 + 40, Y_NP0 - 12, Y_NP1 + 12, 0.0, 19.0, "roof")

B.box(X_PIER0 + 10, X_PIER1, Y_SP0, Y_SP1, 0.0, 15.0, "wall")
B.box(X_PIER0, X_PIER1 + 8, Y_SP0 - 8, Y_SP1 + 8, 15.0, 17.6, "roof")
for i in range(12):
    x0 = X_PIER0 + 20.0 + i * 60.0
    B.box(x0, x0 + 30.0, Y_SP0 + 8, Y_SP1 - 8, 17.6, 18.6, "roof_detail")
B.box(X_PIER1, X_PIER1 + 40, Y_SP0 - 12, Y_SP1 + 12, 0.0, 19.0, "roof")

for x in STAND_X:
    seg(D, (x + 18, Y_NP0), (x + 8, Y_NP0 - 20.0), 7.0, "bridge", 4.4, 7.6)
    B.box(x + 12, x + 28, Y_NP0 - 2, Y_NP0 + 12, 0.0, 4.4, "bridge")
    B.box(x + 2, x + 14, Y_NP0 - 26, Y_NP0 - 12, 2.6, 7.6, "bridge")

for x in STAND_X:
    seg(D, (x + 18, Y_SP0), (x + 8, Y_SP0 + 20.0), 7.0, "bridge", 4.4, 7.6)
    B.box(x + 12, x + 28, Y_SP0 - 12, Y_SP0 + 2, 0.0, 4.4, "bridge")
    B.box(x + 2, x + 14, Y_SP0 + 12, Y_SP0 + 26, 2.6, 7.6, "bridge")

# 塔台
B.box(-1560, -1508, 250, 302, 0.0, 56.0, "wall")
B.box(-1574, -1494, 236, 316, 56.0, 64.0, "glass")
B.box(-1580, -1488, 230, 322, 64.0, 66.4, "roof_detail")

# 消防站
B.box(-980.0, -700.0, -760.0, -630.0, 0.0, 10.0, "wall")
B.box(-988.0, -692.0, -768.0, -622.0, 10.0, 12.2, "roof")
for i in range(4):
    x0 = -960.0 + i * 62.0
    B.box(x0, x0 + 42.0, -634.0, -628.0, 0.0, 8.4, "red")
for x in (-940.0, -850.0, -760.0):
    rrect(D, x, -580.0, 11.0, 3.2, math.radians(90), 0.0, 3.6, "veh_red")


# ----------------------------------------------------------------------------
# 7. 车辆 / 灯柱 / 树木
# ----------------------------------------------------------------------------
vehicle(-1360, 40, 0, "veh_white")
vehicle(-1330, 72, 12, "veh_yellow", 5.0, 2.4, 2.6)
vehicle(-1250, -40, 90, "veh_blue", 12.0, 3.0, 3.4)
vehicle(-1170, 90, -25, "veh_white")
vehicle(-1090, -90, 45, "veh_yellow")
vehicle(-1010, 46, 0, "veh_white", 12.0, 3.0, 3.4)
vehicle(-930, -60, 180, "veh_red", 6.0, 2.6, 2.8)
vehicle(-850, 88, 30, "veh_white")
vehicle(-770, -100, 0, "veh_blue", 10.0, 3.0, 3.2)
vehicle(-930, 190, 90, "veh_white", 9.0, 3.0, 3.2)
vehicle(-830, -190, 20, "veh_yellow")
vehicle(-690, -300, 0, "veh_white", 12.0, 3.0, 3.4)
vehicle(-670, 300, 100, "veh_red")
vehicle(-1280, 470, 0, "veh_white", 6.0, 2.6, 2.8)
vehicle(-1240, -450, 0, "veh_yellow", 6.0, 2.6, 2.8)
vehicle(-1150, 760, 0, "veh_white", 9.0, 3.0, 3.2)
vehicle(-900, 780, 15, "veh_yellow")
vehicle(-760, 770, 80, "veh_blue", 11.0, 3.0, 3.2)
vehicle(-1300, -560, 0, "veh_yellow", 9.0, 3.4, 3.6)

LIGHT_POS = [(-1418, 380), (-1040, 380), (-680, 380), (-1418, -380), (-1040, -380), (-680, -380),
             (-660, 300), (-660, -300), (-1400, 640), (-680, 640)]
for (lx, ly) in LIGHT_POS:
    B.box(lx - 2.2, lx + 2.2, ly - 2.2, ly + 2.2, 0.0, 28.0, "pole")
    B.box(lx - 6.0, lx + 6.0, ly - 6.0, ly + 6.0, 28.0, 30.0, "metal")

# 围界外树林（东侧、西侧）
y = MAP_Y0 + 14.0
while y < MAP_Y1 - 14.0:
    tree(352.0 + rnd() * 96.0, y + rnd() * 14.0, 4.2 + rnd() * 3.0, 8.0 + rnd() * 5.0)
    y += 22.0 + rnd() * 12.0
y = MAP_Y0 + 20.0
while y < MAP_Y1 - 20.0:
    tree(-2090.0 + rnd() * 210.0, y + rnd() * 16.0, 3.6 + rnd() * 2.6, 7.0 + rnd() * 4.0)
    y += 24.0 + rnd() * 14.0
# 稀疏点状树丛（远机坪以北的开阔草地）
for i in range(26):
    tree(-2060.0 + rnd() * 300.0, 560.0 + rnd() * 280.0, 3.2 + rnd() * 2.4, 6.5 + rnd() * 3.5)


# ----------------------------------------------------------------------------
# 8. 相机 / 灯光 / 渲染
# ----------------------------------------------------------------------------
cam_data = bpy.data.cameras.new("TopCam")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = MAP_W
cam_data.clip_start = 1.0
cam_data.clip_end = 6000.0
cam = bpy.data.objects.new("TopCam", cam_data)
cam.location = (CX, CY, 1500.0)
cam.rotation_euler = Euler((0.0, 0.0, 0.0), 'XYZ')
scene.collection.objects.link(cam)
scene.camera = cam

sun_data = bpy.data.lights.new("Sun", type='SUN')
sun_data.energy = 2.9
sun_data.angle = math.radians(3.0)
try:
    sun_data.use_shadow = True
except Exception:
    pass
sun = bpy.data.objects.new("Sun", sun_data)
sun.rotation_euler = Euler((math.radians(50.0), 0.0, math.radians(-38.0)), 'XYZ')
scene.collection.objects.link(sun)

world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.60, 0.62, 0.66, 1.0)
bg.inputs[1].default_value = 0.38

try:
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0.35
except Exception:
    pass

scene.render.film_transparent = False
scene.render.resolution_x = 4608
scene.render.resolution_y = 3072
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGB'

scene.render.engine = 'CYCLES'
try:
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.cycles.device = 'GPU'
    prefs = bpy.context.preferences.addons['cycles'].preferences
    ok = False
    for dt in ('OPTIX', 'CUDA', 'HIP', 'ONEAPI'):
        try:
            prefs.compute_device_type = dt
            prefs.get_devices()
            if any(d.type == dt for d in prefs.devices):
                ok = True
                break
        except Exception:
            continue
    if ok:
        for d in prefs.devices:
            d.use = (d.type == prefs.compute_device_type)
    else:
        scene.cycles.device = 'CPU'
except Exception as e:
    print("cycles setup fallback:", e)
    scene.render.engine = 'BLENDER_EEVEE'

ground_ob = G.build()
build_ob = B.build()
detail_ob = D.build()

dsh_result = {
    "ground_faces": len(ground_ob.data.polygons),
    "building_faces": len(build_ob.data.polygons),
    "detail_faces": len(detail_ob.data.polygons),
    "objects": len(bpy.data.objects),
    "map": [MAP_X0, MAP_X1, MAP_Y0, MAP_Y1],
    "resolution": [scene.render.resolution_x, scene.render.resolution_y],
}
print("BUILD OK", dsh_result)
