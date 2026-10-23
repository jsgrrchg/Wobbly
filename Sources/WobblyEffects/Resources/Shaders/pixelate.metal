// Pixelate: pixelates the window and randomly hides pixels until it is gone.
// Ported from Burn-My-Windows (resources/shaders/pixelate.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

//@@
  float4 run() {
    float progress = uForOpening ? 1.0 - uProgress : uProgress;

    // The current level of pixelation increases with the progress.
    float pixelSize = ceil(uPixelSize * progress + 1.0);
    vec2 pixelGrid  = vec2(pixelSize) / uSize;
    vec2 texcoord   = iTexCoord - mod(iTexCoord, pixelGrid) + pixelGrid * 0.5;
    vec4 oColor     = getInputColor(texcoord);

    // Hide selected pixels based on some random noise.
    float random = simplex2DFractal(texcoord * uNoise * uSize / 1000.0) * 1.5 - 0.25;
    if (progress > random) {
      oColor.a *= max(0.0, 1.0 - (progress - random) * 20.0);
    }
    return oColor;
  }
