// Pixel Wheel: pixelates the window and hides the pixels in a wheel-like fashion.
// Ported from Burn-My-Windows (resources/shaders/pixel-wheel.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

//@@
  float4 run() {
    float progress = smoothstep(0.0, 1.0, uForOpening ? 1.0 - uProgress : uProgress);

    // The current level of pixelation increases with the progress.
    float pixelSize = ceil(uPixelSize * progress + 1.0);
    vec2 pixelGrid  = vec2(pixelSize) / uSize;
    vec2 texcoord   = iTexCoord - mod(iTexCoord, pixelGrid) + pixelGrid * 0.5;
    vec4 oColor     = getInputColor(texcoord);

    // Now hide the spoke sections.
    vec2 down    = vec2(0.0, 1.0);
    vec2 fragDir = normalize(texcoord - 0.5);

    // Compute angle to down direction.
    float angle = 0.5 * acos(dot(down, fragDir)) / 3.14159265359;
    if (fragDir.x < 0.0) {
      angle = 1.0 - angle;
    }

    // Progressively hide the spokes.
    float threshold = mod(angle * uSpokeCount, 1.0);
    if (progress > threshold) {
      oColor.a = 0.0;
    }
    return oColor;
  }
