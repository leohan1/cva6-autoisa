from __future__ import annotations

import unittest

from ci.autoisa.run_g5_native import parse_result, summarize


class G5NativeTest(unittest.TestCase):
    def test_parse_result(self) -> None:
        output = (
            "G5_DATA: profile=P2 mode=1 pattern=1 roi_cycles=400 roi_instret=260 "
            "checksum0=00000c80 checksum1=00000000 ci_issue=64 ci_commit=64 ci_result=64\n"
            "G5_PIPE: issue_span=128 result_span=128 issue_commit_sum=64 "
            "issue_result_sum=192 inflight_hwm=4\n"
        )
        result = parse_result(output, 2, "throughput", "autoisa")
        self.assertEqual(result["roi_cycles"], 400)
        self.assertEqual(result["checksum0"], 3200)
        self.assertEqual(result["ci_commit"], 64)
        self.assertEqual(result["average_issue_to_result"], 3.0)
        self.assertEqual(result["inflight_high_watermark"], 4)

    def test_parse_rejects_identity_mismatch(self) -> None:
        output = (
            "G5_DATA: profile=P1 mode=0 pattern=0 roi_cycles=1 roi_instret=1 "
            "checksum0=0 checksum1=0 ci_issue=0 ci_commit=0 ci_result=0\n"
            "G5_PIPE: issue_span=0 result_span=0 issue_commit_sum=0 "
            "issue_result_sum=0 inflight_hwm=0\n"
        )
        with self.assertRaisesRegex(ValueError, "identity"):
            parse_result(output, 2, "latency", "scalar")

    def test_summarize_computes_ab_metrics(self) -> None:
        runs = []
        for profile_number, measurement in (
            (0, "latency"), (1, "latency"), (1, "throughput"),
            (2, "latency"), (2, "throughput"),
            (8, "latency"), (8, "throughput")
        ):
            profile = f"P{profile_number}"
            runs.extend([
                {"profile": profile, "measurement": measurement, "variant": "scalar",
                 "roi_cycles": 200, "roi_instret": 100, "average_issue_interval": 0,
                 "average_issue_to_commit": 0, "average_issue_to_result": 0,
                 "inflight_high_watermark": 0},
                {"profile": profile, "measurement": measurement, "variant": "autoisa",
                 "roi_cycles": 100, "roi_instret": 75, "average_issue_interval": 1,
                 "average_issue_to_commit": 1, "average_issue_to_result": 2,
                 "inflight_high_watermark": 2},
            ])
        summary = summarize(runs)
        self.assertEqual(summary[0]["speedup"], 2.0)
        self.assertEqual(summary[0]["instruction_reduction"], 0.25)


if __name__ == "__main__":
    unittest.main(verbosity=2)
