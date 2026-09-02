// Package main - chip.go
//
// The wire protocol side of the web UI.  Same four commands the ucom CLI uses
// and the same ones uart_if.v implements, so anything the UI can do you can
// also do by hand:
//
//	Single write  'W' + addr + data
//	Single read   'R' + addr            -> data
//	Block write   'B' + addr + len + data...
//	Block read    'b' + addr + len      -> data...

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"go.bug.st/serial"
	"go.bug.st/serial/enumerator"
)

// Register map, mirrors regmap/regmap_pwm16.md
const (
	RegChipID    = 0x00
	RegVersion   = 0x01
	RegCfg       = 0x02
	RegCenterAll = 0x03
	RegDivComL   = 0x04
	RegDivComH   = 0x05
	RegDivPwmL   = 0x06
	RegDivPwmH   = 0x07
	RegChanEnL   = 0x08
	RegChanEnH   = 0x09
	RegScratch   = 0x0A
	RegStatus    = 0x0B
	RegChan0     = 0x10

	CfgEnable    = 1 << 0
	CfgServoMode = 1 << 1
	CfgUartTxEn  = 1 << 2
	CfgDemo      = 1 << 3
	CfgInvert    = 1 << 4

	ExpectedChipID = 0x16
	NumChannels    = 16
)

// Chip is a serial connection to a tt_um_ida_pwm16, on silicon or on FPGA.
type Chip struct {
	mu   sync.Mutex
	port serial.Port
	name string
	baud int
}

// PortInfo describes one candidate serial port.
type PortInfo struct {
	Name    string `json:"name"`
	Product string `json:"product"`
	VID     string `json:"vid"`
	PID     string `json:"pid"`
	Note    string `json:"note"`
	Score   int    `json:"-"`
}

// scoreNeverProbe marks a port we must not even poke at - writing bytes into a
// cellular modem's command channel is nobody's idea of a good time.
const scoreNeverProbe = 20

// classify scores a port: lower is a better candidate for talking to the chip.
// The product string matters more than the VID.  A Raspberry Pi VID (2e8a) is
// both a debugprobe UART bridge and a MicroPython REPL, and writing register
// bytes into somebody's REPL is not a good time.
func classify(product string) (int, string) {
	p := strings.ToLower(product)
	switch {
	case strings.Contains(p, "debugprobe") || strings.Contains(p, "cmsis-dap"):
		return 0, "debugprobe USB-UART bridge"
	case strings.Contains(p, "uart") || strings.Contains(p, "usb-serial") ||
		strings.Contains(p, "usb serial") || strings.Contains(p, "ft232") ||
		strings.Contains(p, "ft2232") || strings.Contains(p, "cp210") ||
		strings.Contains(p, "ch340") || strings.Contains(p, "ch910"):
		return 1, "USB-serial adapter"
	case strings.Contains(p, "micropython") || strings.Contains(p, "board in fs mode"):
		// Could be a bare MicroPython REPL, or a TT demo board running
		// tt_uart_bridge - the USB descriptor is identical either way, so the
		// only way to tell is to ask the chip.
		return 7, "MicroPython REPL, or a TT demo board running tt_uart_bridge"
	case strings.Contains(p, "modem") || strings.Contains(p, "quectel"):
		return scoreNeverProbe, "cellular modem"
	}
	return 5, ""
}

// productForPort digs out a human readable device name.  go.bug.st leaves
// PortDetails.Product empty on Linux, but /dev/serial/by-id encodes the USB
// product string in the symlink name, so use that when it is available.
func productForPort(name string) string {
	const byID = "/dev/serial/by-id"
	entries, err := os.ReadDir(byID)
	if err != nil {
		return ""
	}
	for _, e := range entries {
		link := filepath.Join(byID, e.Name())
		target, err := filepath.EvalSymlinks(link)
		if err != nil || target != name {
			continue
		}
		label := e.Name()
		label = strings.TrimPrefix(label, "usb-")
		if i := strings.LastIndex(label, "-if"); i > 0 {
			label = label[:i]
		}
		return strings.ReplaceAll(label, "_", " ")
	}
	return ""
}

// ListPorts returns the serial ports on this machine, best candidate first.
func ListPorts() []PortInfo {
	details, err := enumerator.GetDetailedPortsList()
	if err != nil || len(details) == 0 {
		plain, err2 := serial.GetPortsList()
		if err2 != nil {
			return nil
		}
		out := make([]PortInfo, 0, len(plain))
		for _, n := range plain {
			p := productForPort(n)
			sc, note := classify(p)
			out = append(out, PortInfo{Name: n, Product: p, Note: note, Score: sc})
		}
		return out
	}

	type scored struct {
		info  PortInfo
		score int
	}
	list := []scored{}
	for _, d := range details {
		product := d.Product
		if product == "" {
			product = productForPort(d.Name)
		}
		score, note := classify(product)
		if !d.IsUSB {
			score += 10
		}
		list = append(list, scored{
			PortInfo{Name: d.Name, Product: product, VID: d.VID, PID: d.PID, Note: note, Score: score},
			score,
		})
	}
	sort.SliceStable(list, func(i, j int) bool { return list[i].score < list[j].score })

	out := make([]PortInfo, 0, len(list))
	for _, s := range list {
		out = append(out, s.info)
	}
	return out
}

// PortNames is the bare list, best candidate first.
func PortNames() []string {
	out := []string{}
	for _, p := range ListPorts() {
		out = append(out, p.Name)
	}
	return out
}

// Open connects to a named port, or auto-detects when name is empty or "auto".
func Open(name string, baud int) (*Chip, error) {
	if name == "" || name == "auto" {
		return AutoDetect(baud)
	}
	return openPort(name, baud)
}

