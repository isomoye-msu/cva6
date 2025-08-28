// ============================================================================
//  BipBip_KeySchedule.sv
// ----------------------------------------------------------------------------
//  -> 8 bit math for the key index (k8) naturally wraps mod-256 like c++
//  -> Bit-addressing matches the original MK[w][b] mapping exactly
//  -> Arrays are fully initialized each cycle to prevent Xs
// ----------------------------------------------------------------------------

import BipBip_pkg::*;   

module BipBip_KeySchedule (
    input  logic [255:0] key,          // Master key: MK[0]=key[255:192] ... MK[3]=key[63:0]
    input  logic [39:0]  tweak,        // 40-bit tweak T[39:0]
    output logic [23:0]  drk [0:11]    // 12 × 24-bit data round-keys
);

  // --------------------------------------------------------------------------
  // mkbit(idx)
  //  Return MK[w][b] with the exact original word/bit mapping:
  // --------------------------------------------------------------------------
  function automatic logic mkbit(input int unsigned idx);
    int unsigned w = idx / 64;
    int unsigned b = idx % 64;
    int signed   base = 192 - (w * 64);
    return key[base + b];
  endfunction

  // --------------------------------------------------------------------------
  // Tweak schedule words trk[0..6]
  //  trk[0]   : 24 entries built from 8-bit accumulator k8
  //             repeatedly multiplied by 3%256
  //  trk[1..6]: 53 entries each, starting at k8=53, incrementing by 1across rows
  //  Implementation detail: fully initialize to zero to avoid Xs
  // --------------------------------------------------------------------------
  logic [52:0] trk[0:6];
  logic [7:0]  k8;  // 8-bit arithmetic -> natural mod-256 wrap

  always_comb begin
    //clear rows
    for (int r = 0; r < 7; r++) begin
      for (int i = 0; i < 53; i++) trk[r][i] = 1'b0;
    end

    // trk[0] : k8 progression (k8 = k8 * 3) 24 entries
    k8 = 8'd1;
    for (int i = 0; i < 24; i++) begin
      k8 = k8 * 8'd3;          // wraps mod-256
      trk[0][i] = mkbit(k8);   // select MK bit at index k8
    end

    // trk[1..6] : 53 entries each, sequential from k8=53
    k8 = 8'd53;
    for (int row = 1; row < 7; row++) begin
      for (int i = 0; i < 53; i++) begin
        trk[row][i] = mkbit(k8);
        k8 = k8 + 8'd1;        // wraps mod-256
      end
    end
  end

  // --------------------------------------------------------------------------
  // Initial tweak state s[0]
  //  Layout:
  //    s[0][52:13] = T[39:0] (MSB->MSB)
  //    s[0][12]    = 1
  //    s[0][11:0]  = 0
  //  matches the original TwkIn wiring
  // --------------------------------------------------------------------------
  logic [52:0] s [0:15];

  always_comb begin
    // 0 out full word first
    for (int i = 0; i < 53; i++) s[0][i] = 1'b0;

    // Map tweak into the top 40 bits of s[0]
    for (int i = 0; i < 40; i++) s[0][52 - i] = tweak[39 - i];

    // Fixed tag bit
    s[0][12] = 1'b1;
  end

  // --------------------------------------------------------------------------
  // CHI(x)
  //  Non-linear χ layer on 53-bit tweak state with wrap-around:
  //    for 0..50: y[i] = x[i] ^ ((!x[i+1]) & x[i+2])
  //    y[51]     = x[51] ^ ((!x[52]) & x[0])
  //    y[52]     = x[52] ^ ((!x[0])  & x[1])
  //  Purpose: provides non-linearity in the tweak path.
  // --------------------------------------------------------------------------
  function automatic logic [52:0] CHI(input logic [52:0] x);
    logic [52:0] y;
    for (int i = 0; i < 51; i++)
      y[i] = x[i] ^ ((~x[(i+1)%53]) & x[(i+2)%53]);
    y[51] = x[51] ^ ((~x[52]) & x[0]);
    y[52] = x[52] ^ ((~x[0])  & x[1]);
    return y;
  endfunction

  // --------------------------------------------------------------------------
  // RGC(x)
  //  "G" round in tweak path:
  //    p4 = PI4(x)
  //    m2[i] = p4[i] ^ p4[(i+1)%53] ^ p4[(i+8)%53]   // θ_t mix
  //    p5 = PI5(m2)
  //    y  = CHI(p5)
  //  Purpose: linear diffusion (θ_t) between two fixed permutations
  //           followed by non-linearity
  // --------------------------------------------------------------------------
  function automatic logic [52:0] RGC(input logic [52:0] x);
    logic [52:0] p4, m2, p5;
    for (int i = 0; i < 53; i++) p4[i] = x[PI4[i]];
    for (int i = 0; i < 53; i++) m2[i] = p4[i] ^ p4[(i+1)%53] ^ p4[(i+8)%53];
    for (int i = 0; i < 53; i++) p5[i] = m2[PI5[i]];
    return CHI(p5);
  endfunction

  // --------------------------------------------------------------------------
  // RGP(x)
  //  "G′" round in tweak path:
  //    p4 = PI4(x)
  //    m3[i] = p4[i] ^ p4[i+1]   (i=0..51),  m3[52] = p4[52]   // θ′_t mix
  //    p5 = PI5(m3)
  //    y  = CHI(p5)
  //  Purpose: alternate linear mix (θ′_t) -> different diffusion profile
  // --------------------------------------------------------------------------
  function automatic logic [52:0] RGP(input logic [52:0] x);
    logic [52:0] p4, m3, p5;
    for (int i = 0; i < 53; i++) p4[i] = x[PI4[i]];
    for (int i = 0; i < 52; i++) m3[i] = p4[i] ^ p4[i+1];
    m3[52] = p4[52];
    for (int i = 0; i < 53; i++) p5[i] = m3[PI5[i]];
    return CHI(p5);
  endfunction

  // --------------------------------------------------------------------------
  // RKE0(x) / RKE1(x)
  //  Extract 24 bit roun keys from a 53 bit tweak state:
  //    RKE0: even indices  -> drk
  //    RKE1: odd  indices  -> drk
  //  Purpose: matches the origina slicing used by TwkSc
  // --------------------------------------------------------------------------
  function automatic logic [23:0] RKE0(input logic [52:0] x);
    logic [23:0] y;
    for (int i = 0; i < 24; i++) y[i] = x[2*i];
    return y;
  endfunction

  function automatic logic [23:0] RKE1(input logic [52:0] x);
    logic [23:0] y;
    for (int i = 0; i < 24; i++) y[i] = x[2*i + 1];
    return y;
  endfunction

  // --------------------------------------------------------------------------
  // TwkSc sequence -> drk[0..11]
  //  Exact order from the reference:
  //    drk0   = trk0[0..23]
  //    s1     = s0 ^ trk1;   s2  = CHI(s1);       drk1 = RKE0(s2);  drk2 = RKE1(s2)
  //    s3     = s2 ^ trk2;   s4  = RGC(s3);       drk3 = RKE0(s4);  drk4 = RKE1(s4)
  //    s5     = s4 ^ trk3;   s6  = RGC(s5); s7 = RGP(s6);           drk5 = RKE0(s7)
  //    s8     = s7 ^ trk4;   s9  = RGC(s8);                         drk6 = RKE0(s9)
  //    s10    = RGP(s9);                                            drk7 = RKE0(s10)
  //    s11    = s10 ^ trk5;  s12 = RGC(s11);                        drk8 = RKE0(s12)
  //    s13    = RGP(s12);                                           drk9 = RKE0(s13)
  //    s14    = s13 ^ trk6;  s15 = RGC(s14);      drk10 = RKE0(s15); drk11 = RKE1(s15)
  //  All combinational
  // --------------------------------------------------------------------------
  always_comb begin
    // drk0 from trk0 (lower 24 bits used)
    for (int i = 0; i < 24; i++) drk[0][i] = trk[0][i];

    // Round 1: KAT(trk1) + χ -> drk1, drk2
    s[1] = s[0] ^ trk[1];
    s[2] = CHI(s[1]);
    drk[1] = RKE0(s[2]);
    drk[2] = RKE1(s[2]);

    // Round 2: KAT(trk2) + RGC -> drk3, drk4
    s[3] = s[2] ^ trk[2];
    s[4] = RGC(s[3]);
    drk[3] = RKE0(s[4]);
    drk[4] = RKE1(s[4]);

    // Round 3: KAT(trk3) + RGC + RGP -> drk5
    s[5] = s[4] ^ trk[3];
    s[6] = RGC(s[5]);
    s[7] = RGP(s[6]);
    drk[5] = RKE0(s[7]);

    // Round 4: KAT(trk4) + RGC -> drk6
    s[8]  = s[7] ^ trk[4];
    s[9]  = RGC(s[8]);
    drk[6] = RKE0(s[9]);

    // Round 5: RGP -> drk7
    s[10] = RGP(s[9]);
    drk[7] = RKE0(s[10]);

    // Round 6: KAT(trk5) + RGC -> drk8
    s[11] = s[10] ^ trk[5];
    s[12] = RGC(s[11]);
    drk[8] = RKE0(s[12]);

    // Round 7: RGP -> drk9
    s[13] = RGP(s[12]);
    drk[9] = RKE0(s[13]);

    // Round 8: KAT(trk6) + RGC -> drk10, drk11
    s[14] = s[13] ^ trk[6];
    s[15] = RGC(s[14]);
    drk[10] = RKE0(s[15]);
    drk[11] = RKE1(s[15]);
  end

endmodule
