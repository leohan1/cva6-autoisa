#!/usr/bin/env python3
"""Generate AutoISA Layout v2 RTL/software artifacts from one JSON catalog."""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import io
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "config/layout_profiles_v2.json"
DEFAULT_OUT = ROOT / "generated/layout"
DEFAULT_RTL = ROOT / "core/autoisa/autoisa_ci_layout_decoder_v2.sv"
NS_WIDTH = {"GPR32": 5, "GPR16": 4, "RVC8": 3}


class CatalogError(ValueError):
    pass


def _u32(value: str | int) -> int:
    result = int(value, 0) if isinstance(value, str) else int(value)
    if not 0 <= result <= 0xFFFFFFFF:
        raise CatalogError(f"32-bit value out of range: {value}")
    return result


def _slice_width(part: dict[str, int]) -> int:
    return part["instr_msb"] - part["instr_lsb"] + 1


def _validate_slices(label: str, slices: list[dict[str, int]], value_width: int) -> int:
    instr_mask = 0
    value_mask = 0
    for part in slices:
        msb, lsb, value_lsb = part["instr_msb"], part["instr_lsb"], part["value_lsb"]
        if not (0 <= lsb <= msb < 32):
            raise CatalogError(f"{label}: instruction slice [{msb}:{lsb}] is out of range")
        width = _slice_width(part)
        if value_lsb < 0 or value_lsb + width > value_width:
            raise CatalogError(f"{label}: slice exceeds declared value width {value_width}")
        i_mask = ((1 << width) - 1) << lsb
        v_mask = ((1 << width) - 1) << value_lsb
        if instr_mask & i_mask:
            raise CatalogError(f"{label}: instruction slices overlap")
        if value_mask & v_mask:
            raise CatalogError(f"{label}: value slices overlap")
        instr_mask |= i_mask
        value_mask |= v_mask
    if value_mask != (1 << value_width) - 1:
        raise CatalogError(f"{label}: slices do not cover exactly {value_width} value bits")
    return instr_mask


