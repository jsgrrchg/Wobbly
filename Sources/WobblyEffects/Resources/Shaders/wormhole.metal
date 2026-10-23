// Wormhole: the desktop is a rubber sheet that gets sucked into the screen around the window's centre. Its depth
// goes to infinity at a "throat", so the sheet turns into a tube that runs down to a vanishing point, and depth
// fog turns it black. The window lies on the sheet (same warp, fog and lighting) and is carried away with it.
// Ported from Burn-My-Windows (resources/shaders/wormhole.frag). Only the window layer is drawn: the desktop
// behind the window isn't captured, so the real one stays flat and the void is transparent.
//
// Geometry is done in "portal space": v = (pixel - uCenter) / gAxes, and the distance from the centre is a
// superellipse norm of v. The camera sits CAMERA_DIST above the centre looking straight down; a point at depth z
// below the screen is seen at v * CAMERA_DIST / (CAMERA_DIST + z).
// Sheet depth at norm u: gAmp * (1 - u)^2 / (u - gThroat)^THROAT_EXP.
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float SHAPE_POWER = 2.5;  // 2 = ellipse, higher = more like a rounded rectangle
constant float CAMERA_DIST = 1.5;  // camera height (portal-space units); lower = stronger perspective
constant float AMPLITUDE   = 0.5;  // overall depth of the funnel
constant float THROAT_EXP  = 1.0;  // how sharply the sheet plunges near the throat

// The funnel keeps widening while the window rises. Where each quantity starts, as a fraction of its final value:
constant float AMP_START    = 0.6;
constant float THROAT_START = 0.35;
constant float SPREAD_START = 0.55;

constant float FOG_BASE   = 0.9;   // darkening per unit of depth at tunnel depth 1
constant float WALL_LIGHT = 0.35;  // directional light on the funnel walls (0 = none)
constant float2 LIGHT_TO  = float2(0.7071, 0.7071);  // light comes from the top-left

constant float WIN_SHEET_START = 0.12;  // the window's size on the sheet when it starts rising

// The tube has a floor: while it's low the void looks bottomless. As the sheet flattens, the floor rises,
// closing the void from below and pushing the window out.
constant float FLOOR_START = 0.002;
constant float FLOOR_RISE  = 1.0;

// Timeline (as fractions of gProgress; opening runs 0 -> 1).
constant float2 T_SINK   = float2(0.00, 0.30);  // the sheet is sucked in
constant float2 T_WIDEN  = float2(0.05, 0.50);  // ...and keeps widening until the window shows
constant float2 T_APPEAR = float2(0.38, 0.48);  // the window fades in
constant float2 T_FLAT   = float2(0.45, 1.00);  // the sheet flattens, pushing the window out...
constant float2 T_RISE   = float2(0.40, 0.95);  // ...growing to its full size on screen

// Bounce: the sheet dips back into a shallow dimple a few times, each bounce smaller and shorter.
constant bool  BOUNCE          = true;  // opening
constant bool  BOUNCE_ON_CLOSE = true;  // closing
constant int   BOUNCE_COUNT    = 3;
constant bool  BOUNCE_KEEP_INTRO = true;
constant float BOUNCE_WINDOW   = 0.0;
constant int   SOLVE_STEPS     = 24;  // bisection steps (depth changes fast near the throat)

inline float shapeNorm(float2 v) {
  float2 a = abs(v);
  return pow(pow(a.x, SHAPE_POWER) + pow(a.y, SHAPE_POWER), 1.0 / SHAPE_POWER);
}

