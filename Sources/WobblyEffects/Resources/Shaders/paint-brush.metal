// Paint Brush: the window is erased with a thick paint brush.
// Ported from Burn-My-Windows (resources/shaders/paint-brush.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float SHADOW_WIDTH = 0.03;
constant float SHADOW_STEPS = 10.0;
//@@
  // Returns 1.0 if the window texture at the given texCoord should be painted.
  float getMask(vec2 texCoord, float progress) {
    float brush = aux2D(texCoord)[int(uBrushSize - 1.0)];
    if (uForOpening) {
      return step(brush, progress);
    }
    return step(progress, brush);
  }

  float4 run() {
    vec4 oColor = getInputColor(iTexCoord);

    // This will be 0.0 in the masked-out areas.
    float mask = getMask(iTexCoord, uProgress);

    // Add a simple drop shadow below the remaining parts.
    if (mask == 0.0) {
      for (float i = 0.0; i < SHADOW_STEPS; ++i) {
        vec2 shadowTexCoord = iTexCoord - vec2(0.0, i * SHADOW_WIDTH / SHADOW_STEPS);
        float shadowMask    = getMask(shadowTexCoord, uProgress);
        float shadowAlpha   = (1.0 - i / SHADOW_STEPS) * shadowMask * getInputColor(shadowTexCoord).a;

        if (shadowAlpha > 0.0) {
          oColor = vec4(vec3(0.0), shadowAlpha * 0.2);
          break;
        }

        // If we arrived at the end of the shadow, make sure to set the alpha to 0.
        if (i == SHADOW_STEPS - 1.0) {
          oColor.a = 0.0;
        }
      }
    }
    return oColor;
  }
