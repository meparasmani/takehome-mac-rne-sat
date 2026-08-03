`timescale 1ns/1ps
//
// mac_rne_sat -- golden solution per docs/spec.md.
// Synthesizable SystemVerilog only (Icarus Verilog, -g2012). No SVA.
//
module mac_rne_sat (
    input  logic               clk,
    input  logic               rst,       // synchronous, active-high
    input  logic               en,        // accumulate a*b this cycle
    input  logic               clr,       // clear accumulator this cycle
    input  logic               rd,        // request readout snapshot this cycle
    input  logic signed [7:0]  a,
    input  logic signed [7:0]  b,
    output logic signed [15:0] res,       // rounded + saturated snapshot
    output logic               res_valid, // 1-cycle pulse, one cycle after rd
    output logic               ovf        // sticky saturation flag
);

    // 28-bit signed accumulator
    logic signed [27:0] acc;

    // Product: signed 8x8 -> 16-bit, then sign-extended to 28
    logic signed [15:0] prod16;
    logic signed [27:0] prod;

    assign prod16 = a * b;
    assign prod   = {{12{prod16[15]}}, prod16};

    // Snapshot is current acc (before this cycle's update; NBA preserves that)
    logic signed [27:0] snap;
    logic signed [27:0] q;
    logic        [7:0]  r;
    logic               round_up;
    logic signed [27:0] rq;
    logic               sat;
    logic signed [15:0] rres;

    assign snap     = acc;
    // Arithmetic >>> gives floor(snap/256) for two's-complement; r = non-neg rem
    assign q        = snap >>> 8;
    assign r        = snap[7:0];
    assign round_up = (r > 8'd128) || ((r == 8'd128) && q[0]);
    assign rq       = q + {{27{1'b0}}, round_up};
    assign sat      = (rq > 28'sd32767) || (rq < -28'sd32768);
    assign rres     = sat ? (rq[27] ? -16'sd32768 : 16'sd32767)
                          : rq[15:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            acc       <= '0;
            res       <= '0;
            res_valid <= 1'b0;
            ovf       <= 1'b0;
        end else begin
            // Registered readout: appears one edge after rd is sampled
            res_valid <= rd;
            if (rd) begin
                res <= rres;
            end
            // Sticky ovf: set on saturating readout; clr clears only if no sat set
            // Same-cycle saturating rd + clr: set wins
            ovf <= ((clr ? 1'b0 : ovf) | (rd && sat));

            // Accumulator update (after snapshot conceptually)
            if (clr && en) begin
                acc <= prod;   // clear-then-accumulate
            end else if (clr) begin
                acc <= '0;
            end else if (en) begin
                acc <= acc + prod;
            end
        end
    end

endmodule
