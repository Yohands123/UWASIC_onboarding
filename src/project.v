/* 
 * TinyTapeout top module (must start with tt_um_)
 * Rename your previous top module from:
 *   module project (...)
 * to:
 *   module project_core (...)
 *
 * Then this wrapper becomes the required TT top module.
 */

module tt_um_uwasic_onboarding (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,

    input  wire [7:0]  ui_in,
    output wire [7:0]  uo_out,

    input  wire [7:0]  uio_in,
    output wire [7:0]  uio_out,
    output wire [7:0]  uio_oe
);

    // ---------------------------------------------
    // Default IO behavior (safe defaults)
    // ---------------------------------------------

    // If you are NOT using bidirectional IO, keep these:
    assign uio_out = 8'b0000_0000;
    assign uio_oe  = 8'b0000_0000;   // 0 = input, 1 = output

    // ---------------------------------------------
    // Instantiate your real design here
    // ---------------------------------------------

    project_core u_core (
        .clk   (clk),
        .rst_n (rst_n),
        .ena   (ena),

        .ui_in (ui_in),
        .uo_out(uo_out),

        .uio_in(uio_in)
        // If your core uses uio_out/uio_oe, add them here and
        // remove the default assigns above.
    );

endmodule


// =============================================================
// YOUR ORIGINAL PROJECT MODULE GOES BELOW (RENAMED)
// =============================================================
//
// Change your old:
//   module project (...)
// to:
//   module project_core (...)
//
// Keep everything else the same.
//
// Example port list template (YOU MUST MATCH YOUR REAL ONE):
//
module project_core (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ena,

    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in
);
    // --- paste your original contents here ---
endmodule
