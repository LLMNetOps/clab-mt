SHELL := /bin/bash

LAB_TOPOLOGY ?= clab.yml
PYTHON ?= python3
SEED ?= 20260812
ISP_PREFIXES ?= 500
IDREN_PREFIXES ?= 200
IDREN_DIRECT_PREFIXES ?= 100
IDREN_TRANSIT_PREFIXES ?= 100
SHARED_PREFIXES ?= 50

.PHONY: help generate generate-prefixes render-configs test test-endpoint-startup test-exabgp-startup images deploy validate failure-tests destroy

help:
	@echo "make generate       regenerate BGP announcements and RouterOS configs"
	@echo "make test           run local generator tests"
	@echo "make test-endpoint-startup  verify delayed data-interface attachment"
	@echo "make test-exabgp-startup    verify delayed speaker-interface attachment"
	@echo "make images         build endpoint and ExaBGP helper images"
	@echo "make deploy         generate, build images, and deploy Containerlab"
	@echo "make validate       assert reachability, routing adjacencies, and policy"
	@echo "make failure-tests  flap external/core links and assert convergence"
	@echo "make destroy        destroy the Containerlab lab"

generate: generate-prefixes render-configs

generate-prefixes:
	$(PYTHON) tools/generate_prefixes.py \
		--seed $(SEED) \
		--isp-count $(ISP_PREFIXES) \
		--idren-count $(IDREN_PREFIXES) \
		--direct-count $(IDREN_DIRECT_PREFIXES) \
		--transit-count $(IDREN_TRANSIT_PREFIXES) \
		--shared-count $(SHARED_PREFIXES)

render-configs:
	$(PYTHON) tools/render_routeros.py

test:
	$(PYTHON) -m unittest discover -s tests -v
	bash tests/test_lab_manifest.sh

test-endpoint-startup:
	bash tests/test_endpoint_startup.sh

test-exabgp-startup:
	bash tests/test_exabgp_startup.sh

images:
	docker build -f containers/endpoint/Dockerfile -t local/campus-endpoint:12 .
	docker build -f containers/exabgp/Dockerfile -t local/campus-exabgp:5.0.9 .

deploy: generate images
	containerlab deploy -t $(LAB_TOPOLOGY) --reconfigure

validate:
	tools/validate.sh

failure-tests:
	tools/failure-tests.sh

destroy:
	containerlab destroy -t $(LAB_TOPOLOGY)
