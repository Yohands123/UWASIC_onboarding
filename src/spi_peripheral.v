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
    input wire clk,
    input wire rst_n,
    
    //peripherals
    input wire copi,
    input wire ncs,
    input wire sclk,

    output reg [7:0] en_reg_out_7_0,
    output reg [7:0] en_reg_out_15_8,
    output reg [7:0] en_reg_pwm_7_0,
    output reg [7:0] en_reg_pwm_15_8,
    output reg [7:0] pwm_duty_cycle
);

    reg [3:0] counter;

    reg read_write_bit;
    reg [6:0] address;
    reg [7:0] serial_data;

    reg transmitting_data;

    reg sclk_meta;
    reg sclk_sync;

    reg ncs_meta;
    reg ncs_sync;

    reg copi_meta;
    reg copi_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                           //rst_n is active low
            //reset all registers and peripherals
            counter <= 4'b0;
            read_write_bit <= 1'b0;
            address <= 7'b0;
            serial_data <= 8'b0;

            en_reg_out_7_0 <= 8'b0;
            en_reg_out_15_8 <= 8'b0;
            en_reg_pwm_7_0 <= 8'b0;
            en_reg_pwm_15_8 <= 8'b0;
            pwm_duty_cycle <= 8'b0;

            sclk_meta <= 1'b0;
            sclk_sync <= 1'b0;

            ncs_meta <= 1'b0;
            ncs_sync <= 1'b0;

            copi_meta <= 1'b0;
            copi_sync <= 1'b0;

            transmitting_data <= 1'b0;
        end else begin
            sclk_meta <= sclk;
            sclk_sync <= sclk_meta;

            ncs_meta <= ncs;
            ncs_sync <= ncs_meta;

            copi_meta <= copi;
            copi_sync <= copi_meta;
            
            if (!transmitting_data) begin
                counter <= 4'b0;

                if (ncs_falling) begin
                    transmitting_data <= 1;
                end
            end else begin
                if (ncs_rising) begin
                    if ((read_write_bit == 1'b1) && (address <= 7'b0000101)) begin
                        case (address)
                            7'b00: en_reg_out_7_0 <= serial_data;
                            7'b01: en_reg_out_15_8 <= serial_data;
                            7'b10: en_reg_pwm_7_0 <= serial_data;
                            7'b11: en_reg_pwm_15_8 <= serial_data;
                            default:;
                        endcase
                    end

                    transmitting_data <= 1'b0;
                end else if (sclk_rising) begin
                    if (counter == 4'd0) begin
                        read_write_bit <= copi_sync;
                    end else if (counter < 4'd8) begin
                        address <= {address[5:0], copi_sync};
                    end else begin
                        serial_data <= {serial_data[6:0], copi_sync};
                    end

                    if (counter == 4'd15) begin
                        counter <= 0;
                    end else begin
                        counter <= counter + 1;
                    end
                end
            end

        end

    end
    
    wire sclk_rising = (sclk_sync == 1'b0) && (sclk_meta == 1'b1);
    wire ncs_falling = (ncs_sync == 1'b1) && (ncs_meta == 1'b1);
    wire ncs_rising = (ncs_sync == 1'b0) && (ncs_meta == 1'b1);



endmodule