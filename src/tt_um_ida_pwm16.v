/*
 * tt_um_ida_pwm16 - 16 channel PWM / RC servo controller with a UART register interface
 *
 * IDA Embedded open source chip design workshop, Tiny Tapeout IHP shuttle.
 *
 *   ui[0]  demo           strap high: run the built in sweep, no host needed
 *   ui[1]  center         rising edge: reload all 16 channels with 0x80
 *   ui[2]  clk_sel        0 = 10 MHz defaults, 1 = 50 MHz defaults
 *   ui[3]  uart_rx        serial in, 115200 8N1
 *   ui[7:4] unused
 *
 *   uo[3:0] pwm ch0 .. ch3
 *   uo[4]   uart_tx        serial out  (or pwm ch15 when ctrl.uart_tx_en = 0)
 *   uo[7:5] pwm ch4 .. ch6
 *   uio[7:0] pwm ch7 .. ch14      (always driven, uio_oe = 0xFF)
 *
 * ui[3] RX / uo[4] TX is option 1 of Tiny Tapeout's recommended UART pinout
 * (https://tinytapeout.com/specs/pinouts/).  On the demo board those land on
 * RP2350 GPIO20 = UART1.tx and GPIO37 = UART1.rx, so both directions sit on a
 * real hardware UART rather than needing PIO.  It costs nothing: the UART takes
 * one of the 16 output pins wherever it sits, so 15 channels are pinned either
 * way and ch15 muxes onto the TX pin.
 *
 * Copyright (c) 2026 Jorgen Kragh Jakobsen
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ida_pwm16 #(
    // Built in divider defaults.  Selected by the ui[2] strap so one mask
    // works on both of the clock rates the demo board is normally set to.
    // A non zero ctrl.clk_div_* register always wins over these.
    parameter [15:0] DIV_COM_A = 16'd87,    //  10 MHz / 115200 baud
    parameter [15:0] DIV_PWM_A = 16'd39,    //  10 MHz -> 3.90 us tick
    parameter [15:0] DIV_COM_B = 16'd434,   //  50 MHz / 115200 baud
    parameter [15:0] DIV_PWM_B = 16'd195    //  50 MHz -> 3.90 us tick
) (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    wire resetb = rst_n;

    //=========================================================================
    // Strap inputs.  ui[3] is the UART RX and is synchronised inside uart_if.
    //=========================================================================
    reg [2:0] strap_s1, strap_s2;
    always @(posedge clk) begin
        if (!resetb) begin
            strap_s1 <= 3'b000;
            strap_s2 <= 3'b000;
        end else begin
            strap_s1 <= ui_in[2:0];
            strap_s2 <= strap_s1;
        end
    end
    wire pin_demo   = strap_s2[0];   // ui[0]
    wire pin_center = strap_s2[1];   // ui[1]
    wire pin_clksel = strap_s2[2];   // ui[2]

    // rising edge on the centre strap gives a one clock preset pulse
    reg pin_center_d;
    always @(posedge clk) begin
        if (!resetb) pin_center_d <= 1'b0;
        else         pin_center_d <= pin_center;
    end
    wire pin_center_pulse = pin_center & ~pin_center_d;

    //=========================================================================
    // Register bank wiring
    //=========================================================================
    wire [7:0] rb_address;
    wire [7:0] rb_wdata;
    wire [7:0] rb_rdata;
    wire       rb_reg_en;
    wire       rb_write_en;

    wire       ctrl__enable;
    wire       ctrl__servo_mode;
    wire       ctrl__uart_tx_en;
    wire       ctrl__demo_en;
    wire       ctrl__invert;
    wire       ctrl__center_all;
    wire [7:0] ctrl__clk_div_com_l, ctrl__clk_div_com_h;
    wire [7:0] ctrl__clk_div_pwm_l, ctrl__clk_div_pwm_h;
    wire [7:0] ctrl__chan_en_l,     ctrl__chan_en_h;
    wire [7:0] ctrl__scratch;

    wire [7:0] pwm__ch0,  pwm__ch1,  pwm__ch2,  pwm__ch3;
    wire [7:0] pwm__ch4,  pwm__ch5,  pwm__ch6,  pwm__ch7;
    wire [7:0] pwm__ch8,  pwm__ch9,  pwm__ch10, pwm__ch11;
    wire [7:0] pwm__ch12, pwm__ch13, pwm__ch14, pwm__ch15;

    wire frame_tick;
    wire pwm_preset = ctrl__center_all | pin_center_pulse;

    rb_pwm16 #(.ADR_BITS(8)) rb_inst (
        .clk                 (clk),
        .resetb              (resetb),
        .address             (rb_address),
        .data_write_in       (rb_wdata),
        .data_read_out       (rb_rdata),
        .reg_en              (rb_reg_en),
        .write_en            (rb_write_en),
        .pwm_preset          (pwm_preset),

        .ctrl__chip_id       (8'h16),          // 16 channels
        .ctrl__version       (8'h01),
        .ctrl__enable        (ctrl__enable),
        .ctrl__servo_mode    (ctrl__servo_mode),
        .ctrl__uart_tx_en    (ctrl__uart_tx_en),
        .ctrl__demo_en       (ctrl__demo_en),
        .ctrl__invert        (ctrl__invert),
        .ctrl__center_all    (ctrl__center_all),
        .ctrl__clk_div_com_l (ctrl__clk_div_com_l),
        .ctrl__clk_div_com_h (ctrl__clk_div_com_h),
        .ctrl__clk_div_pwm_l (ctrl__clk_div_pwm_l),
        .ctrl__clk_div_pwm_h (ctrl__clk_div_pwm_h),
        .ctrl__chan_en_l     (ctrl__chan_en_l),
        .ctrl__chan_en_h     (ctrl__chan_en_h),
        .ctrl__scratch       (ctrl__scratch),
        .ctrl__pin_demo      (pin_demo),
        .ctrl__pin_clksel    (pin_clksel),
        .ctrl__pin_center    (pin_center),
        .ctrl__frame_tick    (frame_tick),

        .pwm__ch0 (pwm__ch0),  .pwm__ch1 (pwm__ch1),
        .pwm__ch2 (pwm__ch2),  .pwm__ch3 (pwm__ch3),
        .pwm__ch4 (pwm__ch4),  .pwm__ch5 (pwm__ch5),
        .pwm__ch6 (pwm__ch6),  .pwm__ch7 (pwm__ch7),
        .pwm__ch8 (pwm__ch8),  .pwm__ch9 (pwm__ch9),
        .pwm__ch10(pwm__ch10), .pwm__ch11(pwm__ch11),
        .pwm__ch12(pwm__ch12), .pwm__ch13(pwm__ch13),
        .pwm__ch14(pwm__ch14), .pwm__ch15(pwm__ch15)
    );

    //=========================================================================
    // Clock dividers: register value wins, zero falls back to the strapped
    // built in default.  That way the chip always answers at 115200 baud out
    // of reset, whichever of the two clock rates the board is running.
    //=========================================================================
    wire [15:0] div_com_reg = {ctrl__clk_div_com_h, ctrl__clk_div_com_l};
    wire [15:0] div_pwm_reg = {ctrl__clk_div_pwm_h, ctrl__clk_div_pwm_l};

    wire [15:0] div_com = (div_com_reg != 16'd0) ? div_com_reg
                        : (pin_clksel ? DIV_COM_B : DIV_COM_A);
    wire [15:0] div_pwm = (div_pwm_reg != 16'd0) ? div_pwm_reg
                        : (pin_clksel ? DIV_PWM_B : DIV_PWM_A);

    //=========================================================================
    // UART register interface
    //=========================================================================
    wire uart_tx;
    wire uart_busy;

    uart_if uart_inst (
        .clk                (clk),
        .resetb             (resetb),
        .bit_div            (div_com),
        .uart_rx            (ui_in[3]),
        .uart_tx            (uart_tx),
        .address            (rb_address),
        .data_write_to_reg  (rb_wdata),
        .data_read_from_reg (rb_rdata),
        .reg_en             (rb_reg_en),
        .write_en           (rb_write_en),
        .busy               (uart_busy)
    );

    //=========================================================================
    // PWM engine
    //=========================================================================
    wire [127:0] duty = {pwm__ch15, pwm__ch14, pwm__ch13, pwm__ch12,
                         pwm__ch11, pwm__ch10, pwm__ch9,  pwm__ch8,
                         pwm__ch7,  pwm__ch6,  pwm__ch5,  pwm__ch4,
                         pwm__ch3,  pwm__ch2,  pwm__ch1,  pwm__ch0};

    wire [15:0] pwm_out;

    pwm16 pwm_inst (
        .clk        (clk),
        .resetb     (resetb),
        .div        (div_pwm),
        .servo_mode (ctrl__servo_mode),
        .enable     (ctrl__enable),
        .invert     (ctrl__invert),
        .demo       (ctrl__demo_en | pin_demo),
        .chan_en    ({ctrl__chan_en_h, ctrl__chan_en_l}),
        .duty       (duty),
        .pwm_out    (pwm_out),
        .frame_tick (frame_tick)
    );

    //=========================================================================
    // Pin mapping
    //=========================================================================
    assign uo_out[3:0] = pwm_out[3:0];      // ch0 .. ch3
    assign uo_out[4]   = ctrl__uart_tx_en ? uart_tx : pwm_out[15];
    assign uo_out[7:5] = pwm_out[6:4];      // ch4 .. ch6
    assign uio_out     = pwm_out[14:7];     // ch7 .. ch14
    assign uio_oe      = 8'hFF;             // all bidir pins drive out

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, ui_in[7:4], uio_in, ctrl__scratch, uart_busy, 1'b0};

endmodule

`default_nettype wire
