# tt_um_ida_pwm16 - convenience wrapper around the real build systems
#
#   make regs   regenerate the register bank and everything derived from it
#   make test   cocotb RTL tests
#   make gl     cocotb gate level tests (needs gate_level_netlist.v from the gds action)
#   make lint   verilator -Wall
#   make area   synthesise against the IHP standard cells and report area
#   make fpga   Tang Nano 9K bitstream
#   make ui     run the web UI

IHP_LIB ?= /proj/pdks/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
SRC = src/rb_pwm16.v src/uart_if.v src/pwm16.v src/tt_um_ida_pwm16.v

.PHONY: regs test gl lint area fpga ui clean

regs:
	cd regmap && go run register_bank.go -lang v -o .
	cp regmap/rb_pwm16.v src/rb_pwm16.v
	@echo "register bank regenerated; sw/.reg_file_pwm16 follows automatically"

test:
	$(MAKE) -C test

gl:
	$(MAKE) -C test GATES=yes

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module tt_um_ida_pwm16 $(SRC)

area:
	@yosys -l /tmp/pwm16_area.log -p "read_verilog $(SRC); \
	  synth -top tt_um_ida_pwm16 -flatten; \
	  dfflibmap -liberty $(IHP_LIB); \
	  abc -liberty $(IHP_LIB); \
	  opt_clean; \
	  stat -liberty $(IHP_LIB)" > /dev/null 2>&1 || (cat /tmp/pwm16_area.log; false)
	@grep -E "Chip area|sequential elements" /tmp/pwm16_area.log | tail -2
	@echo "   (TT IHP tile: 1x1 = 202.08 x 154.98 um, 2x2 = 419.52 x 313.74 um = 131620 um2)"

fpga:
	$(MAKE) -C fpga/tangnano build

ui:
	cd sw/pwmui && go run .

clean:
	$(MAKE) -C test clean 2>/dev/null || true
	$(MAKE) -C fpga/tangnano clean
	rm -rf sw/pwmui/pwmui
