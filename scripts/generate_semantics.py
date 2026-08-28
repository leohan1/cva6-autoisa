#!/usr/bin/env python3
"""Generate AutoISA RTL and software semantics from the typed v2 catalog."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "config/semantics_v2.json"
DEFAULT_OUT = ROOT / "generated/semantics"
DEFAULT_RTL = ROOT / "core/autoisa/autoisa_ci_semantic_engine.sv"
OPS = {"add", "sub", "mul_lo", "xor", "and", "or", "shl", "lshr", "ashr"}
IDENTIFIER = re.compile(r"^[a-z][a-z0-9_]*$")
SEMANTIC_NAME = re.compile(r"^[A-Z][A-Z0-9_]*$")


class CatalogError(ValueError):
    """Raised when the semantic catalog violates the executable contract."""


def _require_int(item: dict[str, Any], field: str, low: int, high: int, label: str) -> int:
    value = item.get(field)
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise CatalogError(f"{label}.{field} must be an integer in [{low}, {high}]")
    return value


def validate_catalog(catalog: dict[str, Any]) -> list[dict[str, Any]]:
    """Validate and normalize a topologically ordered, stateless 32-bit DAG catalog."""
    if not isinstance(catalog, dict):
        raise CatalogError("catalog must be a JSON object")
    if set(catalog) != {"schema_version", "xlen", "semantics"}:
        raise CatalogError("catalog fields must be exactly schema_version, xlen, semantics")
    if catalog.get("schema_version") != "2.0" or catalog.get("xlen") != 32:
        raise CatalogError("catalog requires schema_version=2.0 and xlen=32")
    semantics = catalog.get("semantics")
    if not isinstance(semantics, list) or not semantics:
        raise CatalogError("catalog.semantics must be a non-empty array")

    ids: set[int] = set()
    names: set[str] = set()
    normalized: list[dict[str, Any]] = []
    required = {"ci_id", "name", "operands", "results", "immediate", "latency",
                "initiation_interval", "compute_only", "nodes", "outputs"}
    for semantic in semantics:
        if not isinstance(semantic, dict) or set(semantic) != required:
            raise CatalogError("each semantic must contain exactly the v2 contract fields")
        ci_id = _require_int(semantic, "ci_id", 0, 255, "semantic")
        name = semantic.get("name")
        if ci_id in ids:
            raise CatalogError(f"duplicate ci_id: {ci_id}")
        if not isinstance(name, str) or not SEMANTIC_NAME.fullmatch(name) or name in names:
            raise CatalogError(f"invalid or duplicate semantic name: {name}")
        ids.add(ci_id)
        names.add(name)
        operands = _require_int(semantic, "operands", 1, 6, name)
        results = _require_int(semantic, "results", 1, 2, name)
        _require_int(semantic, "latency", 1, 31, name)
        _require_int(semantic, "initiation_interval", 1, 31, name)
        if semantic.get("compute_only") is not True:
            raise CatalogError(f"{name}: only stateless compute_only semantics are supported")
        if not isinstance(semantic.get("immediate"), bool):
            raise CatalogError(f"{name}.immediate must be boolean")

        nodes = semantic.get("nodes")
        outputs = semantic.get("outputs")
        if not isinstance(nodes, list) or not nodes:
            raise CatalogError(f"{name}.nodes must be a non-empty array")
        if not isinstance(outputs, list) or len(outputs) != results:
            raise CatalogError(f"{name}.outputs count must equal results")

        available = {f"operand{i}" for i in range(operands)}
        if semantic["immediate"]:
            available.add("immediate")
        node_ids: set[str] = set()
        dependencies: dict[str, list[str]] = {}
        for index, node in enumerate(nodes):
            label = f"{name}.nodes[{index}]"
            if not isinstance(node, dict) or set(node) != {"id", "op", "args"}:
                raise CatalogError(f"{label} must contain exactly id, op, args")
            node_id, op, args = node.get("id"), node.get("op"), node.get("args")
            if not isinstance(node_id, str) or not IDENTIFIER.fullmatch(node_id) or node_id in available:
                raise CatalogError(f"{label}: invalid or duplicate node id: {node_id}")
            if op not in OPS:
                raise CatalogError(f"{label}: unsupported operation: {op}")
            if not isinstance(args, list) or len(args) != 2 or not all(isinstance(arg, str) for arg in args):
                raise CatalogError(f"{label}.args must contain exactly two references")
            unknown = [arg for arg in args if arg not in available]
            if unknown:
                raise CatalogError(f"{label}: forward, cyclic, or invalid reference: {unknown[0]}")
            dependencies[node_id] = list(args)
            node_ids.add(node_id)
            available.add(node_id)

        if len(set(outputs)) != len(outputs) or any(output not in node_ids for output in outputs):
            raise CatalogError(f"{name}.outputs must be unique node ids")
        reachable = set(outputs)
        work = list(outputs)
        while work:
            current = work.pop()
            for dependency in dependencies[current]:
                if dependency in node_ids and dependency not in reachable:
                    reachable.add(dependency)
                    work.append(dependency)
        unused = node_ids - reachable
        if unused:
            raise CatalogError(f"{name}: unused nodes are forbidden: {sorted(unused)}")
        normalized.append(copy.deepcopy(semantic))
    return sorted(normalized, key=lambda item: item["ci_id"])


def normalize(catalog: dict[str, Any]) -> tuple[dict[str, Any], str, str]:
    normalized = {"schema_version": "2.0", "xlen": 32,
                  "semantics": validate_catalog(catalog)}
    text = json.dumps(normalized, indent=2, sort_keys=True) + "\n"
    digest = hashlib.sha256(text.encode()).hexdigest()
    return normalized, text, digest


def _sv_ref(reference: str, prefix: str) -> str:
    if reference.startswith("operand"):
        return f"operands_i[{int(reference[7:])}]"
    if reference == "immediate":
        return "immediate_i"
    return f"{prefix}_{reference}"


def _sv_expression(op: str, left: str, right: str) -> str:
    if op == "add": return f"{left} + {right}"
    if op == "sub": return f"{left} - {right}"
    if op == "mul_lo": return f"{left} * {right}"
    if op == "xor": return f"{left} ^ {right}"
    if op == "and": return f"{left} & {right}"
    if op == "or": return f"{left} | {right}"
    if op == "shl": return f"{left} << {right}[4:0]"
    if op == "lshr": return f"{left} >> {right}[4:0]"
    if op == "ashr": return f"$signed({left}) >>> {right}[4:0]"
    raise AssertionError(op)


def generate_sv(semantics: list[dict[str, Any]], digest: str) -> str:
    lines = [
        "// SPDX-License-Identifier: Apache-2.0",
        "// GENERATED by scripts/generate_semantics.py; DO NOT EDIT.",
        f"// normalized catalog sha256: {digest}",
        "`timescale 1ns / 1ps", "`default_nettype none", "",
        "module autoisa_ci_semantic_engine (",
        "    input wire [7:0] ci_id_i,",
        "    input wire [5:0][31:0] operands_i,",
        "    input wire [31:0] immediate_i,",
        "    output logic supported_o,",
        "    output logic [4:0] latency_o,",
        "    output logic [1:0] result_valid_o,",
        "    output logic [1:0][31:0] results_o",
        ");", ""
    ]
    for semantic in semantics:
        prefix = f"d{semantic['ci_id']}"
        for node in semantic["nodes"]:
            lines.append(f"  logic [31:0] {prefix}_{node['id']};")
    lines.extend(["", "  always_comb begin", "    supported_o = 1'b0;",
                  "    latency_o = 5'd1;", "    result_valid_o = 2'b00;",
                  "    results_o = '0;"])
    for semantic in semantics:
        prefix = f"d{semantic['ci_id']}"
        for node in semantic["nodes"]:
            lines.append(f"    {prefix}_{node['id']} = '0;")
    lines.extend(["    unique case (ci_id_i)"])
    for semantic in semantics:
        prefix = f"d{semantic['ci_id']}"
        lines.extend([f"      8'd{semantic['ci_id']}: begin", "        supported_o = 1'b1;",
                      f"        latency_o = 5'd{semantic['latency']};",
                      f"        result_valid_o = 2'b{(1 << semantic['results']) - 1:02b};"])
        for node in semantic["nodes"]:
            left = _sv_ref(node["args"][0], prefix)
            right = _sv_ref(node["args"][1], prefix)
            lines.append(f"        {prefix}_{node['id']} = {_sv_expression(node['op'], left, right)};")
        for index, output in enumerate(semantic["outputs"]):
            lines.append(f"        results_o[{index}] = {prefix}_{output};")
        lines.append("      end")
    lines.extend(["      default: begin", "      end", "    endcase", "  end", "", "endmodule", "",
                  "`default_nettype wire", ""])
    return "\n".join(lines)


def generate_python(normalized: dict[str, Any], digest: str) -> str:
    embedded = json.dumps(normalized, sort_keys=True, separators=(",", ":"))
    return f'''#!/usr/bin/env python3
"""Generated AutoISA semantic reference model. Do not edit."""
import json

CATALOG_SHA256 = "{digest}"
CATALOG = json.loads({embedded!r})
SEMANTICS = {{item["ci_id"]: item for item in CATALOG["semantics"]}}
MASK = 0xFFFFFFFF


def _apply(op, left, right):
    left &= MASK
    right &= MASK
    if op == "add": value = left + right
    elif op == "sub": value = left - right
    elif op == "mul_lo": value = left * right
    elif op == "xor": value = left ^ right
    elif op == "and": value = left & right
    elif op == "or": value = left | right
    elif op == "shl": value = left << (right & 31)
    elif op == "lshr": value = left >> (right & 31)
    elif op == "ashr":
        signed = left if left < 0x80000000 else left - 0x100000000
        value = signed >> (right & 31)
    else: raise ValueError(f"unsupported operation: {{op}}")
    return value & MASK


def evaluate(ci_id, operands, immediate=0):
    semantic = SEMANTICS.get(int(ci_id))
    if semantic is None:
        return {{"supported": False, "latency": 1, "result_valid": 0, "results": [0, 0]}}
    if len(operands) < semantic["operands"]:
        raise ValueError(f"ci_id {{ci_id}} requires {{semantic['operands']}} operands")
    values = {{f"operand{{i}}": int(operands[i]) & MASK for i in range(semantic["operands"])}}
    if semantic["immediate"]:
        values["immediate"] = int(immediate) & MASK
    for node in semantic["nodes"]:
        values[node["id"]] = _apply(node["op"], values[node["args"][0]], values[node["args"][1]])
    results = [values[name] for name in semantic["outputs"]]
    results.extend([0] * (2 - len(results)))
    return {{"supported": True, "latency": semantic["latency"],
            "result_valid": (1 << semantic["results"]) - 1, "results": results}}
'''


def build(config: Path = DEFAULT_CONFIG, out_dir: Path = DEFAULT_OUT,
          rtl_path: Path = DEFAULT_RTL) -> dict[str, Any]:
    with config.open(encoding="utf-8") as handle:
        catalog = json.load(handle)
    normalized, normalized_text, digest = normalize(catalog)
    semantics = normalized["semantics"]
    outputs = {
        out_dir / "semantics.normalized.json": normalized_text,
        out_dir / "autoisa_ci_semantic_engine.sv": generate_sv(semantics, digest),
        out_dir / "autoisa_ci_semantic_ref.py": generate_python(normalized, digest),
        rtl_path: generate_sv(semantics, digest),
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    rtl_path.parent.mkdir(parents=True, exist_ok=True)
    for path, content in outputs.items():
        path.write_text(content, encoding="utf-8", newline="\n")
    artifact_hashes = {
        "generated/semantics/semantics.normalized.json": hashlib.sha256(normalized_text.encode()).hexdigest(),
        "generated/semantics/autoisa_ci_semantic_engine.sv": hashlib.sha256(generate_sv(semantics, digest).encode()).hexdigest(),
        "generated/semantics/autoisa_ci_semantic_ref.py": hashlib.sha256(generate_python(normalized, digest).encode()).hexdigest(),
        "core/autoisa/autoisa_ci_semantic_engine.sv": hashlib.sha256(generate_sv(semantics, digest).encode()).hexdigest(),
    }
    manifest = {"schema_version": "2.0", "generator": "scripts/generate_semantics.py",
                "catalog": "config/semantics_v2.json",
                "catalog_sha256": digest, "semantic_count": len(semantics),
                "ci_ids": [item["ci_id"] for item in semantics], "artifacts": artifact_hashes}
    manifest_path = out_dir / "generation_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--rtl", type=Path, default=DEFAULT_RTL)
    args = parser.parse_args()
    try:
        manifest = build(args.config.resolve(), args.out.resolve(), args.rtl.resolve())
    except (CatalogError, json.JSONDecodeError, OSError) as error:
        print(f"ERROR: {error}")
        return 1
    print(f"Generated {manifest['semantic_count']} semantics: {manifest['ci_ids']}")
    print(f"Catalog SHA-256: {manifest['catalog_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
