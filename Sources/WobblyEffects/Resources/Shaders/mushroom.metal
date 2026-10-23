// Mushroom: inspired by your favorite Italian plumber. Sparks, rays and rings of stars around a shrinking window.
// Ported from Burn-My-Windows (resources/shaders/mushroom.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

inline float3 getPosByAngle(float angle) { return float3(cos(angle), sin(angle), 0.0); }

// Gets the mask of a star.
inline float getStar(float2 uv, float2 center, float npoints, float radiusRatio, float size, float rotation) {
  float radiusMax = 1.0;
  float radiusMin = radiusMax * radiusRatio;
  float PI        = 3.1415926;
  float starangle = 2.0 * PI / npoints;  // Angle between points on the star

  // Offset rotation to ensure one point is always up when rotation = 0.
  rotation += PI / 2.0 - starangle / 1.0;

  // The positions of the outer and inner points of the star's initial angle, rotated by `rotation`.
  float3 p0 = (radiusMax * size) * getPosByAngle(rotation);
  float3 p1 = (radiusMin * size) * getPosByAngle(starangle + rotation);

  // The position of the current fragment relative to the star's center.
  float2 curPosuv   = (uv - center);
  float curRadius   = length(curPosuv);
  float curPosAngle = atan2(curPosuv.y, curPosuv.x) - rotation;

  // The fractional position within the current star segment.
  float a = fract(curPosAngle / starangle);
  if (a >= 0.5) a = 1.0 - a;

  a            = a * starangle;
  float3 curPos = curRadius * getPosByAngle(a + rotation);

  // Cross product to determine if `curPos` is inside the star's edge.
  float3 dir0 = p1 - p0;
  float3 dir1 = curPos - p0;
  return step(0.0, cross(dir0, dir1).z);
}

// Used to scale the window.
inline float2 scaleUV(float2 uv, float2 scale) {
  uv = uv * 2.0 - 1.0;
  uv /= mix(float2(1.0, 1.0), float2(0.0, 0.0), scale);
  uv = uv * 0.5 + 0.5;
  return uv;
}

// Returns a four-point spark.
inline float getSpark(float2 uv, float2 center, float brightness, float size, float rotation) {
  brightness = clamp(brightness, 0.001, 1.0);
  size       = clamp(size, 0.001, 1.0);
  float bn   = mix(0.0, 0.07, brightness);

  uv = (uv + float2(0.5));
  uv = (uv - center);
  uv = scaleUV(uv, float2(1.0 - size));
  uv = rotateVec(uv, rotation, float2(0.5));

  // This is basically the brightness.
  float p = mix(-1.0, 1000.0, easeInExpo(bn));
  float m = mix(0.0, 1.0, clamp(pow(abs(uv.x - 0.5) * 2.0, p) + pow(abs(uv.y - 0.5) * 2.0, p), 0.0, 1.0));

  float mask = easeInSine(1.0 - (m - bn)) - 0.004;
  return clamp(mask, 0.0, 1.0);
}

// Fades out towards t = 0 and t = 1, based on an even power (2, 4, 8…).
inline float zeroStartEnd(float t, float max_size, float power) {
  float s = -1.0 * pow((t - 0.5) / (0.5), power) + 1.0;
  return clamp(s, 0.0, 1.0) * max_size;
}

