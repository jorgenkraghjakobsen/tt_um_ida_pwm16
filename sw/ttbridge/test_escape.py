"""Replicate the bridge's host->project path and check it stays transparent."""
ESCAPE = b"\x00\xffTTBRK!"
IDLE_MS, HOLD_MS = 250, 60

def feed(stream):
    """stream: list of (gap_ms_before_byte, byte). Returns (forwarded, escaped)."""
    out = bytearray(); held = b""; held_at = 0; last_rx = -10**6; now = 0
    for gap, b in stream:
        now += gap
        # flush a stalled partial match, as the main loop does between polls
        if held and now - held_at > HOLD_MS:
            out += held; held = b""
        idle = now - last_rx >= IDLE_MS
        last_rx = now
        if held:
            if ESCAPE.startswith(held + b):
                held += b; held_at = now
                if held == ESCAPE:
                    return bytes(out), True
                continue
            out += held; held = b""
        elif idle and b == ESCAPE[0:1]:
            held = b; held_at = now; continue
        out += b
    if held: out += held
    return bytes(out), False

def burst(data, gap_before=1000):
    """A command burst: big gap, then bytes back to back."""
    return [(gap_before, data[0:1])] + [(1, data[i:i+1]) for i in range(1, len(data))]

fails = 0
def check(name, stream, want_out, want_esc):
    global fails
    got_out, got_esc = feed(stream)
    ok = got_out == want_out and got_esc == want_esc
    print(("  PASS  " if ok else "  FAIL  ") + name)
    if not ok:
        print(f"        got  out={got_out!r} esc={got_esc}")
        print(f"        want out={want_out!r} esc={want_esc}")
        fails += 1

print("transparency of real register traffic:")
check("single write  W 0x10 0x80", burst(b"W\x10\x80"), b"W\x10\x80", False)
check("single read   R 0x00",      burst(b"R\x00"),     b"R\x00",     False)
check("write of 0x00 as data",     burst(b"W\x10\x00"), b"W\x10\x00", False)
check("block write, all 16 ch",
      burst(b"B\x10\x10" + bytes(range(16))),
      b"B\x10\x10" + bytes(range(16)), False)
check("block write of all zeroes",
      burst(b"B\x10\x10" + b"\x00"*16),
      b"B\x10\x10" + b"\x00"*16, False)
check("block write that CONTAINS the escape bytes mid-burst",
      burst(b"B\x10\x08" + ESCAPE),
      b"B\x10\x08" + ESCAPE, False)
check("back to back bursts, no idle between",
      burst(b"W\x10\x80") + [(1, b) for b in [bytes([c]) for c in b"W\x11\x81"]],
      b"W\x10\x80W\x11\x81", False)

print("\nescape behaviour:")
check("escape after idle", burst(ESCAPE), b"", True)
check("escape without idle is just data",
      burst(b"W\x10\x80") + [(1, ESCAPE[i:i+1]) for i in range(len(ESCAPE))],
      b"W\x10\x80" + ESCAPE, False)
check("partial escape then other data is forwarded intact",
      burst(b"\x00\xffTTX"), b"\x00\xffTTX", False)
check("lone 0x00 after idle, then a stall, is forwarded",
      [(1000, b"\x00"), (500, b"W")], b"\x00W", False)

print("\nFAILURES:", fails)
raise SystemExit(1 if fails else 0)