def validate_catalog(catalog: dict[str, Any]) -> list[dict[str, Any]]:
    if catalog.get("schema_version") != "2.0" or catalog.get("xlen") != 32:
        raise CatalogError("catalog requires schema_version=2.0 and xlen=32")
    layouts = catalog.get("layouts")
    if not isinstance(layouts, list) or not layouts:
        raise CatalogError("catalog.layouts must be a non-empty array")
    ids: set[int] = set()
    names: set[str] = set()
    enabled: list[dict[str, Any]] = []
    for layout in layouts:
        lid, name = layout.get("id"), layout.get("name")
        if not isinstance(lid, int) or not 0 <= lid < 16 or lid in ids:
            raise CatalogError(f"invalid or duplicate layout id: {lid}")
        if not isinstance(name, str) or name in names:
            raise CatalogError(f"invalid or duplicate layout name: {name}")
        ids.add(lid); names.add(name)
        match, mask = _u32(layout["match"]), _u32(layout["mask"])
        if match & ~mask:
            raise CatalogError(f"{name}: match sets bits outside mask")
        if not layout.get("enabled", False):
            continue
        if not layout.get("compute_only", False) or layout.get("backend") == "AUTOISA_HOST_MEMORY_EXPERIMENTAL":
            raise CatalogError(f"{name}: enabled catalog must be compute-only")
        sources = layout.get("sources", [])
        destinations = layout.get("destinations", [])
        if layout.get("logical_sources") != len(sources) or not 1 <= len(sources) <= 6:
            raise CatalogError(f"{name}: logical source count mismatch")
        if layout.get("logical_destinations") != len(destinations) or not 1 <= len(destinations) <= 2:
            raise CatalogError(f"{name}: logical destination count mismatch")

        occupied = 0
        for kind, fields in (("source", sources), ("destination", destinations)):
            known_names = {field.get("name") for field in destinations}
            for index, field in enumerate(fields):
                ns = field.get("namespace")
                label = f"{name}.{kind}[{index}]"
                if ns == "DERIVED_PAIR":
                    if kind != "destination" or field.get("derived_from") not in known_names or field.get("offset") != 1:
                        raise CatalogError(f"{label}: invalid derived pair")
                    continue
                if ns not in NS_WIDTH:
                    raise CatalogError(f"{label}: unsupported namespace {ns}")
                field_mask = _validate_slices(label, field.get("slices", []), NS_WIDTH[ns])
                if occupied & field_mask:
                    raise CatalogError(f"{label}: payload overlaps another field")
                occupied |= field_mask
                if kind == "destination" and ns in ("GPR32", "GPR16") and not field.get("reject_zero", False):
                    raise CatalogError(f"{label}: encoded destination must reject x0")

        semantic = layout.get("semantic", {})
        if semantic.get("kind") == "encoded":
            width = semantic.get("width")
            if not isinstance(width, int) or not 1 <= width <= 8:
                raise CatalogError(f"{name}.semantic: invalid width")
            field_mask = _validate_slices(f"{name}.semantic", semantic.get("slices", []), width)
            if occupied & field_mask:
                raise CatalogError(f"{name}.semantic: overlaps payload")
            occupied |= field_mask
        elif semantic.get("kind") == "fixed":
            if not isinstance(semantic.get("value"), int) or not 0 <= semantic["value"] <= 255:
                raise CatalogError(f"{name}.semantic: invalid fixed value")
        else:
            raise CatalogError(f"{name}.semantic: kind must be fixed or encoded")

        immediate = layout.get("immediate")
        if immediate is not None:
            width = immediate.get("width")
            scale = immediate.get("scale")
            if not isinstance(width, int) or not 1 <= width <= 32:
                raise CatalogError(f"{name}.immediate: invalid width")
            if not isinstance(immediate.get("signed"), bool) or not isinstance(scale, int) or not 0 <= scale < 32:
                raise CatalogError(f"{name}.immediate: signed and scale must be explicit")
            field_mask = _validate_slices(f"{name}.immediate", immediate.get("slices", []), width)
            if occupied & field_mask:
                raise CatalogError(f"{name}.immediate: overlaps payload")
            occupied |= field_mask

        if occupied & mask:
            raise CatalogError(f"{name}: payload overlaps recognition mask")
        pair = layout.get("pair_constraint")
        if any(field.get("namespace") == "DERIVED_PAIR" for field in destinations):
            if not pair or pair.get("base") not in {field["name"] for field in destinations} or pair.get("max", 32) > 30:
                raise CatalogError(f"{name}: derived pair requires bounded pair_constraint")
        enabled.append(layout)

    for index, left in enumerate(enabled):
        lm, lk = _u32(left["match"]), _u32(left["mask"])
        for right in enabled[index + 1:]:
            rm, rk = _u32(right["match"]), _u32(right["mask"])
            if ((lm ^ rm) & (lk & rk)) == 0:
                raise CatalogError(f"layouts overlap: {left['name']} and {right['name']}")
    return sorted(enabled, key=lambda item: item["id"])


def _sv_bits(parts: list[dict[str, int]]) -> str:
    ordered = sorted(parts, key=lambda part: part["value_lsb"], reverse=True)
    values = [f"instr_i[{part['instr_msb']}]" if part["instr_msb"] == part["instr_lsb"]
              else f"instr_i[{part['instr_msb']}:{part['instr_lsb']}]" for part in ordered]
    return values[0] if len(values) == 1 else "{" + ", ".join(values) + "}"


def _sv_reg(field: dict[str, Any], named_destinations: dict[str, int]) -> str:
    ns = field["namespace"]
    if ns == "DERIVED_PAIR":
        return f"desc_o.dst_addr[{named_destinations[field['derived_from']]}] + 5'd{field['offset']}"
    bits = _sv_bits(field["slices"])
    if ns == "RVC8":
        return f"{{2'b01, {bits}}}"
    if ns == "GPR16":
        return f"{{1'b0, {bits}}}"
    return bits


