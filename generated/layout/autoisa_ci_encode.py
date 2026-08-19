#!/usr/bin/env python3
"""Generated AutoISA Layout v2 encoder/decoder. Catalog sha256: 7ad9fd792edf60d848fac03c27ae95bd9023b683b0c769f28e5d3dfb8f4afd70"""
import json
LAYOUTS = json.loads(r'''[{"backend":"AUTOISA_CVXIF_NATIVE","compute_only":true,"destinations":[{"name":"rd0","namespace":"GPR32","reject_zero":true,"slices":[{"instr_lsb":7,"instr_msb":11,"value_lsb":0}]}],"enabled":true,"id":0,"logical_destinations":1,"logical_sources":2,"mask":"0x0000707f","match":"0x0000005b","name":"L_2R1W_GPR32","semantic":{"kind":"encoded","slices":[{"instr_lsb":25,"instr_msb":31,"value_lsb":0}],"width":7},"sources":[{"name":"rs1","namespace":"GPR32","slices":[{"instr_lsb":15,"instr_msb":19,"value_lsb":0}]},{"name":"rs2","namespace":"GPR32","slices":[{"instr_lsb":20,"instr_msb":24,"value_lsb":0}]}]},{"backend":"AUTOISA_CVXIF_NATIVE","compute_only":true,"destinations":[{"name":"rd0","namespace":"GPR32","reject_zero":true,"slices":[{"instr_lsb":7,"instr_msb":11,"value_lsb":0}]}],"enabled":true,"id":1,"logical_destinations":1,"logical_sources":3,"mask":"0x0000707f","match":"0x0000105b","name":"L_3R1W_GPR32","semantic":{"kind":"encoded","slices":[{"instr_lsb":30,"instr_msb":31,"value_lsb":0}],"width":2},"sources":[{"name":"rs1","namespace":"GPR32","slices":[{"instr_lsb":15,"instr_msb":19,"value_lsb":0}]},{"name":"rs2","namespace":"GPR32","slices":[{"instr_lsb":20,"instr_msb":24,"value_lsb":0}]},{"name":"rs3","namespace":"GPR32","slices":[{"instr_lsb":25,"instr_msb":29,"value_lsb":0}]}]},{"backend":"AUTOISA_DIRECT_CI_EXTENDED","compute_only":true,"destinations":[{"name":"rd0","namespace":"RVC8","slices":[{"instr_lsb":9,"instr_msb":11,"value_lsb":0}]}],"enabled":true,"id":2,"logical_destinations":1,"logical_sources":4,"mask":"0x0000707f","match":"0x0000205b","name":"L_4R1W_GPR8","semantic":{"kind":"encoded","slices":[{"instr_lsb":27,"instr_msb":31,"value_lsb":0}],"width":5},"sources":[{"name":"rs1","namespace":"RVC8","slices":[{"instr_lsb":15,"instr_msb":17,"value_lsb":0}]},{"name":"rs2","namespace":"RVC8","slices":[{"instr_lsb":18,"instr_msb":20,"value_lsb":0}]},{"name":"rs3","namespace":"RVC8","slices":[{"instr_lsb":21,"instr_msb":23,"value_lsb":0}]},{"name":"rs4","namespace":"RVC8","slices":[{"instr_lsb":24,"instr_msb":26,"value_lsb":0}]}]},{"backend":"AUTOISA_DIRECT_CI_EXTENDED","compute_only":true,"destinations":[{"name":"rd0","namespace":"GPR32","reject_zero":true,"slices":[{"instr_lsb":7,"instr_msb":11,"value_lsb":0}]},{"derived_from":"rd0","name":"rd1","namespace":"DERIVED_PAIR","offset":1}],"enabled":true,"id":3,"logical_destinations":2,"logical_sources":2,"mask":"0x0000707f","match":"0x0000305b","name":"L_2R2W_PAIR","pair_constraint":{"base":"rd0","even":true,"max":30,"nonzero":true},"semantic":{"kind":"encoded","slices":[{"instr_lsb":25,"instr_msb":31,"value_lsb":0}],"width":7},"sources":[{"name":"rs1","namespace":"GPR32","slices":[{"instr_lsb":15,"instr_msb":19,"value_lsb":0}]},{"name":"rs2","namespace":"GPR32","slices":[{"instr_lsb":20,"instr_msb":24,"value_lsb":0}]}]},{"backend":"AUTOISA_DIRECT_CI_EXTENDED","compute_only":true,"destinations":[{"name":"rd0","namespace":"RVC8","slices":[{"instr_lsb":7,"instr_msb":9,"value_lsb":0}]},{"name":"rd1","namespace":"RVC8","slices":[{"instr_lsb":27,"instr_msb":29,"value_lsb":0}]}],"enabled":true,"id":4,"logical_destinations":2,"logical_sources":4,"mask":"0xc000707f","match":"0x0000405b","name":"L_4R2W_GPR8","semantic":{"kind":"fixed","value":4},"sources":[{"name":"rs1","namespace":"RVC8","slices":[{"instr_lsb":15,"instr_msb":17,"value_lsb":0}]},{"name":"rs2","namespace":"RVC8","slices":[{"instr_lsb":18,"instr_msb":20,"value_lsb":0}]},{"name":"rs3","namespace":"RVC8","slices":[{"instr_lsb":21,"instr_msb":23,"value_lsb":0}]},{"name":"rs4","namespace":"RVC8","slices":[{"instr_lsb":24,"instr_msb":26,"value_lsb":0}]}]},{"backend":"AUTOISA_DIRECT_CI_EXTENDED","compute_only":true,"destinations":[{"name":"rd0","namespace":"RVC8","slices":[{"instr_lsb":7,"instr_msb":9,"value_lsb":0}]}],"enabled":true,"id":5,"logical_destinations":1,"logical_sources":6,"mask":"0xf000007f","match":"0x0000002b","name":"L_6R1W_GPR8","semantic":{"kind":"fixed","value":5},"sources":[{"name":"rs1","namespace":"RVC8","slices":[{"instr_lsb":10,"instr_msb":12,"value_lsb":0}]},{"name":"rs2","namespace":"RVC8","slices":[{"instr_lsb":13,"instr_msb":15,"value_lsb":0}]},{"name":"rs3","namespace":"RVC8","slices":[{"instr_lsb":16,"instr_msb":18,"value_lsb":0}]},{"name":"rs4","namespace":"RVC8","slices":[{"instr_lsb":19,"instr_msb":21,"value_lsb":0}]},{"name":"rs5","namespace":"RVC8","slices":[{"instr_lsb":22,"instr_msb":24,"value_lsb":0}]},{"name":"rs6","namespace":"RVC8","slices":[{"instr_lsb":25,"instr_msb":27,"value_lsb":0}]}]},{"backend":"AUTOISA_DIRECT_CI_EXTENDED","compute_only":true,"destinations":[{"name":"rd0","namespace":"RVC8","slices":[{"instr_lsb":7,"instr_msb":9,"value_lsb":0}]},{"name":"rd1","namespace":"RVC8","slices":[{"instr_lsb":10,"instr_msb":12,"value_lsb":0}]}],"enabled":true,"id":6,"logical_destinations":2,"logical_sources":6,"mask":"0x8000007f","match":"0x0000007b","name":"L_6R2W_GPR8","semantic":{"kind":"fixed","value":6},"sources":[{"name":"rs1","namespace":"RVC8","slices":[{"instr_lsb":13,"instr_msb":15,"value_lsb":0}]},{"name":"rs2","namespace":"RVC8","slices":[{"instr_lsb":16,"instr_msb":18,"value_lsb":0}]},{"name":"rs3","namespace":"RVC8","slices":[{"instr_lsb":19,"instr_msb":21,"value_lsb":0}]},{"name":"rs4","namespace":"RVC8","slices":[{"instr_lsb":22,"instr_msb":24,"value_lsb":0}]},{"name":"rs5","namespace":"RVC8","slices":[{"instr_lsb":25,"instr_msb":27,"value_lsb":0}]},{"name":"rs6","namespace":"RVC8","slices":[{"instr_lsb":28,"instr_msb":30,"value_lsb":0}]}]},{"backend":"AUTOISA_CVXIF_NATIVE","compute_only":true,"destinations":[{"name":"rd0","namespace":"GPR32","reject_zero":true,"slices":[{"instr_lsb":7,"instr_msb":11,"value_lsb":0}]}],"enabled":true,"id":7,"immediate":{"scale":0,"signed":true,"slices":[{"instr_lsb":25,"instr_msb":31,"value_lsb":3},{"instr_lsb":12,"instr_msb":14,"value_lsb":0}],"width":10},"logical_destinations":1,"logical_sources":2,"mask":"0x0000007f","match":"0x0000000b","name":"L_2R1W_IMM","semantic":{"kind":"fixed","value":7},"sources":[{"name":"rs1","namespace":"GPR32","slices":[{"instr_lsb":15,"instr_msb":19,"value_lsb":0}]},{"name":"rs2","namespace":"GPR32","slices":[{"instr_lsb":20,"instr_msb":24,"value_lsb":0}]}]}]''')
BY_NAME = {item["name"]: item for item in LAYOUTS if item["enabled"]}

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
    limits = {"GPR32": (0, 31), "GPR16": (0, 15), "RVC8": (8, 15)}
    low, high = limits[namespace]
    if not low <= reg <= high:
        raise ValueError(f"register {reg} is outside {namespace}")
    return reg - 8 if namespace == "RVC8" else reg

def encode_layout(name, sources, destinations, semantic_id=None, immediate=None):
    layout = BY_NAME[name]
    if len(sources) != layout["logical_sources"] or len(destinations) != layout["logical_destinations"]:
        raise ValueError("logical operand/result count mismatch")
    instr = int(layout["match"], 0)
    for field, reg in zip(layout["sources"], sources):
        instr = _insert(instr, _reg_encode(reg, field["namespace"]), field["slices"])
    decoded_dest = {}
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
    destinations, named = [], {}
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
    return {"name": layout["name"], "layout_id": layout["id"], "sources": sources, "destinations": destinations, "semantic_id": semantic_id, "immediate": immediate}
