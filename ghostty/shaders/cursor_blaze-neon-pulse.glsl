// Based on https://gist.github.com/chardskarth/95874c54e29da6b5a36ab7b50ae2d088
// Purple blaze -- NEON PULSE: cursor_blaze.glsl plus a slow breathing glow.
//
// Variant of cursor_blaze-neon.glsl. Same analytic halo (shape comes from the
// shader's own signed distance fields, not a blur, so only the cursor and its
// trail glow -- text and background gain nothing), but the halo's brightness is
// driven by a sine on iTime instead of by trying to detect Ghostty's cursor
// blink.
//
// Why: no uniform reports cursor visibility. The -neon variant infers it by
// sampling the cursor cell out of iChannel0 and asking "is this cell filled?".
// That premise is false -- glyphs fill cells too. At real font metrics the
// detector confuses letters like M and W with the cursor in both directions,
// which shows up as the halo dropping out, dimming, or burning through the
// blink-off phase depending on what character the cursor is sitting on.
//
// This variant samples nothing and therefore cannot get it wrong. The halo
// never reaches zero, so there is no phase where a lit ring surrounds an unlit
// block -- meaning it does NOT require cursor-style-blink = false, though it
// looks more coherent with Ghostty's own blink off (see the config comment).
//
// Because it makes no texture fetches beyond the stock passthrough, its output
// does not depend on where it sits in the custom-shader chain.
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
// Flat fill applied to the block's interior, on top of Ghostty's own cursor
// color. Tints the block to match the halo so the two read as one lit object
// rather than a solid block inside a separate ring. Keep it low: it composites
// over the glyph under the cursor.
const float GLOW_STRENGTH_INNER = 0.25;
// Breathing pulse. FLOOR is the dimmest the halo ever gets and DEPTH is how far
// it swings above that, so the halo rides between FLOOR and FLOOR+DEPTH.
// FLOOR must stay above 0 -- that is what keeps the block from ever sitting in
// an unlit hole inside a lit ring. SPEED is radians/sec: 2.2 gives a ~2.9s
// period, slow enough to read as breathing rather than flashing.
const float PULSE_FLOOR = 0.72;
const float PULSE_DEPTH = 0.28;
const float PULSE_SPEED = 2.2;
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

    // The breathing pulse, in place of blink detection. Purely a function of
    // time, so it is identical regardless of what glyph the cursor sits on and
    // cannot be fooled by cell contents.
    float pulse = PULSE_FLOOR + PULSE_DEPTH * sin(iTime * PULSE_SPEED);

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
        // Shares the pulse with the cursor halo so the two breathe together.
        newColor.rgb += TRAIL_COLOR.rgb * exp(-max(sdfTrail, 0.) / glowRadius)
                      * GLOW_STRENGTH * pulse;
        newColor = mix(fragColor, newColor, 1.0 - alphaModifier);
        fragColor = mix(newColor, fragColor, step(sdfCursor, 0));
    }

    // Halo around the cursor block. Last, so it lands on top of whatever the
    // branch above wrote. Outer term falls off with distance outside the block;
    // inner term is a flat fill of the block itself.
    float outer = exp(-max(sdfCursor, 0.) / glowRadius) * step(0., sdfCursor);
    float inner = 1.0 - step(0., sdfCursor);
    float glowAmount = (outer * GLOW_STRENGTH + inner * GLOW_STRENGTH_INNER) * pulse;
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
