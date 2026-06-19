# Agent memory index

Notes on non-obvious behavior discovered while working in this repo. Read
the relevant file before re-investigating something already debugged once.
Keep entries here short — one line per file, pointing at the real content.

- [project-overview.md](project-overview.md) — what this distro is and how the pieces fit together
- [akmods-kernel-skew.md](akmods-kernel-skew.md) — why the ZFS kmod can silently fail to match the booted kernel
- [build-pipeline-gotchas.md](build-pipeline-gotchas.md) — concrete fixes for past CI/build breakage (dnf5 quirks, RPM layout, package names)
