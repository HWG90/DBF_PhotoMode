# HUD compatibility in release assets

The standard `tools/build_release.py` packages a combined HUD/Photo shader
closure through the sibling DBF-HUD source module
`tools/shared_shader_assets.py`. The companion source is mandatory; a missing
checkout fails the build instead of publishing a partial global registry.

Owned Photo assets remain available to isolated tests through
`build_release.owned_resources()`. Packaging uses `resources()`, which adds the
verified shared shader libraries and registry. Materials and runtime ownership
are unchanged. Both packages carry the same closure digest.

For an asset-only repair without including runtime development:

```
py -3 tools/build_release.py --assets-only --output dist/releases/shader-coexistence-20261015
```

For the verified matched pair, run `py -3 tools/build_arsenal_pair.py` in DBF-HUD.
Rebuild and distribute both payloads whenever the closure digest changes.
Arbitrary older packages still replace the engine's global registry and are not
covered by this guarantee. Conflicting same-ID shader programs fail the build.

Install native assets through Arsenal. Do not edit deployed game files or use an
Arsenal cache modification as the maintained fix. Keep the runtime release guard
intact; assets-only builds do not promote unrelated runtime experiments.
