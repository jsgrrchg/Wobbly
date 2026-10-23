
fragment float4 fxFragment(VOut in [[stage_in]], constant FXUniforms &u [[buffer(0)]],
                           constant float4 *P [[buffer(1)]], texture2d<float> tex [[texture(0)]],
                           texture2d<float> aux [[texture(1)]]) {
  FX fx(in.uv, u, P, tex, aux);
  return fx.finish(fx.run());
}
