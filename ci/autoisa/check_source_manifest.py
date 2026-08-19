#!/usr/bin/env python3
"""Check the canonical AutoISA production source manifest."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "core/autoisa/autoisa_ci_sources.f"


def main() -> int:
    sources = [line.strip() for line in MANIFEST.read_text(encoding="utf-8").splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
    missing = [source for source in sources if not (ROOT / source).is_file()]
    duplicates = sorted({source for source in sources if sources.count(source) > 1})
    if missing or duplicates:
        print("manifest check FAILED")
        for source in missing:
            print(f"missing: {source}")
        for source in duplicates:
            print(f"duplicate: {source}")
        return 1
    print(f"manifest check PASS: {len(sources)} production sources, ABI v1.0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
