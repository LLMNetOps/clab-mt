import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from tools.generate_prefixes import (
    ADJACENT_ORIGIN_COMMUNITY,
    ISP_SOURCE_COMMUNITY,
    REN_SOURCE_COMMUNITY,
    RouteCategory,
    TRANSIT_LEARNED_COMMUNITY,
    build_parser,
    generate,
    write_outputs,
)


class PrefixGeneratorTests(unittest.TestCase):
    def test_manifest_exposes_complete_private_as_path_profiles(self):
        manifest = generate(
            seed=23,
            isp_count=24,
            isp_transit_learned_count=12,
            ren_count=12,
            ren_adjacent_origin_count=6,
            ren_transit_learned_count=6,
            shared_count=4,
        )
        expected_transit_neighbors = {
            "isp": set(range(65010, 65016)),
            "ren": set(range(65020, 65023)),
        }
        reserved_asns = {
            65000,
            65001,
            65002,
            *range(65010, 65016),
            *range(65020, 65023),
        }
        self.assertEqual(
            manifest.asns.to_manifest(),
            {
                "campus": 65000,
                "isp": 65001,
                "ren": 65002,
                "isp_transit_neighbors": list(range(65010, 65016)),
                "ren_transit_neighbors": list(range(65020, 65023)),
                "generated_asn_range": [64512, 65534],
            },
        )

        for speaker, routes in (
            ("isp", manifest.isp_routes),
            ("ren", manifest.ren_routes),
        ):
            speaker_as = 65001 if speaker == "isp" else 65002
            observed_neighbors = set()
            for route in routes:
                route_data = route.to_manifest()
                path = route.expected_as_path
                self.assertEqual(route_data["path_depth"], len(path))
                self.assertEqual(route_data["origin_as"], path[-1])
                self.assertEqual(path[0], speaker_as)
                self.assertEqual(len(path), len(set(path)))
                self.assertNotIn(65000, path)
                self.assertTrue(all(64512 <= asn <= 65534 for asn in path))

                if route_data["path_class"] == "adjacent-origin":
                    generated_asns = path[1:]
                    self.assertEqual(route_data["transit_neighbor"], None)
                    self.assertEqual(len(path), 2)
                else:
                    generated_asns = path[2:]
                    self.assertEqual(route_data["path_class"], "transit-learned")
                    self.assertIn(path[1], expected_transit_neighbors[speaker])
                    self.assertEqual(route_data["transit_neighbor"], path[1])
                    self.assertLessEqual(3, len(path))
                    self.assertLessEqual(len(path), 6)
                    observed_neighbors.add(path[1])
                self.assertTrue(set(generated_asns).isdisjoint(reserved_asns))
            self.assertEqual(observed_neighbors, expected_transit_neighbors[speaker])

    def test_manifest_uses_canonical_path_class_vocabulary(self):
        manifest = generate(
            seed=23,
            isp_count=4,
            isp_transit_learned_count=2,
            ren_count=4,
            ren_adjacent_origin_count=2,
            ren_transit_learned_count=2,
            shared_count=2,
        ).to_dict()

        self.assertEqual(
            set(manifest["counts"]),
            {
                "isp",
                "ren",
                "isp_adjacent_origin",
                "isp_transit_learned",
                "ren_adjacent_origin",
                "ren_transit_learned",
                "shared",
                "shared_isp_adjacent_origin",
                "shared_isp_transit_learned",
                "shared_ren_adjacent_origin",
                "shared_ren_transit_learned",
            },
        )
        self.assertEqual(
            {
                route["source_category"]
                for routes in manifest["routes"].values()
                for route in routes
            },
            {
                "isp-adjacent-origin",
                "isp-transit-learned",
                "ren-adjacent-origin",
                "ren-transit-learned",
            },
        )

    def test_seed_controls_paths_without_changing_route_budgets(self):
        arguments = {
            "isp_count": 24,
            "isp_transit_learned_count": 12,
            "ren_count": 12,
            "ren_adjacent_origin_count": 6,
            "ren_transit_learned_count": 6,
            "shared_count": 4,
        }
        manifest_a = generate(seed=23, **arguments)
        manifest_b = generate(seed=29, **arguments)

        self.assertEqual(manifest_a.counts, manifest_b.counts)
        self.assertEqual(
            {
                route.prefix
                for route in manifest_a.isp_routes
                if route.shared
            },
            {
                route.prefix
                for route in manifest_a.ren_routes
                if route.shared
            },
        )
        self.assertNotEqual(
            [route.expected_as_path for route in manifest_a.isp_routes],
            [route.expected_as_path for route in manifest_b.isp_routes],
        )

        default_manifest = generate(seed=23)
        for routes in (
            default_manifest.isp_routes,
            default_manifest.ren_routes,
        ):
            depths_by_neighbor: dict[int, set[int]] = {}
            for route in routes:
                if route.transit_neighbor is not None:
                    depths_by_neighbor.setdefault(route.transit_neighbor, set()).add(
                        len(route.expected_as_path)
                    )
            self.assertTrue(
                all(len(depths) > 1 for depths in depths_by_neighbor.values())
            )

    def test_pool_and_prefix_lengths_are_fixed_to_the_lab_contract(self):
        manifest = generate(
            seed=23,
            isp_count=4,
            isp_transit_learned_count=1,
            ren_count=2,
            ren_adjacent_origin_count=1,
            ren_transit_learned_count=1,
            shared_count=1,
        )
        self.assertEqual(str(manifest.pool), "10.64.0.0/10")
        self.assertEqual(manifest.to_dict()["prefix_length_range"], [16, 24])

        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                build_parser().parse_args(["--pool", "192.0.2.0/24"])
            with self.assertRaises(SystemExit):
                build_parser().parse_args(["--min-prefix-length", "20"])
            with self.assertRaises(SystemExit):
                build_parser().parse_args(["--isp-transit-count", "1"])
            with self.assertRaises(SystemExit):
                build_parser().parse_args(["--ren-direct-count", "1"])

    def test_rejects_route_counts_above_lab_maximums(self):
        with self.assertRaisesRegex(ValueError, "isp_count must not exceed 500"):
            generate(
                isp_count=501,
                isp_transit_learned_count=0,
                ren_count=0,
                ren_adjacent_origin_count=0,
                ren_transit_learned_count=0,
                shared_count=0,
            )

        with self.assertRaisesRegex(ValueError, "ren_count must not exceed 200"):
            generate(
                isp_count=0,
                isp_transit_learned_count=0,
                ren_count=201,
                ren_adjacent_origin_count=100,
                ren_transit_learned_count=101,
                shared_count=0,
            )

        with self.assertRaisesRegex(
            ValueError,
            "isp_transit_learned_count must not exceed isp_count",
        ):
            generate(
                isp_count=1,
                isp_transit_learned_count=2,
                ren_count=0,
                ren_adjacent_origin_count=0,
                ren_transit_learned_count=0,
                shared_count=0,
            )

    def test_route_plan_uses_deterministic_categories(self):
        manifest = generate(
            seed=23,
            isp_count=8,
            isp_transit_learned_count=2,
            ren_count=4,
            ren_adjacent_origin_count=2,
            ren_transit_learned_count=2,
            shared_count=2,
        )

        self.assertEqual(
            {route.source_category for route in manifest.isp_routes},
            {RouteCategory.ISP_ADJACENT_ORIGIN, RouteCategory.ISP_TRANSIT_LEARNED},
        )
        self.assertEqual(
            {route.source_category for route in manifest.ren_routes},
            {RouteCategory.REN_ADJACENT_ORIGIN, RouteCategory.REN_TRANSIT_LEARNED},
        )

        for route in [*manifest.isp_routes, *manifest.ren_routes]:
            self.assertNotIn("source_as", route.to_manifest())

    def test_routes_emit_source_and_category_standard_communities(self):
        manifest = generate(
            seed=23,
            isp_count=4,
            isp_transit_learned_count=2,
            ren_count=4,
            ren_adjacent_origin_count=2,
            ren_transit_learned_count=2,
            shared_count=2,
        )

        for route in [*manifest.isp_routes, *manifest.ren_routes]:
            if route.source_category in {
                RouteCategory.ISP_ADJACENT_ORIGIN,
                RouteCategory.ISP_TRANSIT_LEARNED,
            }:
                source_community = ISP_SOURCE_COMMUNITY
            else:
                source_community = REN_SOURCE_COMMUNITY
            category_community = (
                ADJACENT_ORIGIN_COMMUNITY
                if route.source_category
                in {
                    RouteCategory.ISP_ADJACENT_ORIGIN,
                    RouteCategory.REN_ADJACENT_ORIGIN,
                }
                else TRANSIT_LEARNED_COMMUNITY
            )
            self.assertEqual(
                route.communities,
                (source_community, category_community),
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            output_dir = Path(temp_dir)
            write_outputs(manifest, output_dir)
            isp_config = (output_dir / "isp.conf").read_text(encoding="utf-8")
            ren_config = (output_dir / "ren.conf").read_text(encoding="utf-8")
            self.assertIn(
                f"community [ {ISP_SOURCE_COMMUNITY} {ADJACENT_ORIGIN_COMMUNITY} ];",
                isp_config,
            )
            self.assertIn(
                f"community [ {ISP_SOURCE_COMMUNITY} {TRANSIT_LEARNED_COMMUNITY} ];",
                isp_config,
            )
            self.assertIn(
                f"community [ {REN_SOURCE_COMMUNITY} {ADJACENT_ORIGIN_COMMUNITY} ];",
                ren_config,
            )
            self.assertIn(
                f"community [ {REN_SOURCE_COMMUNITY} {TRANSIT_LEARNED_COMMUNITY} ];",
                ren_config,
            )
            for route, config in (
                *((route, isp_config) for route in manifest.isp_routes),
                *((route, ren_config) for route in manifest.ren_routes),
            ):
                rendered_tail = " ".join(str(asn) for asn in route.as_path_tail)
                rendered_communities = " ".join(route.communities)
                expected_stanza = "\n".join(
                    (
                        f"        route {route.prefix} {{",
                        "            next-hop self;",
                        f"            as-path [ {rendered_tail} ];",
                        f"            community [ {rendered_communities} ];",
                        "        }",
                    )
                )
                self.assertIn(expected_stanza, config)
            self.assertNotIn("as-path [ 141682", isp_config + ren_config)

    def test_shared_routes_respect_path_class_budgets(self):
        manifest = generate(
            seed=17,
            isp_count=10,
            isp_transit_learned_count=9,
            ren_count=10,
            ren_adjacent_origin_count=1,
            ren_transit_learned_count=9,
            shared_count=6,
        )

        self.assertEqual(manifest.counts.isp_adjacent_origin, 1)
        self.assertEqual(manifest.counts.isp_transit_learned, 9)
        self.assertEqual(manifest.counts.ren_adjacent_origin, 1)
        self.assertEqual(manifest.counts.ren_transit_learned, 9)
        self.assertEqual(manifest.counts.shared_isp_adjacent_origin, 1)
        self.assertEqual(manifest.counts.shared_isp_transit_learned, 5)
        self.assertEqual(manifest.counts.shared_ren_adjacent_origin, 1)
        self.assertEqual(manifest.counts.shared_ren_transit_learned, 5)

    def test_shared_routes_use_the_same_path_class_at_both_speakers(self):
        manifest = generate(
            seed=17,
            isp_count=10,
            isp_transit_learned_count=8,
            ren_count=10,
            ren_adjacent_origin_count=5,
            ren_transit_learned_count=5,
            shared_count=6,
        )

        for category in (
            RouteCategory.ISP_ADJACENT_ORIGIN,
            RouteCategory.ISP_TRANSIT_LEARNED,
        ):
            isp_prefixes = {
                route.prefix
                for route in manifest.isp_routes
                if route.shared
                and route.source_category is category
            }
            ren_category = (
                RouteCategory.REN_ADJACENT_ORIGIN
                if category is RouteCategory.ISP_ADJACENT_ORIGIN
                else RouteCategory.REN_TRANSIT_LEARNED
            )
            ren_prefixes = {
                route.prefix
                for route in manifest.ren_routes
                if route.shared
                and route.source_category is ren_category
            }
            self.assertEqual(isp_prefixes, ren_prefixes)

    def test_empty_ren_path_class_has_no_legacy_source_as_field(self):
        manifest = generate(
            seed=19,
            isp_count=4,
            isp_transit_learned_count=2,
            ren_count=4,
            ren_adjacent_origin_count=0,
            ren_transit_learned_count=4,
            shared_count=2,
        )

        self.assertEqual(manifest.counts.ren_adjacent_origin, 0)
        self.assertTrue(
            all(
                "source_as" not in route.to_manifest()
                for route in manifest.ren_routes
            )
        )

    def test_counts_and_intentional_overlap(self):
        manifest = generate(
            seed=7,
            isp_count=20,
            isp_transit_learned_count=5,
            ren_count=10,
            ren_adjacent_origin_count=5,
            ren_transit_learned_count=5,
            shared_count=4,
        )
        self.assertEqual(manifest.counts.isp, 20)
        self.assertEqual(manifest.counts.ren, 10)
        self.assertEqual(manifest.counts.shared, 4)
        self.assertEqual(
            manifest.counts.isp_adjacent_origin + manifest.counts.isp_transit_learned,
            20,
        )
        self.assertEqual(
            manifest.counts.ren_adjacent_origin + manifest.counts.ren_transit_learned,
            10,
        )
        self.assertEqual(
            sum(route.shared for route in manifest.isp_routes),
            4,
        )
        self.assertEqual(
            sum(route.shared for route in manifest.ren_routes),
            4,
        )
        self.assertEqual(
            {route.prefix.prefixlen for route in manifest.isp_routes},
            set(range(16, 25)),
        )

        isp = {route.prefix for route in manifest.isp_routes}
        ren = {route.prefix for route in manifest.ren_routes}
        self.assertEqual(len(isp & ren), 4)

        all_routes = [
            route.prefix for route in [*manifest.isp_routes, *manifest.ren_routes]
        ]
        unique_routes = {}
        for route in all_routes:
            unique_routes.setdefault(str(route), route)
        unique_values = list(unique_routes.values())
        for index, route in enumerate(unique_values):
            self.assertTrue(
                all(
                    not route.overlaps(other)
                    for other in unique_values[index + 1:]
                )
            )

    def test_output_files_are_reproducible(self):
        manifest_a = generate(
            seed=11,
            isp_count=8,
            isp_transit_learned_count=2,
            ren_count=4,
            ren_adjacent_origin_count=2,
            ren_transit_learned_count=2,
            shared_count=2,
        )
        manifest_b = generate(
            seed=11,
            isp_count=8,
            isp_transit_learned_count=2,
            ren_count=4,
            ren_adjacent_origin_count=2,
            ren_transit_learned_count=2,
            shared_count=2,
        )
        self.assertEqual(manifest_a, manifest_b)
        with tempfile.TemporaryDirectory() as temp_dir:
            output_dir = Path(temp_dir)
            write_outputs(manifest_a, output_dir)
            saved = json.loads(
                (output_dir / "manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(saved, manifest_a.to_dict())
            self.assertEqual(
                (output_dir / "isp.conf")
                .read_text(encoding="utf-8")
                .count("route "),
                8,
            )
            self.assertEqual(
                (output_dir / "ren.conf")
                .read_text(encoding="utf-8")
                .count("route "),
                4,
            )
            self.assertIn(
                "adj-rib-out true;",
                (output_dir / "isp.conf").read_text(encoding="utf-8"),
            )


if __name__ == "__main__":
    unittest.main()
