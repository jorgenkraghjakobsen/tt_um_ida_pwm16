// GoBank - where you put your registers
//
// Derived from jorgenkraghjakobsen/fpga_template digital/rb_fpga_template/register_bank.go
// Written by Jørgen Kragh Jakobsen.
//
// Extensions for ASIC (Tiny Tapeout / IHP sg13g2) use:
//
//   1. Verilog-2005 back end  (rb_<name>.v)
//      The original back end emits SystemVerilog with packed structs and a
//      package.  That needs yosys+slang.  LibreLane / TT and iverilog are much
//      happier with plain Verilog-2005, so the Verilog back end flattens every
//      symbol into its own port:  <section>__<symbol>.
//
//   2. Section preset         (input <section>_preset)
//      Pulsing it reloads *every* register in that section with its reset
//      value.  Used here for "set all 16 servo channels back to centre".
//
//   3. Self-clearing symbols  (Symbol.selfclear)
//      The register reads back 0 and produces a one clock wide strobe when
//      written.  Used here for ctrl.center_all.
//
// Outputs:
//   rb_<name>.v            Verilog-2005 register bank      (-lang v, default)
//   rb_<name>.sv           SystemVerilog register bank     (-lang sv)
//   rb_<name>_struct.svh   SystemVerilog package           (-lang sv)
//   reg_file_<name>        ucom / dblookup register file
//   reg_file_<name>.json   same thing as JSON
//   regmap_<name>.md       markdown table for the datasheet

package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
)

type RegMap struct {
	name     string    // Name of register bank
	version  int       // Version tag
	size     int       // Number of bits in the address vector
	errorCnt int       // Current number of errors during output
	sections []Section // List of sections
}

type Section struct {
	sid         int      // Section ID
	name        string   // Section name
	description string   // Section description
	parent      *Section // Allow section in sections
	offset      int      // Offset within RegMap
	size        int      // Section size in bytes
	preset      bool     // Generate a <name>_preset input that reloads reset values
	symbols     []Symbol // Array of symbols
}

type Symbol struct {
	syid             int    // Symbol ID
	name             string // Symbol name
	section          string // Section this symbol belongs to
	address          int    // Address within the section
	size             int    // Number of bits in symbol
	pos              int    // Position of the lsb in the byte
	reset            int    // Reset value
	readonly         bool   // Symbol is driven from the design, not writable
	selfclear        bool   // Write-1-to-trigger: clears itself the next clock
	shortDescription string // Short description
	description      string // Long description
}

func check(e error) {
	if e != nil {
		panic(e)
	}
}

//-----------------------------------------------------------------------------
// The register map for the 16 channel PWM / servo controller
//-----------------------------------------------------------------------------

