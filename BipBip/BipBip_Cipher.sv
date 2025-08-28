//-----------------------------------------------------------------------------
//  Condensed top-level wrapper for the BipBip cipher
//  - One-cycle combinational core selected by mode with registered output
//  - Groups functionality into three modules:
//      -> BipBip_KeySchedule : key/tweak expansion → drk[0..11]
//      -> BipBip_Encrypt     : forward data path
//      ->  BipBip_Decrypt     : inverse data path
//-----------------------------------------------------------------------------
import BipBip_pkg::*;

module BipBip_Cipher (
    input  logic         clk,
    input  logic         reset_n,
    input  logic         start,      // pulse to latch output
    input  logic         mode,       // 1 = encrypt, 0 = decrypt
    input  logic [255:0] key,        // master key
    input  logic [39:0]  tweak,      // 40-bit tweak
    input  logic [23:0]  text_in,    // plaintext or ciphertext
    output logic [23:0]  text_out,   // ciphertext or plaintext
    output logic         done        // pulses 1 cycle after start
);

    // -------------------------------------------------------------------------
    // Data round-keys (drk[0..11]) from master key + tweak
    //  Generate 12 × 24-bit data round-keys (drk[0..11]) from {key,tweak}
    //  KeySchedule is combinational
    // -------------------------------------------------------------------------
    logic [23:0] drk [0:11];

    BipBip_KeySchedule u_sched (
        .key   (key),
        .tweak (tweak),
        .drk   (drk)
    );

    // -------------------------------------------------------------------------
    // Forward/inverse data paths
    // -------------------------------------------------------------------------
    logic [23:0] enc_out, dec_out, result;

    BipBip_Encrypt u_enc (
        .data_in  (text_in),
        .drk      (drk),
        .data_out (enc_out)
    );

    BipBip_Decrypt u_dec (
        .data_in  (text_in),
        .drk      (drk),
        .data_out (dec_out)
    );

    // Select encrypt/decrypt
    assign result = (mode == 1'b1) ? enc_out : dec_out;

    // -------------------------------------------------------------------------
    // Output registers and 'done' pulse
    //  -> On start capture the selected result in result_reg
    //  -> done_reg follows start (one cycle)
    //  -> Asynchronous active-low reset clears both registers
    // -------------------------------------------------------------------------
    logic [23:0] result_reg;
    logic        done_reg;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            done_reg   <= 1'b0;
            result_reg <= '0;
        end else begin
            done_reg   <= start;       // pulse 1 cycle after start
            if (start)                 // latch output on start
                result_reg <= result;
        end
    end

    assign text_out = result_reg;
    assign done     = done_reg;

endmodule