// AutoDetect walks the plausible ports in rank order and keeps the first one
// that answers with the right chip id.
//
// Metadata alone is not enough: a TT demo board running tt_uart_bridge presents
// exactly the same USB descriptor as a bare MicroPython REPL, and a Raspberry Pi
// VID is both a debugprobe and a Pico. So ask the chip who it is.
func AutoDetect(baud int) (*Chip, error) {
	ports := ListPorts()
	if len(ports) == 0 {
		return nil, fmt.Errorf("no serial ports found")
	}
	var tried []string
	for _, p := range ports {
		if p.Score >= scoreNeverProbe {
			tried = append(tried, fmt.Sprintf("%s skipped (%s)", p.Name, p.Note))
			continue
		}
		c, err := openPort(p.Name, baud)
		if err != nil {
			tried = append(tried, fmt.Sprintf("%s could not be opened (%v)", p.Name, err))
			continue
		}
		id, err := c.Read(RegChipID)
		switch {
		case err != nil:
			tried = append(tried, fmt.Sprintf("%s did not answer", p.Name))
		case id == ExpectedChipID:
			return c, nil
		default:
			tried = append(tried, fmt.Sprintf("%s answered 0x%02X, not 0x%02X",
				p.Name, id, ExpectedChipID))
		}
		c.Close()
	}
	return nil, fmt.Errorf("no port answered with chip_id 0x%02X: %s",
		ExpectedChipID, strings.Join(tried, "; "))
}

func openPort(name string, baud int) (*Chip, error) {
	p, err := serial.Open(name, &serial.Mode{
		BaudRate: baud,
		Parity:   serial.NoParity,
		DataBits: 8,
		StopBits: serial.OneStopBit,
	})
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", name, err)
	}
	if err := p.SetReadTimeout(300 * time.Millisecond); err != nil {
		p.Close()
		return nil, err
	}
	c := &Chip{port: p, name: name, baud: baud}
	c.drain()
	return c, nil
}

func (c *Chip) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.port == nil {
		return nil
	}
	err := c.port.Close()
	c.port = nil
	return err
}

func (c *Chip) Name() string { return c.name }
func (c *Chip) Baud() int    { return c.baud }

func (c *Chip) drain() {
	buf := make([]byte, 256)
	for {
		n, err := c.port.Read(buf)
		if err != nil || n == 0 {
			return
		}
	}
}

func (c *Chip) writeAll(b []byte) error {
	n, err := c.port.Write(b)
	if err != nil {
		return err
	}
	if n != len(b) {
		return fmt.Errorf("short write: %d of %d", n, len(b))
	}
	return nil
}

func (c *Chip) readExact(n int) ([]byte, error) {
	out := make([]byte, 0, n)
	buf := make([]byte, n)
	deadline := time.Now().Add(time.Second)
	for len(out) < n {
		if time.Now().After(deadline) {
			return nil, fmt.Errorf("timeout: got %d of %d bytes", len(out), n)
		}
		got, err := c.port.Read(buf)
		if err != nil {
			return nil, err
		}
		out = append(out, buf[:got]...)
	}
	return out, nil
}

// Write sets one register.
func (c *Chip) Write(addr, data byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.port == nil {
		return fmt.Errorf("not connected")
	}
	return c.writeAll([]byte{'W', addr, data})
}

// Read returns one register.
func (c *Chip) Read(addr byte) (byte, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.port == nil {
		return 0, fmt.Errorf("not connected")
	}
	if err := c.writeAll([]byte{'R', addr}); err != nil {
		return 0, err
	}
	b, err := c.readExact(1)
	if err != nil {
		return 0, err
	}
	return b[0], nil
}

// WriteBlock writes consecutive registers in one go.  This is what makes the
// sliders feel live: all 16 channels are 19 bytes on the wire, about 1.6 ms.
func (c *Chip) WriteBlock(addr byte, data []byte) error {
	if len(data) == 0 || len(data) > 255 {
		return fmt.Errorf("block size %d out of range", len(data))
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.port == nil {
		return fmt.Errorf("not connected")
	}
	cmd := append([]byte{'B', addr, byte(len(data))}, data...)
	return c.writeAll(cmd)
}

// ReadBlock reads consecutive registers in one go.
func (c *Chip) ReadBlock(addr byte, n int) ([]byte, error) {
	if n <= 0 || n > 255 {
		return nil, fmt.Errorf("block size %d out of range", n)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.port == nil {
		return nil, fmt.Errorf("not connected")
	}
	if err := c.writeAll([]byte{'b', addr, byte(n)}); err != nil {
		return nil, err
	}
	return c.readExact(n)
}

//-----------------------------------------------------------------------------
// Convenience layer
//-----------------------------------------------------------------------------

func (c *Chip) Identify() (id, version byte, err error) {
	id, err = c.Read(RegChipID)
	if err != nil {
		return
	}
	version, err = c.Read(RegVersion)
	return
}

func (c *Chip) SetChannels(values []byte) error {
	if len(values) != NumChannels {
		return fmt.Errorf("need %d channel values, got %d", NumChannels, len(values))
	}
	return c.WriteBlock(RegChan0, values)
}

func (c *Chip) Channels() ([]byte, error) {
	return c.ReadBlock(RegChan0, NumChannels)
}

func (c *Chip) CenterAll() error { return c.Write(RegCenterAll, 0x01) }

func (c *Chip) SetChanEnable(mask uint16) error {
	return c.WriteBlock(RegChanEnL, []byte{byte(mask & 0xFF), byte(mask >> 8)})
}

// PulseMicroseconds converts a position byte to the servo pulse it produces.
// 0x00 -> 1000 us, 0xFF -> 1996 us, with a 3.90625 us tick.
func PulseMicroseconds(v byte) float64 {
	return 1000.0 + float64(v)*(1000.0/256.0)
}