func buildRegMap() RegMap {

	// syid, name, section, address, size, pos, reset, readonly, selfclear, short, long
	ctrl := []Symbol{
		{0, "chip_id", "ctrl", 0x00, 8, 0, 0x16, true, false,
			"Chip id, reads 0x16", "Constant 0x16 (16 channels). Read it first to prove the link is alive."},
		{1, "version", "ctrl", 0x01, 8, 0, 0x01, true, false,
			"RTL version", "Register map / RTL revision."},

		{2, "enable", "ctrl", 0x02, 1, 0, 1, false, false,
			"Global PWM output enable", "0 parks every channel low, servos go limp. 1 runs the pulse train."},
		{3, "servo_mode", "ctrl", 0x02, 1, 1, 1, false, false,
			"1=RC servo pulses, 0=plain PWM", "Servo mode: 20 ms frame, 1.0-2.0 ms pulse. PWM mode: 8 bit duty at frame/20."},
		{4, "uart_tx_en", "ctrl", 0x02, 1, 2, 1, false, false,
			"1=uo[0] is uart_tx, 0=uo[0] is ch15", "Trade the UART transmitter for the 16th PWM channel."},
		{5, "demo_en", "ctrl", 0x02, 1, 3, 0, false, false,
			"Run the built in sweep generator", "Ignores the channel registers and sweeps all channels. Also forced by ui[1]."},
		{6, "invert", "ctrl", 0x02, 1, 4, 0, false, false,
			"Invert all PWM outputs", "For level shifters / drivers that invert."},

		{7, "center_all", "ctrl", 0x03, 1, 0, 0, false, true,
			"Write 1: all channels back to 50%", "Self clearing strobe. Reloads every pwm.chN with its 0x80 reset value."},

		{8, "clk_div_com_l", "ctrl", 0x04, 8, 0, 0x00, false, false,
			"UART bit timer, low byte", "Clocks per UART bit. 0x0000 selects the built in default for the strapped clock."},
		{9, "clk_div_com_h", "ctrl", 0x05, 8, 0, 0x00, false, false,
			"UART bit timer, high byte", "Clocks per UART bit, high byte."},
		{10, "clk_div_pwm_l", "ctrl", 0x06, 8, 0, 0x00, false, false,
			"PWM tick divider, low byte", "Clocks per PWM tick. 0x0000 selects the built in default for the strapped clock."},
		{11, "clk_div_pwm_h", "ctrl", 0x07, 8, 0, 0x00, false, false,
			"PWM tick divider, high byte", "Clocks per PWM tick, high byte."},

		{12, "chan_en_l", "ctrl", 0x08, 8, 0, 0xFF, false, false,
			"Per channel enable, ch0-ch7", "0 parks that single channel low."},
		{13, "chan_en_h", "ctrl", 0x09, 8, 0, 0xFF, false, false,
			"Per channel enable, ch8-ch15", "0 parks that single channel low."},

		{14, "scratch", "ctrl", 0x0A, 8, 0, 0x00, false, false,
			"Scratch register", "Free running read/write byte. Write it, read it back, the link works."},

		{15, "pin_demo", "ctrl", 0x0B, 1, 0, 0, true, false,
			"State of ui[1] demo pin", "Live value of the demo strap."},
		{16, "pin_clksel", "ctrl", 0x0B, 1, 1, 0, true, false,
			"State of ui[2] clock select pin", "0 = 10 MHz defaults, 1 = 50 MHz defaults."},
		{17, "pin_center", "ctrl", 0x0B, 1, 2, 0, true, false,
			"State of ui[3] centre pin", "Live value of the hardware centre-all strap."},
		{18, "frame_tick", "ctrl", 0x0B, 1, 3, 0, true, false,
			"High during the first ms of a frame", "Cheap heartbeat, proves the timebase runs."},
	}

	pwm := []Symbol{}
	for ch := 0; ch < 16; ch++ {
		pwm = append(pwm, Symbol{ch, fmt.Sprintf("ch%d", ch), "pwm", ch, 8, 0, 0x80, false, false,
			fmt.Sprintf("Channel %d position", ch),
			fmt.Sprintf("Channel %d. Servo mode: 0x00=1.0 ms, 0x80=1.5 ms, 0xFF=2.0 ms. PWM mode: duty/256.", ch)})
	}

	sec := []Section{
		// sid, name, description, parent, offset, size, preset, symbols
		{0, "ctrl", "Global control, clocking and status", nil, 0x00, 0x10, false, ctrl},
		{1, "pwm", "The 16 channel position registers", nil, 0x10, 0x10, true, pwm},
	}

	return RegMap{"pwm16", 0x000001, 8, 0, sec}
}

func main() {
	lang := flag.String("lang", "v", "HDL back end: v (Verilog-2005) or sv (SystemVerilog structs)")
	outDir := flag.String("o", ".", "output directory")
	flag.Parse()

	regmap := buildRegMap()

	if err := os.MkdirAll(*outDir, 0o755); err != nil {
		panic(err)
	}

	switch *lang {
	case "v":
		writeVerilog(regmap, *outDir)
	case "sv":
		writeSystemVerilog(regmap, *outDir)
	default:
		fmt.Fprintf(os.Stderr, "unknown -lang %q\n", *lang)
		os.Exit(1)
	}

	writeRegFile(regmap, *outDir)
	writeJSONFile(regmap, *outDir)
	writeMarkdown(regmap, *outDir)
}

//-----------------------------------------------------------------------------
// helpers
//-----------------------------------------------------------------------------

func create(dir, name string) (*os.File, *bufio.Writer) {
	f, err := os.Create(dir + "/" + name)
	check(err)
	w := bufio.NewWriter(f)
	return f, w
}

func (s Symbol) msb() int { return s.pos + s.size - 1 }

func (s Symbol) full() string { return s.section + "__" + s.name }

func (s Symbol) rangeStr() string {
	if s.size == 1 {
		return ""
	}
	return fmt.Sprintf("[%d:0] ", s.size-1)
}

