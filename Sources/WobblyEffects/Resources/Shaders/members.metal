  // ---- Members shared by every effect (standard uniforms and input helpers of Burn-My-Windows) ----
  texture2d<float> tex;
  texture2d<float> aux;
  constant float4 *P;

  float2 iTexCoord;
  float2 uSize;
  float uPadding;
  float uProgress;
  float uDuration;
  bool uForOpening;
  bool uIsFullscreen;
  float2 windowSize;
  float2 uvScale;
  float2 uvOffset;
  float shadow;

  // Layered effects (Aperture Panels, Morph, Wormhole): only the window layer is drawn, so the
  // desktop behind the window stays untouched and shows through.
  float uLayer;
  float2 uLayerSize;
  float4 uTexRect;

  FX(float2 uv, constant FXUniforms &u, constant float4 *p, texture2d<float> t, texture2d<float> a)
      : tex(t), aux(a), P(p), iTexCoord(uv), uSize(u.texSize), uPadding(u.padding), uProgress(u.progress),
        uDuration(u.duration), uForOpening(u.forOpening > 0.5), uIsFullscreen(u.isFullscreen > 0.5),
        windowSize(u.windowSize), uvScale(u.uvScale), uvOffset(u.uvOffset), shadow(u.shadow), uLayer(1.0),
        uLayerSize(u.texSize), uTexRect(float4(0.0, 0.0, u.texSize.x, u.texSize.y)) {}

  // Straight-alpha color of the window capture at the given actor coordinates ([0, 1]² covers
  // the window and its padding). Outside the capture it is transparent.
  float4 getInputColor(float2 coords) const {
    constexpr sampler s(filter::linear, address::clamp_to_zero);
    float2 w = (coords * uSize - uPadding) / windowSize;
    float4 c = tex.sample(s, w * uvScale + uvOffset, level(0));
    float4 r = c.a > 0.0 ? float4(c.rgb / c.a, c.a) : float4(0.0);
    if (any(w < float2(0.0)) || any(w > float2(1.0))) {
      r.a *= shadow;
    }
    return r;
  }

  // The effect's auxiliary texture (brush, claws, dust, font or shards), repeating.
  float4 aux2D(float2 uv) const {
    constexpr sampler s(filter::linear, address::repeat);
    return aux.sample(s, uv, level(0));
  }

  float4 getBlurredInputColor(float2 uv, float radius, float samples) {
    float4 color = float4(0.0);
    const float tau        = 6.28318530718;
    const float directions = 15.0;
    for (float d = 0.0; d < tau; d += tau / directions) {
      for (float s = 0.0; s < 1.0; s += 1.0 / samples) {
        float2 offset = float2(cos(d), sin(d)) * radius * (1.0 - s) / uSize;
        color += getInputColor(uv + offset);
      }
    }
    return color / samples / directions;
  }

  float getEdgeMask(float2 uv, float2 maxUV, float fadeWidth) {
    float mask = 1.0;
    if (!uIsFullscreen) {
      mask *= smoothstep(0.0, 1.0, clamp(uv.x / fadeWidth, 0.0, 1.0));
      mask *= smoothstep(0.0, 1.0, clamp(uv.y / fadeWidth, 0.0, 1.0));
      mask *= smoothstep(0.0, 1.0, clamp((maxUV.x - uv.x) / fadeWidth, 0.0, 1.0));
      mask *= smoothstep(0.0, 1.0, clamp((maxUV.y - uv.y) / fadeWidth, 0.0, 1.0));
    }
    return mask;
  }

  float getAbsoluteEdgeMask(float fadePixels, float offset) {
    float padding = max(0.0, uPadding - fadePixels * offset);
    float2 uv     = iTexCoord * uSize - padding;
    return getEdgeMask(uv, uSize - 2.0 * padding, fadePixels);
  }

  float getRelativeEdgeMask(float fadeAmount) {
    return getEdgeMask(iTexCoord, float2(1.0), fadeAmount);
  }

  float2 getLayerPx() { return uTexRect.xy + iTexCoord * uTexRect.zw; }

  float4 getLayerColor(float2 p) {
    p = clamp(p, float2(0.5), uLayerSize - 0.5);
    return getInputColor((p - uTexRect.xy) / uTexRect.zw);
  }

  float4 finish(float4 c) const {
    if (any(isnan(c))) c = float4(0.0);
    c = clamp(c, 0.0, 1.0);
    return float4(c.rgb * c.a, c.a);
  }

