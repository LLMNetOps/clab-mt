# Test structure

Operator tools and automated tests have different purposes.

- `tools/` contains commands that inspect or change the deployed lab.
- `tests/` contains automated assertions about code, images, and lab behavior.
- `tests/live/` contains tests that need a deployed lab and change link state.

## Local tests

Run:

```bash
make test
```

These tests do not need a deployed lab. They check prefix generation,
RouterOS configuration rendering, container build inputs, manifest helpers,
and operator command interfaces.

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
IDREN, and R2–R3 links. Do not run them while another lab operator is changing
the same lab.
