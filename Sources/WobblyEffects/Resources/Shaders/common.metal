// Wobbly window-close effects: common Metal helpers.
// Ported from the GLSL of Burn-My-Windows (resources/shaders/common.glsl).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

#include <metal_stdlib>
using namespace metal;

typedef float2 vec2;
typedef float3 vec3;
typedef float4 vec4;
typedef float2x2 mat2;
typedef float3x3 mat3;

// GLSL helpers that Metal lacks (scalar bounds on vectors, mod).
template <typename T> inline T mod(T x, T y) { return x - y * floor(x / y); }
inline float2 mod(float2 x, float y) { return x - y * floor(x / y); }
inline float3 mod(float3 x, float y) { return x - y * floor(x / y); }
inline float4 mod(float4 x, float y) { return x - y * floor(x / y); }

inline float2 clamp(float2 x, float a, float b) { return clamp(x, float2(a), float2(b)); }
inline float3 clamp(float3 x, float a, float b) { return clamp(x, float3(a), float3(b)); }
inline float4 clamp(float4 x, float a, float b) { return clamp(x, float4(a), float4(b)); }

inline float2 max(float2 a, float b) { return max(a, float2(b)); }
inline float3 max(float3 a, float b) { return max(a, float3(b)); }
inline float2 min(float2 a, float b) { return min(a, float2(b)); }
inline float3 min(float3 a, float b) { return min(a, float3(b)); }

inline float2 mix(float2 a, float2 b, float t) { return mix(a, b, float2(t)); }
inline float3 mix(float3 a, float3 b, float t) { return mix(a, b, float3(t)); }
inline float4 mix(float4 a, float4 b, float t) { return mix(a, b, float4(t)); }

// ----------------------------------------------------------------------- compositing

// Straight-alpha "over" operator.
inline float4 alphaOver(float4 under, float4 over) {
  if (under.a == 0.0 && over.a == 0.0) {
    return float4(0.0);
  }
  float alpha = mix(under.a, 1.0, over.a);
  return float4(mix(under.rgb * under.a, over.rgb, over.a) / alpha, alpha);
}

// ------------------------------------------------------------------------ color helpers

inline float3 tritone(float val, float3 shadows, float3 midtones, float3 highlights) {
  if (val < 0.5) {
    return mix(shadows, midtones, smoothstep(0.0, 1.0, val * 2.0));
  }
  return mix(midtones, highlights, smoothstep(0.0, 1.0, val * 2.0 - 1.0));
}

inline float3 darken(float3 color, float fac) { return color * (1.0 - fac); }
inline float3 lighten(float3 color, float fac) { return color + (float3(1.0) - color) * fac; }

inline float3 offsetHue(float3 color, float hueOffset) {
  float maxC  = max(max(color.r, color.g), color.b);
  float minC  = min(min(color.r, color.g), color.b);
  float delta = maxC - minC;

  float hue = 0.0;
  if (delta > 0.0) {
    if (maxC == color.r) {
      hue = mod((color.g - color.b) / delta, 6.0);
    } else if (maxC == color.g) {
      hue = (color.b - color.r) / delta + 2.0;
    } else {
      hue = (color.r - color.g) / delta + 4.0;
    }
  }
  hue /= 6.0;

  float saturation = (maxC > 0.0) ? (delta / maxC) : 0.0;
  float value      = maxC;

  hue = mod(hue + hueOffset, 1.0);

  float c = value * saturation;
  float x = c * (1.0 - abs(mod(hue * 6.0, 2.0) - 1.0));
  float m = value - c;

  float3 rgb;
  if (hue < 1.0 / 6.0) {
    rgb = float3(c, x, 0.0);
  } else if (hue < 2.0 / 6.0) {
    rgb = float3(x, c, 0.0);
  } else if (hue < 3.0 / 6.0) {
    rgb = float3(0.0, c, x);
  } else if (hue < 4.0 / 6.0) {
    rgb = float3(0.0, x, c);
  } else if (hue < 5.0 / 6.0) {
    rgb = float3(x, 0.0, c);
  } else {
    rgb = float3(c, 0.0, x);
  }
  return rgb + m;
}

// ----------------------------------------------------------------------------- easing

