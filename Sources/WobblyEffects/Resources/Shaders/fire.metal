// Fire: the classic window burning effect, with a shader instead of a particle system.
// Ported from Burn-My-Windows (resources/shaders/fire.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float EDGE_FADE  = 70.0;
constant float FADE_WIDTH = 0.1;
constant float HIDE_TIME  = 0.4;

// This maps the input value from [0..1] to a color from the gradient.
inline float4 getFireColor(float v, float4 c0, float4 c1, float4 c2, float4 c3, float4 c4) {
  float steps[5];
  steps[0] = 0.0;
  steps[1] = 0.2;
  steps[2] = 0.35;
  steps[3] = 0.5;
  steps[4] = 0.8;

  float4 colors[5];
  colors[0] = c0;
  colors[1] = c1;
  colors[2] = c2;
  colors[3] = c3;
  colors[4] = c4;

  if (v < steps[0]) {
    return colors[0];
  }

  for (int i = 0; i < 4; ++i) {
    if (v <= steps[i + 1]) {
      return mix(colors[i], colors[i + 1], float4(v - steps[i]) / (steps[i + 1] - steps[i]));
    }
  }

  return colors[4];
}
//@@
  // x: alpha for the window texture, which dissolves from top to bottom (or bottom to top).
  // y: a mask for any effect: most opaque where the window is currently fading, dissolving over time.
  vec2 computeEffectMask(float hideTime, float fadeWidth, float edgeFadeWidth) {
    float progress          = easeOutQuad(uProgress);
    float burnProgress      = clamp(progress / hideTime, 0.0, 1.0);
    float afterBurnProgress = clamp((progress - hideTime) / (1.0 - hideTime), 0.0, 1.0);

    // Gradient from top to bottom. Flipping it makes the window burn from bottom to top.
    bool bottomToTop = uForOpening ? uOpeningBottomToTop : uClosingBottomToTop;
    float y          = bottomToTop ? 1.0 - iTexCoord.y : iTexCoord.y;
    float t          = y * (1.0 - fadeWidth);

    // Visible part of the window. Gradually dissolves towards the bottom.
    float windowMask = 1.0 - clamp((burnProgress - t) / fadeWidth, 0.0, 1.0);

    // Gradient from top burning window. The fire is most intense at the burning edge.
    float effectMask = clamp(t * (1.0 - windowMask) / burnProgress, 0.0, 1.0);

    // Fade-out when the window burned down.
    if (progress > hideTime) {
      float fade = sqrt(1.0 - afterBurnProgress * afterBurnProgress);
      effectMask *= mix(1.0, 1.0 - t, afterBurnProgress) * fade;
    }

    // Fade at window borders.
    effectMask *= getAbsoluteEdgeMask(edgeFadeWidth, 0.5);

    if (uForOpening) {
      windowMask = 1.0 - windowMask;
    }

    return vec2(windowMask, effectMask);
  }

  float4 run() {
    // Get a noise value which moves vertically in time.
    vec2 uv = iTexCoord * uSize / vec2(400.0, 600.0) / uScale;
    uv.y += uProgress * uDuration * uMovementSpeed;
    float noise = u3DNoise ? simplex3DFractal(vec3(uv * 4.0, uProgress * uDuration * uMovementSpeed * 1.5))
                           : simplex2DFractal(uv * 4.0);

    // Modulate noise by effect mask.
    vec2 effectMask = computeEffectMask(HIDE_TIME, FADE_WIDTH, EDGE_FADE);
    noise *= effectMask.y;

    // Map noise value to color.
    vec4 fire = vec4(0.0);
    if (uRandomColor) {
      vec3 baseColor0 = offsetHue(vec3(1.0, 0.0, 0.0), hash11(uSeed));
      vec3 baseColor1 = offsetHue(baseColor0, 0.1);
      vec3 baseColor2 = offsetHue(baseColor1, 0.1);

      vec4 c0 = vec4(baseColor0, 0.0);
      vec4 c1 = vec4(baseColor0, 0.5);
      vec4 c2 = vec4(baseColor1, 0.8);
      vec4 c3 = vec4(baseColor1, 0.9);
      vec4 c4 = vec4(baseColor2, 1.0);
      fire    = getFireColor(noise, c0, c1, c2, c3, c4);
    } else {
      fire = getFireColor(noise, uGradient1, uGradient2, uGradient3, uGradient4, uGradient5);
    }

    // Get the window texture and fade it according to the effect mask.
    vec4 oColor = getInputColor(iTexCoord);
    oColor.a *= effectMask.x;

    // Add the fire to the window.
    return alphaOver(oColor, fire);
  }
