#!/usr/bin/env python
"""
Offscreen test harness for the ghostty cursor shaders.

Emulates Ghostty's custom-shader environment (iChannel0 = the terminal render
pass, plus the iCurrentCursor/iPreviousCursor/iTime* uniforms) so shader
behaviour can be asserted on programmatically instead of eyeballed.

Synthesises the terminal pass itself: a dark background with a purple cursor
block that can be toggled on/off to stand in for the two blink phases. That is
the whole point -- the blink phase is an *input* here, so we can check what the
shader does in each one.

Usage:  /tmp/glsltest/bin/python test_shader.py [shader.glsl ...]
"""
import sys, os
import numpy as np
import moderngl

W, H = 800, 450
CURSOR_COLOR = (0xE5 / 255.0, 0x80 / 255.0, 0xFF / 255.0)  # cursor-color in config
BG = (0.05, 0.04, 0.08)

# Cursor cell in pixels: x, y(top), w, h -- matches iCurrentCursor's convention
CELL = (400.0, 250.0, 10.0, 22.0)

VERT = """
#version 330
in vec2 in_pos;
void main() { gl_Position = vec4(in_pos, 0.0, 1.0); }
"""

# Shadertoy-style preamble matching the uniforms Ghostty provides.
HEADER = """
#version 330
uniform vec3 iResolution;
uniform float iTime;
uniform float iTimeCursorChange;
uniform vec4 iCurrentCursor;
uniform vec4 iPreviousCursor;
uniform sampler2D iChannel0;
out vec4 _fragColorOut;
"""

FOOTER = """
void main() {
    vec4 c = vec4(0.0);
    mainImage(c, gl_FragCoord.xy);
    _fragColorOut = c;
}
"""


def make_terminal_pass(cursor_visible, glyph=0.0):
    """Synthetic iChannel0: what Ghostty's terminal renderer would hand us.

    glyph is the fraction of the cell a character covers (0 = empty cell, 0.9 =
    a wide dense glyph like 'M'). Under the cursor the glyph is drawn dark, as
    cursor-text / bg-fg inversion gives.
    """
    img = np.zeros((H, W, 3), dtype=np.float32)
    img[:, :] = BG
    x, ytop, w, h = CELL
    x0, x1 = int(x), int(x + w)
    y0, y1 = int(ytop), int(ytop + h)
    if cursor_visible:
        img[y0:y1, x0:x1] = CURSOR_COLOR
        if glyph > 0:
            gw, gh = w * glyph, h * glyph
            gx0 = int(x + (w - gw) / 2); gx1 = int(x + (w + gw) / 2)
            gy0 = int(ytop + (h - gh) / 2); gy1 = int(ytop + (h + gh) / 2)
            img[gy0:gy1, gx0:gx1] = (0.08, 0.0, 0.12)
    elif glyph > 0:
        # blink-off: normal light-on-dark text in the cell
        gw, gh = w * glyph, h * glyph
        gx0 = int(x + (w - gw) / 2); gx1 = int(x + (w + gw) / 2)
        gy0 = int(ytop + (h - gh) / 2); gy1 = int(ytop + (h + gh) / 2)
        img[gy0:gy1, gx0:gx1] = (0.85, 0.85, 0.88)
    return img


def render(ctx, src, channel0, time=10.0, time_cursor_change=0.0,
           cursor=CELL, prev_cursor=None):
    prev_cursor = prev_cursor if prev_cursor is not None else cursor
    prog = ctx.program(vertex_shader=VERT, fragment_shader=HEADER + src + FOOTER)

    tex = ctx.texture((W, H), 3, channel0[::-1].tobytes(), dtype='f4')
    tex.use(0)

    def setu(name, val):
        if name in prog:
            prog[name].value = val

    setu('iResolution', (float(W), float(H), 1.0))
    setu('iTime', time)
    setu('iTimeCursorChange', time_cursor_change)
    # GL texture origin is bottom-left; flip cursor y into that space
    setu('iCurrentCursor', (cursor[0], H - cursor[1], cursor[2], cursor[3]))
    setu('iPreviousCursor', (prev_cursor[0], H - prev_cursor[1], prev_cursor[2], prev_cursor[3]))
    setu('iChannel0', 0)

    quad = ctx.buffer(np.array([-1, -1, 3, -1, -1, 3], dtype='f4').tobytes())
    vao = ctx.simple_vertex_array(prog, quad, 'in_pos')
    fbo = ctx.framebuffer(color_attachments=[ctx.texture((W, H), 4, dtype='f4')])
    fbo.use()
    fbo.clear(0.0, 0.0, 0.0, 1.0)
    vao.render(moderngl.TRIANGLES)

    out = np.frombuffer(fbo.read(components=4, dtype='f4'), dtype='f4')
    return out.reshape((H, W, 4))[::-1]