// The jerky 8-bit growth effect.
inline float eightBitScale(float progress) {
  float scale = 1.0;
  if (progress <= 0.1) {
    scale = 0.25;
  } else if (progress <= 0.2) {
    scale = 0.5;
  } else if (progress <= 0.3) {
    scale = 0.25;
  } else if (progress <= 0.4) {
    scale = 0.5;
  } else if (progress <= 0.5) {
    scale = 0.25;
  } else if (progress <= 0.6) {
    scale = 0.5;
  } else if (progress <= 0.7) {
    scale = 1.0;
  } else if (progress <= 0.8) {
    scale = 0.25;
  } else if (progress <= 0.9) {
    scale = 0.5;
  }
  return scale;
}
//@@
  // Returns the star's color, which changes with the height of the star.
  vec4 getStarColor(float v, float alpha) {
    v = clamp(v, 0.0, 1.0);

    float steps[6];
    steps[0] = 0.0;
    steps[1] = 0.1666;
    steps[2] = 0.3332;
    steps[3] = 0.4998;
    steps[4] = 0.6664;
    steps[5] = 0.8330;

    vec4 colors[6];
    colors[0] = uStarColor0;
    colors[1] = uStarColor1;
    colors[2] = uStarColor2;
    colors[3] = uStarColor3;
    colors[4] = uStarColor4;
    colors[5] = uStarColor5;

    for (int i = 0; i < 6; ++i) {
      colors[i].a = alpha * colors[i].a;
    }

    if (v <= steps[0]) {
      return colors[0];
    }
    if (v >= steps[5]) {
      return colors[5];
    }

    for (int i = 0; i < 5; ++i) {
      if (v <= steps[i + 1]) {
        float t = (v - steps[i]) / (steps[i + 1] - steps[i]);
        return mix(colors[i], colors[i + 1], t);
      }
    }

    return vec4(0.0, 0.0, 0.0, 1.0);
  }

  // Gets all the sparks.
  vec4 getSparks(float progress) {
    float aspect = uSize.x / uSize.y;
    vec2 uv      = iTexCoord * vec2(aspect, 1.0);

    vec4 result = vec4(0.0);

    // 0 at the edges.
    float xEdge = -1.0 * pow((uv.x - (aspect * 0.5)) / (aspect * 0.5), 8.0) + 1.0;
    xEdge       = clamp(xEdge, 0.0, 1.0);

    vec2 h  = vec2(0.0);
    float y = 0.0;
    float x = 0.0;

    for (float xusp = 0.0; xusp < uSparkCount; ++xusp) {
      h = hash21(xusp + uSeed.x);
      y = mix(0.0 - h.y, 1.0 + (1.0 - h.y), progress);
      y = clamp(y, 0.0, 1.0);
      x = 0.66 * sin(h.x * 6.28);
      x += 0.5 * aspect;

      float a4ps = getSpark(uv, vec2(x, y), zeroStartEnd(y, 1.0, 4.0) * xEdge, zeroStartEnd(y, 0.5, 4.0) * xEdge,
                            progress * 6.28 * float(uSparkRotation));

      result = alphaOver(result, vec4(uSparkColor.r, uSparkColor.g, uSparkColor.b, uSparkColor.a * a4ps));
    }

    return result;
  }

  // Gets the rays.
  vec4 getRays(float progress) {
    vec2 rayUV = iTexCoord;
    rayUV *= vec2(10.0, 0.5);
    rayUV.y += progress * -1.0;
    rayUV.x += uSeed.y;

    float ray = simplex2D(rayUV);

    // 0 around the edges and at the beginning and end of the animation.
    ray *= zeroStartEnd(iTexCoord.y, 1.0, 8.0);
    ray *= zeroStartEnd(iTexCoord.x, 1.0, 8.0);
    ray *= zeroStartEnd(progress, 1.0, 8.0);

    ray         = remap(ray * 1.10, 0.0, 1.0, -5.0, 1.0);
    float alpha = clamp(uRaysColor.a * ray, 0.0, 1.0);

    return vec4(uRaysColor.r, uRaysColor.g, uRaysColor.b, alpha);
  }

  // Returns the rings of stars.
  vec4 getStars(vec2 starUV, float aspect, float progress, float oColorAlpha) {
    vec4 result = vec4(0.0);
    float y     = 0.0;

    for (float r = 0.0; r < uRingCount; ++r) {
      float spread = r * (1.0 / uRingCount);
      y            = mix(0.0 - spread, 1.0 + (1.0 - spread), 1.0 - progress);
      y            = clamp(y, 0.00001, 0.99999);

      for (float s = 0.0; s < uStarCount; ++s) {
        float a5ps = getStar(starUV,
                             vec2(sin(progress * uRingRotation * 6.28 + (s * (6.28 / uStarCount))) * aspect * 0.33, y),
                             5.0, 0.5, zeroStartEnd(y, 0.1, 2.0), 0.0);
        a5ps = clamp(a5ps, 0.0, 1.0);

        // Put the star in the back or the front of the window.
        float depth = cos(progress * uRingRotation * 6.28 + (s * (6.28 / uStarCount)));

        if (depth < 0.0) {
          result = alphaOver(result, getStarColor(y, a5ps));
        } else {
          result = alphaOver(getStarColor(y, a5ps) * (1.0 - oColorAlpha), result);
        }
      }
    }

    return result;
  }

  float4 run() {
    float progress = uForOpening ? 1.0 - uProgress : uProgress;

    vec4 oColor = vec4(0.0, 0.0, 0.0, 0.0);

    float scale8bit = eightBitScale(progress);
    vec2 scaleV2    = vec2(easeInOutSine(progress), easeInQuad(progress));
    vec2 fscale     = mix(vec2(scale8bit), scaleV2, uScaleStyle);

    oColor            = getInputColor(scaleUV(iTexCoord, fscale));
    float oColorAlpha = oColor.a;

    float aspect = uSize.x / uSize.y;

    // starUV.x in [-0.5, 0.5], starUV.y in [1.0, 0.0].
    vec2 starUV = vec2(iTexCoord.x - 0.5, 1.0 - iTexCoord.y) * vec2(aspect, 1.0);

    if (uSparkCount > 0.0) {
      oColor = alphaOver(oColor, getSparks(progress));
    }

    if (uRaysColor.a > 0.0) {
      oColor = alphaOver(oColor, getRays(progress));
    }

    if (uRingCount > 0.0 && uStarCount > 0.0) {
      oColor = alphaOver(oColor, getStars(starUV, aspect, progress, oColorAlpha));
    }

    return oColor;
  }