func (s Symbol) sliceStr() string {
	if s.size == 1 {
		return fmt.Sprintf("[%d]", s.pos)
	}
	return fmt.Sprintf("[%d:%d]", s.msb(), s.pos)
}

func (s Symbol) resetStr() string {
	return fmt.Sprintf("%d'h%0*x", s.size, (s.size+3)/4, s.reset)
}

// usedAddresses returns every absolute address that carries at least one symbol
func usedAddresses(r RegMap) []int {
	set := map[int]bool{}
	for _, sec := range r.sections {
		for _, s := range sec.symbols {
			set[sec.offset+s.address] = true
		}
	}
	out := []int{}
	for a := range set {
		out = append(out, a)
	}
	sort.Ints(out)
	return out
}

func symbolsAt(r RegMap, add int) []struct {
	sec Section
	sym Symbol
} {
	out := []struct {
		sec Section
		sym Symbol
	}{}
	for _, sec := range r.sections {
		if add < sec.offset || add >= sec.offset+sec.size {
			continue
		}
		for _, s := range sec.symbols {
			if sec.offset+s.address == add {
				out = append(out, struct {
					sec Section
					sym Symbol
				}{sec, s})
			}
		}
	}
	return out
}

//-----------------------------------------------------------------------------
// Verilog-2005 back end
//-----------------------------------------------------------------------------

