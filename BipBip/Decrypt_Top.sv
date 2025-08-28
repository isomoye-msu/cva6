//-----------------------------------------------------------------------------
// Decrypt_Top.sv
// Register the incoming ciphertext and the done-pulse before feeding the
// BipBip_Cipher decryption tree.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps
import BipBip_pkg::*;

module Decrypt_Top (
  input  logic        clk,
  input  logic        reset_n,
  input  logic        encrypt_done,    // pulse from encryptor
  input  logic [23:0] cipher_in,       // encrypted 24-bit block
  input  logic [255:0] key,
  input  logic [39:0]  tweak,
  output logic [23:0]  plain_out,
  output logic        done             // pulses at decryption completion
);

  // register the done pulse and the cipher bits
  logic       start_reg;
  logic [23:0] cipher_reg;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      start_reg   <= 1'b0;
      cipher_reg  <= 24'd0;
    end else begin
      start_reg  <= encrypt_done;   // delayed one cycle
      cipher_reg <= cipher_in;      // sample ciphertext
    end
  end

  BipBip_Cipher u_ciph (
    .clk      (clk),
    .reset_n  (reset_n),
    .start    (start_reg),     // clean, registered pulse
    .mode     (1'b0),          // 0 = decrypt
    .key      (key),
    .tweak    (tweak),
    .text_in  (cipher_reg),    // stable, 1-cycle-old data
    .text_out (plain_out),
    .done     (done)
  );

endmodule
