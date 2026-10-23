// Morph: the window melts into a swirling, liquid flow and dissolves.
// Ported from Burn-My-Windows (resources/shaders/morph.frag). Only the window layer is drawn: the desktop
// behind the window isn't captured, so the real one shows through instead of being warped.
//
// The flow field is procedural: a curl-noise field (swirly, liquid, no sources or sinks) plus a gentle radial
// push away from the window's centre. Both are applied to the window while it dissolves unevenly
// (a low-frequency noise threshold), so it leaves in blotches rather than fading uniformly.
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float FLOW_PX        = 30.0;   // how far the liquid flow displaces pixels at its peak
constant float FLOW_SCALE     = 160.0;  // size of the swirls in px
constant float RADIAL_PX      = 30.0;   // extra push away from the window's centre
constant float SPILL_PX       = 5.0;    // the morph reaches this far outside the window, feathered
constant float CORNER_PX      = 24.0;   // rounding of the morph region's corners
constant float BLUR_PX        = 6.0;    // blur radius at the peak of the displacement
constant float DISSOLVE_SCALE = 380.0;  // size of the dissolve blotches in px
constant float DISSOLVE_EDGE  = 0.22;   // softness of the dissolve front

// Edge-guided melt: each layer is pushed around by the edges of its own image.
constant float MELT_PX     = 40.0;
constant float MELT_RADIUS = 8.0;
constant float MELT_ALONG  = 0.7;
constant float MELT_ACROSS = 0.5;
constant float MELT_NOISE  = 0.35;
constant int   MELT_STEPS  = 3;
constant float EDGE_FIRST  = 0.35;

// Timeline (fractions of the opening progress, 0 -> 1).
constant float2 T_WINDOW = float2(0.40, 1.00);  // the window's displacement shrinks to 0 over this span
constant float2 T_FADE   = float2(0.20, 0.85);  // the dissolve from surface to window

// Stream function for the curl noise: two octaves of simplex noise.
inline float streamFn(float2 p) {
  return simplex2D(p) + 0.5 * simplex2D(p * 2.03 + float2(17.1, 5.3));
}

