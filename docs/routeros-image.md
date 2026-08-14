# Build the RouterOS image

R1, R2, and R3 use the pinned image
`vrnetlab/mikrotik_routeros:7.21.5`. This is a VM-backed container image. The
image is not distributed with this repository.

## Automated build

Run:

```bash
make routeros-image
```

The command:

1. Checks for the local image.
2. Creates a temporary build directory.
3. Checks out the pinned Containerlab-compatible vrnetlab commit.
4. Applies the checked-in patch that pins the amd64 vrnetlab base manifest,
   Debian snapshot, and package versions.
5. Downloads the official RouterOS 7.21.5 CHR archive.
6. Verifies the archive against the pinned SHA-256 digest.
7. Builds the vrnetlab image.
8. Removes the temporary build directory.

Show the immutable build inputs:

```bash
bash tools/build-routeros-image.sh --print-inputs
```

The command does not rebuild an image that already exists. To force a rebuild,
run:

```bash
bash tools/build-routeros-image.sh --force
```

The host must be x86_64 and have Docker, Git, curl, patch, `sha256sum`, unzip,
and GNU Make. KVM is strongly recommended when you run the completed lab.

Verify the result:

```bash
docker image inspect vrnetlab/mikrotik_routeros:7.21.5
```

## Manual build

Use these commands if you need to inspect or change the build:

```bash
git clone --no-checkout https://github.com/srl-labs/vrnetlab /tmp/vrnetlab
git -C /tmp/vrnetlab checkout --detach 9dbcd465a75f7c2d048bd3342eac10c3537eb00d
patch --directory=/tmp/vrnetlab/mikrotik/routeros --strip=1 \
  < containers/routeros/vrnetlab-routeros.patch
cd /tmp/vrnetlab/mikrotik/routeros
curl -LO https://download.mikrotik.com/routeros/7.21.5/chr-7.21.5.vmdk.zip
printf '%s  %s\n' \
  acc6b562ad870116c28ce0246e99deac984d815bd9893197ee9b5897422543eb \
  chr-7.21.5.vmdk.zip | sha256sum --check -
unzip chr-7.21.5.vmdk.zip
make docker-image
```

The resulting tag must be `vrnetlab/mikrotik_routeros:7.21.5`. This is the
image in [`clab.yml`](../clab.yml).

The checked-in patch is part of this repository's reproducible build contract;
do not omit it from a manual build. See the pinned upstream
[vrnetlab RouterOS instructions](https://github.com/srl-labs/vrnetlab/tree/9dbcd465a75f7c2d048bd3342eac10c3537eb00d/mikrotik/routeros)
and the
[Containerlab RouterOS kind](https://containerlab.dev/manual/kinds/vr-ros/)
for upstream requirements.
