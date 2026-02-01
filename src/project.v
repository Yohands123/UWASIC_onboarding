/* 
 * TinyTapeout top module (must start with tt_um_)
 * This file contains:
 *   1) The required TinyTapeout wrapper: tt_um_uwasic_onboarding_yohance
 *   2) Your real design: project_core  (your old "module project" renamed)
 */

module tt_um_uwasic_onboarding_yohance (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,

    input  wire [7:0]  ui_in,
    output wire [7:0]  uo_out,

    input  wire [7:0]  uio_in,
    output wire [7:0]  uio_out,
    output wire [7:0]  uio_oe
);

    // Safe defaults (not driving bidirectional IO)
    assign uio_out = 8'b0000_0000;
    assign uio_oe  = 8'b0000_0000;

    // Your real design lives here
    project_core u_core (
        .clk   (clk),
        .rst_n (rst_n),
        .ena   (ena),
        .ui_in (ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in)
    );

endmodule


// =============================================================
// YOUR ORIGINAL DESIGN GOES HERE
// Rename old:  module project ( ... )
// Into:        module project_core ( ... )
// Then paste the FULL body (not empty).
// =============================================================

module project_core (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ena,

    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in
);

    // >>> PASTE YOUR ENTIRE OLD "module project(...)" CONTENTS HERE <<<
    // Must not be empty.

endmodule
