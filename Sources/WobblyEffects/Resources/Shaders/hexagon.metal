// Hexagon: glowing lines and shrinking hexagon-shaped tiles.
// Ported from Burn-My-Windows (resources/shaders/hexagon.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

// Generates a procedural hexagonal pattern.
// result.xy: cell-relative coordinates for the given point ([0, 0] is in the center of a cell).
// result.z:  the distance to the closest edge (shrinking of the tiles and the sharp overlay lines).
// result.w:  the distance to the closest cell center (the glow effect).
inline float4 getHexagons(float2 p) {
  // Length of a cell's edge.
  float edgeLength = sqrt(4.0 / 3.0);

  // The hexgrid repeats after this distance.
  float2 scale = float2(3.0 * edgeLength, 2.0);

  // A repeating grid of scale-sized cells, and the same offset by half scale.
  float2 a    = mod(p, scale) - scale * 0.5;
  float2 aAbs = abs(a);
  float2 b    = mod(p + scale * 0.5, scale) - scale * 0.5;
  float2 bAbs = abs(b);

  // Distance to closer edge, diagonally or horizontally, once for each cell set.
  float distA = max(aAbs.x / edgeLength + aAbs.y * 0.5, aAbs.y);
  float distB = max(bAbs.x / edgeLength + bAbs.y * 0.5, bAbs.y);

  // Minimum of both is distance to closest edge.
  float dist = 1.0 - min(distA, distB);

  // We use the radial distance to the center for glow.
  float glow = min(dot(a, a), dot(b, b)) / 1.5;

  // Take cell-relative coordinates from the closer cell.
  float2 cellCoords = distA < distB ? a : b;

  return float4(cellCoords, dist, glow);
}
//@@
  float4 run() {
    // We simply inverse the progress for opening windows.
    float progress = uForOpening ? 1.0 - uProgress : uProgress;

    // Add some smooth noise to the progress so that not every tile behaves the same.
    float noise = simplex2D(iTexCoord + uSeed);
    progress    = clamp(mix(noise - 1.0, noise + 1.0, progress), 0.0, 1.0);

    // glowProgress fades in in the first half of the animation, tileProgress in the second half.
    float glowProgress = smoothstep(0.0, 1.0, clamp(progress / 0.5, 0.0, 1.0));
    float tileProgress = smoothstep(0.0, 1.0, clamp((progress - 0.5) / 0.5, 0.0, 1.0));

    vec2 texScale = 0.1 * uSize / uScale;
    vec4 hex      = getHexagons(iTexCoord * texScale);

    vec4 oColor = vec4(0.0);

    // Crop outer parts of the shrinking tiles.
    if (tileProgress < hex.z) {

      // Make the tiles shrink by offsetting the texture lookup towards the edge of the cell.
      vec2 lookupOffset = tileProgress * hex.xy / texScale / (1.0 - tileProgress);
      oColor            = getInputColor(iTexCoord + lookupOffset);

      vec4 glow = uGlowColor;
      vec4 line = uLineColor;

      // For the glow, we accumulate a few exponentially scaled versions of hex.w.
      glow.a *= pow(hex.w, 20.0) * 10.0 + pow(hex.w, 10.0) * 5.0 + pow(hex.w, 2.0) * 0.5;

      // Using step(uLineWidth, hex.z) would be simpler, but the below creates some fake antialiasing.
      line.a *= 1.0 - smoothstep(uLineWidth * 0.02 * 0.5, uLineWidth * 0.02, hex.z);

      // Fade in the glowing lines.
      glow.a *= glowProgress;
      line.a *= glowProgress;

      // Do not add the hexagon lines onto transparent parts of the window.
      glow *= oColor.a;
      line *= oColor.a;

      if (uAdditiveBlending) {
        oColor.rgb += glow.rgb * glow.a;
        oColor.rgb += line.rgb * line.a;
      } else {
        oColor.rgb = mix(oColor.rgb, glow.rgb, glow.a);
        oColor.rgb = mix(oColor.rgb, line.rgb, line.a);
      }
    }
    return oColor;
  }
