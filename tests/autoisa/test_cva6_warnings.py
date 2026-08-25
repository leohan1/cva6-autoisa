import unittest

from ci.autoisa.check_cva6_warnings import audit_warning_text


class Cva6WarningPolicyTests(unittest.TestCase):
    def test_rejects_rtl_out_of_bounds_warning(self):
        audit = audit_warning_text(
            "WARNING: [VRFC 10-3705] select index 2 into 'register_read' is out of bounds",
            "xelab",
        )
        self.assertEqual(len(audit.actionable), 1)

    def test_allows_known_hpdcache_unsupported_assertion(self):
        audit = audit_warning_text(
            'WARNING: [XSIM 43-4455] File "D:/repo/core/cache_subsystem/hpdcache/rtl/'
            "src/hpdcache_wbuf.sv\" Line 734 : Unsupported feature in assertion/property/sequence",
            "xelab",
        )
        self.assertEqual(len(audit.allowed), 1)
        self.assertFalse(audit.actionable)

    def test_allows_hpdcache_unique_case_only_at_reset_time(self):
        warning = (
            "WARNING: 0ns : none of the conditions were true for unique case from File:"
            "D:/repo/core/cache_subsystem/hpdcache/rtl/src/hpdcache_wbuf.sv:467"
        )
        self.assertEqual(len(audit_warning_text(warning, "xsim").allowed), 1)
        self.assertEqual(
            len(audit_warning_text(warning.replace("0ns", "25ns"), "xsim").actionable), 1
        )

    def test_rejects_unrelated_warning(self):
        audit = audit_warning_text("WARNING: unexpected core behavior", "xsim")
        self.assertEqual(len(audit.actionable), 1)

    def test_ignores_non_warning_lines(self):
        audit = audit_warning_text("PASS: reset smoke", "xsim")
        self.assertFalse(audit.allowed)
        self.assertFalse(audit.actionable)


if __name__ == "__main__":
    unittest.main()
