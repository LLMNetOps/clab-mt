#!/usr/bin/env python3
"""Render the checked-in RouterOS configurations from shared templates."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

ISP_LOCAL_PREF = 100
IDREN_LOCAL_PREF = 200


@dataclass(frozen=True)
class _CampusCoreRouter:
    name: str
    endpoint_name: str
    router_id: str
    ether2_address: str
    ether2_link: str
    ether3_address: str
    ether3_link: str
    lan_gateway: str
    lan_prefix: str
    dhcp_range: str

    def template_values(self) -> dict[str, str]:
        return {
            "ROUTER_NAME": self.name,
            "ENDPOINT_NAME": self.endpoint_name,
            "ENDPOINT_SLUG": self.endpoint_name.lower(),
            "ROUTER_ID": self.router_id,
            "ETHER2_ADDRESS": self.ether2_address,
            "ETHER2_LINK": self.ether2_link,
            "ETHER3_ADDRESS": self.ether3_address,
            "ETHER3_LINK": self.ether3_link,
            "LAN_GATEWAY": self.lan_gateway,
            "LAN_PREFIX": self.lan_prefix,
            "DHCP_RANGE": self.dhcp_range,
        }


_CAMPUS_CORE_ROUTERS = (
    _CampusCoreRouter(
        name="R2",
        endpoint_name="H1",
        router_id="10.255.0.2",
        ether2_address="10.255.1.2/30",
        ether2_link="R2-R1",
        ether3_address="10.255.1.5/30",
        ether3_link="R2-R3",
        lan_gateway="10.255.10.1",
        lan_prefix="10.255.10.0/24",
        dhcp_range="10.255.10.100-10.255.10.199",
    ),
    _CampusCoreRouter(
        name="R3",
        endpoint_name="H2",
        router_id="10.255.0.3",
        ether2_address="10.255.1.10/30",
        ether2_link="R3-R1",
        ether3_address="10.255.1.6/30",
        ether3_link="R3-R2",
        lan_gateway="10.255.20.1",
        lan_prefix="10.255.20.0/24",
        dhcp_range="10.255.20.100-10.255.20.199",
    ),
)


def _render_template(
    template: Path,
    output: Path,
    values: Mapping[str, str],
) -> None:
    rendered = template.read_text(encoding="utf-8")
    for name, value in values.items():
        rendered = rendered.replace(f"{{{{{name}}}}}", value)
    if "{{" in rendered or "}}" in rendered:
        raise ValueError(f"unrendered template marker remains in {template}")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(rendered, encoding="utf-8")


def render_configs(config_dir: Path = Path("configs/routeros")) -> None:
    """Render the campus edge and campus core RouterOS configurations."""

    _render_template(
        config_dir / "r1.rsc.tmpl",
        config_dir / "r1.rsc",
        {
            "ISP_LOCAL_PREF": str(ISP_LOCAL_PREF),
            "IDREN_LOCAL_PREF": str(IDREN_LOCAL_PREF),
        },
    )

    core_template = config_dir / "core.rsc.tmpl"
    for router in _CAMPUS_CORE_ROUTERS:
        _render_template(
            core_template,
            config_dir / f"{router.name.lower()}.rsc",
            router.template_values(),
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=Path("configs/routeros"),
        help="directory containing RouterOS templates and rendered configs",
    )
    args = parser.parse_args()
    render_configs(args.config_dir)
    print(
        f"rendered R1/R2/R3 configs in {args.config_dir} "
        f"with ISP local-pref={ISP_LOCAL_PREF}, IDREN local-pref={IDREN_LOCAL_PREF}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
