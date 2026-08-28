// Based on https://gist.github.com/chardskarth/95874c54e29da6b5a36ab7b50ae2d088
// Purple blaze -- NEON: cursor_blaze.glsl plus an analytic glow.
//
// The glow shape comes from the signed distance fields this shader already
// builds, not from a blur pass, so only the cursor and its trail glow -- text
// and background gain nothing.
//
// IMPORTANT: blink detection samples iChannel0 (5 fetches per fragment, all at
// the same 5 texels), so this shader is NOT independent of its position in the
// custom-shader chain -- it reads whatever the previous stage produced. Moving
// it earlier or later changes what the detector sees.
//
// Diff vs cursor_blaze.glsl: GLOW_* constants, brightness()/samplePresence()
// helpers, the blink detector, sdfCursor/glowRadius hoisted out of the trail
// branch, two additive glow terms, and a final clamp. Everything else is stock.
#define TRAIL_LENGTH   1.5
#define TRAIL_DURATION 0.35
#define EASE_POWER     4.0

float ease(float x) {
    return pow(1.0 - x, EASE_POWER);
}

float getSdfRectangle(in vec2 p, in vec2 xy, in vec2 b)
{
    vec2 d = abs(p - xy) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
// Based on Inigo Quilez's 2D distance functions article: https://iquilezles.org/articles/distfunctions2d/
// Potencially optimized by eliminating conditionals and loops to enhance performance and reduce branching
float seg(in vec2 p, in vec2 a, in vec2 b, inout float s, float d) {
    vec2 e = b - a;
    vec2 w = p - a;
    vec2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float segd = dot(p - proj, p - proj);
    d = min(d, segd);

    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
    float flip = mix(1.0, -1.0, step(0.5, allCond + noneCond));
    s *= flip;
    return d;
}

float getSdfParallelogram(in vec2 p, in vec2 v0, in vec2 v1, in vec2 v2, in vec2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);

    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);

    return s * sqrt(d);
}

