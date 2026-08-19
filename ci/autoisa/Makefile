# ============================================================
#  AutoISA Direct-CI CI harness - Makefile
# ============================================================
#
#  Targets:
#    make wp0-wp1     - regenerate Layout v2 and run Gate G0
#    make ci          - regenerate Layout v2, then run every AutoISA testbench
#    make ci-v0       - run only the harness_v0 testbench
#    make ci-rq       - run only the request_queue testbench
#    make ci-inf      - run only the inflight table testbench
#    make ci-result   - run only the result queue testbench
#    make ci-proto    - run only the D8-D11 protocol testbench
#    make ci-shell    - run only the concurrent shell testbench
#    make ci-random   - run the fixed-seed 100k-cycle regression
#    make ci-multi    - run the two-engine oldest-ready scheduler test
#    make ci-multi-shell - run the integrated two-engine concurrent shell
#    make ci-random-multi - run the multi-engine 100k regression
#    make check-q     - audit Q00-Q15 evidence after simulation
#    make ci-dst-map  - run the tagged Host destination-map test
#    make ci-host     - run the CVA6 identity/commit/result Host adapter test
#    make ci-gather   - run the queued 1-6R operand gather test
#    make ci-transport - run the end-to-end CVA6 Host transport test
#    make ci-cvxif    - run the real CV-X-IF scalar bridge test
#    make toolchain-smoke - build and inspect the minimal RV32 AutoISA D0 ELF
#    make clean       - remove xsim work dirs and CI logs
#    make vars        - print resolved variables (for debugging)
#
#  Override defaults from the command line:
#    make ci VIVADO=D:/apps/HLS/2025.2/Vivado/bin
#    make ci ROOT=D:/assignment/Direct-CI\ Integration/cva6-autoisa
#
# ============================================================

PYTHON ?= python
VIVADO ?= D:/apps/HLS/2025.2/Vivado/bin

# Project root: ci/autoisa/Makefile -> ../..  =  cva6-autoisa
ROOT   := $(shell python -c "import os, sys; print(os.path.abspath(os.path.join(sys.argv[1], '..', '..')))" "$(CURDIR)")

RUN_CI := $(CURDIR)/run_ci.py

.PHONY: wp0-wp1 ci ci-v0 ci-rq ci-inf ci-result ci-proto ci-shell ci-random ci-multi ci-multi-shell ci-random-multi ci-dst-map ci-host ci-gather ci-transport ci-cvxif toolchain-smoke check-q clean vars help

wp0-wp1:  ## regenerate Layout v2, run G0 tests and Vivado decoder smoke
	"$(PYTHON)" "$(CURDIR)/run_wp0_wp1.py" --vivado "$(VIVADO)"

ci:  ## run every AutoISA testbench
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)"

ci-v0:  ## run only the harness_v0 testbench
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_harness_v0

ci-rq:  ## run only the request_queue testbench
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_request_queue

ci-inf:  ## run only the inflight table testbench
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_inflight_table

ci-result:  ## run only the result queue testbench
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_result_queue

ci-proto:  ## run only the protocol dummy testbench
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_engine_protocols

ci-shell:  ## run only the concurrent shell testbench
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_concurrent_shell

ci-random:  ## run the fixed-seed 100k-cycle randomized regression
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_random_100k

ci-multi:  ## run the two-engine oldest-ready scheduler test
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_multi_engine_cluster

ci-multi-shell:  ## run the integrated two-engine concurrent shell
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_multi_engine_shell

ci-random-multi:  ## run the multi-engine fixed-seed 100k-cycle regression
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_random_100k_multi

ci-dst-map:  ## run the tagged Host destination-map test
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_destination_map

ci-host:  ## run the CVA6 Host adapter test
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_cva6_host_adapter

ci-gather:  ## run the queued 1-6R operand gather test
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_operand_gather

ci-transport:  ## run the end-to-end Host transport test
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_cva6_host_transport

ci-cvxif:  ## run the native scalar CV-X-IF bridge test
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --tb autoisa_ci_cvxif_coprocessor

toolchain-smoke:  ## build and inspect the minimal RV32 AutoISA D0 ELF
	"$(PYTHON)" "$(CURDIR)/check_riscv_toolchain.py"

check-q:  ## audit Q00-Q15 against current XSim logs
	"$(PYTHON)" "$(CURDIR)/check_q_coverage.py"

clean:  ## remove xsim work dirs and CI logs
	"$(PYTHON)" "$(RUN_CI)" --root "$(ROOT)" --vivado "$(VIVADO)" --clean

vars:  ## print resolved variables (for debugging)
	@echo PYTHON   = $(PYTHON)
	@echo VIVADO   = $(VIVADO)
	@echo ROOT     = $(ROOT)
	@echo RUN_CI   = $(RUN_CI)

help:  ## show this help
	@echo Targets:
	@echo   make wp0-wp1 regenerate Layout v2 and run Gate G0
	@echo   make ci       run every AutoISA testbench
	@echo   make ci-v0    run only the harness_v0 testbench
	@echo   make ci-rq    run only the request_queue testbench
	@echo   make ci-inf   run only the inflight table testbench
	@echo   make ci-result run only the result queue testbench
	@echo   make ci-proto run only the D8-D11 protocol testbench
	@echo   make ci-shell run only the concurrent shell testbench
	@echo   make ci-random run the fixed-seed 100k-cycle regression
	@echo   make ci-multi run the two-engine oldest-ready scheduler test
	@echo   make ci-multi-shell run the integrated two-engine shell test
	@echo   make ci-random-multi run the multi-engine 100k-cycle regression
	@echo   make ci-dst-map run the tagged Host destination-map test
	@echo   make ci-host run the CVA6 identity/commit/result Host adapter test
	@echo   make ci-gather run the queued 1-6R operand gather test
	@echo   make ci-transport run the end-to-end CVA6 Host transport test
	@echo   make ci-cvxif run the native scalar CV-X-IF bridge test
	@echo   make toolchain-smoke build and inspect the minimal RV32 AutoISA D0 ELF
	@echo   make check-q audit Q00-Q15 against current passing logs
	@echo   make clean    remove xsim work dirs and CI logs
	@echo   make vars     print resolved variables
