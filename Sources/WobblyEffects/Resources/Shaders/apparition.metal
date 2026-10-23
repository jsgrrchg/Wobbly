// Apparition: windows are violently sucked into the void of magic.
// Ported from Burn-My-Windows (resources/shaders/apparition.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float ACTOR_SCALE = 2.0;
constant float PADDING     = ACTOR_SCALE / 2.0 - 0.5;
//@@
  float4 run() {
    float progress = uForOpening ? 1.0 - uProgress : uProgress;

    // Choose a random suction center.
    vec2 center = uSeed * uRandomness + 0.5 * (1.0 - uRandomness);
    vec2 coords = iTexCoord * ACTOR_SCALE - PADDING - center;

    // Add some shaking.
    coords.x += progress * 0.05 * uShake * sin((progress + uSeed.x) * (1.0 + uSeed.x) * uShake);
    coords.y += progress * 0.05 * uShake * cos((progress + uSeed.y) * (1.0 + uSeed.y) * uShake);

    // "Suck" the texture into the center.
    float dist = length(coords) / sqrt(2.0);
    coords += progress * coords / dist * 0.5 * uSuction;

    // Apply some whirling.
    coords = whirl(coords, uTwirl * progress, 0.0);

    // Fade out the window texture.
    vec4 oColor = getInputColor(coords + center);
    oColor.a *= 1.0 - progress;
    return oColor;
  }
