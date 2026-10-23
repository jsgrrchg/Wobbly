// Incinerate: a less snappy but fancier take on the fire effect.
// Ported from Burn-My-Windows (resources/shaders/incinerate.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

//@@
  // Maps a value in [0..1] to the ramp [transparent black ... semi-transparent uColor ... opaque white].
  vec4 getFireColor(float val) {
    return vec4(tritone(val, vec3(0.0), uColor, vec3(1.0)), val);
  }

  float4 run() {
    // The burning fire edge is composed of multiple regions (scorch, burn, flame and smoke zones),
    // whose widths depend on the configured scale of the effect.
    float SCORCH_WIDTH = 0.2 * uScale;
    float BURN_WIDTH   = 0.03 * uScale;
    float SMOKE_WIDTH  = 0.9 * uScale;
    float FLAME_WIDTH  = 0.2 * uScale;

    // During the animation, the hideThreshold transitions from a small value to a larger value,
    // so that all the above ranges are covered.
    float hideThreshold = mix(uForOpening ? 0.0 : -SCORCH_WIDTH, 1.0 + SMOKE_WIDTH, uProgress);

    // The individual ranges are given by the current hideThreshold and the widths of the zones.
    vec2 scorchRange = uForOpening ? vec2(hideThreshold - SCORCH_WIDTH, hideThreshold)
                                   : vec2(hideThreshold, hideThreshold + SCORCH_WIDTH);
    vec2 burnRange   = vec2(hideThreshold - BURN_WIDTH, hideThreshold + BURN_WIDTH);
    vec2 flameRange  = vec2(hideThreshold - FLAME_WIDTH, hideThreshold);
    vec2 smokeRange  = vec2(hideThreshold - SMOKE_WIDTH, hideThreshold);

    // A 2D gradient in [0..1] which covers the entire window: the dark regions burn first.
    // We mix a radial gradient, centered at uStartPos, with some noise.
    float circle = length((iTexCoord - uStartPos) * (uSize / max(uSize.x, uSize.y)));

    vec2 uv = iTexCoord / uScale * uSize / 1.5;
    float smokeNoise = simplex2DFractal(uv * 0.01 + uSeed + uProgress * vec2(0.0, 0.3 * uDuration));
    float gradient   = mix(circle, smokeNoise, 200.0 * uTurbulence * uScale / max(uSize.x, uSize.y));

    // Derivatives have to be taken outside of divergent control flow.
    vec2 gradientDerivative = vec2(dfdx(gradient), dfdy(gradient));

    // Based on the gradient and the ranges, we can compute masks for the individual zones.
    float smokeMask = smoothstep(0.0, 1.0, (gradient - smokeRange.x) / SMOKE_WIDTH) * getAbsoluteEdgeMask(100.0, 0.3);
    float flameMask = smoothstep(0.0, 1.0, (gradient - flameRange.x) / FLAME_WIDTH) * getAbsoluteEdgeMask(20.0, 0.0);
    float fireMask   = smoothstep(1.0, 0.0, abs(gradient - hideThreshold) / BURN_WIDTH);
    float scorchMask = smoothstep(1.0, 0.0, (gradient - scorchRange.x) / SCORCH_WIDTH);

    if (uForOpening) {
      scorchMask = 1.0 - scorchMask;
    }

    // We only show the window when the burning edge has passed.
    vec4 oColor = vec4(0.0);
    if ((!uForOpening && gradient > hideThreshold) || (uForOpening && gradient < hideThreshold)) {

      // We add some distortion in the scorch zone.
      vec2 distort = vec2(0.0);
      if (scorchRange.x < gradient && gradient < scorchRange.y) {
        distort = gradientDerivative * scorchMask * 5.0;
      }

      oColor = getInputColor(iTexCoord + distort);
    }

    // Add smoke and embers.
    if (smokeRange.x < gradient && gradient < smokeRange.y) {
      float smoke = smokeMask * smokeNoise;
      oColor      = alphaOver(oColor, vec4(0.5 * vec3(smoke), smoke));

      float emberNoise = simplex2DFractal(uv * 0.05 + uSeed - smokeNoise * vec2(0.0, 0.3 * smokeMask * uDuration));
      float embers     = clamp(pow(emberNoise + 0.3, 100.0), 0.0, 2.0) * smoke;
      oColor += getFireColor(embers);
    }

    // Add scorch effect.
    if (scorchRange.x < gradient && gradient < scorchRange.y) {
      oColor.rgb = mix(oColor.rgb, mix(oColor.rgb, vec3(0.1, 0.05, 0.02), 0.4), scorchMask);
    }

    // Add trailing flames.
    if (min(burnRange.x, flameRange.x) < gradient && gradient < max(burnRange.y, flameRange.y)) {
      float flameNoise = simplex2DFractal(uv * 0.02 + uSeed + smokeNoise * vec2(0.0, 1.0 * uDuration) +
                                          vec2(0.0, uProgress * uDuration));

      if (flameRange.x < gradient && gradient < flameRange.y) {
        float flame = clamp(pow(flameNoise + 0.3, 20.0), 0.0, 2.0) * flameMask;
        flame += clamp(pow(flameNoise + 0.4, 10.0), 0.0, 2.0) * flameMask * flameMask * 0.1;
        oColor += getFireColor(flame);
      }

      // Add burning edge.
      if (burnRange.x < gradient && gradient < burnRange.y) {
        float fire = fireMask * pow(flameNoise + 0.4, 4.0) * oColor.a;
        oColor += getFireColor(fire);
      }
    }
    return oColor;
  }
