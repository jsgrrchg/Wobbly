// Team Rocket: ...is blasting off again!
// Ported from Burn-My-Windows (resources/shaders/team-rocket.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float TAU = 6.28;

// Used to scale the window.
inline float2 scaleUV(float2 uv, float2 scale, float2 centerOffset) {
  // Put texture coordinate origin to center of window.
  uv -= centerOffset;
  uv = uv * 2.0 - 1.0;

  uv /= mix(float2(1.0, 1.0), float2(0.0, 0.0), scale);

  // Scale from center.
  uv = uv * 0.5 + 0.5;
  return uv;
}

// Returns the spark.
inline float getSpark(float2 uv, float2 center, float brightness, float size, float rotation) {
  brightness = clamp(brightness, 0.001, 1.0);
  size       = clamp(size, 0.001, 1.0);
  float bn   = mix(0.0, 0.07, brightness);  // recalculate size

  uv = (uv + float2(0.5));  // set center
  uv = (uv - center);       // Center UV coordinates, then scale to fit the star size
  uv = scaleUV(uv, float2(1.0 - size), float2(0.0));
  uv = rotateVec(uv, rotation, float2(0.5));

  // This is basically the brightness.
  float p = mix(-1.0, 1000.0, easeInExpo(bn));
  float m = mix(0.0, 1.0, clamp(pow(abs(uv.x - 0.5) * 2.0, p) + pow(abs(uv.y - 0.5) * 2.0, p), 0.0, 1.0));

  float mask = easeInSine(1.0 - (m - bn)) - 0.004;
  return clamp(mask, 0.0, 1.0);
}

// Fades out at 0 and 1, based on the (even) power.
inline float fadeInOut(float t, float power) {
  float s = -1.0 * pow((t - 0.5) / (0.5), power) + 1.0;
  return clamp(s, 0.0, 1.0);
}
//@@
  float4 run() {
    float progress = uForOpening ? 1.0 - uProgress : uProgress;

    // Scale progress: the first half of the animation.
    float scalep = remap(progress, 0.0, uAnimationSplit + 0.1, 0.0, 1.0);
    scalep       = easeOutQuad(scalep);

    // Sparkle progress: the second half of the animation.
    float sparkp = remap(progress, uAnimationSplit - 0.1, 1.0, 0.0, 1.0);
    sparkp       = easeInOutSine(sparkp);

    // This is the offset of the window.
    vec2 offset = vec2(uHorizontalSparklePosition, uVerticalSparklePosition * -1.0) * 0.20;
    vec2 scaleOffset =
        mix(vec2(0.0), vec2(uHorizontalSparklePosition, uVerticalSparklePosition * -1.0) * 0.50, scalep);

    float aspect = uSize.x / uSize.y;
    vec2 uv      = iTexCoord * vec2(aspect, 1.0);

    vec2 uv2 = iTexCoord;
    uv2      = uv2 * 2.0 - 1.0;
    uv2 -= (scaleOffset / vec2(aspect, 1.0)) * scalep;
    uv2 /= 1.0 - scalep;

    // Rotation (more of a warp), if enabled.
    vec3 rot = vec3(0.0);
    if (uWindowRotation) {
      rot = hash32(uSeed);
      rot *= 2.0;
      rot -= 1.0;
      rot *= 0.1;
    }

    // Rotate around x, y, and z.
    uv2.x /= mix(1.0, rot.x * TAU * uv2.y, scalep);
    uv2.y /= mix(1.0, rot.y * TAU * uv2.x, scalep);
    uv2 = rotateVec(uv2, rot.z * TAU * scalep);

    // Re-center.
    uv2 = uv2 * 0.5 + 0.5;

    // Get the sparkle.
    float size    = mix(25.0, 50.0, uSparkleSize);
    float sparkle = getSpark(uv, offset + vec2(0.5 * aspect, 0.5), fadeInOut(sparkp, 2.0) * uSparkleSize,
                             fadeInOut(sparkp, 2.0) * size, sparkp * TAU * float(uSparkleRot));

    // Fade out at the edges.
    sparkle *= fadeInOut(iTexCoord.y, 8.0);
    sparkle *= fadeInOut(iTexCoord.x, 8.0);

    // Combine the final color.
    vec4 oColor = getInputColor(uv2);
    return alphaOver(oColor, vec4(1.0, 1.0, 1.0, sparkle));
  }
