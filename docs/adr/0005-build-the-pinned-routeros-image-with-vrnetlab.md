# Build the pinned RouterOS image with Containerlab-compatible vrnetlab

The lab uses the official MikroTik CHR VMDK for RouterOS 7.21.5 and builds
`vrnetlab/mikrotik_routeros:7.21.5` with the `srl-labs/vrnetlab` fork. This keeps
the vendor runtime and exact patch version explicit instead of depending on an
unverified floating Docker tag. The trade-off is a one-time image build and a
runtime dependency on QEMU/KVM; the topology allocates 1 GiB to each RouterOS
node and can fall back to software emulation where supported.
