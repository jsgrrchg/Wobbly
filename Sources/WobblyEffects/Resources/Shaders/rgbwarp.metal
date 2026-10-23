// RGB Warp: red, green and blue move away at different speeds.
// Ported from Burn-My-Windows (resources/shaders/rgbwarp.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

inline float FadeInOut(float t, float power) {
  float s = -1.0 * pow((t - 0.5) / (0.5), power) + 1.0;
  return clamp(s, 0.0, 1.0);
}
//@@
  float4 run() {
    float progress = uForOpening ? 1.0 - uProgress : uProgress;

    // Percentage of the progress time which is spent until all pixels start moving up.
    float minSpeed     = min(uSpeedR, min(uSpeedG, uSpeedB));
    float waveTime     = mix(0.1, 0.9, minSpeed);
    float waveProgress = progress / waveTime;

    // Gradient from top to bottom (0 at top, 1 at bottom).
    float t = iTexCoord.y;

    // Calculate the vertical wave offset.
    float offset = max(waveProgress - t, 0.0);
    offset /= (1.0 / waveTime) - 1.0;
    offset *= (1.0 - waveTime);

    vec4 colorR = getInputColor(iTexCoord + vec2(0.0, offset * (uSpeedR - minSpeed + 1.0)));
    vec4 colorG = getInputColor(iTexCoord + vec2(0.0, offset * (uSpeedG - minSpeed + 1.0)));
    vec4 colorB = getInputColor(iTexCoord + vec2(0.0, offset * (uSpeedB - minSpeed + 1.0)));

    vec4 oColor = vec4(colorR.r, colorG.g, colorB.b, (colorR.a + colorG.a + colorB.a) / 3.0);

    oColor.rgb *= mix(1.0, uBrightness, FadeInOut(progress, 4.0));
    oColor.a *= getAbsoluteEdgeMask(30.0, 1.0);
    return oColor;
  }
