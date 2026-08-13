import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ContainerBuildInputTests(unittest.TestCase):
    def test_base_images_are_immutable(self):
        for relative_path in (
            "containers/endpoint/Dockerfile",
            "containers/exabgp/Dockerfile",
        ):
            dockerfile = (ROOT / relative_path).read_text(encoding="utf-8")
            from_line = next(
                line for line in dockerfile.splitlines() if line.startswith("FROM ")
            )
            self.assertRegex(
                from_line,
                r"^FROM [^ ]+@sha256:[0-9a-f]{64}$",
                relative_path,
            )

    def test_installed_packages_are_version_pinned(self):
        endpoint = (ROOT / "containers/endpoint/Dockerfile").read_text(
            encoding="utf-8"
        )
        for package in (
            "isc-dhcp-client",
            "iproute2",
            "iputils-ping",
            "procps",
            "tcpdump",
            "traceroute",
        ):
            self.assertRegex(endpoint, rf"\b{re.escape(package)}=[^ \\\n]+")

        exabgp = (ROOT / "containers/exabgp/Dockerfile").read_text(
            encoding="utf-8"
        )
        self.assertRegex(exabgp, r"\biproute2=[^ \\\n]+")

    def test_apt_indexes_use_a_dated_snapshot(self):
        sources = (ROOT / "containers/common/debian.sources").read_text(
            encoding="utf-8"
        )
        self.assertRegex(
            sources,
            r"http://snapshot\.debian\.org/archive/debian/\d{8}T\d{6}Z",
        )
        self.assertRegex(
            sources,
            r"http://snapshot\.debian\.org/archive/debian-security/\d{8}T\d{6}Z",
        )
        self.assertIn("Check-Valid-Until: no", sources)

        for relative_path in (
            "containers/endpoint/Dockerfile",
            "containers/exabgp/Dockerfile",
        ):
            dockerfile = (ROOT / relative_path).read_text(encoding="utf-8")
            self.assertIn(
                "COPY containers/common/debian.sources "
                "/etc/apt/sources.list.d/debian.sources",
                dockerfile,
            )

    def test_endpoint_retries_dhcp_while_routeros_boots(self):
        dhclient = (ROOT / "containers/endpoint/dhclient.conf").read_text(
            encoding="utf-8"
        )
        self.assertIn("timeout 20;", dhclient)
        self.assertIn("retry 5;", dhclient)

        dockerfile = (ROOT / "containers/endpoint/Dockerfile").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "COPY containers/endpoint/dhclient.conf /etc/dhcp/dhclient.conf",
            dockerfile,
        )


if __name__ == "__main__":
    unittest.main()
