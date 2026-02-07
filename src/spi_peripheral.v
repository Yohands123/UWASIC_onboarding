/*
 * SPI Peripheral for UWASIC Onboarding
 * Mode 0, write-only, 16-bit fixed transaction
 *
 * Frame (MSB first):
 *   [15]    R/W   (1=write, 0=read ignored)
 *   [14:8]  ADDR  (0x00..0x04 valid)
 *   [7:0]   DATA
 *
 * Behavior:
 * - Sample COPI on SCLK rising edges (mode 0)
 * - Capture exactly 16 bits while nCS is low
 * - Commit register write only on nCS rising edge (end of transaction)
 * - Ignore reads and invalid addresses
 */

`default_nettype none

module spi_peripheral (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       nCS,
    input  wire       SCLK,
    input  wire       COPI,

    output reg  [7:0] en_reg_out_7_0,
    output reg  [7:0] en_reg_out_15_8,
    output reg  [7:0] en_reg_pwm_7_0,
    output reg  [7:0] en_reg_pwm_15_8,
    output reg  [7:0] pwm_duty_cycle
);

    localparam [6:0] MAX_ADDR = 7'h04;

    // ------------------------------------------------------------
    // CDC synchronizers (2-FF) for async SPI pins
    // ------------------------------------------------------------
    reg [1:0] ncs_sync;
    reg [1:0] sclk_sync;
    reg [1:0] copi_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ncs_sync  <= 2'b11; // idle high
            sclk_sync <= 2'b00; // assume idle low for mode 0
            copi_sync <= 2'b00;
        end else begin
            ncs_sync  <= {ncs_sync[0],  nCS};
            sclk_sync <= {sclk_sync[0], SCLK};
            copi_sync <= {copi_sync[0], COPI};
        end
    end

    wire ncs_syncd  = ncs_sync[1];
    wire copi_syncd = copi_sync[1];

    // ------------------------------------------------------------
    // Edge detection in clk domain
    // ------------------------------------------------------------
    wire sclk_rise = ( sclk_sync[1] & ~sclk_sync[0]);
    wire ncs_rise  = ( ncs_sync[1]  & ~ncs_sync[0]);
    wire ncs_low   = ~ncs_syncd;

    // ------------------------------------------------------------
    // Shift in 16 bits while nCS is low, on SCLK rising edges
    // ------------------------------------------------------------
    reg [15:0] shift_reg;
    reg [4:0]  bit_count; // needs to count to 16

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 16'h0000;
            bit_count <= 5'd0;
        end else if (ncs_low) begin
            if (sclk_rise) begin
                shift_reg <= {shift_reg[14:0], copi_syncd};
                bit_count <= bit_count + 1'b1;
            end
        end else begin
            // idle (between transactions)
            bit_count <= 5'd0;
            shift_reg <= shift_reg; // keep last frame (optional)
        end
    end

    // Decode fields from the captured frame
    wire        rw_bit = shift_reg[15];
    wire [6:0]  addr   = shift_reg[14:8];
    wire [7:0]  data   = shift_reg[7:0];

    // ------------------------------------------------------------
    // Commit write only when transaction ends (nCS rising edge)
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_reg_out_7_0   <= 8'h00;
            en_reg_out_15_8  <= 8'h00;
            en_reg_pwm_7_0   <= 8'h00;
            en_reg_pwm_15_8  <= 8'h00;
            pwm_duty_cycle   <= 8'h00;
        end else if (ncs_rise) begin
            // Use old bit_count value in this cycle (nonblocking semantics)
            if (bit_count == 5'd16 && rw_bit && (addr <= MAX_ADDR)) begin
                case (addr)
                    7'h00: en_reg_out_7_0  <= data;
                    7'h01: en_reg_out_15_8 <= data;
                    7'h02: en_reg_pwm_7_0  <= data;
                    7'h03: en_reg_pwm_15_8 <= data;
                    7'h04: pwm_duty_cycle  <= data;
                    default: ; // unreachable due to addr <= MAX_ADDR
                endcase
            end
        end
    end

endmodule