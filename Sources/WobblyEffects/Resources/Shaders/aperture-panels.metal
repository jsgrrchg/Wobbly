// Aperture Panels: the window is split into a grid of panels, like the moving wall panels in the Portal games,
// which flip over one after another. Closing flips them from showing the window to showing what is behind it.
// Ported from Burn-My-Windows (resources/shaders/aperture-panels.frag). The original draws two layers (the
// windows behind, and the window); here the desktop behind is live, so only the window's side of the panels
// is drawn, and the other side is left transparent.
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float SPREAD        = 0.6;    // part of the timeline the wave takes to cross the window
constant float JITTER        = 0.0;    // 0 = clean wave
constant float WAVE_AMP      = 0.08;   // shapes 2 and 3: how far the edge bends (fraction of the sweep)
constant float WAVE_FREQ     = 2.0;    // shape 2: ripples along the edge
constant float WAVE_NOISE_PX = 300.0;  // shape 3: size of the noise bends, in pixels

// Panel borders: a wave of outlines runs ahead of the flip wave and/or another wave removes them behind it.
constant float BORDER_LEAD  = 0.25;
constant float BORDER_TRAIL = 0.15;
constant float BORDER_PX    = 1.0;  // line width drawn by each panel
constant float EDGE_SHADE   = 0.4;  // brightness of a panel seen edge-on (1 = no shading)
constant float PERSPECTIVE  = 2.5;  // camera distance in window sizes; larger = subtler 3D
constant float PI           = 3.14159265;

// Easter egg ("The cake is a lie!"): a cake peeking through the gaps between the turning panels.
constant float CAKE_PX        = 128.0;
constant float CAKE_MIN_SCALE = 3.0;

