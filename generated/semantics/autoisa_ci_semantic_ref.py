#!/usr/bin/env python3
"""Generated AutoISA semantic reference model. Do not edit."""
import json

CATALOG_SHA256 = "fbadcad47d75a3b5b54a7c3a62066888cdfa342b5f1498ebfee4e5435e98f3f0"
CATALOG = json.loads('{"schema_version":"2.0","semantics":[{"ci_id":0,"compute_only":true,"immediate":false,"initiation_interval":1,"latency":1,"name":"D0_ADD2","nodes":[{"args":["operand0","operand1"],"id":"sum","op":"add"}],"operands":2,"outputs":["sum"],"results":1},{"ci_id":1,"compute_only":true,"immediate":false,"initiation_interval":1,"latency":2,"name":"D1_MAC3","nodes":[{"args":["operand0","operand1"],"id":"product","op":"mul_lo"},{"args":["product","operand2"],"id":"result","op":"add"}],"operands":3,"outputs":["result"],"results":1},{"ci_id":2,"compute_only":true,"immediate":false,"initiation_interval":1,"latency":3,"name":"D2_MAC_XOR4","nodes":[{"args":["operand0","operand1"],"id":"product","op":"mul_lo"},{"args":["product","operand2"],"id":"sum","op":"add"},{"args":["sum","operand3"],"id":"result","op":"xor"}],"operands":4,"outputs":["result"],"results":1},{"ci_id":3,"compute_only":true,"immediate":false,"initiation_interval":1,"latency":2,"name":"D3_ADD_SUB2","nodes":[{"args":["operand0","operand1"],"id":"sum","op":"add"},{"args":["operand0","operand1"],"id":"difference","op":"sub"}],"operands":2,"outputs":["sum","difference"],"results":2},{"ci_id":4,"compute_only":true,"immediate":false,"initiation_interval":1,"latency":4,"name":"D4_COMPLEX_MUL4","nodes":[{"args":["operand0","operand2"],"id":"ac","op":"mul_lo"},{"args":["operand1","operand3"],"id":"bd","op":"mul_lo"},{"args":["operand0","operand3"],"id":"ad","op":"mul_lo"},{"args":["operand1","operand2"],"id":"bc","op":"mul_lo"},{"args":["ac","bd"],"id":"real","op":"sub"},{"args":["ad","bc"],"id":"imag","op":"add"}],"operands":4,"outputs":["real","imag"],"results":2},{"ci_id":5,"compute_only":true,"immediate":false,"initiation_interval":1,"latency":3,"name":"D5_ADD6","nodes":[{"args":["operand0","operand1"],"id":"s01","op":"add"},{"args":["operand2","operand3"],"id":"s23","op":"add"},{"args":["operand4","operand5"],"id":"s45","op":"add"},{"args":["s01","s23"],"id":"s0123","op":"add"},{"args":["s0123","s45"],"id":"result","op":"add"}],"operands":6,"outputs":["result"],"results":1},{"ci_id":6,"compute_only":true,"immediate":false,"initiation_interval":1,"latency":5,"name":"D6_DUAL_MAC6","nodes":[{"args":["operand0","operand1"],"id":"ab","op":"mul_lo"},{"args":["operand2","operand3"],"id":"cd","op":"mul_lo"},{"args":["operand4","operand5"],"id":"ef","op":"mul_lo"},{"args":["ab","cd"],"id":"sum_ab_cd","op":"add"},{"args":["ab","cd"],"id":"diff_ab_cd","op":"sub"},{"args":["sum_ab_cd","ef"],"id":"sum","op":"add"},{"args":["diff_ab_cd","ef"],"id":"difference","op":"add"}],"operands":6,"outputs":["sum","difference"],"results":2},{"ci_id":7,"compute_only":true,"immediate":true,"initiation_interval":1,"latency":1,"name":"D7_SHIFT_XOR_IMM","nodes":[{"args":["operand0","immediate"],"id":"shifted","op":"shl"},{"args":["operand1","immediate"],"id":"biased","op":"add"},{"args":["shifted","biased"],"id":"result","op":"xor"}],"operands":2,"outputs":["result"],"results":1}],"xlen":32}')
SEMANTICS = {item["ci_id"]: item for item in CATALOG["semantics"]}
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
    else: raise ValueError(f"unsupported operation: {op}")
    return value & MASK


def evaluate(ci_id, operands, immediate=0):
    semantic = SEMANTICS.get(int(ci_id))
    if semantic is None:
        return {"supported": False, "latency": 1, "result_valid": 0, "results": [0, 0]}
    if len(operands) < semantic["operands"]:
        raise ValueError(f"ci_id {ci_id} requires {semantic['operands']} operands")
    values = {f"operand{i}": int(operands[i]) & MASK for i in range(semantic["operands"])}
    if semantic["immediate"]:
        values["immediate"] = int(immediate) & MASK
    for node in semantic["nodes"]:
        values[node["id"]] = _apply(node["op"], values[node["args"][0]], values[node["args"][1]])
    results = [values[name] for name in semantic["outputs"]]
    results.extend([0] * (2 - len(results)))
    return {"supported": True, "latency": semantic["latency"],
            "result_valid": (1 << semantic["results"]) - 1, "results": results}
