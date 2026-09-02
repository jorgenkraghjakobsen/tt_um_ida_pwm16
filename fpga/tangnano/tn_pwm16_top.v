// Tang Nano 9K board wrapper for tt_um_ida_pwm16
//
// This is a *test implementation*: the exact same RTL that goes to the IHP
// shuttle, wrapped so it can be built with yosys/nextpnr and poked with ucom
// long before any silicon exists.  Nothing inside tt_um_ida_pwm16 changes, only
// the divider parameters (27 MHz here instead of 10 MHz) and the pin mapping.
//
//   ch0  .. ch10  -> header pins, hook your servos here
//   ch11 .. ch14  -> LED5..LED2, visible without a scope
//   ch15          -> not routed on this board (uo[0] is the UART TX)
//
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module tn_pwm16_top (
    input  wire        clk,             // 27 MHz crystal, pin 52
    input  wire        btn_s1_resetb,   // S1: pulls LOW when pressed on the 9K
    input  wire        btn_s2,          // S2: demo sweep strap
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire [10:0] pwm_hdr,         // ch0 .. ch10
    output wire [5:0]  led              // active LOW
);

    // 27 MHz: 27e6/115200 = 234.4 -> 234,  1 ms/256 = 3.90625 us -> 105.5 -> 105
    localparam [15:0] DIV_COM_27M = 16'd234;
    localparam [15:0] DIV_PWM_27M = 16'd105;

    //-------------------------------------------------------------------------
    // Power on reset.  The ASIC gets rst_n from the harness; on the FPGA nobody
    // presses S1 after configuration, so make our own reset pulse.
    //-------------------------------------------------------------------------
    reg [7:0] por = 8'd0;
    always @(posedge clk) begin
        if (!por[7]) por <= por + 8'd1;
    end
    wire rst_n = por[7] & btn_s1_resetb;

    // heartbeat, proves the bitstream is alive
    reg [24:0] hb = 25'd0;
    always @(posedge clk) hb <= hb + 25'd1;

    //-------------------------------------------------------------------------
    // The design under test, unmodified
    //-------------------------------------------------------------------------
    wire [7:0] ui_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    assign ui_in[0]   = ~btn_s2;      // S2 pulls low when pressed -> demo on
    assign ui_in[1]   = 1'b0;         // centre strap, unused on this board
    assign ui_in[2]   = 1'b0;         // both divider sets are the 27 MHz ones
    assign ui_in[3]   = uart_rx;
    assign ui_in[7:4] = 4'b0000;

    tt_um_ida_pwm16 #(
        .DIV_COM_A (DIV_COM_27M),
        .DIV_PWM_A (DIV_PWM_27M),
        .DIV_COM_B (DIV_COM_27M),
        .DIV_PWM_B (DIV_PWM_27M)
    ) dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (8'h00),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (1'b1),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    //-------------------------------------------------------------------------
    // Pin mapping
    //-------------------------------------------------------------------------
    assign uart_tx = uo_out[4];

    // ch0..ch3 on uo[3:0], ch4..ch6 on uo[7:5], ch7..ch14 on uio[7:0]
    assign pwm_hdr = {uio_out[3:0], uo_out[7:5], uo_out[3:0]};  // ch10..ch0

    assign led[5] = ~uio_out[7];    // ch14
    assign led[4] = ~uio_out[6];    // ch13
    assign led[3] = ~uio_out[5];    // ch12
    assign led[2] = ~uio_out[4];    // ch11
    assign led[1] =  uart_rx;       // lights up on serial traffic
    assign led[0] = ~hb[24];        // ~0.8 Hz heartbeat

    wire _unused = &{uio_oe, 1'b0};

endmodule

`default_nettype wire
