// pwmui - a small web front end for tt_um_ida_pwm16
//
//	go run .                      # auto detect the serial port, serve :8080
//	go run . -port /dev/ttyUSB1   # pick the port
//	go run . -addr :9000          # pick the http port
//	go run . -demo                # no hardware, just drive the UI
//
// SPDX-License-Identifier: Apache-2.0

package main

import (
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
)

//go:embed index.html
var indexHTML []byte

type server struct {
	mu       sync.Mutex
	chip     *Chip
	offline  bool // -demo: keep a local model so the UI can be shown dry
	values   [NumChannels]byte
	cfg      byte
	chanEn   uint16
	lastErr  string
	chipID   byte
	version  byte
	identOK  bool
	baudRate int
	port     string // what -port asked for, "" means auto
}

func main() {
	port := flag.String("port", "", "serial port (default: auto detect)")
	baud := flag.Int("baud", 115200, "baud rate")
	addr := flag.String("addr", ":8080", "http listen address")
	demo := flag.Bool("demo", false, "run without hardware")
	flag.Parse()

	s := &server{
		cfg:      CfgEnable | CfgServoMode | CfgUartTxEn,
		chanEn:   0xFFFF,
		offline:  *demo,
		baudRate: *baud,
	}
	for i := range s.values {
		s.values[i] = 0x80
	}

	s.port = *port
	if !*demo {
		if err := s.connect(*port, *baud); err != nil {
			log.Printf("no chip yet (%v)", err)
			log.Printf("retrying every 3s - start the bridge and it will pick it up, " +
				"or run with -demo to look around")
		}
		go s.reconnectLoop()
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleIndex)
	mux.HandleFunc("/api/status", s.handleStatus)
	mux.HandleFunc("/api/ports", s.handlePorts)
	mux.HandleFunc("/api/connect", s.handleConnect)
	mux.HandleFunc("/api/channels", s.handleChannels)
	mux.HandleFunc("/api/cfg", s.handleCfg)
	mux.HandleFunc("/api/center", s.handleCenter)
	mux.HandleFunc("/api/chanen", s.handleChanEn)

	log.Printf("16 channel PWM controller UI on http://localhost%s", *addr)
	if s.chip != nil {
		log.Printf("chip on %s at %d baud", s.chip.Name(), s.chip.Baud())
	}
	log.Fatal(http.ListenAndServe(*addr, mux))
}

// reconnectLoop keeps looking for the chip so you can start the UI first and
// bring the bridge up afterwards.
func (s *server) reconnectLoop() {
	for range time.Tick(3 * time.Second) {
		s.mu.Lock()
		need := s.chip == nil && !s.offline
		port, baud := s.port, s.baudRate
		s.mu.Unlock()
		if !need {
			continue
		}
		c, err := Open(port, baud)
		if err != nil {
			continue
		}
		s.mu.Lock()
		if s.chip == nil {
			s.chip = c
			s.adopt(c)
			log.Printf("chip found on %s at %d baud", c.Name(), c.Baud())
		} else {
			c.Close()
		}
		s.mu.Unlock()
	}
}

// adopt pulls the live state off a freshly opened chip. Caller holds the lock.
func (s *server) adopt(c *Chip) {
	s.lastErr = ""
	if id, ver, err := c.Identify(); err == nil {
		s.chipID, s.version, s.identOK = id, ver, id == ExpectedChipID
	}
	if vals, err := c.Channels(); err == nil && len(vals) == NumChannels {
		copy(s.values[:], vals)
	}
	if cfg, err := c.Read(RegCfg); err == nil {
		s.cfg = cfg
	}
	if lo, err := c.Read(RegChanEnL); err == nil {
		if hi, err := c.Read(RegChanEnH); err == nil {
			s.chanEn = uint16(lo) | uint16(hi)<<8
		}
	}
}

func (s *server) connect(port string, baud int) error {
	c, err := Open(port, baud)
	if err != nil {
		s.lastErr = err.Error()
		return err
	}
	if s.chip != nil {
		s.chip.Close()
	}
	s.chip = c
	s.baudRate = baud
	s.lastErr = ""

	id, ver, err := c.Identify()
	if err != nil {
		s.lastErr = "no answer from the chip: " + err.Error()
		s.identOK = false
		return nil
	}
	s.chipID, s.version, s.identOK = id, ver, id == ExpectedChipID
	if !s.identOK {
		s.lastErr = fmt.Sprintf("chip_id read back 0x%02X, expected 0x%02X", id, ExpectedChipID)
	}
	// pull the live state so the sliders start where the hardware is
	if vals, err := c.Channels(); err == nil && len(vals) == NumChannels {
		copy(s.values[:], vals)
	}
	if cfg, err := c.Read(RegCfg); err == nil {
		s.cfg = cfg
	}
	if lo, err := c.Read(RegChanEnL); err == nil {
		if hi, err := c.Read(RegChanEnH); err == nil {
			s.chanEn = uint16(lo) | uint16(hi)<<8
		}
	}
	return nil
}

