# UI Screenshot Snapshots

This directory holds the baseline fixtures used to verify the app's visual layout.

- `window.png` — the committed baseline (a real capture of the app window).
- `actual/` — captures produced by the UI tests on each run (git-ignored).
- `diff-*.png` / `actual-*.png` — written on comparison failure (git-ignored).

## Workflow

1. Run the UI tests to capture the current window:
   ```sh
   ./Scripts/run-ui-tests.sh
   ```
   This writes `Tests/Snapshots/actual/window.png`.

2. Baseline (only when you intentionally changed the UI):
   ```sh
   ./Scripts/record_snapshots.sh
   ```
   This promotes `actual/` → the committed fixtures.

3. Verify against the baseline:
   ```sh
   ./Scripts/compare_snapshots.sh
   ```
   Fails if any capture differs by more than 0.1% of pixels.

CI runs the UI tests and compares snapshots; captured images are uploaded as
artifacts so a mismatch can be inspected. macOS requires **Screen Recording**
permission for screenshot capture, which is available on CI runners but must be
granted to the terminal app when running locally.
