#!/usr/bin/env python3
"""Cross-check the executable Layout v2 and Semantic v2 contracts."""
from __future__ import annotations

from typing import Any


class ContractError(ValueError):
    """Raised when layout reachability and semantic capability disagree."""


def validate_bidirectional(
    layout_catalog: dict[str, Any], semantic_catalog: dict[str, Any]
) -> list[int]:
    """Require a one-to-one, shape-compatible D0-D7 layout/semantic mapping."""
    layouts = {
        item["id"]: item
        for item in layout_catalog.get("layouts", [])
        if item.get("enabled") is True
    }
    semantics = {
        item["ci_id"]: item for item in semantic_catalog.get("semantics", [])
    }
    if set(layouts) != set(semantics):
        missing_layout = sorted(set(semantics) - set(layouts))
        missing_semantic = sorted(set(layouts) - set(semantics))
        raise ContractError(
            "bidirectional ID coverage mismatch: "
            f"missing_layout={missing_layout}, missing_semantic={missing_semantic}"
        )

    for ci_id in sorted(layouts):
        layout = layouts[ci_id]
        semantic = semantics[ci_id]
        selector = layout.get("semantic", {})
        if selector.get("kind") == "fixed":
            reachable = selector.get("value") == ci_id
        elif selector.get("kind") == "encoded":
            width = selector.get("width")
            reachable = isinstance(width, int) and 0 <= ci_id < (1 << width)
        else:
            reachable = False
        if not reachable:
            raise ContractError(f"L{ci_id} cannot select D{ci_id}")

        pairs = (
            ("operands", layout.get("logical_sources"), semantic.get("operands")),
            ("results", layout.get("logical_destinations"), semantic.get("results")),
            ("immediate", "immediate" in layout, semantic.get("immediate")),
        )
        for field, layout_value, semantic_value in pairs:
            if layout_value != semantic_value:
                raise ContractError(
                    f"L{ci_id}/D{ci_id} {field} mismatch: "
                    f"layout={layout_value}, semantic={semantic_value}"
                )
    return sorted(layouts)


def verify_reference_triplet(reference: Any) -> None:
    """Independently pin the G3 D0/D1/D7 reference-model behavior."""
    cases = (
        (0, [0xFFFFFFFF, 1], 0, 0),
        (1, [6, 7, 8], 0, 50),
        (7, [5, 9], 3, 36),
    )
    for ci_id, operands, immediate, expected in cases:
        actual = reference.evaluate(ci_id, operands, immediate)
        if not actual["supported"] or actual["results"][0] != expected:
            raise ContractError(
                f"D{ci_id} reference behavior mismatch: "
                f"expected=0x{expected:08x}, actual={actual}"
            )