func writeVerilog(r RegMap, dir string) {
	f, w := create(dir, fmt.Sprintf("rb_%s.v", r.name))
	defer f.Close()
	defer w.Flush()

	p := func(format string, a ...interface{}) { fmt.Fprintf(w, format, a...) }

	p("// Register bank - Verilog-2005\n")
	p("// Auto generated from %s version %d - DO NOT EDIT\n", r.name, r.version)
	p("// Generator: regmap/register_bank.go   (go run register_bank.go -lang v)\n")
	p("// Written by Jorgen Kragh Jakobsen, all rights reserved\n")
	p("//-----------------------------------------------------------------------------\n\n")
	p("`default_nettype none\n\n")
	p("module rb_%s #(\n", r.name)
	p("    parameter ADR_BITS = %d\n", r.size)
	p(") (\n")
	p("    input  wire                 clk,\n")
	p("    input  wire                 resetb,\n")
	p("    input  wire [ADR_BITS-1:0]  address,\n")
	p("    input  wire [7:0]           data_write_in,\n")
	p("    output reg  [7:0]           data_read_out,\n")
	p("    input  wire                 reg_en,\n")
	// build the remaining ports as {declaration, trailing comment} pairs so the
	// commas land between the declaration and the comment
	type portLine struct{ pre, decl, comment string }
	ports := []portLine{}
	for _, sec := range r.sections {
		if sec.preset {
			ports = append(ports, portLine{
				fmt.Sprintf("\n    // --- %s: pulse high to reload every register with its reset value\n", sec.name),
				fmt.Sprintf("    input  wire                 %s_preset", sec.name), ""})
		}
	}
	for _, sec := range r.sections {
		for i, s := range sec.symbols {
			dir := "output wire"
			if s.readonly {
				dir = "input  wire"
			}
			rng := "       "
			if s.size > 1 {
				rng = fmt.Sprintf("%-7s", s.rangeStr())
			}
			pre := ""
			if i == 0 {
				pre = fmt.Sprintf("\n    // --- Section %s @ 0x%02x : %s\n", sec.name, sec.offset, sec.description)
			}
			ports = append(ports, portLine{pre,
				fmt.Sprintf("    %s %s%-24s", dir, rng, s.full()), s.shortDescription})
		}
	}
	p("    input  wire                 write_en,\n")
	for i, pl := range ports {
		sep := ","
		if i == len(ports)-1 {
			sep = " "
		}
		cmt := ""
		if pl.comment != "" {
			cmt = "  // " + pl.comment
		}
		p("%s%s%s%s\n", pl.pre, pl.decl, sep, cmt)
	}
	p(");\n\n")

	//--- storage -------------------------------------------------------------
	p("//----------------------------------------------------------- storage ---\n")
	for _, sec := range r.sections {
		p("\n    // Section: %s   offset 0x%02x   size %d\n", sec.name, sec.offset, sec.size)
		for _, s := range sec.symbols {
			if s.readonly {
				continue
			}
			rng := s.rangeStr()
			if rng == "" {
				rng = "      "
			} else {
				rng = fmt.Sprintf("%-6s", rng)
			}
			p("    reg  %s r_%-24s // %s\n", rng, s.full()+";", s.shortDescription)
		}
	}

	//--- write / reset / preset ----------------------------------------------
	p("\n//------------------------------------------ write, reset and preset ---\n")
	p("    always @(posedge clk) begin\n")
	p("        if (!resetb) begin\n")
	for _, sec := range r.sections {
		p("            // %s\n", sec.name)
		for _, s := range sec.symbols {
			if s.readonly {
				continue
			}
			p("            r_%-24s <= %s;\n", s.full(), s.resetStr())
		}
	}
	p("        end else begin\n")

	// self clearing strobes first, a write later in the same block overrides
	strobes := false
	for _, sec := range r.sections {
		for _, s := range sec.symbols {
			if s.selfclear && !s.readonly {
				if !strobes {
					p("            // self clearing strobes\n")
					strobes = true
				}
				p("            r_%-24s <= %d'h0;\n", s.full(), s.size)
			}
		}
	}

	for _, sec := range r.sections {
		if !sec.preset {
			continue
		}
		p("\n            // section preset: reload reset values\n")
		p("            if (%s_preset) begin\n", sec.name)
		for _, s := range sec.symbols {
			if s.readonly {
				continue
			}
			p("                r_%-24s <= %s;\n", s.full(), s.resetStr())
		}
		p("            end\n")
	}

	p("\n            if (write_en) begin\n")
	p("                case (address)\n")
	for _, add := range usedAddresses(r) {
		hits := symbolsAt(r, add)
		wr := []string{}
		for _, h := range hits {
			if h.sym.readonly {
				continue
			}
			wr = append(wr, fmt.Sprintf("r_%-24s <= data_write_in%s;", h.sym.full(), h.sym.sliceStr()))
		}
		if len(wr) == 0 {
			continue
		}
		if len(wr) == 1 {
			p("                    8'h%02X: %s\n", add, wr[0])
		} else {
			p("                    8'h%02X: begin\n", add)
			for _, l := range wr {
				p("                        %s\n", l)
			}
			p("                    end\n")
		}
	}
	p("                    default: ;\n")
	p("                endcase\n")
	p("            end\n")
	p("        end\n")
	p("    end\n")

	//--- readback ------------------------------------------------------------
	p("\n//---------------------------------------------------------- readback ---\n")
	p("    always @(posedge clk) begin\n")
	p("        if (!resetb) begin\n")
	p("            data_read_out <= 8'h00;\n")
	p("        end else begin\n")
	p("            data_read_out <= 8'h00;\n")
	p("            case (address)\n")
	for _, add := range usedAddresses(r) {
		hits := symbolsAt(r, add)
		rd := []string{}
		for _, h := range hits {
			src := "r_" + h.sym.full()
			if h.sym.readonly {
				src = h.sym.full()
			}
			if h.sym.selfclear {
				// strobes always read back zero
				continue
			}
			rd = append(rd, fmt.Sprintf("data_read_out%-7s <= %s;", h.sym.sliceStr(), src))
		}
		if len(rd) == 0 {
			continue
		}
		if len(rd) == 1 {
			p("                8'h%02X: %s\n", add, rd[0])
		} else {
			p("                8'h%02X: begin\n", add)
			for _, l := range rd {
				p("                    %s\n", l)
			}
			p("                end\n")
		}
	}
	p("                default: data_read_out <= 8'h00;\n")
	p("            endcase\n")
	p("        end\n")
	p("    end\n")

	//--- outputs -------------------------------------------------------------
	p("\n//----------------------------------------------------------- outputs ---\n")
	for _, sec := range r.sections {
		for _, s := range sec.symbols {
			if s.readonly {
				continue
			}
			p("    assign %-26s = r_%s;\n", s.full(), s.full())
		}
	}

	p("\n    wire _unused_rb = &{1'b0, reg_en, 1'b0};\n")
	p("\nendmodule\n")
	p("`default_nettype wire\n")
}

//-----------------------------------------------------------------------------
// SystemVerilog back end (original flavour, kept for the Tang Nano / slang flow)
//-----------------------------------------------------------------------------

