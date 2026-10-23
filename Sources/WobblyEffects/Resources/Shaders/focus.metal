// Focus: the window blurs and fades away.
// Ported from Burn-My-Windows (resources/shaders/focus.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

//@@
  float4 run() {
    float progl = uForOpening ? uProgress : 1.0 - uProgress;

    float easedProgressBlur  = easeInOutSine(progl);
    float easedProgressAlpha = easeInOutCubic(progl);

    float blurAmount = mix(uBlurAmount, 0.0, easedProgressBlur);
    vec4 texColor    = getBlurredInputColor(iTexCoord, blurAmount, uBlurQuality);

    texColor.a *= easedProgressAlpha;
    return texColor;
  }
