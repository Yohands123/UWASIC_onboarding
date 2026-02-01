// Tiny Tapeout user module wrapper
// This is the top-level module name the TinyTapeout testbench expects.
//
// It maps:
//   ui_in[0] -> SCLK
//   ui_in[1] -> COPI (MOSI)
//   ui_in[2] -> nCS  (active-low chip select)
// and exposes your PWM outputs on uo_out[7:0] and uio_out[7:0].
//
// If your internal project.v uses different port names,
// update ONLY the "project dut (...)" port map at the bottom.

module tt_um_uwasic_onboarding_yohance (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  ui_in,
    output wire [7:0]  uo_out,

    input  wire [7:0]  uio_in,
    output wire [7:0]  uio_out,
    output wire [7:0]  uio_oe
);

    // SPI pins from Tiny Tapeout UI inputs
    wire sclk = ui_in[0];
    wire copi = ui_in[1];
    wire ncs  = ui_in[2];

    // Drive all bidirectional pins as outputs (we're using them as extra outputs)
    assign uio_oe = 8'hFF;

    // Your design outputs (16 total)
    wire [15:0] outs;

    // Map to TT outputs
    assign uo_out  = outs[7:0];
    assign uio_out = outs[15:8];

    // If your design doesn't use uio_in, this keeps lint/tools happy
    wire [7:0] unused_uio_in = uio_in;
    (void)unused_uio_in;

    // Instantiate your actual design
    // IMPORTANT: Update these port names to match src/project.v if they differ.
    project dut (
        .clk   (clk),
        .rst_n (rst_n),
        .sclk  (sclk),
        .copi  (copi),
        .ncs   (ncs),
        .outs  (outs)
    );

endmodule
