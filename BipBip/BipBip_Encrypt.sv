// ============================================================================
//  BipBip_Encrypt.sv
// ----------------------------------------------------------------------------
//  Implements the encryption data path of the BipBip cipher.
//  - Consumes 12 × 24-bit round keys (drk[0..11]) from the key schedule
//  - Consolidates IRFS/IRFC into local combinational functions
// ----------------------------------------------------------------------------
import BipBip_pkg::*;  

module BipBip_Encrypt (
    input  logic [23:0] data_in,         
    input  logic [23:0] drk [0:11],       
    output logic [23:0] data_out         
);

  // --------------------------------------------------------------------------
  // ISBL(x)
  //  Inverse S-box layer
  //  Splits input into 4×6-bit words  applies IBBB LUT reassembles
  // --------------------------------------------------------------------------
  function automatic logic [23:0] ISBL(input logic [23:0] x);
    logic [23:0] y;
    for (int j = 0; j < 4; j++) begin
      logic [5:0] val = x[6*j +: 6];
      y[6*j +: 6] = IBBB[val];
    end
    return y;
  endfunction

  // --------------------------------------------------------------------------
  // IBPL1/2/3(x)
  //  Inverse bit-permutation layers for data path 
  //  Each returns state_out[i] = state_in[IPI* [i]].
  // --------------------------------------------------------------------------
  function automatic logic [23:0] IBPL1(input logic [23:0] x);
    logic [23:0] y;
    for (int i = 0; i < 24; i++) y[i] = x[IPI1[i]];
    return y;
  endfunction

  function automatic logic [23:0] IBPL2(input logic [23:0] x);
    logic [23:0] y;
    for (int i = 0; i < 24; i++) y[i] = x[IPI2[i]];
    return y;
  endfunction

  function automatic logic [23:0] IBPL3(input logic [23:0] x);
    logic [23:0] y;
    for (int i = 0; i < 24; i++) y[i] = x[IPI3[i]];
    return y;
  endfunction

  // --------------------------------------------------------------------------
  // ILML1(x)
  //  Inverse linear mixing layer in data path:
  //    y[i] = x[(i+8)%24] ^ x[(i+20)%24] ^ x[(i+22)%24]
  // --------------------------------------------------------------------------
  function automatic logic [23:0] ILML1(input logic [23:0] x);
    logic [23:0] y;
    for (int i = 0; i < 24; i++)
      y[i] = x[(i+8)%24] ^ x[(i+20)%24] ^ x[(i+22)%24];
    return y;
  endfunction

  // --------------------------------------------------------------------------
  // IRFS_func(x)
  //  Inverse shell round:
  //    IRFS(x) = ISBL(IBPL3(x))
  // --------------------------------------------------------------------------
  function automatic logic [23:0] IRFS_func(input logic [23:0] x);
    return ISBL(IBPL3(x));
  endfunction

  // --------------------------------------------------------------------------
  // IRFC_func(x)
  //  Inverse core round:
  //    IRFC(x) = ISBL(IBPL1(ILML1(IBPL2(x))))
  // --------------------------------------------------------------------------
  function automatic logic [23:0] IRFC_func(input logic [23:0] x);
    return ISBL(IBPL1(ILML1(IBPL2(x))));
  endfunction

  // --------------------------------------------------------------------------
  // Encryption round pipeline
  //  Matches C++ order:
  //    -> 3 × (KAD + IRFS)   using drk[11..9]
  //    -> 5 × (KAD + IRFC)   using drk[8..4]
  //    -> 3 × (KAD + IRFS)   using drk[3..1]
  //    -> Final KAD          with drk[0]
  // --------------------------------------------------------------------------
  logic [23:0] st;

  always_comb begin
    st = data_in;

    // Rounds 0–2: KAD + IRFS
    st ^= drk[11];  st = IRFS_func(st);
    st ^= drk[10];  st = IRFS_func(st);
    st ^= drk[9];   st = IRFS_func(st);

    // Rounds 3–7: KAD + IRFC
    st ^= drk[8];   st = IRFC_func(st);
    st ^= drk[7];   st = IRFC_func(st);
    st ^= drk[6];   st = IRFC_func(st);
    st ^= drk[5];   st = IRFC_func(st);
    st ^= drk[4];   st = IRFC_func(st);

    // Rounds 8–10: KAD + IRFS
    st ^= drk[3];   st = IRFS_func(st);
    st ^= drk[2];   st = IRFS_func(st);
    st ^= drk[1];   st = IRFS_func(st);

    // Final KAD
    st ^= drk[0];

    data_out = st;
  end

endmodule