def generate_sv(layouts: list[dict[str, Any]], digest: str) -> str:
    out = [
        "// SPDX-License-Identifier: Apache-2.0",
        "// GENERATED by scripts/generate_layout_decoder.py; DO NOT EDIT.",
        f"// normalized catalog sha256: {digest}",
        "`timescale 1ns/1ps", "`default_nettype none", "",
        "module autoisa_ci_layout_decoder_v2 (",
        "    input wire [31:0] instr_i,",
        "    input wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] tag_i,",
        "    input wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] epoch_i,",
        "    output logic valid_o,", "    output logic illegal_o,",
        "    output autoisa_ci_types_pkg::autoisa_ci_host_desc_t desc_o", ");",
        "  import autoisa_ci_types_pkg::*;", "",
        "  function automatic logic match_mask_hit(input logic [31:0] instruction, input logic [31:0] match_value, input logic [31:0] mask_value);",
        "    match_mask_hit = ((instruction & mask_value) == match_value);",
        "  endfunction", "", "  always_comb begin",
        "    valid_o = 1'b0;", "    illegal_o = 1'b0;", "    desc_o = '0;",
        "    desc_o.tag = tag_i;", "    desc_o.epoch = epoch_i;", ""
    ]
    for ordinal, layout in enumerate(layouts):
        lead = "    if" if ordinal == 0 else "    end else if"
        out.append(f"{lead} (match_mask_hit(instr_i, 32'h{_u32(layout['match']):08x}, 32'h{_u32(layout['mask']):08x})) begin")
        out.extend(["      valid_o = 1'b1;", f"      desc_o.layout_id = 4'd{layout['id']};"])
        semantic = layout["semantic"]
        if semantic["kind"] == "fixed":
            out.append(f"      desc_o.ci_id = 8'd{semantic['value']};")
        else:
            out.extend(["      desc_o.ci_id = '0;", f"      desc_o.ci_id[{semantic['width']-1}:0] = {_sv_bits(semantic['slices'])};"])
        for index, source in enumerate(layout["sources"]):
            out.extend([f"      desc_o.src_valid[{index}] = 1'b1;", f"      desc_o.src_addr[{index}] = {_sv_reg(source, {})};"])
        named = {field["name"]: index for index, field in enumerate(layout["destinations"])}
        for index, destination in enumerate(layout["destinations"]):
            out.extend([f"      desc_o.dst_valid[{index}] = 1'b1;", f"      desc_o.dst_addr[{index}] = {_sv_reg(destination, named)};"])
        if "immediate" in layout:
            imm = layout["immediate"]
            out.extend(["      desc_o.imm_valid = 1'b1;", "      desc_o.immediate = '0;"])
            for part in imm["slices"]:
                width = _slice_width(part)
                vm = part["value_lsb"] + width - 1
                out.append(f"      desc_o.immediate[{vm}:{part['value_lsb']}] = instr_i[{part['instr_msb']}:{part['instr_lsb']}];")
            if imm["signed"] and imm["width"] < 32:
                out.append(f"      desc_o.immediate[31:{imm['width']}] = {{{32-imm['width']}{{desc_o.immediate[{imm['width']-1}]}}}};")
            if imm["scale"]:
                out.append(f"      desc_o.immediate = desc_o.immediate << {imm['scale']};")
        if "pair_constraint" in layout:
            pair = layout["pair_constraint"]
            base = named[pair["base"]]
            out.append("      desc_o.pair_constrained = 1'b1;")
            checks = []
            if pair["nonzero"]: checks.append(f"(desc_o.dst_addr[{base}] == 5'd0)")
            if pair["even"]: checks.append(f"desc_o.dst_addr[{base}][0]")
            checks.append(f"(desc_o.dst_addr[{base}] > 5'd{pair['max']})")
            out.append("      if (" + " || ".join(checks) + ") illegal_o = 1'b1;")
        out.append(f"      desc_o.backend = {layout['backend']};")
    out.extend([
        "    end", "",
        "    if (valid_o && ((desc_o.dst_valid[0] && (desc_o.dst_addr[0] == 5'd0)) ||",
        "                    (desc_o.dst_valid[1] && (desc_o.dst_addr[1] == 5'd0)))) begin",
        "      illegal_o = 1'b1;", "    end", "  end", "endmodule", "", "`default_nettype wire", ""
    ])
    return "\n".join(out)


