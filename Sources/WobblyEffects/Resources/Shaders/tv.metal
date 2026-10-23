// TV Effect: a very simple old-TV switch-off effect.
// Ported from Burn-My-Windows (resources/shaders/tv.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float BLUR_WIDTH = 0.01;  // Width of the gradients.
constant float TB_TIME    = 0.7;   // Relative time for the top/bottom animation.
constant float LR_TIME    = 0.4;   // Relative time for the left/right animation.
constant float LR_DELAY   = 0.6;   // Delay after which the left/right animation starts.
constant float FF_TIME    = 0.1;   // Relative time for the final fade to transparency.
constant float SCALING    = 0.5;   // Additional vertical scaling of the window.
//@@
  float4 run() {
    float prog = uForOpening ? 1.0 - easeOutQuad(uProgress) : easeOutQuad(uProgress);

    // Scale down the window vertically.
    float scale = 1.0 / mix(1.0, SCALING, prog) - 1.0;
    vec2 coords = iTexCoord;
    coords.y    = coords.y * (scale + 1.0) - scale * 0.5;

    // All of these are in [0..1] during the different stages of the animation.
    // tb: top-bottom animation, lr: left-right animation, ff: final fade animation.
    float tbProg = smoothstep(0.0, 1.0, clamp(prog / TB_TIME, 0.0, 1.0));
    float lrProg = smoothstep(0.0, 1.0, clamp((prog - LR_DELAY) / LR_TIME, 0.0, 1.0));
    float ffProg = smoothstep(0.0, 1.0, clamp((prog - 1.0 + FF_TIME) / FF_TIME, 0.0, 1.0));

    // A top-center-bottom gradient in [0..1..0].
    float tb = coords.y * 2.0;
    tb       = tb < 1.0 ? tb : 2.0 - tb;

    // A left-center-right gradient in [0..1..0].
    float lr = coords.x * 2.0;
    lr       = lr < 1.0 ? lr : 2.0 - lr;

    // Combine the progress values with the gradients to create the alpha masks.
    float tbMask = 1.0 - smoothstep(0.0, 1.0, clamp((tbProg - tb) / BLUR_WIDTH, 0.0, 1.0));
    float lrMask = 1.0 - smoothstep(0.0, 1.0, clamp((lrProg - lr) / BLUR_WIDTH, 0.0, 1.0));
    float ffMask = 1.0 - smoothstep(0.0, 1.0, ffProg);

    // Assemble the final alpha value.
    float mask = tbMask * lrMask * ffMask;

    vec4 oColor = getInputColor(coords);
    oColor.rgb  = mix(oColor.rgb, uColor.rgb * oColor.a, uColor.a * smoothstep(0.0, 1.0, prog));
    oColor.a *= mask;
    return oColor;
  }