inline float luma(float4 c) {
  // Transparent counts as mid-grey, so the window's outline is an edge too.
  return c.a * dot(c.rgb, float3(0.299, 0.587, 0.114)) + (1.0 - c.a) * 0.5;
}
//@@
  float gProgress;
  bool MELT;
  float gBlur;
  float gEdge;

  float span(vec2 t) { return smoothstep(t.x, t.y, gProgress); }

  // Signed distance to the frame rect, rounded by CORNER_PX (> 0 outside).
  float frameDist(vec2 px) {
    vec2 c = uFrameRect.xy + 0.5 * uFrameRect.zw;
    vec2 h = max(0.5 * uFrameRect.zw - CORNER_PX, vec2(0.0));
    vec2 q = abs(px - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - CORNER_PX;
  }

  // 1 inside the window, fading to 0 SPILL_PX outside it.
  float regionMask(vec2 px) { return 1.0 - smoothstep(0.0, SPILL_PX, frameDist(px)); }

  // The full flow field at layer pixel px, in pixels (before the timeline scales it).
  vec2 flowAt(vec2 px) {
    float m = regionMask(px);
    if (m <= 0.0) return vec2(0.0);

    vec2 p        = px / FLOW_SCALE + uSeed * 100.0;
    const float E = 0.01;
    float dx      = (streamFn(p + vec2(E, 0.0)) - streamFn(p - vec2(E, 0.0))) / (2.0 * E);
    float dy      = (streamFn(p + vec2(0.0, E)) - streamFn(p - vec2(0.0, E))) / (2.0 * E);
    vec2 c        = vec2(dy, -dx);
    c /= 2.3 + 0.3 * length(c);  // ~unit length, soft-limited

    // Push away from the centre, strongest halfway out.
    vec2 centre  = uFrameRect.xy + 0.5 * uFrameRect.zw;
    vec2 rel     = (px - centre) / max(0.5 * uFrameRect.zw, vec2(1.0));
    float r      = length(rel);
    vec2 radial  = r > 1e-4 ? rel / r * sin(3.14159 * min(r, 1.0)) : vec2(0.0);

    return m * uStrength * (c * FLOW_PX + radial * RADIAL_PX);
  }

  // Straight-alpha read of the window at texture coord tc. It has nothing outside its texture.
  vec4 readLayer(vec2 tc) {
    if (any(tc < vec2(0.0)) || any(tc > vec2(1.0))) {
      return vec4(0.0);
    }
    return getInputColor(tc);
  }

  // A small disc blur of radius r px around tc, averaged with premultiplied alpha.
  vec4 blurredRead(vec2 tc, float r) {
    if (r < 0.5) return readLayer(tc);
    vec4 acc = vec4(0.0);
    float n  = 0.0;
    for (int i = 0; i < 13; i++) {
      vec2 o;
      if (i == 0) {
        o = vec2(0.0);
      } else {
        float k   = float(i - 1);
        float ang = k * 0.5235988 + (k < 6.0 ? 0.0 : 0.2617994);  // two rings of 6, offset
        float rad = k < 6.0 ? 0.5 * r : r;
        o         = vec2(cos(ang), sin(ang)) * rad;
      }
      vec4 smp = readLayer(tc + o / uTexRect.zw);
      acc += vec4(smp.rgb * smp.a, smp.a);
      n += 1.0;
    }
    acc /= n;
    return acc.a > 0.0 ? vec4(acc.rgb / acc.a, acc.a) : vec4(0.0);
  }

  // Melt direction at texture coord tc, from the image itself: "along the contour" and "across it".
  vec2 meltDir(vec2 tc) {
    vec2 g = vec2(0.0);
    for (int k = 0; k < 8; k++) {
      float ang = float(k) * 0.7853982;
      vec2 dir  = vec2(cos(ang), sin(ang));
      g += luma(readLayer(tc + dir * MELT_RADIUS / uTexRect.zw)) * dir;
    }
    g *= 0.25;
    float len = length(g);
    if (len < 1e-4) return vec2(0.0);
    float strength = smoothstep(0.02, 0.25, len);
    if (gEdge < 0.0) gEdge = strength;
    vec2 n = g / len;
    return strength * (MELT_ALONG * vec2(-n.y, n.x) + MELT_ACROSS * n);
  }

  // Moves texture coord tc through the melt field, amt = signed share of the full motion.
  vec2 meltAdvect(vec2 tc, float amt, vec2 px, vec2 flow) {
    float m = regionMask(px);
    gEdge   = -1.0;
    for (int i = 0; i < MELT_STEPS; i++) {
      vec2 d = m * meltDir(tc) * MELT_PX * uStrength + flow * MELT_NOISE;
      tc += d * amt / float(MELT_STEPS) / uTexRect.zw;
    }
    if (gEdge < 0.0) gEdge = 0.0;
    return tc;
  }

  float4 run() {
    gProgress = uForOpening ? uProgress : 1.0 - uProgress;
    MELT      = uStyle > 0.5;
    gBlur     = BLUR_PX * min(uStrength, 1.0);
    gEdge     = 0.0;

    vec2 px   = getLayerPx();
    vec2 flow = flowAt(px);

    float w = 1.0 - span(T_WINDOW);
    float f = span(T_FADE);

    if (w <= 0.0 && f >= 1.0) {
      return getInputColor(iTexCoord);  // at rest
    }

    // The window is carried away along the flow.
    vec2 tc     = MELT ? meltAdvect(iTexCoord, w, px, flow) : iTexCoord + flow * w / uTexRect.zw;
    vec4 oColor = blurredRead(tc, gBlur * w * regionMask(px));

    // Uneven dissolve: each spot has its own threshold n in [0, 1]; the fade front f sweeps from
    // below 0 to above 1.
    float n = simplex2D(px / DISSOLVE_SCALE + uSeed * 37.0 + 3.7);
    n       = clamp((n - 0.5) * 1.6 + 0.5, 0.0, 1.0);
    float early = MELT ? EDGE_FIRST : 0.0;
    n -= early * gEdge;  // strong edges of the window leave first
    float a = smoothstep(n - DISSOLVE_EDGE, n + DISSOLVE_EDGE, mix(-DISSOLVE_EDGE - early, 1.0 + DISSOLVE_EDGE, f));
    oColor.a *= a;
    return oColor;
  }
