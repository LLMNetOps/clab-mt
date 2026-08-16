# Test structure

Operator tools and automated tests have different purposes.

- `tools/` contains commands that inspect or change the deployed lab.
- `tests/` contains automated assertions about code, images, and lab behavior.
- `tests/live/` contains tests that need a deployed lab and exercise live lab
  state.

## Local tests

Run:

```bash
make test
```

These tests do not need a deployed lab. They check prefix generation,
RouterOS configuration rendering, container build inputs, manifest helpers,
the rendered community-policy contract, and operator command interfaces.

## Helper-image startup tests

Build the endpoint and ExaBGP images:

```bash
make helper-images
```

Then run:

```bash
make test-endpoint-startup
make test-exabgp-startup
```

These tests need Docker. They verify startup when Containerlab attaches a data
interface after the container starts.

## Deployed-lab validation

Run:

```bash
make validate
```

This is an operator acceptance check. It reads the state of a deployed lab and
does not intentionally disable links.

The control-plane portion proves that both external sessions establish and
that R1 receives the manifest's route counts. For representative routes from
all four path categories, it compares the complete received AS path with the
manifest and reports path depth, transit neighbor, communities, and local
preference. It also checks shared adjacent-origin equality, REN preference for
the shared transit-learned route even when ISP has the shorter AS path,
generated-route containment at the campus edge, and the ISP-gated OSPF
default.

## Live community-policy fixture

Run against a healthy deployed lab:

```bash
make test-community-policy
```

The fixture uses the pinned ExaBGP CLI to announce temporary routes from ISP,
then checks R1's received-route table. It verifies that an empty community
attribute is accepted without an explicit local-preference override (RouterOS
uses its default of 100), while a peer-mismatched, extra, or missing path-class
community is rejected and retained as filtered. It also verifies that a route
with contradictory ISP and REN source communities is filtered. A cleanup trap
withdraws all temporary routes before the test exits.

## DHCP client test

Run:

```bash
make test-dhcp-client
```

This test needs a deployed lab. For H1 and H2, it requests a lease, releases
the lease, verifies that the endpoint host stays running without an address or
data-plane default route, and requests a new lease. It then verifies the
expected subnet and gateway.

## Live failure tests

Run:

```bash
make failure-tests
```

These tests need a healthy deployed lab. They disable and restore the ISP,
REN, and R2–R3 links and restart R1 once while the ISP data interface is
unavailable. The external-link test verifies that only ISP session state gates
the OSPF default. Do not run them while another lab operator is changing the
same lab.
