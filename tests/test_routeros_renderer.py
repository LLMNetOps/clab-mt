import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

from tools.render_routeros import render_configs


class RouterOsRendererTests(unittest.TestCase):
    def test_routeros_nodes_force_qemu_tcg_fallback_when_kvm_is_unavailable(self):
        clab_path = Path(__file__).parents[1] / "clab.yml"
        with clab_path.open("r", encoding="utf-8") as fh:
            clab = yaml.safe_load(fh)

        for node_name in ("R1", "R2", "R3"):
            node = clab["topology"]["nodes"][node_name]
            self.assertIn("QEMU_ADDITIONAL_ARGS", node["env"])
            self.assertIn("-accel", node["env"]["QEMU_ADDITIONAL_ARGS"])
            self.assertIn("tcg", node["env"]["QEMU_ADDITIONAL_ARGS"])

    def test_build_script_uses_pre_downloaded_chr_archive(self):
        script_path = Path(__file__).parents[1] / "tools" / "build-routeros-image.sh"
        archive_path = Path(__file__).parents[1] / "chr-7.21.5.vmdk.zip"
        archive_path.write_bytes(b"fake-archive")
        self.addCleanup(archive_path.unlink, missing_ok=True)

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_dir_path = Path(temp_dir)
            fake_bin = temp_dir_path / "bin"
            fake_bin.mkdir()

            (fake_bin / "git").write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"$1\" == \"clone\" ]]; then\n"
                "  mkdir -p \"$4/mikrotik/routeros\"\n"
                "  exit 0\n"
                "fi\n"
                "if [[ \"$1\" == \"-C\" ]]; then\n"
                "  exit 0\n"
                "fi\n"
                "exit 0\n",
                encoding="utf-8",
            )
            (fake_bin / "patch").write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            (fake_bin / "make").write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            (fake_bin / "unzip").write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            (fake_bin / "sha256sum").write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s  %s\\n' 'acc6b562ad870116c28ce0246e99deac984d815bd9893197ee9b5897422543eb' \"$*\"\n",
                encoding="utf-8",
            )
            (fake_bin / "docker").write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"$1\" == \"info\" ]]; then exit 0; fi\n"
                "if [[ \"$1\" == \"image\" && \"$2\" == \"inspect\" ]]; then exit 0; fi\n"
                "if [[ \"$1\" == \"tag\" ]]; then exit 0; fi\n"
                "exit 0\n",
                encoding="utf-8",
            )
            for path in fake_bin.iterdir():
                path.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}:{env['PATH']}"
            result = subprocess.run(
                ["bash", str(script_path), "--force", "--archive", str(archive_path)],
                cwd=str(Path(__file__).parents[1]),
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("Using pre-downloaded RouterOS", result.stdout)

    def _render_repository_edge_config(self) -> str:
        repository_config_dir = Path(__file__).parents[1] / "configs" / "routeros"

        with tempfile.TemporaryDirectory() as temp_dir:
            config_dir = Path(temp_dir)
            for template_name in ("r1.rsc.tmpl", "core.rsc.tmpl"):
                shutil.copy2(
                    repository_config_dir / template_name,
                    config_dir / template_name,
                )
            render_configs(config_dir)
            return (config_dir / "r1.rsc").read_text(encoding="utf-8")

    def test_checked_in_startup_configs_do_not_change_login_credentials(self):
        config_dir = Path(__file__).parents[1] / "configs" / "routeros"

        for config_path in config_dir.glob("*.rsc*"):
            with self.subTest(config=config_path.name):
                config = config_path.read_text(encoding="utf-8")
                self.assertNotIn("/user set", config)
                self.assertNotIn("password=", config)

    def test_renders_edge_policy_and_both_campus_core_routers(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            config_dir = Path(temp_dir)
            (config_dir / "r1.rsc.tmpl").write_text(
                "ADJACENT_ORIGIN={{ADJACENT_ORIGIN_LOCAL_PREF}} "
                "ISP_TRANSIT_LEARNED={{ISP_TRANSIT_LEARNED_LOCAL_PREF}} "
                "REN_TRANSIT_LEARNED={{REN_TRANSIT_LEARNED_LOCAL_PREF}}\n",
                encoding="utf-8",
            )
            (config_dir / "core.rsc.tmpl").write_text(
                "router={{ROUTER_NAME}} endpoint={{ENDPOINT_NAME}} "
                "slug={{ENDPOINT_SLUG}}\n"
                "router-id={{ROUTER_ID}}\n"
                "ether2={{ETHER2_ADDRESS}} {{ETHER2_LINK}}\n"
                "ether3={{ETHER3_ADDRESS}} {{ETHER3_LINK}}\n"
                "lan={{LAN_GATEWAY}}/24 {{LAN_PREFIX}} {{DHCP_RANGE}}\n",
                encoding="utf-8",
            )

            render_configs(config_dir)

            self.assertEqual(
                (config_dir / "r1.rsc").read_text(encoding="utf-8"),
                "ADJACENT_ORIGIN=200 ISP_TRANSIT_LEARNED=160 REN_TRANSIT_LEARNED=180\n",
            )
            self.assertEqual(
                (config_dir / "r2.rsc").read_text(encoding="utf-8"),
                "router=R2 endpoint=H1 slug=h1\n"
                "router-id=10.255.0.2\n"
                "ether2=10.255.1.2/30 R2-R1\n"
                "ether3=10.255.1.5/30 R2-R3\n"
                "lan=10.255.10.1/24 10.255.10.0/24 "
                "10.255.10.100-10.255.10.199\n",
            )
            self.assertEqual(
                (config_dir / "r3.rsc").read_text(encoding="utf-8"),
                "router=R3 endpoint=H2 slug=h2\n"
                "router-id=10.255.0.3\n"
                "ether2=10.255.1.10/30 R3-R1\n"
                "ether3=10.255.1.6/30 R3-R2\n"
                "lan=10.255.20.1/24 10.255.20.0/24 "
                "10.255.20.100-10.255.20.199\n",
            )

    def test_edge_exports_only_a_default_route_into_campus_ospf(self):
        edge_config = self._render_repository_edge_config()

        self.assertIn("originate-default=never", edge_config)
        self.assertIn("out-filter-chain=ospf-default", edge_config)
        self.assertNotIn("redistribute=bgp", edge_config)
        self.assertIn(
            'chain=ospf-default rule="if (dst == 0.0.0.0/0) { '
            "set ospf-ext-type type1; set ospf-ext-metric 20; accept } "
            'else { reject }"',
            edge_config,
        )

    def test_edge_default_origination_follows_the_isp_bgp_session(self):
        edge_config = self._render_repository_edge_config()

        self.assertIn(
            "add name=sync-isp-ospf-default dont-require-permissions=no "
            "policy=read,write source={",
            edge_config,
        )
        self.assertIn(
            "remote.address=10.255.2.2 and established",
            edge_config,
        )
        self.assertNotIn(
            "remote.address=10.255.2.6 and established",
            edge_config,
        )
        self.assertIn(':set desired "always"', edge_config)
        self.assertIn("originate-default=$desired", edge_config)
        self.assertIn(
            "add name=sync-isp-default-startup start-time=startup interval=0s "
            "on-event=sync-isp-ospf-default policy=read,write",
            edge_config,
        )
        self.assertIn(
            "add name=sync-isp-default-periodic interval=2s "
            "on-event=sync-isp-ospf-default policy=read,write",
            edge_config,
        )

    def test_edge_uses_exact_standard_community_sets_for_inbound_policy(self):
        edge_config = self._render_repository_edge_config()

        self.assertIn(
            "add list=community-isp-adjacent-origin communities=65000:10,65000:0",
            edge_config,
        )
        self.assertIn(
            "add list=community-ren-adjacent-origin communities=65000:20,65000:0",
            edge_config,
        )
        self.assertIn(
            "bgp-communities-empty) { accept }",
            edge_config,
        )
        self.assertIn(
            "bgp-communities equal-list community-isp-adjacent-origin) "
            "{ set bgp-local-pref 200; accept }",
            edge_config,
        )
        self.assertIn(
            "bgp-communities equal-list community-ren-adjacent-origin) "
            "{ set bgp-local-pref 200; accept }",
            edge_config,
        )
        self.assertIn(
            "bgp-communities equal-list community-isp-transit-learned) "
            "{ set bgp-local-pref 160; accept }",
            edge_config,
        )
        self.assertIn(
            "bgp-communities equal-list community-ren-transit-learned) "
            "{ set bgp-local-pref 180; accept }",
            edge_config,
        )
        self.assertIn('add chain=bgp-in-isp rule="reject"', edge_config)
        self.assertIn('add chain=bgp-in-ren rule="reject"', edge_config)

    def test_empty_community_fallback_does_not_set_local_preference(self):
        edge_config = self._render_repository_edge_config()

        empty_rules = [
            line
            for line in edge_config.splitlines()
            if "bgp-communities-empty" in line
        ]
        self.assertEqual(len(empty_rules), 2)
        self.assertTrue(
            all("set bgp-local-pref" not in line for line in empty_rules)
        )


if __name__ == "__main__":
    unittest.main()
