import contextlib
import io
import json
import tempfile
import unittest
from ipaddress import ip_network
from pathlib import Path

from tools.generate_prefixes import RouteCategory, build_parser, generate, write_outputs


class PrefixGeneratorTests(unittest.TestCase):
    def test_pool_and_prefix_lengths_are_fixed_to_the_lab_contract(self):
        manifest = generate(
            seed=23,
            isp_count=4,
            idren_count=2,
            direct_count=1,
            transit_count=1,
            shared_count=1,
        )
        self.assertEqual(str(manifest.pool), "10.64.0.0/10")
        self.assertEqual(manifest.to_dict()["prefix_length_range"], [16, 24])

        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                build_parser().parse_args(["--pool", "192.0.2.0/24"])
            with self.assertRaises(SystemExit):
                build_parser().parse_args(["--min-prefix-length", "20"])

    def test_rejects_route_counts_above_lab_maximums(self):
        with self.assertRaisesRegex(ValueError, "isp_count must not exceed 500"):
            generate(
                isp_count=501,
                idren_count=0,
                direct_count=0,
                transit_count=0,
                shared_count=0,
            )

        with self.assertRaisesRegex(ValueError, "idren_count must not exceed 200"):
            generate(
                isp_count=0,
                idren_count=201,
                direct_count=100,
                transit_count=101,
                shared_count=0,
            )

    def test_shared_routes_respect_direct_and_transit_budgets(self):
        manifest = generate(
            seed=17,
            isp_count=10,
            idren_count=10,
            direct_count=1,
            transit_count=9,
            shared_count=6,
        )

        self.assertEqual(manifest.counts.idren_direct, 1)
        self.assertEqual(manifest.counts.idren_transit_141682, 9)
        self.assertEqual(manifest.counts.shared_direct, 1)
        self.assertEqual(manifest.counts.shared_transit_141682, 5)

    def test_empty_idren_category_has_no_synthetic_source_asns(self):
        manifest = generate(
            seed=19,
            isp_count=4,
            idren_count=4,
            direct_count=0,
            transit_count=4,
            shared_count=2,
        )

        self.assertEqual(manifest.counts.idren_direct, 0)
        self.assertEqual(manifest.asns.direct_sources, ())

    def test_counts_and_intentional_overlap(self):
        manifest = generate(
            seed=7,
            isp_count=20,
            idren_count=10,
            direct_count=5,
            transit_count=5,
            shared_count=4,
        )
        self.assertEqual(manifest.counts.isp, 20)
        self.assertEqual(manifest.counts.idren, 10)
        self.assertEqual(manifest.counts.shared, 4)
        self.assertEqual(manifest.counts.shared_direct, 2)
        self.assertEqual(manifest.counts.shared_transit_141682, 2)
        self.assertEqual(
            {route.prefix.prefixlen for route in manifest.isp_routes},
            set(range(16, 25)),
        )

        isp = {route.prefix for route in manifest.isp_routes}
        idren = {route.prefix for route in manifest.idren_routes}
        self.assertEqual(len(isp & idren), 4)
        self.assertEqual(
            sum(
                route.source_category is RouteCategory.IDREN_DIRECT
                for route in manifest.idren_routes
            ),
            5,
        )
        self.assertEqual(
            sum(
                route.source_category is RouteCategory.IDREN_TRANSIT
                for route in manifest.idren_routes
            ),
            5,
        )

        all_routes = [
            route.prefix for route in [*manifest.isp_routes, *manifest.idren_routes]
        ]
        unique_routes = {}
        for route in all_routes:
            unique_routes.setdefault(str(route), route)
        unique_values = list(unique_routes.values())
        for index, route in enumerate(unique_values):
            self.assertTrue(
                all(not route.overlaps(other) for other in unique_values[index + 1:])
            )

    def test_output_files_are_reproducible(self):
        manifest_a = generate(seed=11, isp_count=8, idren_count=4, direct_count=2, transit_count=2, shared_count=2)
        manifest_b = generate(seed=11, isp_count=8, idren_count=4, direct_count=2, transit_count=2, shared_count=2)
        self.assertEqual(manifest_a, manifest_b)
        with tempfile.TemporaryDirectory() as temp_dir:
            output_dir = Path(temp_dir)
            write_outputs(manifest_a, output_dir)
            saved = json.loads((output_dir / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(saved, manifest_a.to_dict())
            self.assertEqual(
                (output_dir / "isp.conf").read_text(encoding="utf-8").count("route "),
                8,
            )
            self.assertEqual(
                (output_dir / "idren.conf").read_text(encoding="utf-8").count("route "),
                4,
            )
            self.assertIn(
                "adj-rib-out true;",
                (output_dir / "isp.conf").read_text(encoding="utf-8"),
            )


if __name__ == "__main__":
    unittest.main()
