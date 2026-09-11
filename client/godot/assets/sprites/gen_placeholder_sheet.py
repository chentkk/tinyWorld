#!/usr/bin/env python3
"""生成占位序列帧表(hero.png)。

纯标准库实现(zlib + struct), 无需 PIL。
产物是"能看出朝向和动作"的色块小人, 用于在没有正式美术时验证
序列帧管线(加载 -> 切帧 -> 朝向选择 -> 动作切换)。

正式美术到位后, 按同样的布局替换 hero.png 即可, 不用改代码:
  行 = 朝向(4 方向各一行), 列 = 帧序号

布局(每帧 64x64, 共 4 方向 x 3 动作 = 12 行):
  行 0-3  idle   : down / up / left / right
  行 4-7  walk   : down / up / left / right
  行 8-11 attack : down / up / left / right

4 方向各占一行(不用镜像), 与 Game/config 里 4 向 sprite 的约定一致。
若改用 3 行布局(down/up/side + 镜像), 把 DIRS 换成
  ["down", "up", "side"]
并把 left/right 都画成"朝右"即可 —— facing.gd 的 render_for() 两种都支持。

用法: python gen_placeholder_sheet.py
"""
import struct
import zlib
import os

FRAME = 64
COLS = 6             # 每行动画帧数
DIRS = ["down", "up", "left", "right"]
ROWS = len(DIRS) * 3  # 4 方向 x 3 动作

# 每个动作的主色(和方向无关, 便于一眼区分动作)
ACTION_COLORS = {
    "idle":   (70, 130, 220),
    "walk":   (70, 200, 130),
    "attack": (230, 120, 60),
}


def blend(dst, src, alpha):
    """把 src 按 alpha 叠到 dst 上。"""
    return tuple(int(d + (s - d) * alpha) for d, s in zip(dst, src))


def draw_frame(px, ox, oy, action, direction, frame_index, total_frames):
    """在 (ox, oy) 处画一帧占位角色。"""
    base = ACTION_COLORS[action]
    body = (40, 40, 48)
    outline = (16, 16, 20)
    phase = frame_index / max(1, total_frames)

    def put(x, y, color, alpha=1.0):
        if not (0 <= x < FRAME and 0 <= y < FRAME):
            return
        i = ((oy + y) * (FRAME * COLS) + (ox + x)) * 4
        old = (px[i], px[i + 1], px[i + 2], px[i + 3])
        new = blend(old[:3], color, alpha)
        px[i], px[i + 1], px[i + 2] = new
        px[i + 3] = 255

    def rect(x0, y0, w, h, color, alpha=1.0):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                put(x, y, color, alpha)

    # 走路时躯干上下轻微起伏; 攻击时躯干前倾。
    bob = 0
    if action == "walk":
        bob = -1 if int(phase * 4) % 2 == 0 else 1
    lean = 2 if action == "attack" and phase > 0.5 else 0

    cx = FRAME // 2

    # 腿(走路时前后摆动)
    leg_swing = 0
    if action == "walk":
        leg_swing = 3 if int(phase * 4) % 2 == 0 else -3
    rect(cx - 7, 46 + bob, 5, 12 + leg_swing, body)
    rect(cx + 2, 46 + bob, 5, 12 - leg_swing, body)

    # 躯干
    rect(cx - 9 + lean, 26 + bob, 18, 22, base)
    rect(cx - 9 + lean, 26 + bob, 18, 2, outline)   # 肩线, 帮助看清朝向

    # 水平朝向: -1 = 朝左, 0 = 正面/背面, +1 = 朝右。
    hx = -1 if direction == "left" else (1 if direction == "right" else 0)

    # 手臂(攻击时朝面朝方向前伸)
    if action == "attack" and phase > 0.5:
        arm_x = cx + (hx * 12 if hx != 0 else 6)
        rect(arm_x, 30 + bob, 10, 5, base)
    else:
        rect(cx - 12 + lean, 30 + bob, 4, 14, base)
        rect(cx + 8 + lean, 30 + bob, 4, 14, base)

    # 头(侧向时稍微收窄, 看起来像侧脸)
    head_w = 12 if hx != 0 else 16
    head_x = cx - head_w // 2 + lean + (hx * 2)
    rect(head_x, 12 + bob, head_w, 15, body)
    rect(head_x, 12 + bob, head_w, 2, outline)

    # 朝向标记: 让四个方向一眼可辨
    eye = (250, 250, 250)
    if direction == "down":
        # 面向屏幕: 两只眼睛
        rect(cx - 5 + lean, 19 + bob, 3, 3, eye)
        rect(cx + 2 + lean, 19 + bob, 3, 3, eye)
    elif direction == "up":
        # 背对屏幕: 后脑勺发色块, 无眼
        rect(cx - 6 + lean, 15 + bob, 12, 3, (90, 70, 60))
    else:
        # 侧脸: 单眼偏向面朝的一侧
        rect(cx + hx * 3 + lean - 1, 19 + bob, 3, 3, eye)
        # 鼻子/朝向凸起, 强化方向感
        rect(cx + hx * 6 + lean, 20 + bob, 3, 3, body)

    # 攻击动作: 画一道朝面朝方向的"挥砍"弧线
    if action == "attack" and phase > 0.4:
        for k in range(14):
            if hx == 1:
                put(cx + 16 + k // 3, 20 + bob + k, (255, 240, 180), 0.9)
            elif hx == -1:
                put(cx - 18 - k // 3, 20 + bob + k, (255, 240, 180), 0.9)
            elif direction == "down":
                put(cx - 14 + k, 44 + bob + k // 2, (255, 240, 180), 0.9)
            else:
                put(cx - 14 + k, 4 + bob + k // 2, (255, 240, 180), 0.9)


def build_sheet():
    w, h = FRAME * COLS, FRAME * ROWS
    px = bytearray(w * h * 4)   # RGBA, 初始全透明

    actions = ["idle", "walk", "attack"]
    for ai, action in enumerate(actions):
        for di, direction in enumerate(DIRS):
            row = ai * len(DIRS) + di
            for col in range(COLS):
                draw_frame(px, col * FRAME, row * FRAME,
                           action, direction, col, COLS)
    return px, w, h


def write_png(path, px, w, h):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)   # filter type 0
        raw.extend(px[y * stride:(y + 1) * stride])

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        out += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return out

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    px, w, h = build_sheet()
    out = os.path.join(here, "hero.png")
    write_png(out, px, w, h)
    print(f"wrote {out} ({w}x{h}, {FRAME}x{FRAME} per frame, "
          f"{COLS} cols x {ROWS} rows)")