def generate_python(normalized: dict[str, Any], digest: str) -> str:
    embedded = json.dumps(normalized["layouts"], sort_keys=True, separators=(",", ":"))
    return f'''#!/usr/bin/env python3
"""Generated AutoISA Layout v2 encoder/decoder. Catalog sha256: {digest}"""
import json
LAYOUTS = json.loads(r\'''{embedded}\''')
BY_NAME = {{item["name"]: item for item in LAYOUTS if item["enabled"]}}

def _extract(instr, parts):
    value = 0
    for part in parts:
        width = part["instr_msb"] - part["instr_lsb"] + 1
        value |= ((instr >> part["instr_lsb"]) & ((1 << width) - 1)) << part["value_lsb"]
    return value

def _insert(instr, value, parts):
    for part in parts:
        width = part["instr_msb"] - part["instr_lsb"] + 1
        field_mask = (1 << width) - 1
        instr |= ((value >> part["value_lsb"]) & field_mask) << part["instr_lsb"]
    return instr

def _reg_decode(raw, namespace):
    return raw + 8 if namespace == "RVC8" else raw

def _reg_encode(reg, namespace):
    limits = {{"GPR32": (0, 31), "GPR16": (0, 15), "RVC8": (8, 15)}}
    low, high = limits[namespace]
    if not low <= reg <= high:
        raise ValueError(f"register {{reg}} is outside {{namespace}}")
    return reg - 8 if namespace == "RVC8" else reg

def encode_layout(name, sources, destinations, semantic_id=None, immediate=None):
    layout = BY_NAME[name]
    if len(sources) != layout["logical_sources"] or len(destinations) != layout["logical_destinations"]:
        raise ValueError("logical operand/result count mismatch")
    instr = int(layout["match"], 0)
    for field, reg in zip(layout["sources"], sources):
        instr = _insert(instr, _reg_encode(reg, field["namespace"]), field["slices"])
    decoded_dest = {{}}
    for field, reg in zip(layout["destinations"], destinations):
        if field["namespace"] == "DERIVED_PAIR":
            expected = decoded_dest[field["derived_from"]] + field["offset"]
            if reg != expected: raise ValueError("derived pair destination mismatch")
        else:
            if field.get("reject_zero") and reg == 0: raise ValueError("x0 destination is illegal")
            instr = _insert(instr, _reg_encode(reg, field["namespace"]), field["slices"])
        decoded_dest[field["name"]] = reg
    sem = layout["semantic"]
    if sem["kind"] == "encoded":
        if semantic_id is None or not 0 <= semantic_id < (1 << sem["width"]): raise ValueError("semantic_id out of range")
        instr = _insert(instr, semantic_id, sem["slices"])
    elif semantic_id not in (None, sem["value"]): raise ValueError("fixed semantic mismatch")
    imm = layout.get("immediate")
    if imm:
        if immediate is None: raise ValueError("immediate is required")
        if immediate % (1 << imm["scale"]): raise ValueError("immediate violates scale")
        raw = immediate >> imm["scale"]
        low = -(1 << (imm["width"] - 1)) if imm["signed"] else 0
        high = (1 << (imm["width"] - (1 if imm["signed"] else 0))) - 1
        if not low <= raw <= high: raise ValueError("immediate out of range")
        instr = _insert(instr, raw & ((1 << imm["width"]) - 1), imm["slices"])
    elif immediate is not None: raise ValueError("layout has no immediate")
    if (instr & int(layout["mask"], 0)) != int(layout["match"], 0): raise AssertionError("payload changed recognition bits")
    return instr & 0xffffffff

def decode_instruction(instr):
    hits = [layout for layout in BY_NAME.values() if (instr & int(layout["mask"], 0)) == int(layout["match"], 0)]
    if len(hits) != 1: return None
    layout = hits[0]
    sources = [_reg_decode(_extract(instr, f["slices"]), f["namespace"]) for f in layout["sources"]]
    destinations, named = [], {{}}
    for field in layout["destinations"]:
        if field["namespace"] == "DERIVED_PAIR": value = named[field["derived_from"]] + field["offset"]
        else: value = _reg_decode(_extract(instr, field["slices"]), field["namespace"])
        destinations.append(value); named[field["name"]] = value
    sem = layout["semantic"]
    semantic_id = sem["value"] if sem["kind"] == "fixed" else _extract(instr, sem["slices"])
    immediate = None
    if "immediate" in layout:
        spec = layout["immediate"]; raw = _extract(instr, spec["slices"])
        if spec["signed"] and raw & (1 << (spec["width"] - 1)): raw -= 1 << spec["width"]
        immediate = raw << spec["scale"]
    return {{"name": layout["name"], "layout_id": layout["id"], "sources": sources, "destinations": destinations, "semantic_id": semantic_id, "immediate": immediate}}
'''


