# Operate the lab

Run these commands from the repository root.

## Deploy and validate

Deploy or replace the lab:

```bash
make deploy
```

This command generates configuration files, builds all required images, and
runs Containerlab with `--reconfigure`.

Validate endpoint reachability and routing state:

```bash
make validate
```

The full validation checks H1-to-H2 traffic, both external BGP sessions,
received route counts, OSPF neighbors, shared-prefix preference, and OSPF
external-route propagation.

The validation tool also has limited modes:

```bash
bash tools/validate.sh reachability-only
bash tools/validate.sh control-plane-only
```

## Generate endpoint traffic

The default command sends continuous ICMP traffic from H1 to H2:

```bash
make traffic
```

Press Ctrl-C to stop it. Use a fixed probe count when you do not want a
continuous command:

```bash
make traffic TRAFFIC_COUNT=20
```

Reverse the direction:

```bash
make traffic TRAFFIC_SOURCE=H2 TRAFFIC_DESTINATION=H1
```

`TRAFFIC_INTERVAL` sets the interval in seconds. Its default is `1`.

## Control endpoint DHCP

Show the DHCP client state, IPv4 address, and data-plane default route:

```bash
make dhcp-status ENDPOINT=H1
```

Release the lease:

```bash
make dhcp-release ENDPOINT=H1
```

The endpoint container stays running. The command removes the IPv4 address
and default route from `eth1`. The DHCP client stays stopped until you request
a new lease or recreate the container.

Request a new lease:

```bash
make dhcp-renew ENDPOINT=H1
```

Use `ENDPOINT=H2` for H2. `DHCP_TIMEOUT` controls how many seconds the release
or renewal operation can take. Its default is `30`.

Run the client lease-cycle test on both endpoint hosts:

```bash
make test-dhcp-client
```

The tool does not change the DHCP servers on R2 or R3.

## Control links

The supported link names are:

| Link name | Lab connection |
| --- | --- |
| `r2-r3` | R2–R3 campus-core link |
| `isp` | R1–ISP external BGP link |
| `idren` | R1–IDREN external BGP link |

Show a link:

```bash
make link-status LINK=isp
```

Disable and restore the link:

```bash
make link-down LINK=isp
make link-up LINK=isp
```

The link tool makes only the requested change. It does not restore a disabled
link automatically.

## Run automated failure tests

Run:

```bash
make failure-tests
```

The tests are under `tests/live/`. They use the same link-control tool as the
manual commands.

The external-link test disables and restores the ISP link, and then disables
and restores the IDREN link. It verifies route withdrawal, recovery, endpoint
reachability, and ExaBGP process continuity.

The campus-core test disables the R2–R3 link. It verifies that H1-to-H2 traffic
moves from R2–R3 to R2–R1–R3. It then restores the link and verifies the normal
path.

Each test has a cleanup trap that tries to restore a link after a failed
assertion or an interrupted command.

## Destroy the lab

Run:

```bash
make destroy
```
