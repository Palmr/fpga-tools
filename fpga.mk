
SELF_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Show usage by default
.PHONY: usage
usage:
	@cat $(SELF_DIR)/fpga.txt

# Don't delete these
.PRECIOUS: build/%.d build/%.json build/%.bin build/%.asc

# Top module
TOP ?= top

# Tool paths

# Use apio toolchain
TOOLCHAIN = $(HOME)/.apio/packages/toolchain-icestorm/bin
export PATH := $(TOOLCHAIN):$(PATH)

YOSYS ?= yosys
PNR ?= nextpnr-ice40
ICEPACK ?= icepack
ICEPROG ?= iceprog
ICEBURN ?= iCEburn
TINYPROG ?= tinyprog
ICETIME ?= icetime
IVERILOG ?= iverilog
GTKWAVE ?= gtkwave

SHARE_ICEBOX = $$(dirname $$(which $(ICETIME)))/../share/icebox

ifeq ($(USE_SUDO),1)
ICEPROG := sudo $$(which $(ICEPROG))
ICEBURN := sudo $$(which $(ICEBURN))
TINYPROG := sudo $$(which $(TINYPROG))
endif

# Board-specific configuration

BOARD ?= icestick
PCF := $(SELF_DIR)/pcf/$(BOARD).pcf

YOSYS_OPTS =

ifeq ($(BOARD),icestick)
PNR_OPTS = --hx1k --package tq144
DEVICE = hx1k
CHIPDB = 1k
PROG = $(ICEPROG)
endif

ifeq ($(BOARD),iceblink)
PNR_OPTS = --lp1k --package qn84
DEVICE = lp1k
CHIPDB = 1k
PROG = $(ICEBURN) -vew
endif

ifeq ($(BOARD),bx)
PNR_OPTS = --lp8k --package cm81
DEVICE = lp8k
CHIPDB = 8k
PROG = $(TINYPROG) -p
endif

ifeq ($(BOARD),icebreaker)
PNR_OPTS = --up5k --package sg48
DEVICE = up5k
CHIPDB = 5k
PROG = $(ICEPROG)
endif

# To use install 'moreutils'

CHRONIC =
ifndef VERBOSE
PNR_OPTS := -q $(PNR_OPTS)
YOSYS_OPTS := -q $(YOSYS_OPTS)
CHRONIC = $(shell which chronic)
endif

# Dependencies

build/%.d: %.v
	@mkdir -p $(dir $@)
	@$(SELF_DIR)/make-deps $(@:.d=.bx.json) $< > $@
	@$(SELF_DIR)/make-deps $(@:.d=.icestick.json) $< >> $@
	@$(SELF_DIR)/make-deps $(@:.d=.iceblink.json) $< >> $@
	@$(SELF_DIR)/make-deps $(@:.d=.out) $< >> $@

# Synthesis

build/%.$(BOARD).json: %.v build/%.d
	$(YOSYS) $(YOSYS_OPTS) \
		-p "verilog_defines -DBOARD_$(BOARD) -DBOARD=$(BOARD)" \
		-p "read_verilog -noautowire $<" \
		-p "synth_ice40 -top $(TOP) -json $@"

build/%.$(BOARD).asc: build/%.$(BOARD).json $(PCF)
	$(PNR) $(PNR_OPTS) --pcf $(PCF) --json $< --asc $@

build/%.bin: build/%.asc
	$(ICEPACK) $< $@

# Simulation

build/%.out: %.v build/%.d
	$(IVERILOG) -grelative-include -DVCD_FILE=\"build/$(<:.v=.vcd)\" -o $@ $<

# Top-level goals, using V= parameter

TESTS = $(wildcard *_tb.v)

json bin flash sim run time::
ifeq ($(V),)
	$(error Define target name first, e.g.: make $@ V=myfile.v)
endif

.PHONY: json
json:: build/$(V:.v=.$(BOARD).json)

.PHONY: bin
bin:: build/$(V:.v=.$(BOARD).bin)

.PHONY: flash
flash:: build/$(V:.v=.$(BOARD).bin)
	$(PROG) $<

.PHONY: sim
sim:: run
	$(GTKWAVE) build/$(V:.v=.vcd)

.PHONY: run
run:: build/$(V:.v=.out)
	./$<

.PHONY: time
time:: build/$(V:.v=.$(BOARD).asc)
	$(ICETIME) -d $(DEVICE) -C $(SHARE_ICEBOX)/chipdb-$(CHIPDB).txt $<

.PHONY: test
test::
	@set -e; \
	for v in $(TESTS); do \
		echo $(MAKE) run V=$$v; \
		$(CHRONIC) $(MAKE) run V=$$v; \
	done; \
	echo "All OK"

# Cleanup

.PHONY: clean
clean:
	rm -rf build/*

include $(shell find build -name '*.d')