inline float easeOutQuad(float x) { return -1.0 * x * (x - 2.0); }
inline float easeInQuad(float x) { return x * x; }
inline float easeInBack(float x, float e) { return x * x * ((e + 1.0) * x - e); }
inline float easeOutBack(float x, float e) {
  float p = x - 1.0;
  return p * p * ((e + 1.0) * p + e) + 1.0;
}
inline float easeInOutQuad(float t) { return t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t; }
inline float easeInCubic(float t) { return t * t * t; }
inline float easeOutCubic(float t) {
  float f = t - 1.0;
  return f * f * f + 1.0;
}
inline float easeInOutCubic(float t) {
  return t < 0.5 ? 4.0 * t * t * t : (t - 1.0) * (2.0 * t - 2.0) * (2.0 * t - 2.0) + 1.0;
}
inline float easeInQuart(float t) { return t * t * t * t; }
inline float easeOutQuart(float t) {
  float f = t - 1.0;
  return 1.0 - f * f * f * f;
}
inline float easeInOutQuart(float t) {
  return t < 0.5 ? 8.0 * t * t * t * t : 1.0 - 8.0 * (t - 1.0) * (t - 1.0) * (t - 1.0) * (t - 1.0);
}
inline float easeInSine(float t) { return 1.0 - cos((t * 3.141592653589793) / 2.0); }
inline float easeOutSine(float t) { return sin((t * 3.141592653589793) / 2.0); }
inline float easeInOutSine(float t) { return -0.5 * (cos(3.141592653589793 * t) - 1.0); }
inline float easeInExpo(float t) { return t == 0.0 ? 0.0 : pow(2.0, 10.0 * (t - 1.0)); }
inline float easeOutExpo(float t) { return t == 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * t); }
inline float easeInOutExpo(float t) {
  if (t == 0.0) return 0.0;
  if (t == 1.0) return 1.0;
  return t < 0.5 ? 0.5 * pow(2.0, 20.0 * t - 10.0) : 1.0 - 0.5 * pow(2.0, -20.0 * t + 10.0);
}

// -------------------------------------------------------------------------------- 2D math

inline float2 whirl(float2 coords, float warping, float rotation) {
  float angle = pow(1.0 - length(coords), 2.0) * warping + rotation;
  float s     = sin(angle);
  float c     = cos(angle);
  return float2(dot(coords, float2(c, -s)), dot(coords, float2(s, c)));
}

inline float distToLine(float2 origin, float2 direction, float2 point) {
  float2 perpendicular = float2(direction.y, -direction.x);
  return abs(dot(normalize(perpendicular), origin - point));
}

inline float getWinding(float2 a, float2 b) { return a.x * b.y - a.y * b.x; }

// Rotates a clockwise by the angle (radians).
inline float2 rotateVec(float2 a, float angle) {
  return float2(a.x * cos(angle) - a.y * sin(angle), a.x * sin(angle) + a.y * cos(angle));
}

inline float2 rotateVec(float2 a, float angle, float2 center) {
  return float2(cos(angle) * (a.x - center.x) + sin(angle) * (a.y - center.y) + center.x,
                cos(angle) * (a.y - center.y) - sin(angle) * (a.x - center.x) + center.y);
}

// -------------------------------------------------------------------------------- noise
// Hash functions: MIT License, https://www.shadertoy.com/view/4djSRW, Copyright (c) 2014 David Hoskins.

