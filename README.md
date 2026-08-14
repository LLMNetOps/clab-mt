# Containerlab campus eBGP testbed

This repository deploys a small campus routing lab with Containerlab.

R1 is the **campus edge**. R1, R2, and R3 form the OSPF **campus core**.
R1 also has external BGP sessions with ISP and IDREN. H1 and H2 receive
addresses through DHCP.

![Containerlab campus eBGP topology](campus-ebgp.svg)

The lab demonstrates:

- OSPF routing and convergence in the campus core.
- External BGP sessions with ISP and IDREN.
- IDREN preference for a shared test prefix.
- Propagation of selected external routes into OSPF.
- Endpoint traffic during normal and failed-link conditions.

The generated BGP prefixes are control-plane test routes. There is no host or
service behind these prefixes.

## Requirements

- An x86_64 Linux host with Docker and Containerlab.
- KVM access through `/dev/kvm` is strongly recommended for the three
  RouterOS nodes.
- GNU Make, GNU coreutils (`sha256sum`), Bash, Git, curl, patch, unzip,
  Python 3.10 or newer, `pexpect`, and an OpenSSH client.

The lab uses the pinned RouterOS image
`vrnetlab/mikrotik_routeros:7.21.5`. The Makefile can build this image from
the official MikroTik CHR download.

## Quick start

Run these commands from the repository root:

```bash
make deploy
make validate
make destroy
```

The first `make deploy`:

1. Generates the BGP advertisements and RouterOS startup files.
2. Builds the RouterOS image if it is not present.
3. Builds the endpoint and ExaBGP images.
4. Deploys or replaces the Containerlab lab.

The RouterOS image build checks out a pinned vrnetlab commit, locks its base
image and Debian packages, and verifies the official RouterOS 7.21.5 CHR
archive before extraction. Use
`make routeros-image` if you want to run this build separately. See
[Build the RouterOS image](docs/routeros-image.md) for details and manual
instructions.

RouterOS uses the lab-only credential `admin` / `admin`. Do not expose this
lab to an untrusted network.

## Run experiments

Send continuous ICMP traffic from H1 to H2:

```bash
make traffic
```

Press Ctrl-C to stop the traffic.

Show, disable, and restore one lab link:

```bash
make link-status LINK=r2-r3
make link-down LINK=r2-r3
make link-up LINK=r2-r3
```

Valid link names are `r2-r3`, `isp`, and `idren`. A link that you disable
stays disabled until you restore it or destroy the lab.

Inspect, release, and renew DHCP on an endpoint host:

```bash
make dhcp-status ENDPOINT=H1
make dhcp-release ENDPOINT=H1
make dhcp-renew ENDPOINT=H1
```

The supported endpoint hosts are H1 and H2. Releasing a lease does not stop
the endpoint container.

Run the automated failure and recovery tests:

```bash
make failure-tests
```

See [Operate the lab](docs/operations.md) for traffic options, all link
commands, validation modes, and failure-test behavior.

## More information

- [RouterOS image build](docs/routeros-image.md)
- [Lab operations](docs/operations.md)
- [Address and route-generation reference](docs/lab-reference.md)
- [Test structure](docs/testing.md)
- [Contribution guide](CONTRIBUTING.md)
- [Campus routing lab language](CONTEXT.md)
- [Architecture decisions](docs/adr)

Run `make help` to list the main operator and development commands.

## License

This project is available under the [MIT License](LICENSE).
