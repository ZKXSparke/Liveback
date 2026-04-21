# Test Mode bundled sample

`djimimo_sample.jpg` is the self-check sample bundled with the APK for
Test Mode (Doc 1 §5.3.6 + Doc 2 §10 + Doc 3 §9).

## Current source

Copied from `D:\repos\livephoto\20260420_140350.jpg`. Size 7.44 MB.
This file is a real djimimo-produced Motion Photo (JPEG + trailing
MP4 segment, no SEF trailer) and is the expected Test Mode input.

## Acceptance criteria

A valid Test Mode sample must:

1. Parse as a JPEG (SOI / EOI bracket present).
2. Contain an MP4 segment immediately after the EOI.
3. NOT contain a Samsung SEF trailer (otherwise Test Mode exercises
   the `skippedAlreadySamsung` path, not the repair path).
4. Be small enough to bundle without bloating the APK (ideally < 5 MB;
   current 7.44 MB is acceptable until we find a smaller authentic sample).

## Future work

Consider trimming the sample to < 2 MB before v1.0 ship. The video segment
can be re-encoded to shorter duration without breaking the Motion Photo
structure as long as `mvhd.duration / mvhd.timescale` remains non-zero.
