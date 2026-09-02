// Register bank - Verilog-2005
// Auto generated from pwm16 version 1 - DO NOT EDIT
// Generator: regmap/register_bank.go   (go run register_bank.go -lang v)
// Written by Jorgen Kragh Jakobsen, all rights reserved
//-----------------------------------------------------------------------------

`default_nettype none

module rb_pwm16 #(
    parameter ADR_BITS = 8
) (
    input  wire                 clk,
    input  wire                 resetb,
    input  wire [ADR_BITS-1:0]  address,
    input  wire [7:0]           data_write_in,
    output reg  [7:0]           data_read_out,
    input  wire                 reg_en,
    input  wire                 write_en,

    // --- pwm: pulse high to reload every register with its reset value
    input  wire                 pwm_preset,

    // --- Section ctrl @ 0x00 : Global control, clocking and status
    input  wire [7:0]  ctrl__chip_id           ,  // Chip id, reads 0x16
    input  wire [7:0]  ctrl__version           ,  // RTL version
    output wire        ctrl__enable            ,  // Global PWM output enable
    output wire        ctrl__servo_mode        ,  // 1=RC servo pulses, 0=plain PWM
    output wire        ctrl__uart_tx_en        ,  // 1=uo[4] is uart_tx, 0=uo[4] is ch15
    output wire        ctrl__demo_en           ,  // Run the built in sweep generator
    output wire        ctrl__invert            ,  // Invert all PWM outputs
    output wire        ctrl__center_all        ,  // Write 1: all channels back to 50%
    output wire [7:0]  ctrl__clk_div_com_l     ,  // UART bit timer, low byte
    output wire [7:0]  ctrl__clk_div_com_h     ,  // UART bit timer, high byte
    output wire [7:0]  ctrl__clk_div_pwm_l     ,  // PWM tick divider, low byte
    output wire [7:0]  ctrl__clk_div_pwm_h     ,  // PWM tick divider, high byte
    output wire [7:0]  ctrl__chan_en_l         ,  // Per channel enable, ch0-ch7
    output wire [7:0]  ctrl__chan_en_h         ,  // Per channel enable, ch8-ch15
    output wire [7:0]  ctrl__scratch           ,  // Scratch register
    input  wire        ctrl__pin_demo          ,  // State of ui[0] demo pin
    input  wire        ctrl__pin_clksel        ,  // State of ui[2] clock select pin
    input  wire        ctrl__pin_center        ,  // State of ui[1] centre pin
    input  wire        ctrl__frame_tick        ,  // High during the first ms of a frame

    // --- Section pwm @ 0x10 : The 16 channel position registers
    output wire [7:0]  pwm__ch0                ,  // Channel 0 position
    output wire [7:0]  pwm__ch1                ,  // Channel 1 position
    output wire [7:0]  pwm__ch2                ,  // Channel 2 position
    output wire [7:0]  pwm__ch3                ,  // Channel 3 position
    output wire [7:0]  pwm__ch4                ,  // Channel 4 position
    output wire [7:0]  pwm__ch5                ,  // Channel 5 position
    output wire [7:0]  pwm__ch6                ,  // Channel 6 position
    output wire [7:0]  pwm__ch7                ,  // Channel 7 position
    output wire [7:0]  pwm__ch8                ,  // Channel 8 position
    output wire [7:0]  pwm__ch9                ,  // Channel 9 position
    output wire [7:0]  pwm__ch10               ,  // Channel 10 position
    output wire [7:0]  pwm__ch11               ,  // Channel 11 position
    output wire [7:0]  pwm__ch12               ,  // Channel 12 position
    output wire [7:0]  pwm__ch13               ,  // Channel 13 position
    output wire [7:0]  pwm__ch14               ,  // Channel 14 position
    output wire [7:0]  pwm__ch15                  // Channel 15 position
);

//----------------------------------------------------------- storage ---

    // Section: ctrl   offset 0x00   size 16
    reg         r_ctrl__enable;            // Global PWM output enable
    reg         r_ctrl__servo_mode;        // 1=RC servo pulses, 0=plain PWM
    reg         r_ctrl__uart_tx_en;        // 1=uo[4] is uart_tx, 0=uo[4] is ch15
    reg         r_ctrl__demo_en;           // Run the built in sweep generator
    reg         r_ctrl__invert;            // Invert all PWM outputs
    reg         r_ctrl__center_all;        // Write 1: all channels back to 50%
    reg  [7:0]  r_ctrl__clk_div_com_l;     // UART bit timer, low byte
    reg  [7:0]  r_ctrl__clk_div_com_h;     // UART bit timer, high byte
    reg  [7:0]  r_ctrl__clk_div_pwm_l;     // PWM tick divider, low byte
    reg  [7:0]  r_ctrl__clk_div_pwm_h;     // PWM tick divider, high byte
    reg  [7:0]  r_ctrl__chan_en_l;         // Per channel enable, ch0-ch7
    reg  [7:0]  r_ctrl__chan_en_h;         // Per channel enable, ch8-ch15
    reg  [7:0]  r_ctrl__scratch;           // Scratch register

    // Section: pwm   offset 0x10   size 16
    reg  [7:0]  r_pwm__ch0;                // Channel 0 position
    reg  [7:0]  r_pwm__ch1;                // Channel 1 position
    reg  [7:0]  r_pwm__ch2;                // Channel 2 position
    reg  [7:0]  r_pwm__ch3;                // Channel 3 position
    reg  [7:0]  r_pwm__ch4;                // Channel 4 position
    reg  [7:0]  r_pwm__ch5;                // Channel 5 position
    reg  [7:0]  r_pwm__ch6;                // Channel 6 position
    reg  [7:0]  r_pwm__ch7;                // Channel 7 position
    reg  [7:0]  r_pwm__ch8;                // Channel 8 position
    reg  [7:0]  r_pwm__ch9;                // Channel 9 position
    reg  [7:0]  r_pwm__ch10;               // Channel 10 position
    reg  [7:0]  r_pwm__ch11;               // Channel 11 position
    reg  [7:0]  r_pwm__ch12;               // Channel 12 position
    reg  [7:0]  r_pwm__ch13;               // Channel 13 position
    reg  [7:0]  r_pwm__ch14;               // Channel 14 position
    reg  [7:0]  r_pwm__ch15;               // Channel 15 position

//------------------------------------------ write, reset and preset ---
    always @(posedge clk) begin
        if (!resetb) begin
            // ctrl
            r_ctrl__enable             <= 1'h1;
            r_ctrl__servo_mode         <= 1'h1;
            r_ctrl__uart_tx_en         <= 1'h1;
            r_ctrl__demo_en            <= 1'h0;
            r_ctrl__invert             <= 1'h0;
            r_ctrl__center_all         <= 1'h0;
            r_ctrl__clk_div_com_l      <= 8'h00;
            r_ctrl__clk_div_com_h      <= 8'h00;
            r_ctrl__clk_div_pwm_l      <= 8'h00;
            r_ctrl__clk_div_pwm_h      <= 8'h00;
            r_ctrl__chan_en_l          <= 8'hff;
            r_ctrl__chan_en_h          <= 8'hff;
            r_ctrl__scratch            <= 8'h00;
            // pwm
            r_pwm__ch0                 <= 8'h80;
            r_pwm__ch1                 <= 8'h80;
            r_pwm__ch2                 <= 8'h80;
            r_pwm__ch3                 <= 8'h80;
            r_pwm__ch4                 <= 8'h80;
            r_pwm__ch5                 <= 8'h80;
            r_pwm__ch6                 <= 8'h80;
            r_pwm__ch7                 <= 8'h80;
            r_pwm__ch8                 <= 8'h80;
            r_pwm__ch9                 <= 8'h80;
            r_pwm__ch10                <= 8'h80;
            r_pwm__ch11                <= 8'h80;
            r_pwm__ch12                <= 8'h80;
            r_pwm__ch13                <= 8'h80;
            r_pwm__ch14                <= 8'h80;
            r_pwm__ch15                <= 8'h80;
        end else begin
            // self clearing strobes
            r_ctrl__center_all         <= 1'h0;

            // section preset: reload reset values
            if (pwm_preset) begin
                r_pwm__ch0                 <= 8'h80;
                r_pwm__ch1                 <= 8'h80;
                r_pwm__ch2                 <= 8'h80;
                r_pwm__ch3                 <= 8'h80;
                r_pwm__ch4                 <= 8'h80;
                r_pwm__ch5                 <= 8'h80;
                r_pwm__ch6                 <= 8'h80;
                r_pwm__ch7                 <= 8'h80;
                r_pwm__ch8                 <= 8'h80;
                r_pwm__ch9                 <= 8'h80;
                r_pwm__ch10                <= 8'h80;
                r_pwm__ch11                <= 8'h80;
                r_pwm__ch12                <= 8'h80;
                r_pwm__ch13                <= 8'h80;
                r_pwm__ch14                <= 8'h80;
                r_pwm__ch15                <= 8'h80;
            end

            if (write_en) begin
                case (address)
                    8'h02: begin
                        r_ctrl__enable             <= data_write_in[0];
                        r_ctrl__servo_mode         <= data_write_in[1];
                        r_ctrl__uart_tx_en         <= data_write_in[2];
                        r_ctrl__demo_en            <= data_write_in[3];
                        r_ctrl__invert             <= data_write_in[4];
                    end
                    8'h03: r_ctrl__center_all         <= data_write_in[0];
                    8'h04: r_ctrl__clk_div_com_l      <= data_write_in[7:0];
                    8'h05: r_ctrl__clk_div_com_h      <= data_write_in[7:0];
                    8'h06: r_ctrl__clk_div_pwm_l      <= data_write_in[7:0];
                    8'h07: r_ctrl__clk_div_pwm_h      <= data_write_in[7:0];
                    8'h08: r_ctrl__chan_en_l          <= data_write_in[7:0];
                    8'h09: r_ctrl__chan_en_h          <= data_write_in[7:0];
                    8'h0A: r_ctrl__scratch            <= data_write_in[7:0];
                    8'h10: r_pwm__ch0                 <= data_write_in[7:0];
                    8'h11: r_pwm__ch1                 <= data_write_in[7:0];
                    8'h12: r_pwm__ch2                 <= data_write_in[7:0];
                    8'h13: r_pwm__ch3                 <= data_write_in[7:0];
                    8'h14: r_pwm__ch4                 <= data_write_in[7:0];
                    8'h15: r_pwm__ch5                 <= data_write_in[7:0];
                    8'h16: r_pwm__ch6                 <= data_write_in[7:0];
                    8'h17: r_pwm__ch7                 <= data_write_in[7:0];
                    8'h18: r_pwm__ch8                 <= data_write_in[7:0];
                    8'h19: r_pwm__ch9                 <= data_write_in[7:0];
                    8'h1A: r_pwm__ch10                <= data_write_in[7:0];
                    8'h1B: r_pwm__ch11                <= data_write_in[7:0];
                    8'h1C: r_pwm__ch12                <= data_write_in[7:0];
                    8'h1D: r_pwm__ch13                <= data_write_in[7:0];
                    8'h1E: r_pwm__ch14                <= data_write_in[7:0];
                    8'h1F: r_pwm__ch15                <= data_write_in[7:0];
                    default: ;
                endcase
            end
        end
    end

//---------------------------------------------------------- readback ---
    always @(posedge clk) begin
        if (!resetb) begin
            data_read_out <= 8'h00;
        end else begin
            data_read_out <= 8'h00;
            case (address)
                8'h00: data_read_out[7:0]   <= ctrl__chip_id;
                8'h01: data_read_out[7:0]   <= ctrl__version;
                8'h02: begin
                    data_read_out[0]     <= r_ctrl__enable;
                    data_read_out[1]     <= r_ctrl__servo_mode;
                    data_read_out[2]     <= r_ctrl__uart_tx_en;
                    data_read_out[3]     <= r_ctrl__demo_en;
                    data_read_out[4]     <= r_ctrl__invert;
                end
                8'h04: data_read_out[7:0]   <= r_ctrl__clk_div_com_l;
                8'h05: data_read_out[7:0]   <= r_ctrl__clk_div_com_h;
                8'h06: data_read_out[7:0]   <= r_ctrl__clk_div_pwm_l;
                8'h07: data_read_out[7:0]   <= r_ctrl__clk_div_pwm_h;
                8'h08: data_read_out[7:0]   <= r_ctrl__chan_en_l;
                8'h09: data_read_out[7:0]   <= r_ctrl__chan_en_h;
                8'h0A: data_read_out[7:0]   <= r_ctrl__scratch;
                8'h0B: begin
                    data_read_out[0]     <= ctrl__pin_demo;
                    data_read_out[1]     <= ctrl__pin_clksel;
                    data_read_out[2]     <= ctrl__pin_center;
                    data_read_out[3]     <= ctrl__frame_tick;
                end
                8'h10: data_read_out[7:0]   <= r_pwm__ch0;
                8'h11: data_read_out[7:0]   <= r_pwm__ch1;
                8'h12: data_read_out[7:0]   <= r_pwm__ch2;
                8'h13: data_read_out[7:0]   <= r_pwm__ch3;
                8'h14: data_read_out[7:0]   <= r_pwm__ch4;
                8'h15: data_read_out[7:0]   <= r_pwm__ch5;
                8'h16: data_read_out[7:0]   <= r_pwm__ch6;
                8'h17: data_read_out[7:0]   <= r_pwm__ch7;
                8'h18: data_read_out[7:0]   <= r_pwm__ch8;
                8'h19: data_read_out[7:0]   <= r_pwm__ch9;
                8'h1A: data_read_out[7:0]   <= r_pwm__ch10;
                8'h1B: data_read_out[7:0]   <= r_pwm__ch11;
                8'h1C: data_read_out[7:0]   <= r_pwm__ch12;
                8'h1D: data_read_out[7:0]   <= r_pwm__ch13;
                8'h1E: data_read_out[7:0]   <= r_pwm__ch14;
                8'h1F: data_read_out[7:0]   <= r_pwm__ch15;
                default: data_read_out <= 8'h00;
            endcase
        end
    end

//----------------------------------------------------------- outputs ---
    assign ctrl__enable               = r_ctrl__enable;
    assign ctrl__servo_mode           = r_ctrl__servo_mode;
    assign ctrl__uart_tx_en           = r_ctrl__uart_tx_en;
    assign ctrl__demo_en              = r_ctrl__demo_en;
    assign ctrl__invert               = r_ctrl__invert;
    assign ctrl__center_all           = r_ctrl__center_all;
    assign ctrl__clk_div_com_l        = r_ctrl__clk_div_com_l;
    assign ctrl__clk_div_com_h        = r_ctrl__clk_div_com_h;
    assign ctrl__clk_div_pwm_l        = r_ctrl__clk_div_pwm_l;
    assign ctrl__clk_div_pwm_h        = r_ctrl__clk_div_pwm_h;
    assign ctrl__chan_en_l            = r_ctrl__chan_en_l;
    assign ctrl__chan_en_h            = r_ctrl__chan_en_h;
    assign ctrl__scratch              = r_ctrl__scratch;
    assign pwm__ch0                   = r_pwm__ch0;
    assign pwm__ch1                   = r_pwm__ch1;
    assign pwm__ch2                   = r_pwm__ch2;
    assign pwm__ch3                   = r_pwm__ch3;
    assign pwm__ch4                   = r_pwm__ch4;
    assign pwm__ch5                   = r_pwm__ch5;
    assign pwm__ch6                   = r_pwm__ch6;
    assign pwm__ch7                   = r_pwm__ch7;
    assign pwm__ch8                   = r_pwm__ch8;
    assign pwm__ch9                   = r_pwm__ch9;
    assign pwm__ch10                  = r_pwm__ch10;
    assign pwm__ch11                  = r_pwm__ch11;
    assign pwm__ch12                  = r_pwm__ch12;
    assign pwm__ch13                  = r_pwm__ch13;
    assign pwm__ch14                  = r_pwm__ch14;
    assign pwm__ch15                  = r_pwm__ch15;

    wire _unused_rb = &{1'b0, reg_en, 1'b0};

endmodule
`default_nettype wire