inline float panelHash(float2 p) {
  p = fract(p * float2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

// Signed distance from p to a rounded rectangle centred on the origin, with half-size b and corner radius r.
inline float sdRoundBox(float2 p, float2 b, float r) {
  float2 d = abs(p) - b + r;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// Paints one shape over what was painted before; the smoothstep anti-aliases its edge.
#define CAKE_LAYER(d, c) { float m = smoothstep(aa, -aa, d); col = mix(col, c, m); a = max(a, m); }

// The cake, in straight alpha. p: centred on the cake, y up, the cake fits in [-0.8, 0.8].
// aa: the size of one pixel in those units. t: time in seconds (for the candle flame).
inline float4 drawCake(float2 p, float aa, float t) {
  float3 col = float3(0.0);
  float a    = 0.0;

  float3 sponge  = float3(0.26, 0.13, 0.07);
  float3 filling = float3(0.45, 0.26, 0.15);
  float3 icing   = float3(0.17, 0.08, 0.04);
  float3 cream   = float3(0.98, 0.95, 0.90);

  CAKE_LAYER(sdRoundBox(p - float2(0.0, -0.58), float2(0.78, 0.04), 0.04), float3(0.78, 0.80, 0.82));  // plate
  CAKE_LAYER(sdRoundBox(p - float2(0.0, -0.26), float2(0.56, 0.29), 0.06), sponge);
  CAKE_LAYER(sdRoundBox(p - float2(0.0, -0.26), float2(0.56, 0.03), 0.02), filling);
  CAKE_LAYER(sdRoundBox(p - float2(0.0, 0.06), float2(0.58, 0.07), 0.07), icing);

  // Glaze drips running down the sponge, each with a pseudo-random length.
  for (int i = 0; i < 6; i++) {
    float x   = -0.45 + float(i) * 0.18;
    float len = 0.04 + 0.05 * fract(sin(float(i) * 12.9898) * 43758.5453);
    CAKE_LAYER(sdRoundBox(p - float2(x, -0.02 - len * 0.5), float2(0.035, len), 0.035), icing);
  }
  CAKE_LAYER(sdRoundBox(p - float2(-0.12, 0.10), float2(0.30, 0.012), 0.012), float3(0.42, 0.25, 0.15));

  // Two pairs of cherries, each on a dollop of cream, leaving room for the candle between.
  for (int i = 0; i < 4; i++) {
    float x = (i < 2) ? -0.42 + float(i) * 0.2 : 0.22 + float(i - 2) * 0.2;
    CAKE_LAYER(length(p - float2(x, 0.15)) - 0.06, cream);
    CAKE_LAYER(length(p - float2(x, 0.21)) - 0.055, float3(0.70, 0.05, 0.08));
  }

  // A candle with diagonal red and white stripes and a flickering flame on top.
  float3 stripe = mix(float3(1.0), float3(0.85, 0.15, 0.2), step(0.5, fract((p.y + p.x) * 14.0)));
  CAKE_LAYER(sdRoundBox(p - float2(0.0, 0.30), float2(0.03, 0.17), 0.01), stripe);
  float2 fp   = p - float2(0.01 * sin(t * 31.0), 0.56);
  float flame = length(fp * float2(1.0, 0.55 + 0.15 * step(0.0, fp.y))) - 0.045;
  CAKE_LAYER(flame, mix(float3(1.0, 0.55, 0.1), float3(1.0, 0.95, 0.6), smoothstep(0.0, -0.04, flame)));

  return float4(col, a);
}
#undef CAKE_LAYER
//@@
  float gProgress;
  int gWaveShape;
  bool gVertical;
  bool gBorder;
  float gBorderLead;
  float gBorderTrail;

  // Where along the sweep (0..1) the panel at grid position `cell` sits: 0 flips first, 1 flips last.
  //   0 = straight diagonal line, 1 = arc spreading from the top-left corner, 2 = wavy diagonal,
  //   3 = organic diagonal bent by smooth noise, 4 = ripple from the centre.
  float wavePosition(vec2 cell) {
    vec2 pos    = (cell + 0.5) * uCell;  // panel centre, pixels from the window's top-left
    vec2 size   = uFrame.zw;
    float diag  = (pos.x + pos.y) / (size.x + size.y);

    if (gWaveShape == 1) {
      return length(pos) / length(size);
    }
    if (gWaveShape == 2) {
      float along = (pos.x - pos.y) / (size.x + size.y);
      float bent  = diag + WAVE_AMP * sin(along * WAVE_FREQ * 2.0 * PI);
      return (bent + WAVE_AMP) / (1.0 + 2.0 * WAVE_AMP);
    }
    if (gWaveShape == 3) {
      float bent = diag + WAVE_AMP * (simplex2D(pos / WAVE_NOISE_PX + vec2(17.3, 5.9)) * 2.0 - 1.0);
      return (bent + WAVE_AMP) / (1.0 + 2.0 * WAVE_AMP);
    }
    if (gWaveShape == 4) {
      return length(pos - size * 0.5) / length(size * 0.5);
    }
    return diag;
  }

  // When the panel at `cell` flips, as a range of gProgress: x = start, y = end.
  vec2 cellTiming(vec2 cell) {
    float wave  = clamp(mix(wavePosition(cell), panelHash(cell), JITTER), 0.0, 1.0);
    float span  = 1.0 - gBorderLead - gBorderTrail;
    float start = gBorderLead + wave * SPREAD * span;
    return vec2(start, start + (1.0 - SPREAD) * span);
  }

  // Flip progress (0..1) of the panel at grid position `cell`.
  float cellProgress(vec2 cell) {
    vec2 t = cellTiming(cell);
    return clamp((gProgress - t.x) / (t.y - t.x), 0.0, 1.0);
  }

  // How strongly (0..1) the panel at `cell` shows its border right now.
  float cellBorder(vec2 cell) {
    vec2 t        = cellTiming(cell);
    float fadeIn  = smoothstep(t.x - max(gBorderLead, 0.001), t.x, gProgress);
    float fadeOut = smoothstep(t.y, t.y + max(gBorderTrail, 0.001), gProgress);
    return gBorder ? fadeIn * (1.0 - fadeOut) : 0.0;
  }

  float4 run() {
    gProgress    = uForOpening ? uProgress : 1.0 - uProgress;
    gWaveShape   = int(uWaveShape + 0.5);
    gVertical    = uVerticalAxis > 0.5;
    int style    = int(uBorderStyle + 0.5);
    gBorder      = style > 0 && uBorderColor.a > 0.0;
    gBorderLead  = (style == 2 || style == 4) ? BORDER_LEAD : 0.0;
    gBorderTrail = (style == 3 || style == 4) ? BORDER_TRAIL : 0.0;

    vec4 oColor = vec4(0.0);
    vec2 px     = getLayerPx();
    vec2 q      = px - uFrame.xy;  // relative to the visible window

    if (any(q < vec2(0.0)) || any(q >= uFrame.zw)) {
      // Shadow margin: outside the visible window, no panels. The shadow fades with the nearest edge panel.
      oColor        = getInputColor(iTexCoord);
      vec2 nearest  = floor(clamp(q, vec2(0.0), uFrame.zw - 0.001) / uCell);
      float reveal  = clamp(cellProgress(nearest) * 2.0 - 1.0, 0.0, 1.0);
      oColor.a *= reveal;
      return oColor;
    }

    // Panels over the visible window.
    vec2 cell    = floor(q / uCell);
    vec2 cellUV  = (q - cell * uCell) / uCell;
    float local  = cellProgress(cell);
    float squash = abs(cos(local * PI));

    // Rotate the panel around its centre axis and project it with the vanishing point in the middle of the
    // window. We invert the projection: from the screen position, find the position on the panel itself.
    float theta = local * PI;
    float cT    = cos(theta);
    float sT    = sin(theta);
    float dist  = PERSPECTIVE * max(uFrame.z, uFrame.w);  // camera distance

    vec2 centre = (cell + 0.5) * uCell - uFrame.zw * 0.5;  // panel centre from window centre
    vec2 screen = centre + (cellUV - 0.5) * uCell;         // fragment from window centre
    if (!gVertical) {
      centre = centre.yx;
      screen = screen.yx;
    }

    bool onPanel = false;
    vec2 panelUV = cellUV;
    float den    = dist * cT + screen.x * sT;
    if (abs(den) > 0.001) {
      float u = dist * (screen.x - centre.x) / den;
      float s = dist / (dist - u * sT);
      float v = screen.y / s - centre.y;
      if (local > 0.5) u = -u;  // the back face is not mirrored
      vec2 m  = gVertical ? vec2(u, v) : vec2(v, u);
      panelUV = m / uCell + 0.5;

      // A pixel on a shared edge can land just outside [0, 1] and leave a gap.
      const float EPS = 0.002;
      onPanel = dist - u * sT > 0.0 && all(panelUV >= vec2(-EPS)) && all(panelUV <= vec2(1.0 + EPS));
      panelUV = clamp(panelUV, 0.0, 1.0);
    }

    if (onPanel) {
      // Only the window's face is drawn: panels that are past 90 degrees. The other face stays transparent.
      vec4 panel = vec4(0.0);
      if (local > 0.5) {
        panel = getLayerColor(uFrame.xy + (cell + panelUV) * uCell);
      }

      // Shade the panel as it turns edge-on (none at local = 0 and 1).
      panel.rgb *= mix(EDGE_SHADE, 1.0, squash);

      // The panel border (see uBorderStyle), drawn on its own where the face is bare.
      float amount = cellBorder(cell);
      if (amount > 0.0) {
        vec2 rimScale = gVertical ? vec2(uCell.x * squash, uCell.y) : vec2(uCell.x, uCell.y * squash);
        vec2 edge     = min(panelUV, 1.0 - panelUV) * rimScale;
        float line    = 1.0 - smoothstep(BORDER_PX - 0.5, BORDER_PX + 0.5, min(edge.x, edge.y));
        vec4 border   = uBorderColor;
        border.a *= line * amount;
        panel = alphaOver(panel, border);
      }
      return panel;
    }

    // A gap between turning panels: transparent, so the desktop shows through. Easter egg: the cake
    // sits on the backdrop, so it only peeks through the gaps.
    if (uShowCake > 0.5 && all(uFrame.zw >= vec2(CAKE_PX * CAKE_MIN_SCALE))) {
      // uCakePos picks the cake's centre so that the whole cake stays inside the window.
      vec2 cakeCentre = CAKE_PX * 0.5 + uCakePos * (uFrame.zw - CAKE_PX);
      vec2 c          = (q - cakeCentre) / (CAKE_PX * 0.5) * 0.8;  // cake units
      c.y             = -c.y;

      // Only pixels near the cake are drawn, which keeps the cost low elsewhere.
      if (all(abs(c) <= vec2(0.82))) {
        oColor = alphaOver(oColor, drawCake(c, 0.8 / (CAKE_PX * 0.5), uProgress * uDuration));
      }
    }
    return oColor;
  }
