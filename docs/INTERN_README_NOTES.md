# Intern README draft — land instructions

**Against:** Mac.lan `feat/pointer-feel-click-modes` @ `14b8f47`
**Checkout:** `/Users/diegocabezas2/Documents/code_projects/mac-hand-mouse`
**Draft:** `/workspace/mac-hand-mouse-intern/README.md`

## What changed vs current README
- Lead with ~10s first-run: AX → camera → index points → Allow clicks stays OFF until ready.
- Gesture table matches shipped UI only: pointer, Allow clicks (default OFF), Pinch | Point forward (experimental), optional practice, Pinch feel, pause.
- Soft-edge pointing mentioned in plain language (no invented gestures).
- Explicit “not yet” list: no drag / scroll / right-click / double-click / tap.
- Link to `docs/SAFETY.md` for accidental-click guidance.

## Land
```sh
cp /workspace/mac-hand-mouse-intern/README.md \
  /Users/diegocabezas2/Documents/code_projects/mac-hand-mouse/README.md
# from that checkout:
bash scripts/test.sh   # docs-only; expect still green
```

No source/test edits in this drop. Tap and wave-2 modes intentionally omitted.