def generate_header(layouts: list[dict[str, Any]], digest: str) -> str:
    lines = ["/* GENERATED AutoISA Layout v2 constants. */", f"/* catalog sha256: {digest} */", "#ifndef AUTOISA_CI_ENCODING_H", "#define AUTOISA_CI_ENCODING_H", "#include <stdint.h>"]
    for layout in layouts:
        lines.extend([f"#define AUTOISA_{layout['name']}_ID {layout['id']}u", f"#define AUTOISA_{layout['name']}_MATCH UINT32_C(0x{_u32(layout['match']):08x})", f"#define AUTOISA_{layout['name']}_MASK UINT32_C(0x{_u32(layout['mask']):08x})"])
    lines.extend(["#endif", ""])
    return "\n".join(lines)


def generate_assembly(layouts: list[dict[str, Any]], digest: str) -> str:
    lines = ["# GENERATED AutoISA Layout v2 constants", f"# catalog sha256: {digest}"]
    for layout in layouts:
        lines.extend([f".equ AUTOISA_{layout['name']}_ID, {layout['id']}", f".equ AUTOISA_{layout['name']}_MATCH, 0x{_u32(layout['match']):08x}", f".equ AUTOISA_{layout['name']}_MASK, 0x{_u32(layout['mask']):08x}"])
    return "\n".join(lines) + "\n"


def generate_bit_budget(layouts: list[dict[str, Any]]) -> str:
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow(["layout_id", "name", "recognition_bits", "source_bits", "destination_bits", "semantic_bits", "immediate_bits", "payload_bits", "free_bits"])
    for layout in layouts:
        source_bits = sum(NS_WIDTH[field["namespace"]] for field in layout["sources"])
        destination_bits = sum(NS_WIDTH.get(field["namespace"], 0) for field in layout["destinations"])
        semantic_bits = layout["semantic"].get("width", 0)
        immediate_bits = layout.get("immediate", {}).get("width", 0)
        recognition = _u32(layout["mask"]).bit_count()
        payload = source_bits + destination_bits + semantic_bits + immediate_bits
        writer.writerow([layout["id"], layout["name"], recognition, source_bits, destination_bits, semantic_bits, immediate_bits, payload, 32 - recognition - payload])
    return stream.getvalue()


def build(config: Path, out_dir: Path, rtl_out: Path) -> dict[str, str]:
    catalog = json.loads(config.read_text(encoding="utf-8"))
    layouts = validate_catalog(catalog)
    normalized = copy.deepcopy(catalog)
    normalized["layouts"] = sorted(normalized["layouts"], key=lambda item: item["id"])
    normalized_text = json.dumps(normalized, indent=2, sort_keys=True) + "\n"
    digest = hashlib.sha256(normalized_text.encode()).hexdigest()
    overlap = {"catalog_sha256": digest, "enabled_layouts": len(layouts), "overlaps": [], "status": "PASS"}
    artifacts = {
        "layout_profiles.normalized.json": normalized_text,
        "layout_overlap_report.json": json.dumps(overlap, indent=2, sort_keys=True) + "\n",
        "autoisa_ci_layout_decoder.sv": generate_sv(layouts, digest),
        "autoisa_ci_encode.py": generate_python(normalized, digest),
        "autoisa_ci_encoding.h": generate_header(layouts, digest),
        "autoisa_ci_encoding.S": generate_assembly(layouts, digest),
        "layout_bit_budget.csv": generate_bit_budget(layouts),
    }
    manifest = {name: hashlib.sha256(content.encode()).hexdigest() for name, content in sorted(artifacts.items())}
    artifacts["generation_manifest.json"] = json.dumps({"catalog_sha256": digest, "artifacts": manifest}, indent=2, sort_keys=True) + "\n"
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, content in artifacts.items():
        (out_dir / name).write_text(content, encoding="utf-8", newline="\n")
    rtl_out.parent.mkdir(parents=True, exist_ok=True)
    rtl_out.write_text(artifacts["autoisa_ci_layout_decoder.sv"], encoding="utf-8", newline="\n")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--rtl-out", type=Path, default=DEFAULT_RTL)
    args = parser.parse_args()
    try:
        manifest = build(args.config.resolve(), args.out_dir.resolve(), args.rtl_out.resolve())
    except (CatalogError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"layout generation FAILED: {error}")
        return 1
    print(f"layout generation PASS: {len(manifest)} deterministic artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
