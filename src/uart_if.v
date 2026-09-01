// UART register interface
//
// Derived from jorgenkraghjakobsen/fpga_template  digital/uart_if/uart_if.v
//
// Same wire protocol, same register bank handshake, but reworked for silicon:
//
//   * the 256 byte TX queue (2048 flops!) is gone.  Block reads now stream one
//     byte at a time straight out of the register bank, so the whole TX path is
//     a single shift register.
//   * the baud rate divider is a runtime input instead of a parameter, driven
//     from ctrl.clk_div_com, so one mask works at any clock rate.
//   * the RX/TX bit timers reload with div-1, giving exactly `div` clocks per
//     bit instead of div+1.
//   * debug/monitor ports removed.
//
// Protocol (unchanged, this is what ucom speaks):
//   Single write : 'W' + addr + data
//   Single read  : 'R' + addr                 -> data
//   Block write  : 'B' + addr + len + data...
//   Block read   : 'b' + addr + len           -> data...
//
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module uart_if (
    input  wire        clk,
    input  wire        resetb,

    input  wire [15:0] bit_div,             // clocks per UART bit, >= 4

    input  wire        uart_rx,
    output wire        uart_tx,

    output wire [7:0]  address,
    output wire [7:0]  data_write_to_reg,
    input  wire [7:0]  data_read_from_reg,
    output wire        reg_en,
    output wire        write_en,
    output wire        busy                 // high while a command is in flight
);

    //=========================================================================
    // Bit timer helpers
    //=========================================================================
    wire [15:0] div_full = (bit_div < 16'd4) ? 16'd4 : bit_div;
    wire [15:0] div_m1   = div_full - 16'd1;   // full bit period
    wire [15:0] div_half = {1'b0, div_full[15:1]};

    //=========================================================================
    // Receiver
    //=========================================================================
    localparam [1:0] RX_IDLE  = 2'd0,
                     RX_START = 2'd1,
                     RX_DATA  = 2'd2,
                     RX_STOP  = 2'd3;

    reg  [1:0]  rx_state;
    reg  [15:0] rx_div;
    reg  [2:0]  rx_bit;
    reg  [7:0]  rx_shift;
    reg  [7:0]  rx_data;
    reg         rx_valid;

    // two flop synchroniser on the async input
    reg rx_sync1, rx_sync2;
    always @(posedge clk) begin
        if (!resetb) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= uart_rx;
            rx_sync2 <= rx_sync1;
        end
    end
    wire rx_in = rx_sync2;

    always @(posedge clk) begin
        if (!resetb) begin
            rx_state <= RX_IDLE;
            rx_div   <= 16'd0;
            rx_bit   <= 3'd0;
            rx_shift <= 8'd0;
            rx_data  <= 8'd0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    rx_bit <= 3'd0;
                    if (!rx_in) begin            // falling edge, possible start bit
                        rx_div   <= div_half;    // sample in the middle of the start bit
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (rx_div == 16'd0) begin
                        if (!rx_in) begin        // still low: real start bit
                            rx_div   <= div_m1;
                            rx_shift <= 8'd0;
                            rx_bit   <= 3'd0;
                            rx_state <= RX_DATA;
                        end else begin           // glitch
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_div <= rx_div - 16'd1;
                    end
                end

                RX_DATA: begin
                    if (rx_div == 16'd0) begin
                        rx_div   <= div_m1;
                        rx_shift <= {rx_in, rx_shift[7:1]};   // LSB first
                        rx_bit   <= rx_bit + 3'd1;
                        if (rx_bit == 3'd7) rx_state <= RX_STOP;
                    end else begin
                        rx_div <= rx_div - 16'd1;
                    end
                end

                RX_STOP: begin
                    if (rx_div == 16'd0) begin
                        // Accept the byte whatever the stop bit looks like; a
                        // framing error would only lose the next byte anyway.
                        rx_data  <= rx_shift;
                        rx_valid <= 1'b1;
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_div <= rx_div - 16'd1;
                    end
                end
            endcase
        end
    end

    //=========================================================================
    // Transmitter - single byte, no queue
    //=========================================================================
    localparam [1:0] TX_IDLE  = 2'd0,
                     TX_START = 2'd1,
                     TX_DATA  = 2'd2,
                     TX_STOP  = 2'd3;

    reg  [1:0]  tx_state;
    reg  [15:0] tx_div;
    reg  [2:0]  tx_bit;
    reg  [7:0]  tx_shift;
    reg         tx_pin;

    reg  [7:0]  tx_data;      // driven by the protocol engine
    reg         tx_start;

    wire tx_busy = (tx_state != TX_IDLE);

    assign uart_tx = tx_pin;

    always @(posedge clk) begin
        if (!resetb) begin
            tx_state <= TX_IDLE;
            tx_div   <= 16'd0;
            tx_bit   <= 3'd0;
            tx_shift <= 8'd0;
            tx_pin   <= 1'b1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_pin <= 1'b1;
                    if (tx_start) begin
                        tx_shift <= tx_data;
                        tx_bit   <= 3'd0;
                        tx_div   <= div_m1;
                        tx_state <= TX_START;
                    end
                end

                TX_START: begin
                    tx_pin <= 1'b0;
                    if (tx_div == 16'd0) begin
                        tx_div   <= div_m1;
                        tx_state <= TX_DATA;
                    end else begin
                        tx_div <= tx_div - 16'd1;
                    end
                end

                TX_DATA: begin
                    tx_pin <= tx_shift[0];
                    if (tx_div == 16'd0) begin
                        tx_div   <= div_m1;
                        tx_shift <= {1'b0, tx_shift[7:1]};
                        tx_bit   <= tx_bit + 3'd1;
                        if (tx_bit == 3'd7) tx_state <= TX_STOP;
                    end else begin
                        tx_div <= tx_div - 16'd1;
                    end
                end

                TX_STOP: begin
                    tx_pin <= 1'b1;
                    if (tx_div == 16'd0) begin
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_div <= tx_div - 16'd1;
                    end
                end
            endcase
        end
    end

    //=========================================================================
    // Protocol engine
    //=========================================================================
    localparam [3:0] P_IDLE     = 4'd0,
                     P_ADDR     = 4'd1,
                     P_DATA     = 4'd2,
                     P_LEN      = 4'd3,
                     P_BWRITE   = 4'd4,
                     P_RD_ADDR  = 4'd5,
                     P_RD_W1    = 4'd6,
                     P_RD_W2    = 4'd7,
                     P_RD_GO    = 4'd8,
                     P_RD_BUSY  = 4'd9,
                     P_RD_DONE  = 4'd10;

    reg  [3:0] p_state;
    reg  [7:0] cmd_reg;
    reg  [7:0] addr_reg;
    reg  [7:0] len_reg;
    reg  [7:0] cnt_reg;
    reg  [7:0] cur_addr;
    reg  [7:0] wr_data;
    reg        wr_en;

    assign address           = cur_addr;
    assign data_write_to_reg = wr_data;
    assign write_en          = wr_en;
    assign reg_en            = wr_en | (p_state == P_RD_W1) | (p_state == P_RD_W2);
    assign busy              = (p_state != P_IDLE);

    wire cmd_is_write  = (cmd_reg == 8'h57) || (cmd_reg == 8'h77);  // 'W' 'w'
    wire cmd_is_read   = (cmd_reg == 8'h52) || (cmd_reg == 8'h72);  // 'R' 'r'
    wire cmd_is_bwrite = (cmd_reg == 8'h42);                        // 'B'
    // 'b' (block read) needs no decode of its own: it is the only block
    // command left once cmd_is_bwrite is false.

    always @(posedge clk) begin
        if (!resetb) begin
            p_state  <= P_IDLE;
            cmd_reg  <= 8'd0;
            addr_reg <= 8'd0;
            len_reg  <= 8'd0;
            cnt_reg  <= 8'd0;
            cur_addr <= 8'd0;
            wr_data  <= 8'd0;
            wr_en    <= 1'b0;
            tx_data  <= 8'd0;
            tx_start <= 1'b0;
        end else begin
            wr_en    <= 1'b0;
            tx_start <= 1'b0;

            case (p_state)
                //-------------------------------------------------- command --
                P_IDLE: begin
                    if (rx_valid) begin
                        cmd_reg <= rx_data;
                        cnt_reg <= 8'd0;
                        case (rx_data)
                            8'h57, 8'h77,
                            8'h52, 8'h72,
                            8'h42, 8'h62: p_state <= P_ADDR;
                            default:      p_state <= P_IDLE;   // resync on junk
                        endcase
                    end
                end

                //----------------------------------------------------- addr --
                P_ADDR: begin
                    if (rx_valid) begin
                        addr_reg <= rx_data;
                        cur_addr <= rx_data;
                        if (cmd_is_write)      p_state <= P_DATA;
                        else if (cmd_is_read)  p_state <= P_RD_W1;
                        else                   p_state <= P_LEN;
                    end
                end

                //---------------------------------------------- single write --
                P_DATA: begin
                    if (rx_valid) begin
                        wr_data  <= rx_data;
                        cur_addr <= addr_reg;
                        wr_en    <= 1'b1;
                        p_state  <= P_IDLE;
                    end
                end

                //--------------------------------------------- block length --
                P_LEN: begin
                    if (rx_valid) begin
                        len_reg <= rx_data;
                        cnt_reg <= 8'd0;
                        if (rx_data == 8'd0) begin
                            p_state <= P_IDLE;          // nothing to do
                        end else if (cmd_is_bwrite) begin
                            p_state <= P_BWRITE;
                        end else begin
                            p_state <= P_RD_W1;
                        end
                    end
                end

                //----------------------------------------------- block write --
                P_BWRITE: begin
                    if (rx_valid) begin
                        wr_data  <= rx_data;
                        cur_addr <= addr_reg + cnt_reg;
                        wr_en    <= 1'b1;
                        cnt_reg  <= cnt_reg + 8'd1;
                        if (cnt_reg + 8'd1 >= len_reg) p_state <= P_IDLE;
                    end
                end

                //--------------------------------- read, single and streamed --
                // cur_addr is already valid when we get here.  The register
                // bank registers its readout, so wait two clocks before we
                // sample data_read_from_reg.
                P_RD_ADDR: begin
                    cur_addr <= addr_reg + cnt_reg;
                    p_state  <= P_RD_W1;
                end

                P_RD_W1: p_state <= P_RD_W2;

                P_RD_W2: begin
                    tx_data <= data_read_from_reg;
                    p_state <= P_RD_GO;
                end

                P_RD_GO: begin
                    tx_start <= 1'b1;
                    p_state  <= P_RD_BUSY;
                end

                P_RD_BUSY: begin
                    if (tx_busy) p_state <= P_RD_DONE;
                end

                P_RD_DONE: begin
                    if (!tx_busy) begin
                        cnt_reg <= cnt_reg + 8'd1;
                        if (cmd_is_read || (cnt_reg + 8'd1 >= len_reg)) begin
                            p_state <= P_IDLE;
                        end else begin
                            p_state <= P_RD_ADDR;
                        end
                    end
                end

                default: p_state <= P_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
