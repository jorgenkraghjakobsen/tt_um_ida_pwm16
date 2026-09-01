# Tang Nano 9K test build of tt_um_ida_pwm16
#
#   make build     synth + pnr + bitstream
#   make load      load into SRAM (gone on power cycle)
#   make flash     write to the on board flash
#   make clean
#
# The design is plain Verilog-2005, so there is no sv2v / slang step here.

BOARD   ?= tangnano9k
PROJ     = tn_pwm16
TOP      = tn_pwm16_top

ifeq ($(BOARD),tangnano9k)
    FAMILY  = GW1N-9C
    DEVICE  = GW1NR-LV9QN88PC6/I5
    CST     = tangnano9k.cst
    FREQ    = 27
else
    $(error Unknown BOARD: $(BOARD))
endif

HERE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SRC   = $(HERE)../../src
OBJ   = $(HERE)obj

SOURCES = \
	$(SRC)/rb_pwm16.v \
	$(SRC)/uart_if.v \
	$(SRC)/pwm16.v \
	$(SRC)/tt_um_ida_pwm16.v \
	$(HERE)tn_pwm16_top.v

.PHONY: build load flash clean lint info help

$(OBJ):
	mkdir -p $@

$(OBJ)/$(PROJ).json: $(SOURCES) | $(OBJ)
	yosys -p "read_verilog $(SOURCES); synth_gowin -top $(TOP) -json $@" -l $(OBJ)/01-synth.log

$(OBJ)/$(PROJ)_pnr.json: $(OBJ)/$(PROJ).json $(HERE)$(CST)
	nextpnr-himbaechel --freq $(FREQ) --json $< --write $@ \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(HERE)$(CST) \
	    -l $(OBJ)/02-pnr.log

$(OBJ)/$(PROJ).fs: $(OBJ)/$(PROJ)_pnr.json
	gowin_pack -d $(FAMILY) -o $@ $<

build: $(OBJ)/$(PROJ).fs
	@echo "bitstream: $(OBJ)/$(PROJ).fs"

load: $(OBJ)/$(PROJ).fs
	openFPGALoader -b $(BOARD) $<

flash: $(OBJ)/$(PROJ).fs
	openFPGALoader -b $(BOARD) -f $<

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module $(TOP) $(SOURCES)

clean:
	rm -rf $(OBJ)

info help:
	@echo "BOARD  = $(BOARD)   ($(DEVICE), $(FREQ) MHz)"
	@echo "TOP    = $(TOP)"
	@echo "targets: build load flash lint clean"
