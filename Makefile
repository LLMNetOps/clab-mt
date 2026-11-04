SHELL := /bin/bash

LAB_TOPOLOGY ?= llmnetops.clab.yml
PYTHON ?= python3
SEED ?= 20260812
ISP_PREFIXES ?= 500
ISP_TRANSIT_LEARNED_PREFIXES ?= 100
REN_PREFIXES ?= 200
REN_ADJACENT_ORIGIN_PREFIXES ?= 100
REN_TRANSIT_LEARNED_PREFIXES ?= 100
SHARED_PREFIXES ?= 50
TRAFFIC_SOURCE ?= H1
TRAFFIC_DESTINATION ?= H2
TRAFFIC_COUNT ?= 0
TRAFFIC_INTERVAL ?= 1
ENDPOINT ?= H1
DHCP_TIMEOUT ?= 30

.PHONY: help generate generate-prefixes render-configs test test-endpoint-startup test-exabgp-startup test-community-policy test-dhcp-client routeros-image helper-images images qemu-accel-check deploy-dependencies deploy validate ovs-prepare ovs-preflight link traffic dhcp-status dhcp-release dhcp-renew failure-tests destroy

help:
	@printf '  %-42s %s\n' \
		'make routeros-image' 'build the pinned RouterOS image when it is missing' \
		'make images' 'build the RouterOS, endpoint, and ExaBGP images' \
		'make deploy' 'install host dependencies, prepare OVS bridges, build images, and deploy' \
		'make validate' 'verify endpoint reachability and routing state' \
		'make link status r2-r3|isp|ren' 'show a lab link' \
		'make link down r2-r3|isp|ren' 'disable a lab link' \
		'make link up r2-r3|isp|ren' 'restore a lab link' \
		'make traffic' 'send ICMP traffic between endpoint hosts until interrupted' \
		'make dhcp-status ENDPOINT=H1|H2|H3|H4' 'show client DHCP state' \
		'make dhcp-release ENDPOINT=H1|H2|H3|H4' 'release a client lease' \
		'make dhcp-renew ENDPOINT=H1|H2|H3|H4' 'request a client lease' \
		'make failure-tests' 'run automated link-failure and recovery tests' \
		'make destroy' 'destroy the lab and remove Makefile-managed OVS bridges' \
		'make generate' 'regenerate BGP announcements and RouterOS configs' \
		'make test' 'run local unit and contract tests' \
		'make test-endpoint-startup' 'verify delayed data-interface attachment' \
		'make test-exabgp-startup' 'verify delayed speaker-interface attachment' \
		'make test-community-policy' 'verify live community fallback and rejection' \
		'make test-dhcp-client' 'verify client lease release and renewal'

generate: generate-prefixes render-configs

generate-prefixes:
	$(PYTHON) tools/generate_prefixes.py \
		--seed $(SEED) \
		--isp-count $(ISP_PREFIXES) \
		--isp-transit-learned-count $(ISP_TRANSIT_LEARNED_PREFIXES) \
		--ren-count $(REN_PREFIXES) \
		--ren-adjacent-origin-count $(REN_ADJACENT_ORIGIN_PREFIXES) \
		--ren-transit-learned-count $(REN_TRANSIT_LEARNED_PREFIXES) \
		--shared-count $(SHARED_PREFIXES)

render-configs:
	$(PYTHON) tools/render_routeros.py

test: generate
	$(PYTHON) -m unittest discover -s tests -v
	bash tests/test_lab_manifest.sh
	bash tests/test_operator_tools.sh
	bash tests/test_control_plane_contract.sh
	bash tests/test_routeros_image_build.sh

test-endpoint-startup:
	bash tests/test_endpoint_startup.sh

test-exabgp-startup:
	bash tests/test_exabgp_startup.sh

test-community-policy:
	bash tests/live/test_community_policy.sh

test-dhcp-client:
	bash tests/live/test_dhcp_client.sh

routeros-image:
	bash tools/build-routeros-image.sh

helper-images:
	docker build -f containers/endpoint/Dockerfile -t local/campus-endpoint:12 .
	docker build -f containers/exabgp/Dockerfile -t local/campus-exabgp:5.0.9 .

images: routeros-image helper-images

qemu-accel-check:
	@if [ -e /dev/kvm ]; then \
		echo "KVM detected at /dev/kvm; using QEMU hardware acceleration."; \
	else \
		echo "KVM not available (/dev/kvm missing); falling back to QEMU TCG software emulation."; \
	fi

deploy-dependencies:
	bash tools/install-dependencies.sh

ovs-prepare:
	bash tools/ovs-bridges.sh ensure
	bash tools/ovs-preflight.sh

ovs-preflight:
	bash tools/ovs-preflight.sh

deploy: deploy-dependencies ovs-prepare qemu-accel-check generate images
	CLAB_QEMU_ACCEL_ARGS="$$(test -e /dev/kvm || echo '-accel tcg')" containerlab deploy -t $(LAB_TOPOLOGY) --reconfigure

validate:
	tools/validate.sh

# Lets `make link <status|down|up> <link>` take the words as make goals.
ifeq ($(firstword $(MAKECMDGOALS)),link)
LINK_ACTION := $(word 2,$(MAKECMDGOALS))
LINK_NAME := $(word 3,$(MAKECMDGOALS))
ifneq ($(LINK_ACTION),)
$(LINK_ACTION):
	@:
endif
ifneq ($(LINK_NAME),)
$(LINK_NAME):
	@:
endif
endif

link:
	bash tools/link-state.sh "$(LINK_ACTION)" "$(LINK_NAME)"

traffic:
	TRAFFIC_SOURCE="$(TRAFFIC_SOURCE)" \
	TRAFFIC_DESTINATION="$(TRAFFIC_DESTINATION)" \
	TRAFFIC_COUNT="$(TRAFFIC_COUNT)" \
	TRAFFIC_INTERVAL="$(TRAFFIC_INTERVAL)" \
		bash tools/traffic.sh

dhcp-status:
	DHCP_TIMEOUT="$(DHCP_TIMEOUT)" bash tools/dhcp-client.sh status "$(ENDPOINT)"

dhcp-release:
	DHCP_TIMEOUT="$(DHCP_TIMEOUT)" bash tools/dhcp-client.sh release "$(ENDPOINT)"

dhcp-renew:
	DHCP_TIMEOUT="$(DHCP_TIMEOUT)" bash tools/dhcp-client.sh renew "$(ENDPOINT)"

failure-tests:
	bash tests/live/test_external_link_failure.sh
	bash tests/live/test_core_link_failure.sh

destroy:
	containerlab destroy -t $(LAB_TOPOLOGY) && bash tools/ovs-bridges.sh cleanup