inline float hash11(float p) {
  p = fract(p * .1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

inline float hash12(float2 p) {
  float3 p3 = fract(float3(p.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

inline float2 hash21(float p) {
  float3 p3 = fract(float3(p) * float3(.1031, .1030, .0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

inline float2 hash22(float2 p) {
  float3 p3 = fract(float3(p.xyx) * float3(.1031, .1030, .0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

inline float3 hash32(float2 p) {
  float3 p3 = fract(float3(p.xyx) * float3(.1031, .1030, .0973));
  p3 += dot(p3, p3.yxz + 33.33);
  return fract((p3.xxy + p3.yzz) * p3.zyx);
}

inline float3 hash33(float3 p3) {
  p3 = fract(p3 * float3(.1031, .1030, .0973));
  p3 += dot(p3, p3.yxz + 33.33);
  return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 2D simplex noise: MIT License, https://www.shadertoy.com/view/Msf3WH, Copyright © 2013 Inigo Quilez.
inline float simplex2D(float2 p) {
  const float K1 = 0.366025404;  // (sqrt(3)-1)/2
  const float K2 = 0.211324865;  // (3-sqrt(3))/6

  float2 i = floor(p + (p.x + p.y) * K1);
  float2 a = p - i + (i.x + i.y) * K2;
  float m  = step(a.y, a.x);
  float2 o = float2(m, 1.0 - m);
  float2 b = a - o + K2;
  float2 c = a - 1.0 + 2.0 * K2;
  float3 h = max(0.5 - float3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
  float3 n = h * h * h * h *
             float3(dot(a, -1.0 + 2.0 * hash22(i + 0.0)), dot(b, -1.0 + 2.0 * hash22(i + o)),
                    dot(c, -1.0 + 2.0 * hash22(i + 1.0)));
  return 0.5 + 0.5 * dot(n, float3(70.0));
}

inline float simplex2DFractal(float2 p) {
  float2x2 m = float2x2(float2(1.6, 1.2), float2(-1.2, 1.6));
  float f    = 0.5000 * simplex2D(p);
  p          = m * p;
  f += 0.2500 * simplex2D(p);
  p = m * p;
  f += 0.1250 * simplex2D(p);
  p = m * p;
  f += 0.0625 * simplex2D(p);
  p = m * p;
  return f;
}

// 3D simplex noise: MIT License, https://www.shadertoy.com/view/XsX3zB, Copyright © 2013 Nikita Miropolskiy.
inline float simplex3D(float3 p) {
  const float F3 = 0.3333333;
  const float G3 = 0.1666667;

  float3 s = floor(p + dot(p, float3(F3)));
  float3 x = p - s + dot(s, float3(G3));

  float3 e  = step(float3(0.0), x - x.yzx);
  float3 i1 = e * (1.0 - e.zxy);
  float3 i2 = 1.0 - e.zxy * (1.0 - e);

  float3 x1 = x - i1 + G3;
  float3 x2 = x - i2 + 2.0 * G3;
  float3 x3 = x - 1.0 + 3.0 * G3;

  float4 w, d;
  w.x = dot(x, x);
  w.y = dot(x1, x1);
  w.z = dot(x2, x2);
  w.w = dot(x3, x3);

  w = max(0.6 - w, 0.0);

  d.x = dot(-0.5 + hash33(s), x);
  d.y = dot(-0.5 + hash33(s + i1), x1);
  d.z = dot(-0.5 + hash33(s + i2), x2);
  d.w = dot(-0.5 + hash33(s + 1.0), x3);

  w *= w;
  w *= w;
  d *= w;

  return dot(d, float4(52.0)) * 0.5 + 0.5;
}

inline float simplex3DFractal(float3 m) {
  const float3x3 rot1 = float3x3(float3(-0.37, 0.36, 0.85), float3(-0.14, -0.93, 0.34), float3(0.92, 0.01, 0.4));
  const float3x3 rot2 = float3x3(float3(-0.55, -0.39, 0.74), float3(0.33, -0.91, -0.24), float3(0.77, 0.12, 0.63));
  const float3x3 rot3 = float3x3(float3(-0.71, 0.52, -0.47), float3(-0.08, -0.72, -0.68), float3(-0.7, -0.45, 0.56));

  return 0.5333333 * simplex3D(m * rot1) + 0.2666667 * simplex3D(2.0 * m * rot2) +
         0.1333333 * simplex3D(4.0 * m * rot3) + 0.0666667 * simplex3D(8.0 * m);
}

// ------------------------------------------------------------------------------- remap

inline float remap(float value, float oldMin, float oldMax, float newMin, float newMax) {
  return clamp(newMin + (value - oldMin) * (newMax - newMin) / (oldMax - oldMin), newMin, newMax);
}

// ------------------------------------------------------------------- shared declarations

struct FXUniforms {
  float2 quadOrigin;    // quad on screen, in global points
  float2 quadSize;
  float2 screenOrigin;  // the screen this draw call targets, in global points
  float2 screenSize;
  float2 texSize;       // uSize: window plus padding, in points
  float2 windowSize;    // the window itself, in points
  float2 uvScale;       // window-relative uv -> capture texture uv
  float2 uvOffset;
  float padding;        // uPadding: transparent border around the window
  float progress;
  float duration;
  float forOpening;
  float isFullscreen;
  float shadow;         // opacity of the shadow part of the capture
  float2 reserved;
};

struct VOut {
  float4 position [[position]];
  float2 uv;
};

vertex VOut fxVertex(uint vid [[vertex_id]], constant FXUniforms &u [[buffer(0)]]) {
  float2 corner = float2(float(vid & 1u), float(vid >> 1u));
  float2 global = u.quadOrigin + corner * u.quadSize;
  float2 p      = (global - u.screenOrigin) / u.screenSize;
  VOut out;
  out.position = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
  out.uv       = corner;
  return out;
}