// Accelerating into the landing (a falling ball: no easing out).
inline float fallSpan(float2 t, float progress) {
  float x = clamp((progress - t.x) / (t.y - t.x), 0.0, 1.0);
  return x * x;
}
//@@
  float gProgress;    // 0 = nothing of the window, 1 = the window at rest
  float gAmp;         // current funnel amplitude (0 = flat)
  float gThroat;      // current throat radius
  float gFog;         // darkening per unit of depth
  float gFloor;       // current tube floor
  float gSheetScale;  // the window's scale on the sheet (1 = its real size)
  vec2 gAxes;         // current funnel semi-axes in pixels
  float gWinAlpha;

  // Depth of the sheet at norm u. It plunges towards the throat, down to the floor.
  float surfaceDepth(float u) {
    if (u >= 1.0 || gAmp <= 0.0) return 0.0;
    float d = max(u - gThroat, 0.0) + gFloor;
    return gAmp * (1.0 - u) * (1.0 - u) / pow(d, THROAT_EXP);
  }

  // Where a sheet point at norm u appears on screen (as a norm).
  float project(float u) { return u * CAMERA_DIST / (CAMERA_DIST + surfaceDepth(u)); }

  // Inverse of project(): the sheet point seen at screen norm uq (project() rises monotonically).
  float unproject(float uq) {
    if (uq >= 1.0 || gAmp <= 0.0) return uq;
    float lo = 0.0;
    float hi = 1.0;
    for (int i = 0; i < SOLVE_STEPS; i++) {
      float mid = 0.5 * (lo + hi);
      if (project(mid) < uq) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return 0.5 * (lo + hi);
  }

  float span(vec2 t) { return smoothstep(t.x, t.y, gProgress); }

  // After landing: how far below "at rest" the bounce is, at time s since the landing in units of the fall's duration.
  float bounceDip(float s) {
    float start = 0.0;
    float e     = 1.0;
    for (int i = 0; i < BOUNCE_COUNT; i++) {
      e *= uBounce;
      float dur = 2.0 * e;
      if (s < start + dur) {
        float x = (s - start) / dur;
        return e * e * 4.0 * x * (1.0 - x);
      }
      start += dur;
    }
    return 0.0;
  }

  // Total time of the bounces, in units of the fall's duration.
  float bounceTime() {
    float total = 0.0;
    float e     = 1.0;
    for (int i = 0; i < BOUNCE_COUNT; i++) {
      e *= uBounce;
      total += 2.0 * e;
    }
    return total;
  }

  // The sheet point seen at layer pixel px (portal space v, screen norm uq), in layer pixels, and how bright
  // the sheet is there: fog with depth, plus light on the slopes.
  void sheetAt(vec2 px, vec2 v, float uq, thread vec2 &sheetPx, thread float &bright) {
    if (uq >= 1.0 || gAmp <= 0.0) {
      sheetPx = px;
      bright  = 1.0;
      return;
    }
    float u = unproject(uq);
    sheetPx = uCenter + v * (u / max(uq, 1e-6)) * gAxes;

    float h     = surfaceDepth(u);
    float slope = (surfaceDepth(u + 1e-3) - h) / -1e-3;
    slope       = max(slope, 0.0) / (1.0 + max(slope, 0.0));
    vec2 dir    = uq > 1e-5 ? normalize(v) : vec2(0.0);
    bright      = max(exp(-h * gFog) * (1.0 + WALL_LIGHT * dot(dir, LIGHT_TO) * slope), 0.0);
  }

  float4 run() {
    gProgress = uForOpening ? uProgress : 1.0 - uProgress;
    gFog      = FOG_BASE / max(uTunnelDepth, 0.05);

    // Bounce: the main timeline runs first, the bounces in the rest. Closing lands the funnel's collapse.
    bool bounceOn     = uBounce > 0.001;
    bool openBounce   = bounceOn && BOUNCE && uForOpening;
    bool closeBounce  = bounceOn && BOUNCE_ON_CLOSE && !uForOpening;
    float dip         = 0.0;
    bool landed       = false;
    float landAt      = 1.0;  // elapsed time (uProgress) of the landing
    if ((openBounce || closeBounce) && BOUNCE_KEEP_INTRO) {
      // Normal pace until the landing phase starts at `knee`; then the fall runs faster, so fall plus
      // bounces exactly fill the rest of the animation.
      float knee    = openBounce ? T_FLAT.x : 1.0 - T_SINK.y;
      float speed   = 1.0 + bounceTime();
      float fallDur = (1.0 - knee) / speed;
      landAt        = knee + fallDur;
      float p       = uProgress <= knee ? uProgress : min(knee + (uProgress - knee) * speed, 1.0);
      gProgress     = uForOpening ? p : 1.0 - p;
      if (uProgress > landAt) {
        landed = true;
        dip    = bounceDip((uProgress - landAt) / fallDur);
      }
    } else if (openBounce || closeBounce) {
      vec2 fall      = openBounce ? T_FLAT : T_SINK;
      float fallTime = fall.y - fall.x;
      float mainPart = 1.0 / (1.0 + bounceTime() * fallTime);
      float p        = min(uProgress / mainPart, 1.0);
      gProgress      = uForOpening ? p : 1.0 - p;
      landAt         = mainPart;
      if (uProgress > mainPart) {
        landed = true;
        dip    = bounceDip((uProgress - mainPart) / (mainPart * fallTime));
      }
    }

    float sink = span(T_SINK);
    if (closeBounce) {
      // Collapsing: accelerating to flat (no easing out), then the dips.
      float x = clamp((T_SINK.y - gProgress) / (T_SINK.y - T_SINK.x), 0.0, 1.0);
      sink    = 1.0 - x * x + dip;
    }
    float widen = span(T_WIDEN);
    float flatT = openBounce ? fallSpan(T_FLAT, gProgress) - dip : span(T_FLAT);
    if (closeBounce && landed) {
      // The closing dips use the same dimple as the opening ones. The sheet is flat at the landing either way.
      sink  = 1.0;
      widen = 1.0;
      flatT = 1.0 - dip;
    }
    float riseT = openBounce ? fallSpan(vec2(T_RISE.x, T_FLAT.y), gProgress) - dip * BOUNCE_WINDOW : span(T_RISE);
    if (openBounce && BOUNCE_KEEP_INTRO) {
      float x = clamp((uProgress - T_RISE.x) / (landAt - T_RISE.x), 0.0, 1.0);
      riseT   = x * x - dip * BOUNCE_WINDOW;
    }
    float flatness = 1.0 - flatT;

    // The floor rises as the sheet flattens (and, when closing, as the funnel collapses).
    float floorT = closeBounce ? max(flatT, 1.0 - sink) : flatT;
    gFloor       = FLOOR_START + FLOOR_RISE * floorT * floorT;

    gAmp    = AMPLITUDE * sink * mix(AMP_START, 1.0, widen) * flatness;
    gThroat = uVoidSize * sink * mix(THROAT_START, 1.0, widen) * flatness;
    gAxes   = uAxes * mix(SPREAD_START, 1.0, widen);

    gWinAlpha   = span(T_APPEAR);
    gSheetScale = exp(log(WIN_SHEET_START) * (1.0 - riseT));

    vec2 px  = getLayerPx();
    vec2 v   = (px - uCenter) / gAxes;  // portal space
    float uq = shapeNorm(v);           // screen norm of this fragment

    if (gAmp <= 0.0 && gSheetScale >= 0.9999 && gWinAlpha >= 1.0) {
      return getInputColor(iTexCoord);  // at rest
    }

    // The window lies on the sheet, scaled around the centre: find the sheet point seen here, then the
    // window pixel at that point. Same shading as the sheet.
    vec2 sheetPx;
    float bright;
    sheetAt(px, v, uq, sheetPx, bright);
    vec2 srcPx = uCenter + (sheetPx - uCenter) / max(gSheetScale, 1e-4);
    vec2 tc    = iTexCoord + (srcPx - px) / uTexRect.zw;

    vec4 oColor = vec4(0.0);
    if (all(tc >= vec2(0.0)) && all(tc <= vec2(1.0))) {
      oColor = getInputColor(tc);
    }
    oColor.rgb *= bright;
    oColor.a *= gWinAlpha;
    return oColor;
  }