func writeSystemVerilog(r RegMap, dir string) {
	// package with one packed struct per section
	fs, ws := create(dir, fmt.Sprintf("rb_%s_struct.svh", r.name))
	defer fs.Close()
	ps := func(format string, a ...interface{}) { fmt.Fprintf(ws, format, a...) }
	ps("\n// Interface structures for register bank symbol access - DO NOT EDIT\n\n")
	ps("package %s_pkg;\n", r.name)
	for _, sec := range r.sections {
		ps("\n// Wire interface for %s\n", sec.name)
		ps("typedef struct packed {\n")
		for i := 0; i < 8*sec.size; i++ {
			for _, s := range sec.symbols {
				if s.address == i/8 && s.pos == i%8 {
					rng := "     "
					if s.size > 1 {
						rng = fmt.Sprintf("[%d:%d]", s.size-1, 0)
					}
					ps("  logic %s %-24s // %s\n", rng, s.name+";", s.shortDescription)
				}
			}
		}
		ps("} rb_%s_wire_t;\n", sec.name)
	}
	ps("\nendpackage\n")
	ws.Flush()

	f, w := create(dir, fmt.Sprintf("rb_%s.sv", r.name))
	defer f.Close()
	defer w.Flush()
	p := func(format string, a ...interface{}) { fmt.Fprintf(w, format, a...) }

	p("// Register bank - SystemVerilog\n")
	p("// Auto generated from %s version %d - DO NOT EDIT\n", r.name, r.version)
	p("import %s_pkg::*;\n\n", r.name)
	p("module rb_%s #(parameter ADR_BITS = %d) (\n", r.name, r.size)
	p("    input  logic                clk,\n")
	p("    input  logic                resetb,\n")
	p("    input  logic [ADR_BITS-1:0] address,\n")
	p("    input  logic [7:0]          data_write_in,\n")
	p("    output logic [7:0]          data_read_out,\n")
	p("    input  logic                reg_en,\n")
	p("    input  logic                write_en")
	for _, sec := range r.sections {
		if sec.preset {
			p(",\n    input  logic                %s_preset", sec.name)
		}
	}
	for _, sec := range r.sections {
		p(",\n    inout  rb_%s_wire_t %s", sec.name, sec.name)
	}
	p("\n);\n\n")

	for _, sec := range r.sections {
		for _, s := range sec.symbols {
			if s.readonly {
				continue
			}
			rng := s.rangeStr()
			if rng == "" {
				rng = "      "
			} else {
				rng = fmt.Sprintf("%-6s", rng)
			}
			p("logic %s r_%s;\n", rng, s.full())
		}
	}

	p("\nalways_ff @(posedge clk) begin\n")
	p("  if (!resetb) begin\n")
	for _, sec := range r.sections {
		for _, s := range sec.symbols {
			if s.readonly {
				continue
			}
			p("    r_%-24s <= %s;\n", s.full(), s.resetStr())
		}
	}
	p("  end else begin\n")
	for _, sec := range r.sections {
		for _, s := range sec.symbols {
			if s.selfclear && !s.readonly {
				p("    r_%-24s <= %d'h0;\n", s.full(), s.size)
			}
		}
	}
	for _, sec := range r.sections {
		if !sec.preset {
			continue
		}
		p("    if (%s_preset) begin\n", sec.name)
		for _, s := range sec.symbols {
			if s.readonly {
				continue
			}
			p("      r_%-24s <= %s;\n", s.full(), s.resetStr())
		}
		p("    end\n")
	}
	p("    if (write_en) begin\n")
	p("      case (address)\n")
	for _, add := range usedAddresses(r) {
		wr := []string{}
		for _, h := range symbolsAt(r, add) {
			if h.sym.readonly {
				continue
			}
			wr = append(wr, fmt.Sprintf("r_%-24s <= data_write_in%s;", h.sym.full(), h.sym.sliceStr()))
		}
		if len(wr) == 0 {
			continue
		}
		p("        8'h%02X: begin %s end\n", add, strings.Join(wr, " "))
	}
	p("        default: ;\n")
	p("      endcase\n")
	p("    end\n")
	p("  end\nend\n\n")

	p("always_ff @(posedge clk) begin\n")
	p("  if (!resetb) data_read_out <= 8'h00;\n")
	p("  else begin\n")
	p("    data_read_out <= 8'h00;\n")
	p("    case (address)\n")
	for _, add := range usedAddresses(r) {
		rd := []string{}
		for _, h := range symbolsAt(r, add) {
			if h.sym.selfclear {
				continue
			}
			src := "r_" + h.sym.full()
			if h.sym.readonly {
				src = fmt.Sprintf("%s.%s", h.sec.name, h.sym.name)
			}
			rd = append(rd, fmt.Sprintf("data_read_out%s <= %s;", h.sym.sliceStr(), src))
		}
		if len(rd) == 0 {
			continue
		}
		p("      8'h%02X: begin %s end\n", add, strings.Join(rd, " "))
	}
	p("      default: data_read_out <= 8'h00;\n")
	p("    endcase\n")
	p("  end\nend\n\n")

	for _, sec := range r.sections {
		for _, s := range sec.symbols {
			if s.readonly {
				continue
			}
			p("assign %s.%-22s = r_%s;\n", sec.name, s.name, s.full())
		}
	}
	p("\nendmodule\n")
}

