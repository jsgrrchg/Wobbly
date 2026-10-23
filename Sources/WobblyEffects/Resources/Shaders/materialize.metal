// Materialize: the window shrinks into a flat, tinted panel, like the screens of The Matrix Resurrections.
// Ported from Burn-My-Windows (resources/shaders/materialize.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float GROW_TIME     = 0.5;   // Relative time for scaling the panel to full size.
constant float FADE_TIME     = 0.15;  // Relative time for the initial fade-in (smooth only).
constant float PANEL_OPACITY = 0.6;   // Initial opacity of the panel.
//@@
  float4 run() {
    // This is 0 when the window is gone and 1 when it is fully materialized.
    float prog = uForOpening ? uProgress : 1.0 - uProgress;

    // In smooth mode, the panel fades in quickly at the very beginning.
    float fade = uSteps > 0.0 ? 1.0 : smoothstep(0.0, FADE_TIME, prog);

    // Quantize the progress to a few discrete steps, like a slow, stuttering computer from the movies.
    if (uSteps > 1.0) {
      prog = min(floor(prog * uSteps), uSteps - 1.0) / (uSteps - 1.0);
    } else if (uSteps > 0.0) {
      prog = 1.0;
    }

    // During the first part of the animation, the panel grows from its initial size.
    float growProg = easeOutCubic(clamp(prog / GROW_TIME, 0.0, 1.0));
    float scale    = mix(uStartScale, 1.0, growProg);

    // Scale around the window's center.
    vec2 coords = (iTexCoord - 0.5) / scale + 0.5;
    vec4 oColor = getInputColor(coords);

    // Hide anything which was scaled in from outside the texture.
    if (coords.x < 0.0 || coords.x > 1.0 || coords.y < 0.0 || coords.y > 1.0) {
      oColor.a = 0.0;
    }

    // While growing, the panel is covered in the flat tint color. Afterwards, the tint fades away.
    float tint = 1.0 - smoothstep(GROW_TIME, 1.0, prog);
    oColor.rgb = mix(oColor.rgb, uColor.rgb, uColor.a * tint);

    // The panel is translucent at first and becomes opaque while growing.
    oColor.a *= fade * mix(PANEL_OPACITY, 1.0, growProg);
    return oColor;
  }
