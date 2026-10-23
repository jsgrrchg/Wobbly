// Portal: teleports the window to an alternative dimension, through a portal that may resemble the one
// from a well-known cartoon series.
// Ported from Burn-My-Windows (resources/shaders/portal.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float PORTAL_WOBBLE_TIME     = 0.8;
constant float PORTAL_WOBBLE_STRENGTH = 1.2;
constant float GLOW_EDGE_WIDTH        = 5.0;
constant float WINDOW_SCALE           = 0.3;
constant float WINDOW_SQUISH          = 1.0;
constant float WINDOW_TILT            = -1.0;

// Make sure that the portal and window open / close animations are quick even if the duration is longer.
constant float PORTAL_OPEN_TIME  = 0.4;
constant float PORTAL_CLOSE_TIME = 0.4;
constant float WINDOW_OPEN_TIME  = 0.35;
//@@
  // Distorts the given coordinate to achieve the wobble of the portal when the window passes through.
  vec2 getPortalWobble(vec2 coords) {
    float progress = (uForOpening ? (1.0 - uProgress) : uProgress) / WINDOW_OPEN_TIME * uDuration;
    progress       = clamp(1.0 - abs((progress - 1.0) / PORTAL_WOBBLE_TIME), 0.0, 1.0);
    progress       = easeInBack(progress, 1.7);
    float dist     = length(coords);
    return coords * (1.0 - dist) * exp(-dist) * progress * PORTAL_WOBBLE_STRENGTH;
  }

  // The scale of the portal: it grows during the first PORTAL_OPEN_TIME seconds, stays at one, and
  // shrinks during the last PORTAL_CLOSE_TIME seconds.
  float getPortalScale() {
    float scale     = 1.0;
    float closeTime = PORTAL_CLOSE_TIME / uDuration;
    float openTime  = PORTAL_OPEN_TIME / uDuration;

    if (uProgress < openTime) {
      scale = easeOutBack(uProgress / openTime, 1.5);
    } else if (uProgress > 1.0 - closeTime) {
      scale = easeOutBack(1.0 - (uProgress - 1.0 + closeTime) / closeTime, 1.5);
    }
    return scale;
  }

  // A random 2D vector in [(-0.5, -0.5) ... (0.5, 0.5)], from simplex noise.
  vec2 getRandomDisplace(vec2 seed, float scale) {
    return vec2(simplex2D(seed * scale + uSeed) - 0.5, simplex2D(seed * scale + uSeed + vec2(7.89, 123.0)) - 0.5);
  }

  // Twists the given coordinates around the origin.
  vec2 getWhirledCoords(vec2 coords, float speedMultiplier, float warpMultiplier) {
    float rotation = uRotationSpeed * uProgress * uDuration * speedMultiplier;
    float warping  = uWhirling * (6.0 + 1.5 * uProgress) * warpMultiplier;
    return whirl(coords, warping, rotation);
  }

  // The portal, composed of several layers: a distorted radial gradient, two layers of whirled bands,
  // the rim of the portal, and some sparkling dots.
  vec4 getPortalColor() {
    // Put coordinate origin to the center of the window, with some margin for the elastic overshooting.
    vec2 coords = (iTexCoord - vec2(0.5)) * 2.0;
    coords *= 1.5;

    // Add the open-close animation of the portal.
    float scale = getPortalScale();
    coords /= max(scale * 0.5 + 0.5, 0.01);

    // The elastic wobbling when the window passes through the portal.
    vec2 wobble = getPortalWobble(coords);

    // If the portal is small, we want to have less details.
    float detailScale = 10000.0 / (uSize.x + uSize.y) / uDetails;

    // 1. layer: a radial gradient from a dark color in the center to a not-so-dark color outside.
    vec2 layerCoords = getWhirledCoords(coords - wobble * 1.0, 0.25, 1.0);
    vec2 displace    = getRandomDisplace(layerCoords, 2.1);
    layerCoords += displace * 0.1;

    float dist  = length(layerCoords);
    float alpha = dist > 1.0 ? 0.0 : 1.0;

    vec4 color = vec4(mix(darken(uColor, 0.8), darken(uColor, 0.2), pow(dist, 5.0)), alpha);

    float rand = dot(displace, displace);

    // 2. layer: the first layer of whirly bands.
    float noise = simplex2D(layerCoords / detailScale * 1.0 + vec2(12.3, 56.4) + uSeed);
    vec4 layer  = vec4(darken(uColor, 0.3), noise > 0.6 ? alpha : 0.0);
    color       = alphaOver(color, layer);

    // 3. layer: the second layer of whirly bands, lighter and with a different set of coordinates.
    layerCoords = getWhirledCoords(coords - wobble * 1.5, 0.75, 0.5);
    displace    = getRandomDisplace(layerCoords, 12.2);
    layerCoords += displace * 0.1;
    noise = simplex2D(layerCoords / detailScale * 1.3 + uSeed);
    layer = vec4(uColor, noise > 0.6 ? alpha : 0.0);
    color = alphaOver(color, layer);

    // Some color components can be outside the [0..1] range, which would create artifacts.
    color = clamp(color, 0.0, 1.0);

    // 4. layer: the edge around the portal, varying in thickness.
    float edge = mix(1.0, 5.0, rand) * GLOW_EDGE_WIDTH * detailScale - 150.0 * abs(dist - 1.0);
    layer      = vec4(uColor, clamp(edge, 0.0, 1.0));
    color      = alphaOver(color, layer);

    // 5. layer: some sparkling lights.
    layerCoords = getWhirledCoords(coords - wobble * 1.8, 1.25, 0.0);
    noise       = simplex2D(layerCoords / detailScale * 3.0 + uSeed);
    layer.rgb   = lighten(uColor, 0.8) * clamp(pow(noise * rand + 0.9, 50.0), 0.0, 1.0);
    color.rgb += layer.rgb;

    // Fade in / out the portal when it appears / disappears.
    color.a *= pow(clamp(scale, 0.0, 1.0), 2.0);

    return clamp(color, 0.0, 1.0);
  }

  // The window is scaled down and faded to transparency to create the illusion of travelling through the portal.
  vec4 getWindowColor() {
    float progress = (uForOpening ? (1.0 - uProgress) : uProgress) / WINDOW_OPEN_TIME * uDuration;

    // Add some elastic easing to make the effect more dynamic.
    progress = easeInBack(clamp(progress, 0.0, 1.0), 1.2);

    // Put texture coordinate origin to center of window.
    vec2 coords = iTexCoord * 2.0 - 1.0;

    // Scale, squish and 'tilt' the window.
    coords /= mix(1.0, WINDOW_SCALE, progress);
    coords.y /= mix(1.0, (1.0 - 0.2 * WINDOW_SQUISH), progress);
    coords.x /= mix(1.0, 1.0 - 0.1 * WINDOW_TILT * coords.y, progress);

    // Move texture coordinate center to corner again.
    coords = coords * 0.5 + 0.5;

    // Fade the window to transparency, quite late.
    vec4 oColor = getInputColor(coords);
    oColor.a *= clamp((1.0 - progress) * 3.0, 0.0, 1.0);
    return oColor;
  }

  float4 run() {
    vec4 portal = getPortalColor();
    vec4 window = getWindowColor();
    return alphaOver(portal, window);
  }
