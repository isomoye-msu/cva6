//-----------------------------------------------------------------------------
//  BipBip_Decrypt
//    Decrypt round order]:
//      KAD(drk[0])  → RFS
//      KAD(drk[1])  → RFS
//      KAD(drk[2])  → RFS
//      KAD(drk[3])  → RFC
//      KAD(drk[4])  → RFC
//      KAD(drk[5])  → RFC
//      KAD(drk[6])  → RFC
//      KAD(drk[7])  → RFC
//      KAD(drk[8])  → RFS
//      KAD(drk[9])  → RFS
//      KAD(drk[10]) → RFS
//      KAD(drk[11]) (final XOR)
//-----------------------------------------------------------------------------
`timescale 1ns/1ps
import BipBip_pkg::*;

module BipBip_Decrypt (
    input  logic [23:0] data_in,
    input  logic [23:0] drk [0:11],
    output logic [23:0] data_out
);
    // --------------------------------------------------------------------------
    // SBL(x)
    //  Forward S-box layer
    //  Splits inpute into 4×6-bit words applies BBB LUT reassembles
    // --------------------------------------------------------------------------
    function automatic logic [23:0] SBL(input logic [23:0] x);
        logic [23:0] y;
        for (int j=0; j<4; j++) begin
            logic [5:0] val = x[6*j +: 6];
            y[6*j +: 6] = BBB[val];
        end
        return y;
    endfunction

    // --------------------------------------------------------------------------
    // BPL1/2/3(x)
    //  Each returns state_out[i] = state_in[PI* [i]]
    // --------------------------------------------------------------------------
    function automatic logic [23:0] BPL1(input logic [23:0] x);
        logic [23:0] y; for(int i=0;i<24;i++) y[i] = x[PI1[i]]; return y;
    endfunction
    function automatic logic [23:0] BPL2(input logic [23:0] x);
        logic [23:0] y; for(int i=0;i<24;i++) y[i] = x[PI2[i]]; return y;
    endfunction
    function automatic logic [23:0] BPL3(input logic [23:0] x);
        logic [23:0] y; for(int i=0;i<24;i++) y[i] = x[PI3[i]]; return y;
    endfunction

    // --------------------------------------------------------------------------
    // LML1(x)
    //    y[i] = x[i] ^ x[(i+2)%24] ^ x[(i+12)%24]
    //  diffusion
    // --------------------------------------------------------------------------
    function automatic logic [23:0] LML1(input logic [23:0] x);
        logic [23:0] y;
        for (int i=0;i<24;i++)
            y[i] = x[i] ^ x[(i+2)%24] ^ x[(i+12)%24];
        return y;
    endfunction

    // Shell round: RFS(x) = BPL3(SBL(x))
    function automatic logic [23:0] RFS_func(input logic [23:0] x);
        return BPL3(SBL(x));
    endfunction

    // Core round: RFC(x) = BPL2(LML1(BPL1(SBL(x))))
    function automatic logic [23:0] RFC_func(input logic [23:0] x);
        return BPL2(LML1(BPL1(SBL(x))));
    endfunction

    // --------------------------------------------------------------------------
    // Decryption round pipeline
    //  Matches c++:
    //    -> 3 × (KAD + RFS)   using drk[0..2]
    //    -> 5 × (KAD + RFC)   using drk[3..7]
    //    -> 3 × (KAD + RFS)   using drk[8..10]
    //    -> Final KAD         with drk[11]
    // --------------------------------------------------------------------------
    logic [23:0] st;

    always_comb begin
        st = data_in;

        // Rounds 0–2: KAD + RFS
        st ^= drk[0];  st = RFS_func(st);
        st ^= drk[1];  st = RFS_func(st);
        st ^= drk[2];  st = RFS_func(st);

        // Rounds 3–7: KAD + RFC
        st ^= drk[3];  st = RFC_func(st);
        st ^= drk[4];  st = RFC_func(st);
        st ^= drk[5];  st = RFC_func(st);
        st ^= drk[6];  st = RFC_func(st);
        st ^= drk[7];  st = RFC_func(st);

        // Rounds 8–10: KAD + RFS
        st ^= drk[8];   st = RFS_func(st);
        st ^= drk[9];   st = RFS_func(st);
        st ^= drk[10];  st = RFS_func(st);

        // Final key addition
        st ^= drk[11];

        data_out = st;
    end

endmodule
