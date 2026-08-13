# Contributing

Thanks for helping improve the campus routing lab. Contributions should keep
the lab reproducible, understandable, and safe to run on a development host.

## Before starting

- Read [README.md](README.md) for prerequisites and the supported workflow.
- Read [CONTEXT.md](CONTEXT.md) and the relevant files in
  [docs/adr](docs/adr) before changing topology, routing policy, address space,
  generated advertisements, or pinned runtimes.
- For a substantial behavior or design change, open an issue first so its
  scope and acceptance criteria can be agreed before implementation.
- Report vulnerabilities through [SECURITY.md](SECURITY.md), not a public bug
  report.

## Development workflow

1. Fork the repository and create a focused branch from `main`.
2. Make the smallest coherent change that solves the issue.
3. Add or update tests at the public behavior seam.
4. If generation inputs or templates changed, run `make generate` and commit
   the resulting files under `generated/` and `configs/routeros/`.
5. Run the checks appropriate to the change.

The baseline local checks are:

```bash
make test
make generate
git diff --exit-code -- generated configs/routeros
```

Changes to endpoint or ExaBGP startup should additionally run:

```bash
make images
make test-endpoint-startup
make test-exabgp-startup
```

When a deployed lab is available, topology, routing, or failure-handling
changes should also run:

```bash
make validate
make failure-tests
```

State which checks you ran in the pull request. Explain why any applicable
check could not be run.

## Commit and pull-request conventions

Use Conventional Commit subjects in the form `type: imperative summary` or
`type(scope): imperative summary`. Common types are `feat`, `fix`, `docs`,
`refactor`, `test`, `build`, and `chore`.

Examples:

```text
feat(generator): add a new prefix source category
fix(validation): handle delayed OSPF convergence
docs: clarify RouterOS image prerequisites
```

Keep commits focused. Pull requests should explain the problem, the chosen
approach, contract or ADR effects, and verification performed. Update the
README, context glossary, or ADRs when the externally visible lab contract or
an architectural decision changes. Use the same Conventional Commit format for
a pull-request title when it will become a squash-merge commit.

## Repository hygiene

- Do not commit `clab-*` deployment state, generated TLS material, private
  keys, credentials, packet captures, caches, or local agent files.
- The checked-in RouterOS password and eBGP TCP MD5 strings are lab-only test
  values. Do not replace them with real credentials.
- Keep the management network separate from routed data links.
- Preserve the exact pinned runtime and package versions unless the change is
  explicitly an upgrade with regenerated artifacts and verification.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
