// Broken Glass: shatters the window into a shower of sharp shards.
// Ported from Burn-My-Windows (resources/shaders/broken-glass.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float SHARD_LAYERS = 5.0;
constant float ACTOR_SCALE  = 2.0;
constant float PADDING      = ACTOR_SCALE / 2.0 - 0.5;
//@@
  float4 run() {
    vec4 oColor = vec4(0.0);

    float progress = uForOpening ? 1.0 - uProgress : uProgress;

    // Draw the individual shard layers.
    for (float i = 0.0; i < SHARD_LAYERS; ++i) {

      // To enable drawing shards outside of the window bounds, the quad is scaled by ACTOR_SCALE.
      // Here we scale and move the texture coordinates so that the window gets drawn at the right place.
      vec2 coords = iTexCoord * ACTOR_SCALE - PADDING;

      // Scale and rotate around our epicenter.
      coords -= uEpicenter;

      // Scale each layer a bit differently.
      coords /= mix(1.0, 1.0 + uBlowForce * (i + 2.0) / SHARD_LAYERS, progress);

      // Rotate each layer a bit differently.
      float rotation = (mod(i, 2.0) - 0.5) * 0.2 * progress;
      coords         = vec2(coords.x * cos(rotation) - coords.y * sin(rotation),
                            coords.x * sin(rotation) + coords.y * cos(rotation));

      // Move down each layer a bit.
      float gravity = (uForOpening ? -1.0 : 1.0) * uGravity * 0.1 * (i + 1.0) * progress * progress;
      coords += vec2(0.0, gravity);

      // Restore correct position.
      coords += uEpicenter;

      // Retrieve information from the shard texture for our layer.
      vec2 shardCoords = (coords + uSeed) * uSize / uShardScale / 500.0;
      vec2 shardMap    = aux2D(shardCoords).rg;

      // The green channel contains a random value in [0..1] for each shard. We discretize this into
      // SHARD_LAYERS bins and check if our layer falls into the bin of the current shard.
      float shardGroup = floor(shardMap.g * SHARD_LAYERS * 0.999);

      if (shardGroup == i && (shardMap.x - pow(progress + 0.1, 2.0)) > 0.0) {
        oColor = getInputColor(coords);
      }
    }
    return oColor;
  }