//-----------------------------------------------------------------------------
// Software facing outputs
//-----------------------------------------------------------------------------

func writeRegFile(r RegMap, dir string) {
	f, w := create(dir, fmt.Sprintf("reg_file_%s", r.name))
	defer f.Close()
	defer w.Flush()
	fmt.Fprintf(w, "// Register database generic build system\n")
	for _, sec := range r.sections {
		for _, s := range sec.symbols {
			fmt.Fprintf(w, "%s.%s 0x%02x %d %d %d %s\n",
				sec.name, s.name, sec.offset+s.address, s.pos, s.size, s.reset, s.shortDescription)
		}
	}
}

func writeJSONFile(r RegMap, dir string) {
	f, w := create(dir, fmt.Sprintf("reg_file_%s.json", r.name))
	defer f.Close()
	defer w.Flush()
	fmt.Fprintf(w, "{\n  \"registers\": [\n")
	first := true
	for _, sec := range r.sections {
		for _, s := range sec.symbols {
			if !first {
				fmt.Fprintf(w, ",\n")
			}
			first = false
			ro := 0
			if s.readonly {
				ro = 1
			}
			fmt.Fprintf(w, "    {\n")
			fmt.Fprintf(w, "      \"symbol\"      : \"%s.%s\",\n", sec.name, s.name)
			fmt.Fprintf(w, "      \"address\"     : \"0x%02x\",\n", sec.offset+s.address)
			fmt.Fprintf(w, "      \"pos\"         : \"%d\",\n", s.pos)
			fmt.Fprintf(w, "      \"size\"        : \"%d\",\n", s.size)
			fmt.Fprintf(w, "      \"reset\"       : \"%d\",\n", s.reset)
			fmt.Fprintf(w, "      \"readonly\"    : \"%d\",\n", ro)
			fmt.Fprintf(w, "      \"description\" : \"%s\"\n", s.shortDescription)
			fmt.Fprintf(w, "    }")
		}
	}
	fmt.Fprintf(w, "\n  ]\n}\n")
}

func writeMarkdown(r RegMap, dir string) {
	f, w := create(dir, fmt.Sprintf("regmap_%s.md", r.name))
	defer f.Close()
	defer w.Flush()
	fmt.Fprintf(w, "<!-- Auto generated by regmap/register_bank.go - DO NOT EDIT -->\n")
	fmt.Fprintf(w, "# %s register map (version %d)\n", r.name, r.version)
	for _, sec := range r.sections {
		fmt.Fprintf(w, "\n## `%s` @ 0x%02x - %s\n\n", sec.name, sec.offset, sec.description)
		fmt.Fprintf(w, "| Addr | Bits | Symbol | Access | Reset | Description |\n")
		fmt.Fprintf(w, "|------|------|--------|--------|-------|-------------|\n")
		for _, s := range sec.symbols {
			bits := fmt.Sprintf("%d", s.pos)
			if s.size > 1 {
				bits = fmt.Sprintf("%d:%d", s.msb(), s.pos)
			}
			acc := "RW"
			if s.readonly {
				acc = "RO"
			}
			if s.selfclear {
				acc = "W1S"
			}
			fmt.Fprintf(w, "| 0x%02x | %s | `%s.%s` | %s | 0x%02x | %s |\n",
				sec.offset+s.address, bits, sec.name, s.name, acc, s.reset, s.shortDescription)
		}
	}
	fmt.Fprintf(w, "\nAccess: RW read/write, RO read only (driven by the design), ")
	fmt.Fprintf(w, "W1S write-1-to-strobe (self clearing, always reads 0).\n")
}
