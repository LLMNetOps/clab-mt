import tempfile
import unittest
from pathlib import Path

from tools.render_routeros import render_configs


class RouterOsRendererTests(unittest.TestCase):
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
                "ISP={{ISP_LOCAL_PREF}} IDREN={{IDREN_LOCAL_PREF}}\n",
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
                "ISP=100 IDREN=200\n",
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


if __name__ == "__main__":
    unittest.main()
