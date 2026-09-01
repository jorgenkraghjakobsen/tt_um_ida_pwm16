// 16 channel PWM / RC servo generator
//
// One shared timebase, sixteen 8 bit comparators.  That is the whole trick:
// the expensive part of a servo controller (the 20 ms frame counter) is shared,
// each channel only pays for a comparator and an output flop.
//
//                 |<------------------ 20 ms frame ------------------>|
//   servo mode    |<-- 1 ms -->|<-- 0..1 ms -->|                      |
//                  ____________________________
//   pwm_out[n] ___|                            |______________________
//                 always high    position       always low
//
// Timebase: one "tick" every `div` clocks.  A tick is meant to be 1 ms / 256 =
// 3.90625 us, so a frame is 5120 ticks = 20 ms and the position byte spans
// exactly 1 ms.  5120 = 20 * 256, so the low 8 bits of the frame counter also
// give a clean 256 tick period for plain PWM mode.
//
//   servo mode (servo_mode = 1)   0x00 -> 1.0 ms,  0x80 -> 1.5 ms,  0xFF -> 2.0 ms
//   pwm mode   (servo_mode = 0)   duty = value / 256, period = 256 ticks
//
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module pwm16 (
    input  wire         clk,
    input  wire         resetb,

    input  wire [15:0]  div,          // clocks per tick, 0 is treated as 1
    input  wire         servo_mode,   // 1 = RC servo framing, 0 = plain PWM
    input  wire         enable,       // global output enable
    input  wire         invert,       // invert every output pin
    input  wire         demo,         // ignore duty[], run the sweep generator
    input  wire [15:0]  chan_en,      // per channel enable
    input  wire [127:0] duty,         // 16 x 8 bit, channel n is duty[8n+7:8n]

    output reg  [15:0]  pwm_out,
    output wire         frame_tick    // high during the first ms of every frame
);

    localparam [12:0] FRAME_LAST = 13'd5119;   // 5120 ticks = 20 ms

    //=========================================================================
    // Tick prescaler
    //=========================================================================
    reg  [15:0] pre;
    wire [15:0] div_eff = (div == 16'd0) ? 16'd1 : div;
    wire        tick    = (pre >= div_eff - 16'd1);

    always @(posedge clk) begin
        if (!resetb)     pre <= 16'd0;
        else if (tick)   pre <= 16'd0;
        else             pre <= pre + 16'd1;
    end

    //=========================================================================
    // Frame counter
    //=========================================================================
    reg [12:0] fc;
    wire frame_end = tick && (fc == FRAME_LAST);

    always @(posedge clk) begin
        if (!resetb)        fc <= 13'd0;
        else if (frame_end) fc <= 13'd0;
        else if (tick)      fc <= fc + 13'd1;
    end

    wire       in_first_ms = (fc[12:8] == 5'd0);   // 0.000 .. 1.000 ms
    wire       in_window   = (fc[12:8] == 5'd1);   // 1.000 .. 2.000 ms
    wire [7:0] fc_lo       = fc[7:0];

    assign frame_tick = in_first_ms;

    //=========================================================================
    // Demo sweep generator - a slow triangle, updated once per frame.
    // Even channels follow it, odd channels mirror it, so the board does
    // something obviously alive without a single UART byte.
    //=========================================================================
    reg [7:0] sweep;
    reg       sweep_up;

    always @(posedge clk) begin
        if (!resetb) begin
            sweep    <= 8'h80;
            sweep_up <= 1'b1;
        end else if (frame_end) begin
            if (sweep_up) begin
                if (sweep >= 8'hF0) sweep_up <= 1'b0;
                else                sweep    <= sweep + 8'd4;
            end else begin
                if (sweep <= 8'h10) sweep_up <= 1'b1;
                else                sweep    <= sweep - 8'd4;
            end
        end
    end

    //=========================================================================
    // The 16 channels.  Each one is an 8 bit comparator against the shared
    // timebase, and one output flop so the pin never shows a comparator glitch.
    //=========================================================================
    wire [15:0] raw;

    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : channel
            // demo mode mirrors the odd channels against the even ones
            wire [7:0] value = demo ? (((g % 2) == 1) ? ~sweep : sweep)
                                    : duty[8*g +: 8];

            assign raw[g] = servo_mode
                          ? (in_first_ms | (in_window & (fc_lo < value)))
                          : (fc_lo < value);
        end
    endgenerate

    always @(posedge clk) begin
        if (!resetb) pwm_out <= 16'h0000;
        else         pwm_out <= ({16{enable}} & chan_en & raw) ^ {16{invert}};
    end

endmodule

`default_nettype wire