vec2 normalize(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

float blend(float t)
{
    float sqr = t * t;
    return sqr / (2.0 * (sqr - t) + 1.0);
}

float antialising(float distance) {
    return 1. - smoothstep(0., normalize(vec2(2., 2.), 0.).x, distance);
}

float determineStartVertexFactor(vec2 a, vec2 b) {
    // Conditions using step
    float condition1 = step(b.x, a.x) * step(a.y, b.y); // a.x < b.x && a.y > b.y
    float condition2 = step(a.x, b.x) * step(b.y, a.y); // a.x > b.x && a.y < b.y

    // If neither condition is met, return 1 (else case)
    return 1.0 - max(condition1, condition2);
}
vec2 getRectangleCenter(vec4 rectangle) {
    return vec2(rectangle.x + (rectangle.z / 2.), rectangle.y - (rectangle.w / 2.));
}

// Brightness of a pixel, used to detect the blink phase: a drawn cursor cell is
// far brighter than the background behind it, whatever color it happens to be.
// Deliberately color-agnostic -- an earlier version keyed on "purpleness", which
// silently disabled the glow whenever cursor-color was not purple.
float brightness(vec3 c) {
    return max(max(c.r, c.g), c.b);
}

// Sample iChannel0 at a position given in the shader's -1..1 space.
// Inverse of normalize(fragCoord, 1.), then to 0..1 UV.
float samplePresence(vec2 posN) {
    vec2 uv = (posN * iResolution.y + iResolution.xy) * 0.5 / iResolution.xy;
    return brightness(texture(iChannel0, uv).rgb);
}

const vec4 TRAIL_COLOR = vec4(0.678, 0.361, 0.949, 1.0); // purple
const vec4 TRAIL_COLOR_ACCENT = vec4(0.898, 0.502, 1.000, 1.0); // purple accent
const float DURATION = TRAIL_DURATION;
// Glow halo. GLOW_RADIUS_PX is the exponential's falloff constant in *physical*
// pixels (so it covers fewer logical cells on a Retina display, where a cell is
// more pixels). Visible lift extends well past it -- roughly 4x -- because the
// exponential has no cutoff; treat it as a softness knob, not an extent.
// Radius is what reads as "neon" -- widen it before pushing strength past 1.0.
const float GLOW_RADIUS_PX = 12.0;
const float GLOW_STRENGTH = 0.6;
// Flat fill applied to the block's interior while the cursor is drawn, on top of
// Ghostty's own cursor color. Tints the block to match the halo so the two read
// as one lit object rather than a solid block inside a separate ring. Keep it
// low: it composites over the glyph under the cursor.
const float GLOW_STRENGTH_INNER = 0.25;
// Don't draw trail within that distance * cursor size.
// This prevents trails from appearing when typing.
const float DRAW_THRESHOLD = 1.5;
// Don't draw trails within the same line: same line jumps are usually where
// people expect them.
const bool HIDE_TRAILS_ON_THE_SAME_LINE = false;

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #endif
    //Normalization for fragCoord to a space of -1 to 1;
    vec2 vu = normalize(fragCoord, 1.);
    vec2 offsetFactor = vec2(-.5, 0.5);

    //Normalization for cursor position and size;
    //cursor xy has the postion in a space of -1 to 1;
    //zw has the width and height
    vec4 currentCursor = vec4(normalize(iCurrentCursor.xy, 1.), normalize(iCurrentCursor.zw, 0.));
    vec4 previousCursor = vec4(normalize(iPreviousCursor.xy, 1.), normalize(iPreviousCursor.zw, 0.));

    //When drawing a parellelogram between cursors for the trail i need to determine where to start at the top-left or top-right vertex of the cursor
    float vertexFactor = determineStartVertexFactor(currentCursor.xy, previousCursor.xy);
    float invertedVertexFactor = 1.0 - vertexFactor;

    //Set every vertex of my parellogram
    vec2 v0 = vec2(currentCursor.x + currentCursor.z * vertexFactor, currentCursor.y - currentCursor.w);
    vec2 v1 = vec2(currentCursor.x + currentCursor.z * invertedVertexFactor, currentCursor.y);
    vec2 v2 = vec2(previousCursor.x + currentCursor.z * invertedVertexFactor, previousCursor.y);
    vec2 v3 = vec2(previousCursor.x + currentCursor.z * vertexFactor, previousCursor.y - previousCursor.w);

    vec4 newColor = vec4(fragColor);

    float progress = blend(clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1));
    float easedProgress = ease(progress);

    //Distance between cursors determine the total length of the parallelogram;
    vec2 centerCC = getRectangleCenter(currentCursor);
    vec2 centerCP = getRectangleCenter(previousCursor);
    float cursorSize = max(currentCursor.z, currentCursor.w);
    float trailThreshold = DRAW_THRESHOLD * cursorSize;
    float lineLength = distance(centerCC, centerCP);
    //
    // Hoisted out of the trail branch: the cursor halo has to be drawn on every
    // frame, not only while a jump is in flight.
    float sdfCursor = getSdfRectangle(vu, currentCursor.xy - (currentCursor.zw * offsetFactor), currentCursor.zw * 0.5);
    float glowRadius = normalize(vec2(GLOW_RADIUS_PX, GLOW_RADIUS_PX), 0.).x;

    // Blink detection. No uniform reports cursor visibility, so infer it from
    // the cell Ghostty already drew: a drawn cursor fills its whole cell with a
    // color that contrasts against the surrounding background.
    //
    // Measured as *contrast against a nearby reference cell*, in absolute value,
    // so it holds on light themes (dark cursor on light bg) as well as dark ones
    // and for any cursor-color. Earlier versions keyed on hue (broke whenever
    // cursor-color changed) and then on signed brightness (broke on light
    // themes) -- both failed silently, with no halo at all.
    vec2 cursorCenter = currentCursor.xy - (currentCursor.zw * offsetFactor);

    // Reference cell: 3 cells to the side, vertically centred -- a whole number
    // of cells so the sample lands mid-cell rather than on a cell boundary where
    // it would straddle two glyphs. Sample to the right when the cursor is near
    // the left edge, otherwise the offset falls outside the texture and the
    // wrap mode (which the shader does not control) decides the result: clamp
    // returns the edge pixel and repeat wraps to the far right, both wrong.
    float refDist = currentCursor.z * 3.0;
    float refDir = (cursorCenter.x - refDist < -1. * iResolution.x / iResolution.y) ? 1. : -1.;
    float ref = samplePresence(cursorCenter + vec2(refDir * refDist, 0.));

    // Probe the cell at 35% of its half-extent: comfortably inside the
    // antialiased border (which 45% grazes on fractional font metrics) while
    // still outside where most glyph strokes reach.
    vec2 q = currentCursor.zw * 0.35;
    float c0 = samplePresence(cursorCenter + vec2(q.x, q.y));
    float c1 = samplePresence(cursorCenter + vec2(-q.x, q.y));
    float c2 = samplePresence(cursorCenter + vec2(q.x, -q.y));
    float c3 = samplePresence(cursorCenter + vec2(-q.x, -q.y));

    // Mean, not min: a single corner clipped by a descender or a diagonal (`_`,
    // `/`) must not zero the halo, or it flickers off while typing. The mean
    // still separates a filled block from a glyph, which leaves most of the
    // cell at background. abs() so dark-on-light contrasts as well as
    // light-on-dark.
    float cell = 0.25 * (c0 + c1 + c2 + c3);
    float coverage = abs(cell - ref);
    float cursorVisible = smoothstep(0.15, 0.4, coverage);

    bool isFarEnough = lineLength > trailThreshold;
    bool isOnSeparateLine = HIDE_TRAILS_ON_THE_SAME_LINE ? currentCursor.y != previousCursor.y : true;
    if (isFarEnough && isOnSeparateLine) {
        float distanceToEnd = distance(vu.xy, centerCC);
        float alphaModifier = distanceToEnd / (lineLength * (easedProgress) * TRAIL_LENGTH);

        if (alphaModifier > 1.0) { // this change fixed it for me.
            alphaModifier = 1.0;
        }

        float sdfTrail = getSdfParallelogram(vu, v0, v1, v2, v3);

        newColor = mix(newColor, TRAIL_COLOR_ACCENT, 1.0 - smoothstep(sdfTrail, -0.01, 0.001));
        newColor = mix(newColor, TRAIL_COLOR, antialising(sdfTrail));
        // Halo around the trail. Goes before the alphaModifier mix below so the
        // glow fades along the streak with the rest of it. max() clamps the
        // interior to distance 0 so exp() doesn't blow up on negative distances.
        // Gated by cursorVisible for the same reason the cursor halo is -- so
        // the streak and the block's halo blink together rather than the trail
        // glowing on while the cursor's halo is dark.
        newColor.rgb += TRAIL_COLOR.rgb * exp(-max(sdfTrail, 0.) / glowRadius)
                      * GLOW_STRENGTH * cursorVisible;
        newColor = mix(fragColor, newColor, 1.0 - alphaModifier);
        fragColor = mix(newColor, fragColor, step(sdfCursor, 0));
    }

    // Halo around the cursor block. Last, so it lands on top of whatever the
    // branch above wrote. Outer term falls off with distance outside the block;
    // inner term is a flat fill of the block itself. Both scale by cursorVisible
    // so the glow blinks in step with Ghostty's cursor rather than burning
    // through the off phase.
    float outer = exp(-max(sdfCursor, 0.) / glowRadius) * step(0., sdfCursor);
    float inner = 1.0 - step(0., sdfCursor);
    float glowAmount = (outer * GLOW_STRENGTH + inner * GLOW_STRENGTH_INNER) * cursorVisible;
    fragColor.rgb += TRAIL_COLOR.rgb * glowAmount;

    // The background is translucent when background-opacity < 1, and an additive
    // glow that leaves alpha alone would composite over the desktop -- making the
    // halo's apparent brightness depend on the wallpaper. Raise alpha with it.
    fragColor.a = max(fragColor.a, clamp(glowAmount, 0., 1.));

    // Clamp last. The additive terms can push channels past 1.0, and channels
    // clip independently, which rotates the hue: [1.07, 0.59, 1.24] clips to
    // [1.0, 0.59, 1.0], turning the brightest part of the halo magenta.
    fragColor.rgb = min(fragColor.rgb, vec3(1.0));
}
