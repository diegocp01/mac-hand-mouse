# DEV-Olympiad: adaptive pointer filter

## Crux
Feel dies on two cliffs in `PointerFilter` (`Sources/Gesture.swift`):
1. Fixed EMA `τ = 0.025s` → laggy flicks, jittery hover.
2. Hard crop `(t-0.15)/0.70` clamp → dead FOV + derivative discontinuity at the dashed-box wall.

## Change
- **SoftMargin.normalize**: wider inset `0.10`, tanh softclamp (k=1.2). Mid-band nearly linear; soft shoulders replace the hard 0.15 wall. Preview guide uses `GestureTuning.softInset`.
- **Velocity-aware τ**: `τ(v) = lerp(τ_max, τ_min, saturate(v / v_ref))`, `α = 1 - e^{-dt/τ}`. Hover damps; flicks track.
- **Synthetic proofs** in `Tests/main.swift`: soft vs hard at 0.15 wall; jitter RMS; fractional step lag (fast < slow).

## Land
Cloud Agents unavailable on plan; `gh` unauthed on box. Apply `pointer-filter.patch` from repo root:
```sh
git apply pointer-filter.patch
bash scripts/test.sh
```
