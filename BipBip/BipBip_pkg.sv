// BipBip_Constants module containing constant lookup tables for the BipBip cipher
package BipBip_pkg;

// S-box (BBB) and inverse S-box (IBBB) – 6-bit input/output substitution boxes
  // actual BipBipBox from the C code
localparam logic [5:0] BBB [0:63] = '{
    6'h00, 6'h01, 6'h02, 6'h03, 6'h04, 6'h06, 6'h3E, 6'h3C,
    6'h08, 6'h11, 6'h0E, 6'h17, 6'h2B, 6'h33, 6'h35, 6'h2D,
    6'h19, 6'h1C, 6'h09, 6'h0C, 6'h15, 6'h13, 6'h3D, 6'h3B,
    6'h31, 6'h2C, 6'h25, 6'h38, 6'h3A, 6'h26, 6'h36, 6'h2A,
    6'h34, 6'h1D, 6'h37, 6'h1E, 6'h30, 6'h1A, 6'h0B, 6'h21,
    6'h2E, 6'h1F, 6'h29, 6'h18, 6'h0F, 6'h3F, 6'h10, 6'h20,
    6'h28, 6'h05, 6'h39, 6'h14, 6'h24, 6'h0A, 6'h0D, 6'h23,
    6'h12, 6'h27, 6'h07, 6'h32, 6'h1B, 6'h2F, 6'h16, 6'h22
  };

  localparam logic [5:0] IBBB[0:63] = '{
    6'h00, 6'h01, 6'h02, 6'h03, 6'h04, 6'h31, 6'h05, 6'h3A,
    6'h08, 6'h12, 6'h35, 6'h26, 6'h13, 6'h36, 6'h0A, 6'h2C,
    6'h2E, 6'h09, 6'h38, 6'h15, 6'h33, 6'h14, 6'h3E, 6'h0B,
    6'h2B, 6'h10, 6'h25, 6'h3C, 6'h11, 6'h21, 6'h23, 6'h29,
    6'h2F, 6'h27, 6'h3F, 6'h37, 6'h34, 6'h1A, 6'h1D, 6'h39,
    6'h30, 6'h2A, 6'h1F, 6'h0C, 6'h19, 6'h0F, 6'h28, 6'h3D,
    6'h24, 6'h18, 6'h3B, 6'h0D, 6'h20, 6'h0E, 6'h1E, 6'h22,
    6'h1B, 6'h32, 6'h1C, 6'h17, 6'h07, 6'h16, 6'h06, 6'h2D
  };

  // the three 24-bit bit-permutes
  localparam logic [4:0] PI1 [0:23] = '{
      1,  7,  6,  0,  2,  8, 12, 18, 19, 13, 14, 20,
     21, 15, 16, 22, 23, 17,  9,  3,  4, 10, 11,  5
  };
  localparam logic [4:0] PI2 [0:23] = '{
      0,  1,  4,  5,  8,  9,  2,  3,  6,  7, 10, 11,
     16, 12, 13, 17, 20, 21, 15, 14, 18, 19, 22, 23
  };
  localparam logic [4:0] PI3 [0:23] = '{
     16, 22, 11,  5,  2,  8,  0,  6, 19, 13, 12, 18,
     14, 15,  1,  7, 21, 20,  4,  3, 17, 23, 10,  9
  };

  // their inverses
  localparam logic [4:0] IPI1[0:23] = '{
      3,  0,  4, 19, 20, 23,  2,  1,  5, 18, 21, 22,
      6,  9, 10, 13, 14, 17,  7,  8, 11, 12, 15, 16
  };
  localparam logic [4:0] IPI2[0:23] = '{
      0,  1,  6,  7,  2,  3,  8,  9,  4,  5, 10, 11,
     13, 14, 19, 18, 12, 15, 20, 21, 16, 17, 22, 23
  };
  localparam logic [4:0] IPI3[0:23] = '{
      6, 14,  4, 19, 18,  3,  7, 15,  5, 23, 22,  2,
     10,  9, 12, 13,  0, 20, 11,  8, 17, 16,  1, 21
  };
  // Tweak path bit permutations (PI4, PI5) – operate on a 53-bit tweak state
  // correct PI4
  localparam logic [5:0] PI4 [0:52] = '{
      6'd0,  6'd13, 6'd26, 6'd39, 6'd52,
      6'd12, 6'd25, 6'd38, 6'd51, 6'd11,
      6'd24, 6'd37, 6'd50, 6'd10, 6'd23,
      6'd36, 6'd49, 6'd9,  6'd22, 6'd35,
      6'd48, 6'd8,  6'd21, 6'd34, 6'd47,
      6'd7,  6'd20, 6'd33, 6'd46, 6'd6,
      6'd19, 6'd32, 6'd45, 6'd5,  6'd18,
      6'd31, 6'd44, 6'd4,  6'd17, 6'd30,
      6'd43, 6'd3,  6'd16, 6'd29, 6'd42,
      6'd2,  6'd15, 6'd28, 6'd41, 6'd1,
      6'd14, 6'd27, 6'd40
  };
  
  // correct PI5
  localparam logic [5:0] PI5 [0:52] = '{
      6'd0,  6'd11, 6'd22, 6'd33, 6'd44,
      6'd2,  6'd13, 6'd24, 6'd35, 6'd46,
      6'd4,  6'd15, 6'd26, 6'd37, 6'd48,
      6'd6,  6'd17, 6'd28, 6'd39, 6'd50,
      6'd8,  6'd19, 6'd30, 6'd41, 6'd52,
      6'd10, 6'd21, 6'd32, 6'd43, 6'd1,
      6'd12, 6'd23, 6'd34, 6'd45, 6'd3,
      6'd14, 6'd25, 6'd36, 6'd47, 6'd5,
      6'd16, 6'd27, 6'd38, 6'd49, 6'd7,
      6'd18, 6'd29, 6'd40, 6'd51, 6'd9,
      6'd20, 6'd31, 6'd42
  };


endpackage : BipBip_pkg
