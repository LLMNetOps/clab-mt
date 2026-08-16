SHELL := /bin/bash

LAB_TOPOLOGY ?= clab.yml
PYTHON ?= python3
SEED ?= 20260812
ISP_PREFIXES ?= 500
ISP_TRANSIT_LEARNED_PREFIXES ?= 100
REN_PREFIXES ?= 200
REN_ADJACENT_ORIGIN_PREFIXES ?= 100
REN_TRANSIT_LEARNED_PREFIXES ?= 100
SHARED_PREFIXES ?= 50
LINK ?=
TRAFFIC_SOURCE ?= H1
TRAFFIC_DESTINATION ?= H2
TRAFFIC_COUNT ?= 0
TRAFFIC_INTERVAL ?= 1
ENDPOINT ?= H1
DHCP_TIMEOUT ?= 30

.PHONY: help generate generate-prefixes render-configs test test-endpoint-startup test-exabgp-startup test-community-policy test-dhcp-client routeros-image helper-images images deploy validate link-status link-down link-up traffic dhcp-status dhcp-release dhcp-renew failure-tests destroy

help:
	@echo "make routeros-image build the pinned RouterOS image when it is missing"
	@echo "make images         build the RouterOS, endpoint, and ExaBGP images"
	@echo "make deploy         generate files, build images, and deploy the lab"
	@echo "make validate       verify endpoint reachability and routing state"
	@echo "make link-status LINK=r2-r3|isp|ren  show a lab link"
	@echo "make link-down   LINK=r2-r3|isp|ren  disable a lab link"
	@echo "make link-up     LINK=r2-r3|isp|ren  restore a lab link"
	@echo "make traffic        send H1-to-H2 ICMP traffic until interrupted"
	@echo "make dhcp-status  ENDPOINT=H1|H2  show client DHCP state"
	@echo "make dhcp-release ENDPOINT=H1|H2  release a client lease"
	@echo "make dhcp-renew   ENDPOINT=H1|H2  request a client lease"
	@echo "make failure-tests  run automated link-failure and recovery tests"
	@echo "make destroy        destroy the Containerlab lab"
	@echo "make generate       regenerate BGP announcements and RouterOS configs"
	@echo "make test           run local unit and contract tests"
	@echo "make test-endpoint-startup  verify delayed data-interface attachment"
	@echo "make test-exabgp-startup    verify delayed speaker-interface attachment"
	@echo "make test-community-policy  verify live community fallback and rejection"
	@echo "make test-dhcp-client       verify client lease release and renewal"

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

deploy: generate images
	containerlab deploy -t $(LAB_TOPOLOGY) --reconfigure

validate:
	tools/validate.sh

link-status:
	bash tools/link-state.sh status "$(LINK)"

link-down:
	bash tools/link-state.sh down "$(LINK)"

link-up:
	bash tools/link-state.sh up "$(LINK)"

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
	containerlab destroy -t $(LAB_TOPOLOGY)
