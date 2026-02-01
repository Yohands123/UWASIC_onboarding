/*
 * Copyright (c) 2024 Damir Gazizullin
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module pwm_peripheral (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] en_reg_out_7_0,
    input  wire [7:0] en_reg_out_15_8,
    input  wire [7:0] en_reg_pwm_7_0,
    input  wire [7:0] en_reg_pwm_15_8,
    input  wire [7:0] pwm_duty_cycle,
    output reg  [15:0] out
);

    // Divide by (clk_div_trig+1)*256 -> ~3kHz from 10MHz
    // 10 MHz / ((12+1)*256) ≈ 3004.8 Hz
    localparam clk_div_trig = 12;

    reg [10:0] clk_counter;
    reg [7:0]  pwm_counter;

    // PWM comparator (special case: 0xFF => always high)
    wire pwm_signal = (pwm_duty_cycle == 8'hFF) ? 1'b1
                    : (pwm_counter < pwm_duty_cycle);

    // Combine the two 8-bit banks into 16-bit buses
    wire [15:0] out_en = {en_reg_out_15_8, en_reg_out_7_0};
    wire [15:0] pwm_en = {en_reg_pwm_15_8, en_reg_pwm_7_0};

    // Combinational next-state for output
    reg [15:0] out_next;
    integer i;

    always @(*) begin
        out_next = 16'h0000;

        for (i = 0; i < 16; i = i + 1) begin
            if (out_en[i]) begin
                // output enabled
                if (pwm_en[i]) begin
                    // PWM mode
                    out_next[i] = pwm_signal;
                end else begin
                    // static high
                    out_next[i] = 1'b1;
                end
            end else begin
                // disabled
                out_next[i] = 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out         <= 16'h0000;
            pwm_counter <= 8'h00;
            clk_counter <= 11'h000;
        end else begin
            // PWM counters
            clk_counter <= clk_counter + 1'b1;
            if (clk_counter == clk_div_trig) begin
                clk_counter <= 11'h000;
                pwm_counter <= pwm_counter + 1'b1;
            end

            // Update outputs
            out <= out_next;
        end
    end

endmodule
