# DartPad snapshots (not maintained)

Single-file copies of the first extraction stages, made so each stage could be
tried on a phone in [dartpad.dev](https://dartpad.dev) before CI existed.

They are frozen at the stage they were written and are **not** kept in step
with the real code: for example `tier1_dartpad.dart` has no Al Salam Fawri or
prepaid-card templates. The source of truth is
`packages/beaza_extraction/lib/src/`, tested in CI on every push. Do not copy
code from here back into the package.
