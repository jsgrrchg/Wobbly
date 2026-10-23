// Wisps: windows are carried away to the realm of dreams by little fairies.
// Ported from Burn-My-Windows (resources/shaders/wisps.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float WISPS_RADIUS    = 20.0;
constant float WISPS_SPEED     = 10.0;
constant float WISPS_SPACING   = 40.0 + WISPS_RADIUS;
constant float WISPS_LAYERS    = 8.0;
constant float WISPS_IN_TIME   = 0.5;
constant float WINDOW_OUT_TIME = 1.0;
constant float SCALING         = 0.9;
//@@
  // Returns a grid of randomly moving points. Each grid cell contains one point which moves on an ellipse.
  vec4 getWisps(vec2 texCoords, float gridSize, vec2 seed) {
    // Shift coordinates by a random offset.
    vec2 coords = (texCoords + hash22(seed)) * uSize;

    // Apply global scale.
    coords /= gridSize;

    // Get grid cell coordinates in [0..1].
    vec2 cellUV = mod(coords, vec2(1.0));

    // This is unique for each cell.
    vec2 cellID = coords - cellUV + vec2(362.456);

    // Add random rotation, scale and offset to each grid cell.
    float speed     = mix(10.0, 15.0, hash12(cellID * seed * 134.451)) / gridSize * WISPS_SPEED;
    float rotation  = mix(0.0, 6.283, hash12(cellID * seed * 54.4129));
    float radius    = mix(0.5, 1.0, hash12(cellID * seed * 19.1249)) * WISPS_RADIUS;
    float roundness = mix(-1.0, 1.0, hash12(cellID * seed * 7.51949));

    vec2 offset = vec2(sin(speed * (uProgress * uDuration + 1.0)) * roundness, cos(speed * (uProgress * uDuration + 1.0)));
    offset *= 0.5 - 0.5 * radius / gridSize;
    offset = vec2(offset.x * cos(rotation) - offset.y * sin(rotation),
                  offset.x * sin(rotation) + offset.y * cos(rotation));

    cellUV += offset;

    vec3 color = tritone(hash12(cellID * seed * 1.256), uColor1, uColor2, uColor3);

    // Use distance to center of shifted / rotated UV coordinates to draw a glaring point.
    float dist = length(cellUV - 0.5) * gridSize / radius;

    if (dist < 1.0) {
      float alpha = min(5.0, 0.01 / pow(dist, 2.0));
      return vec4(color * alpha, alpha);
    }

    return vec4(0.0);
  }

  float4 run() {
    float progress = uForOpening ? 1.0 - easeOutQuad(uProgress) : easeOutQuad(uProgress);

    // Scale down the window slightly.
    float scale = 1.0 / mix(1.0, SCALING, progress) - 1.0;
    vec2 coords = iTexCoord * (scale + 1.0) - scale * 0.5;

    // Get the color of the window.
    vec4 oColor = getInputColor(coords);

    // Compute several layers of moving wisps.
    vec2 uv = (iTexCoord - 0.5) / mix(1.0, 0.5, progress) + 0.5;
    uv /= uScale;

    vec4 wisps = vec4(0.0);
    for (float i = 0.0; i < WISPS_LAYERS; ++i) {
      wisps = alphaOver(wisps, getWisps(uv * 0.3, WISPS_SPACING, uSeed * (i + 1.0)));
    }

    // Compute shrinking edge mask.
    float mask = getRelativeEdgeMask(mix(0.01, 0.5, progress));

    // Compute three different progress values.
    float wispsIn   = smoothstep(0.0, 1.0, clamp(progress / WISPS_IN_TIME, 0.0, 1.0));
    float wispsOut  = smoothstep(0.0, 1.0, clamp((progress - WISPS_IN_TIME) / (1.0 - WISPS_IN_TIME), 0.0, 1.0));
    float windowOut = smoothstep(0.0, 1.0, clamp(progress / WINDOW_OUT_TIME, 0.0, 1.0));

    // Use a noise function to dissolve the window.
    float noise = smoothstep(1.0, 0.0, abs(2.0 * simplex2DFractal(uv * uSize / 250.0) - 1.0));
    float windowMask = 1.0 - (windowOut < 0.5 ? mix(0.0, noise, windowOut * 2.0) : mix(noise, 1.0, windowOut * 2.0 - 1.0));

    oColor.a *= windowMask * mask;

    // Add the wisps.
    wisps.a *= min(wispsIn, 1.0 - wispsOut) * mask;
    return alphaOver(oColor, wisps);
  }