//-----------------------------------------------------------------------------
// handlers
//-----------------------------------------------------------------------------

func (s *server) handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(indexHTML)
}

func writeJSON(w http.ResponseWriter, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func (s *server) handleStatus(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()

	type status struct {
		Connected bool      `json:"connected"`
		Offline   bool      `json:"offline"`
		Port      string    `json:"port"`
		Baud      int       `json:"baud"`
		ChipID    string    `json:"chipId"`
		Version   string    `json:"version"`
		IdentOK   bool      `json:"identOk"`
		Values    []int     `json:"values"`
		Pulses    []float64 `json:"pulses"`
		Cfg       int       `json:"cfg"`
		ChanEn    int       `json:"chanEn"`
		Error     string    `json:"error"`
	}

	st := status{
		Offline: s.offline,
		Baud:    s.baudRate,
		Cfg:     int(s.cfg),
		ChanEn:  int(s.chanEn),
		IdentOK: s.identOK,
		Error:   s.lastErr,
		ChipID:  fmt.Sprintf("0x%02X", s.chipID),
		Version: fmt.Sprintf("0x%02X", s.version),
	}
	if s.chip != nil {
		st.Connected = true
		st.Port = s.chip.Name()
	}
	for _, v := range s.values {
		st.Values = append(st.Values, int(v))
		st.Pulses = append(st.Pulses, PulseMicroseconds(v))
	}
	writeJSON(w, st)
}

func (s *server) handlePorts(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]interface{}{"ports": ListPorts()})
}

func (s *server) handleConnect(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Port string `json:"port"`
		Baud int    `json:"baud"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	if req.Baud == 0 {
		req.Baud = 115200
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.offline = false
	s.port = req.Port
	err := s.connect(req.Port, req.Baud)
	writeJSON(w, map[string]interface{}{"ok": err == nil, "error": s.lastErr})
}

func (s *server) handleChannels(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Values []int `json:"values"`
		Index  *int  `json:"index"`
		Value  *int  `json:"value"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	switch {
	case len(req.Values) == NumChannels:
		for i, v := range req.Values {
			s.values[i] = byte(clamp(v))
		}
		if s.chip != nil {
			// one block write, 19 bytes, so every servo moves together
			if err := s.chip.SetChannels(s.values[:]); err != nil {
				s.fail(w, err)
				return
			}
		}
	case req.Index != nil && req.Value != nil:
		i := *req.Index
		if i < 0 || i >= NumChannels {
			http.Error(w, "channel out of range", http.StatusBadRequest)
			return
		}
		s.values[i] = byte(clamp(*req.Value))
		if s.chip != nil {
			if err := s.chip.Write(byte(RegChan0+i), s.values[i]); err != nil {
				s.fail(w, err)
				return
			}
		}
	default:
		http.Error(w, "send either values[16] or index+value", http.StatusBadRequest)
		return
	}
	s.lastErr = ""
	writeJSON(w, map[string]bool{"ok": true})
}

func (s *server) handleCfg(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Enable    *bool `json:"enable"`
		ServoMode *bool `json:"servoMode"`
		UartTxEn  *bool `json:"uartTxEn"`
		Demo      *bool `json:"demo"`
		Invert    *bool `json:"invert"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	set := func(bit byte, on *bool) {
		if on == nil {
			return
		}
		if *on {
			s.cfg |= bit
		} else {
			s.cfg &^= bit
		}
	}
	set(CfgEnable, req.Enable)
	set(CfgServoMode, req.ServoMode)
	set(CfgUartTxEn, req.UartTxEn)
	set(CfgDemo, req.Demo)
	set(CfgInvert, req.Invert)

	if s.chip != nil {
		if err := s.chip.Write(RegCfg, s.cfg); err != nil {
			s.fail(w, err)
			return
		}
	}
	writeJSON(w, map[string]interface{}{"ok": true, "cfg": s.cfg})
}

func (s *server) handleCenter(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.values {
		s.values[i] = 0x80
	}
	if s.chip != nil {
		if err := s.chip.CenterAll(); err != nil {
			s.fail(w, err)
			return
		}
	}
	writeJSON(w, map[string]bool{"ok": true})
}

func (s *server) handleChanEn(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Mask int `json:"mask"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.chanEn = uint16(req.Mask)
	if s.chip != nil {
		if err := s.chip.SetChanEnable(s.chanEn); err != nil {
			s.fail(w, err)
			return
		}
	}
	writeJSON(w, map[string]interface{}{"ok": true, "chanEn": s.chanEn})
}

func (s *server) fail(w http.ResponseWriter, err error) {
	s.lastErr = err.Error()
	writeJSON(w, map[string]interface{}{"ok": false, "error": s.lastErr})
}

func clamp(v int) int {
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return v
}
