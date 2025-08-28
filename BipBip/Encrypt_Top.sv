//-----------------------------------------------------------------------------
//  Encrypt wrapper: gates start on your AXI window, one‐shots it,
//                     then calls BipBip_Cipher(mode=1)
//-----------------------------------------------------------------------------
module EncryptTop (
    input  logic         clk,
    input  logic         reset_n,
    input  logic [63:0]  lock_ar,
    input  logic         ar_valid,
    input  logic         start,   
    input  logic [255:0] key,
    input  logic [39:0]  tweak,
    input  logic [23:0]  text_in,
    output logic [23:0]  text_out,
    output logic         done
  );
  
    // 1) inside‐window latch
    localparam logic [63:0] BASE = 64'h8000_0000, END = 64'h8000_0420;
    logic in_window;
    always_ff @(posedge clk or negedge reset_n) begin
      if (!reset_n)      in_window <= 1'b0;
      else if (ar_valid && lock_ar >= BASE && lock_ar <= END)
                          in_window <= 1'b1;
      else if (ar_valid && lock_ar > END)
                          in_window <= 1'b0;
    end
  
    // 2) gate + one‐shot
    logic prev, start_pulse;
    always_ff @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
        prev         <= 1'b0;
        start_pulse  <= 1'b0;
      end else begin
        start_pulse  <= start & in_window & ~prev;
        prev         <= start & in_window;
      end
    end
  
    // 3) single, shared core
    BipBip_Cipher core (
      .clk      (clk),
      .reset_n  (reset_n),
      .start    (start_pulse),
      .mode     (1'b1),       // ENCRYPT
      .key      (key),
      .tweak    (tweak),
      .text_in  (text_in),
      .text_out (text_out),
      .done     (done)
    );
  
  endmodule
  