def probe(img, px, py):
    """Sample the rendered result at a pixel, in top-down coords."""
    return img[int(py), int(px), :3]


def halo_ring_mean(img, dist=6):
    """Mean color of a ring `dist` px outside the cursor block."""
    x, ytop, w, h = CELL
    cx, cy = x + w / 2, ytop + h / 2
    pts = [(cx, ytop - dist), (cx, ytop + h + dist),
           (x - dist, cy), (x + w + dist, cy)]
    return np.mean([probe(img, p, q) for p, q in pts], axis=0)


def compat(src):
    """Ghostty's shader frontend accepts brace array initialisers
    (`const vec3[24] x = {...}`); desktop GLSL 330 requires constructor syntax
    (`vec3[24](...)`). Rewrite for the test context only -- the shader files
    themselves are left alone, since Ghostty compiles them fine as written."""
    import re
    def fix(m):
        return f"{m.group(1)} {m.group(2)} = {m.group(1).split(']')[0]}]("
    src = re.sub(r'(vec[234]\[\d+\])\s+(\w+)\s*=\s*\{', fix, src)
    # close the matching brace of any initialiser we rewrote
    if 'samples = vec3[24](' in src:
        i = src.index('samples = vec3[24](')
        depth = 0
        for j in range(i, len(src)):
            if src[j] == '(':
                depth += 1
            elif src[j] == ')':
                depth -= 1
            elif src[j] == '}' and depth == 1:
                src = src[:j] + ')' + src[j + 1:]
                break
    return src


def render_chain(ctx, srcs, channel0, **kw):
    """Run shaders in sequence, each one's output feeding the next iChannel0 --
    exactly how Ghostty chains multiple custom-shader lines."""
    buf = channel0
    for s in srcs:
        buf = render(ctx, s, buf, **kw)[:, :, :3].copy()
    return buf


def report(name, srcs, ctx):
    print(f"\n=== {name} ===")
    results = {}
    cases = [("blink-ON empty", True, 0.0),
             ("blink-OFF empty", False, 0.0),
             ("blink-ON glyph.5", True, 0.5),
             ("blink-ON glyph.9", True, 0.9),
             ("blink-OFF glyph.9", False, 0.9)]
    for label, visible, glyph in cases:
        ch0 = make_terminal_pass(visible, glyph)
        img = render_chain(ctx, srcs, ch0)
        ring = halo_ring_mean(img)
        x, ytop, w, h = CELL
        inside = probe(img, x + w / 2, ytop + h / 2)
        far = probe(img, 100, 100)
        bg = np.array(BG)
        lift = float(np.linalg.norm(ring - bg))
        results[label] = lift
        print(f"  {label:18s} halo_ring={ring.round(4)} inside={inside.round(4)} lift={lift:.4f}")

    print()
    on_lifts = {k: v for k, v in results.items() if k.startswith("blink-ON")}
    off_lifts = {k: v for k, v in results.items() if k.startswith("blink-OFF")}
    worst_on = min(on_lifts.values())
    worst_off = max(off_lifts.values())
    if worst_on < 0.02:
        print(f"  FAIL: halo missing during blink-ON (worst case {worst_on:.4f}) -- neon lost")
    elif worst_on < 0.15:
        print(f"  WEAK: halo present but faint in worst ON case ({worst_on:.4f})")
    else:
        print(f"  ok: halo strong in all ON cases (worst {worst_on:.4f})")
    if worst_off > 0.02:
        print(f"  FAIL: halo burns through blink-OFF (worst {worst_off:.4f})")
    else:
        print(f"  ok: halo suppressed in all OFF cases (worst {worst_off:.4f})")
    spread = max(on_lifts.values()) - worst_on
    if spread > 0.1:
        print(f"  WARN: halo brightness varies {spread:.3f} with glyph coverage -- flicker while typing")
    return results


def main():
    args = sys.argv[1:]
    chain = args or ["shaders/cursor_blaze-neon.glsl"]
    ctx = moderngl.create_standalone_context(require=330)
    srcs = []
    for f in chain:
        srcs.append(compat(open(f).read()))
    try:
        report(" -> ".join(os.path.basename(f) for f in chain), srcs, ctx)
    except Exception as e:
        print(f"  COMPILE/RUN ERROR:\n{e}")


if __name__ == "__main__":
    main()
