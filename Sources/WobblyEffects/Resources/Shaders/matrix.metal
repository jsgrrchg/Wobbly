// Matrix: turns the window into a shower of green letters.
// Ported from Burn-My-Windows (resources/shaders/matrix.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float EDGE_FADE             = 30.0;
constant float FADE_WIDTH            = 150.0;
constant float TRAIL_LENGTH          = 0.2;
constant float FINAL_FADE_START_TIME = 0.8;
constant float LETTER_TILES          = 16.0;
constant float LETTER_FLICKER_SPEED  = 2.0;
//@@
  // This returns a flickering grid of random letters.
  float getText(vec2 fragCoord) {
    vec2 pixelCoords = fragCoord * uSize;
    vec2 uv          = mod(pixelCoords, uLetterSize) / uLetterSize;
    vec2 block       = pixelCoords / uLetterSize - uv;

    // Choose random letter.
    uv += floor(hash22(floor(hash22(block) * vec2(12.9898, 78.233) + LETTER_FLICKER_SPEED * uProgress * uDuration + 42.254)) *
                LETTER_TILES);

    return aux2D(uv / LETTER_TILES).r;
  }

  // x: gradients for the "raindrops" which move from top to bottom (fades the letters).
  // y: one below each drop and zero above it (fades the window texture).
  vec2 getRain(vec2 fragCoord) {
    float column = iTexCoord.x * uSize.x;
    column -= mod(column, uLetterSize);

    float delay = fract(sin(column) * 78.233) * mix(0.0, 1.0, uRandomness);
    float speed = fract(cos(column) * 12.989) * mix(0.0, 0.3, uRandomness) + 1.5;

    float distToDrop = (uProgress * 2.0 - delay) * speed - iTexCoord.y;

    float rainAlpha   = distToDrop >= 0.0 ? exp(-distToDrop / TRAIL_LENGTH) : 0.0;
    float windowAlpha = 1.0 - clamp(uSize.y * distToDrop, 0.0, FADE_WIDTH) / FADE_WIDTH;

    // Fade at window borders.
    rainAlpha *= getAbsoluteEdgeMask(EDGE_FADE, 0.5);

    // Add some variation to the drop start and end position.
    float shorten = fract(sin(column + 42.0) * 33.423) * mix(0.0, uOverShoot * 0.25, uRandomness);
    rainAlpha *= smoothstep(0.0, 1.0, clamp(iTexCoord.y / shorten, 0.0, 1.0));
    rainAlpha *= smoothstep(0.0, 1.0, clamp((1.0 - iTexCoord.y) / shorten, 0.0, 1.0));

    if (uForOpening) {
      windowAlpha = 1.0 - windowAlpha;
    }

    return vec2(rainAlpha, windowAlpha);
  }

  float4 run() {
    vec2 coords = iTexCoord;
    coords.y    = coords.y * (uOverShoot + 1.0) - uOverShoot * 0.5;

    vec2 rainMask  = getRain(coords);
    float textMask = getText(coords);

    // Get the window texture and fade it according to the effect mask.
    vec4 oColor = getInputColor(coords);
    oColor.a *= rainMask.y;

    // This is used to fade out the remaining trails in the end.
    float finalFade = 1.0 - clamp((uProgress - FINAL_FADE_START_TIME) / (1.0 - FINAL_FADE_START_TIME), 0.0, 1.0);
    float rainAlpha = finalFade * rainMask.x;

    // Add the matrix effect to the window.
    vec4 text = vec4(mix(uTrailColor, uTipColor, min(1.0, pow(rainAlpha + 0.1, 4.0))), rainAlpha * textMask);
    return alphaOver(oColor, text);
  }
