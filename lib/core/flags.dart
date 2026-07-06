/// Feature flags — compile-time consts so dead branches tree-shake away.
///
/// Scanner V3 (docs/SCANNER_V3_POSTMORTEM.md): long-lived cv_worker isolate +
/// zero-codec live detection. Flip to false to fall back to the V2 hot path
/// (per-frame compute() + PNG round-trip) for A/B or rollback.
const bool kUseScannerV3 = true;
