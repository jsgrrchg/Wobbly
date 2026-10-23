// Aura Glow: a radiant edge-lit animation.
// Ported from Burn-My-Windows (resources/shaders/aura-glow.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

//@@
  float4 run() {
    // We simply inverse the progress for opening windows.
    float progress = uForOpening ? uProgress : 1.0 - uProgress;

    // Map UV to window content (without the shadow padding).
    vec2 uv = (iTexCoord - 0.5) * uSize / (vec2(1.0) - vec2(uPadding * 2.0) / uSize);
    uv      = uv / uSize + 0.5;

    // The shapes of the masks at the end of the animation have a 1:1 aspect ratio. We blend
    // between the original UV and the 1:1 UV based on the progress.
    vec2 oneToOneUV = uv;
    oneToOneUV -= 0.5;
    if (uSize.x > uSize.y) {
      oneToOneUV.y *= uSize.y / uSize.x;
    } else {
      oneToOneUV.x *= uSize.x / uSize.y;
    }
    oneToOneUV += 0.5;
    uv = mix(oneToOneUV, uv, progress);

    // This blends between a square-shaped gradient towards the window edges and a circular gradient.
    float shape    = mix(2.0, 100.0, pow(progress, 5.0));
    float gradient = pow(abs(uv.x - 0.5) * 2.0, shape) + pow(abs(uv.y - 0.5) * 2.0, shape);
    gradient += simplex2D((iTexCoord + uSeed)) * 0.5;

    // This mask is used for the color overlay.
    float glowMask = (progress - gradient) / (uEdgeSize + 0.1);
    glowMask       = 1.0 - clamp(glowMask, 0.0, 1.0);

    // Quickly fade out the glow mask at the end of the animation.
    glowMask *= easeOutSine(min(1.0, (1.0 - progress) * 4.0));

    // Gradually blur the input color and slightly scale it up during the animation.
    vec2 windowUV = (iTexCoord - 0.5) * mix(1.1, 1.0, easeOutCubic(progress)) + 0.5;
    vec4 windowColor;
    if (uBlur > 0.0) {
      windowColor = getBlurredInputColor(windowUV, (1.0 - progress) * uBlur, 3.0);
    } else {
      windowColor = getInputColor(windowUV);
    }

    glowMask *= windowColor.a;

    vec3 glowColor    = cos(vec3(progress * uSpeed) + uv.xyx + vec3(0.0, 2.0, 4.0));
    float colorOffset = (uRandomColor) ? hash12(uSeed) : uStartHue;
    glowColor         = offsetHue(glowColor, colorOffset + 0.1);
    glowColor         = clamp(glowColor * uSaturation, vec3(0.0), vec3(1.0));

    windowColor.rgb += glowColor * glowMask;

    // To make this look better on light themes, we also add some color non-additively.
    windowColor = alphaOver(windowColor, vec4(glowColor, glowMask * 0.2));

    // A mask which will crop the window gradually into a circle.
    float softCrop = 1.0 - smoothstep(progress - 0.5, progress + 0.5, gradient);
    float hardCrop = 1.0 - smoothstep(progress - 0.05, progress + 0.05, gradient);
    float cropMask = mix(softCrop, hardCrop, uEdgeHardness);

    // Quickly fade in the alpha mask at the beginning of the animation.
    cropMask *= easeInSine(min(1.0, progress * 2.0));

    // Quickly fade out the alpha mask at the end of the animation.
    cropMask = max(cropMask, 1.0 - easeOutSine(min(1.0, (1.0 - progress) * 4.0)));

    windowColor.a *= cropMask;
    return windowColor;
  }
