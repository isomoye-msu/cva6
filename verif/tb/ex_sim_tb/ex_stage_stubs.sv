`timescale 1ns/1ps
import ex_stage_stub_pkg::*;  // Pulls in fu_data_t, plus operation codes
import config_pkg::*;         // Pulls in cva6_cfg_t

import riscv::*;               

module popcount #(
  parameter int INPUT_WIDTH = 64
)(
  input  logic [INPUT_WIDTH-1:0] data_i,
  output logic [$clog2(INPUT_WIDTH):0] popcount_o
);
  assign popcount_o = '0;
endmodule

module lzc #(
  parameter int WIDTH = 64,
  parameter int MODE  = 1
)(
  input  logic [WIDTH-1:0] in_i,
  output logic [$clog2(WIDTH)-1:0] cnt_o,
  output logic empty_o
);
  assign cnt_o   = '0;
  assign empty_o = (in_i == '0);
endmodule

module alu #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  parameter bit HasBranch = 1'b1,
  parameter type fu_data_t = logic
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  fu_data_t fu_data_i,
  output logic [CVA6Cfg.XLEN-1:0] result_o,
  output logic alu_branch_res_o
);

  localparam bit L_IS_XLEN64  = (CVA6Cfg.XLEN == 64); 
  localparam bit L_IS_XLEN32  = (CVA6Cfg.XLEN == 32); 
  localparam bit L_RVB        = 1'b1;  
  localparam bit L_ZKN        = 1'b0;  
  localparam bit L_RVZiCond   = 1'b0;  
  logic [CVA6Cfg.XLEN-1:0] operand_a_rev;
  logic [31:0]             operand_a_rev32;
  logic [CVA6Cfg.XLEN:0]   operand_b_neg;
  logic [CVA6Cfg.XLEN+1:0] adder_result_ext_o;
  logic                    less;  // handles both signed and unsigned comparisons
  logic [31:0]             rolw;  // Rotate Left Word
  logic [31:0]             rorw;  // Rotate Right Word
  logic [31:0]             orcbw, rev8w;
  logic [$clog2(CVA6Cfg.XLEN):0] cpop; // Count Population
  logic [$clog2(CVA6Cfg.XLEN)-1:0] lz_tz_count;  // Count Leading Zeros
  logic [4:0]              lz_tz_wcount;         // Count Leading Zeros Word
  logic                    lz_tz_empty, lz_tz_wempty;
  logic [CVA6Cfg.XLEN-1:0] orcbw_result, rev8w_result;
  logic [CVA6Cfg.XLEN-1:0] brev8_reversed;
  logic [31:0]             unzip_gen;
  logic [31:0]             zip_gen;

  // Adder signals
  logic adder_op_b_negate;
  logic adder_z_flag;
  logic [CVA6Cfg.XLEN:0]   adder_in_a, adder_in_b;
  logic [CVA6Cfg.XLEN-1:0] adder_result;
  logic [CVA6Cfg.XLEN-1:0] operand_a_bitmanip, bit_indx;

  // Shifts
  logic shift_left;
  logic shift_arithmetic;
  logic [CVA6Cfg.XLEN-1:0] shift_amt;
  logic [CVA6Cfg.XLEN-1:0] shift_op_a;
  logic [31:0]             shift_op_a32;
  logic [CVA6Cfg.XLEN-1:0] shift_result;
  logic [31:0]             shift_result32;
  logic [CVA6Cfg.XLEN:0]   shift_op_a_64, shift_right_result;
  logic [32:0]             shift_op_a_32, shift_right_result32;
  logic [CVA6Cfg.XLEN-1:0] shift_left_result;
  logic [31:0]             shift_left_result32;

  generate
    genvar k;
    for (k = 0; k < CVA6Cfg.XLEN; k++) begin
      assign operand_a_rev[k] = fu_data_i.operand_a[CVA6Cfg.XLEN-1-k];
    end
    for (k = 0; k < 32; k++) begin
      assign operand_a_rev32[k] = fu_data_i.operand_a[31-k];
    end
  endgenerate

  assign adder_op_b_negate = fu_data_i.operation inside {
    EQ, NE, SUB, SUBW, ANDN, ORN, XNOR
  };

  always_comb begin
    $display($time, " ALU sees op=%0d, a=%h, b=%h => result=%h",
            fu_data_i.operation, fu_data_i.operand_a, fu_data_i.operand_b, adder_result);
    operand_a_bitmanip = fu_data_i.operand_a;

    // Some bit manip instructions rewrite operand_a
    //  only if L_RVB is enabled
    if (L_RVB) begin
      if (L_IS_XLEN64) begin
        unique case (fu_data_i.operation)
          SH1ADDUW:           operand_a_bitmanip = fu_data_i.operand_a[31:0] << 1;
          SH2ADDUW:           operand_a_bitmanip = fu_data_i.operand_a[31:0] << 2;
          SH3ADDUW:           operand_a_bitmanip = fu_data_i.operand_a[31:0] << 3;
          CTZW:               operand_a_bitmanip = operand_a_rev32;
          ADDUW, CPOPW, CLZW: operand_a_bitmanip = fu_data_i.operand_a[31:0];
          default:            ;
        endcase
      end

      unique case (fu_data_i.operation)
        SH1ADD: operand_a_bitmanip = fu_data_i.operand_a << 1;
        SH2ADD: operand_a_bitmanip = fu_data_i.operand_a << 2;
        SH3ADD: operand_a_bitmanip = fu_data_i.operand_a << 3;
        CTZ:    operand_a_bitmanip = operand_a_rev;
        default: ;
      endcase
    end
  end

  // Prepare operand_a, operand_b for the adder
  assign adder_in_a         = {operand_a_bitmanip, 1'b1};
  assign operand_b_neg      = {fu_data_i.operand_b, 1'b0} ^ {CVA6Cfg.XLEN + 1{adder_op_b_negate}};
  assign adder_in_b         = operand_b_neg;

  // addition
  assign adder_result_ext_o = adder_in_a + adder_in_b;
  assign adder_result       = adder_result_ext_o[CVA6Cfg.XLEN:1];
  assign adder_z_flag       = ~|adder_result;

  if (HasBranch) begin
    always_comb begin : branch_resolve
      case (fu_data_i.operation)
        EQ:       alu_branch_res_o = adder_z_flag;
        NE:       alu_branch_res_o = ~adder_z_flag;
        LTS, LTU: alu_branch_res_o = less;
        GES, GEU: alu_branch_res_o = ~less;
        default:  alu_branch_res_o = 1'b1;
      endcase
    end
  end else begin
    assign alu_branch_res_o = 1'b0;
  end

  assign shift_amt        = fu_data_i.operand_b;
  assign shift_left       = (fu_data_i.operation == SLL) 
                            | (L_IS_XLEN64 && fu_data_i.operation == SLLW);
  assign shift_arithmetic = (fu_data_i.operation == SRA) 
                            | (L_IS_XLEN64 && fu_data_i.operation == SRAW);

  assign shift_op_a       = shift_left ? operand_a_rev : fu_data_i.operand_a;
  assign shift_op_a32     = shift_left ? operand_a_rev32 : fu_data_i.operand_a[31:0];

  assign shift_op_a_64    = {shift_arithmetic & shift_op_a[CVA6Cfg.XLEN-1], shift_op_a};
  assign shift_op_a_32    = {shift_arithmetic & shift_op_a32[31], shift_op_a32};

  assign shift_right_result   = $unsigned($signed(shift_op_a_64) >>> shift_amt[5:0]);
  assign shift_right_result32 = $unsigned($signed(shift_op_a_32) >>> shift_amt[4:0]);

  genvar j;
  generate
    for (j = 0; j < CVA6Cfg.XLEN; j++)
      assign shift_left_result[j] = shift_right_result[CVA6Cfg.XLEN-1-j];

    for (j = 0; j < 32; j++)
      assign shift_left_result32[j] = shift_right_result32[31-j];
  endgenerate

  assign shift_result   = shift_left ? shift_left_result : shift_right_result[CVA6Cfg.XLEN-1:0];
  assign shift_result32 = shift_left ? shift_left_result32 : shift_right_result32[31:0];

  // Signed vs. unsigned compare
  always_comb begin
    logic sgn;
    sgn = 1'b0;
    if ((fu_data_i.operation == SLTS) ||
        (fu_data_i.operation == LTS)  ||
        (fu_data_i.operation == GES)  ||
        (fu_data_i.operation == MAX)  ||
        (fu_data_i.operation == MIN))
      sgn = 1'b1;

    less = ($signed({sgn & fu_data_i.operand_a[CVA6Cfg.XLEN-1], fu_data_i.operand_a}) <
            $signed({sgn & fu_data_i.operand_b[CVA6Cfg.XLEN-1], fu_data_i.operand_b}));
  end

  // Only do if L_RVB is set, or you can always do it 
  popcount #(.INPUT_WIDTH(CVA6Cfg.XLEN)) i_cpop_count (
    .data_i    (operand_a_bitmanip),
    .popcount_o(cpop)
  );

  // Leading zero count on full XLEN
  lzc #(.WIDTH(CVA6Cfg.XLEN), .MODE(1)) i_clz_64b (
    .in_i   (operand_a_bitmanip),
    .cnt_o  (lz_tz_count),
    .empty_o(lz_tz_empty)
  );

  generate
    if (L_IS_XLEN64) begin : maybe_lzc_32
      lzc #(.WIDTH(32), .MODE(1)) i_clz_32b (
        .in_i   (operand_a_bitmanip[31:0]),
        .cnt_o  (lz_tz_wcount),
        .empty_o(lz_tz_wempty)
      );
    end
  endgenerate

  generate
    if (L_RVB) begin : gen_orcbw_rev8w_results
      always_comb begin
        orcbw = {
          {8{|fu_data_i.operand_a[31:24]}},
          {8{|fu_data_i.operand_a[23:16]}},
          {8{|fu_data_i.operand_a[15:8]}},
          {8{|fu_data_i.operand_a[7:0]}}
        };

        rev8w = {
          fu_data_i.operand_a[7:0],
          fu_data_i.operand_a[15:8],
          fu_data_i.operand_a[23:16],
          fu_data_i.operand_a[31:24]
        };
      end

      if (L_IS_XLEN64) begin : gen_64b
        assign orcbw_result = {
          {8{|fu_data_i.operand_a[63:56]}},
          {8{|fu_data_i.operand_a[55:48]}},
          {8{|fu_data_i.operand_a[47:40]}},
          {8{|fu_data_i.operand_a[39:32]}},
          orcbw
        };
        assign rev8w_result = {
          rev8w,
          fu_data_i.operand_a[39:32],
          fu_data_i.operand_a[47:40],
          fu_data_i.operand_a[55:48],
          fu_data_i.operand_a[63:56]
        };
      end
      else begin : gen_32b
        assign orcbw_result = orcbw;
        assign rev8w_result = rev8w;
      end
    end
    else begin
      // If L_RVB=0, tie them off
      assign orcbw        = '0;
      assign rev8w        = '0;
      assign orcbw_result = '0;
      assign rev8w_result = '0;
    end
  endgenerate

  generate
    if (L_ZKN && L_RVB) begin : zkn_gen_block
      genvar i, m, n;
      for (i = 0; i < (CVA6Cfg.XLEN / 8); i++) begin : brev8_gen
        for (m = 0; m < 8; m++) begin : reverse_bits
          assign brev8_reversed[(i<<3)+m] = fu_data_i.operand_a[(i<<3)+(7-m)];
        end
      end
      if (L_IS_XLEN32) begin
        for (n = 0; n < 16; n++) begin : zip_unzip_gen
          assign zip_gen[n<<1]     = fu_data_i.operand_a[n];
          assign zip_gen[(n<<1)+1] = fu_data_i.operand_a[n+16];
          assign unzip_gen[n]      = fu_data_i.operand_a[n<<1];
          assign unzip_gen[n+16]   = fu_data_i.operand_a[(n<<1)+1];
        end
      end
    end
    else begin
      assign brev8_reversed = '0;
      assign zip_gen        = '0;
      assign unzip_gen      = '0;
    end
  endgenerate

  always_comb begin
    result_o = '0;

    // 64-bit sign extension for W instructions
    if (L_IS_XLEN64) begin
      unique case (fu_data_i.operation)
        // Add word => sign-extend 32 bits
        ADDW, SUBW:
          result_o = {{(CVA6Cfg.XLEN - 32){adder_result[31]}}, adder_result[31:0]};
        SH1ADDUW, SH2ADDUW, SH3ADDUW:
          result_o = adder_result;
        SLLW, SRLW, SRAW:
          result_o = {{(CVA6Cfg.XLEN - 32){shift_result32[31]}}, shift_result32[31:0]};
        default: ;
      endcase
    end

    unique case (fu_data_i.operation)
      // Bitwise
      ANDL, ANDN:
        result_o = fu_data_i.operand_a & operand_b_neg[CVA6Cfg.XLEN:1];
      ORL, ORN:
        result_o = fu_data_i.operand_a | operand_b_neg[CVA6Cfg.XLEN:1];
      XORL, XNOR:
        result_o = fu_data_i.operand_a ^ operand_b_neg[CVA6Cfg.XLEN:1];

      // Add/sub
      ADD, SUB, ADDUW, SH1ADD, SH2ADD, SH3ADD:
        result_o = adder_result;

      // Shift
      SLL, SRL, SRA:
        if (L_IS_XLEN64) result_o = shift_result;
        else             result_o = shift_result32;

      // Compare
      SLTS, SLTU:
        result_o = {{(CVA6Cfg.XLEN - 1){1'b0}}, less};

      default: ;
    endcase

    // Additional RVB-based rotates, min/max, etc.
    if (L_RVB) begin
      bit_indx = 1 << (fu_data_i.operand_b & (CVA6Cfg.XLEN - 1));
      if (L_IS_XLEN64) begin
        // 32-bit rotates
        rolw = ({{(CVA6Cfg.XLEN-32){1'b0}}, fu_data_i.operand_a[31:0]} << fu_data_i.operand_b[4:0])
             | ({{(CVA6Cfg.XLEN-32){1'b0}}, fu_data_i.operand_a[31:0]} >> (CVA6Cfg.XLEN-32 - fu_data_i.operand_b[4:0]));
        rorw = ({{(CVA6Cfg.XLEN-32){1'b0}}, fu_data_i.operand_a[31:0]} >> fu_data_i.operand_b[4:0])
             | ({{(CVA6Cfg.XLEN-32){1'b0}}, fu_data_i.operand_a[31:0]} << (CVA6Cfg.XLEN-32 - fu_data_i.operand_b[4:0]));

        unique case (fu_data_i.operation)
          CLZW, CTZW:
            result_o = (lz_tz_wempty) ? 32
                      : {{(CVA6Cfg.XLEN - 5){1'b0}}, lz_tz_wcount};
          ROLW:
            result_o = {{(CVA6Cfg.XLEN - 32){rolw[31]}}, rolw};
          RORW, RORIW:
            result_o = {{(CVA6Cfg.XLEN - 32){rorw[31]}}, rorw};
          default: ;
        endcase
      end

      unique case (fu_data_i.operation)
        // Min/Max
        MAX:  result_o = less ? fu_data_i.operand_b : fu_data_i.operand_a;
        MAXU: result_o = less ? fu_data_i.operand_b : fu_data_i.operand_a;
        MIN:  result_o = ~less ? fu_data_i.operand_b : fu_data_i.operand_a;
        MINU: result_o = ~less ? fu_data_i.operand_b : fu_data_i.operand_a;

        // Single-bit instructions
        BCLR, BCLRI:
          result_o = fu_data_i.operand_a & ~bit_indx;
        BEXT, BEXTI:
          result_o = {{(CVA6Cfg.XLEN-1){1'b0}}, |(fu_data_i.operand_a & bit_indx)};
        BINV, BINVI:
          result_o = fu_data_i.operand_a ^ bit_indx;
        BSET, BSETI:
          result_o = fu_data_i.operand_a | bit_indx;

        // Leading/Trailing zeros
        CLZ, CTZ:
          result_o = (lz_tz_empty)
            ? ({{(CVA6Cfg.XLEN - $clog2(CVA6Cfg.XLEN)){1'b0}}, lz_tz_count} + 1)
            : {{(CVA6Cfg.XLEN - $clog2(CVA6Cfg.XLEN)){1'b0}}, lz_tz_count};

        // Popcount
        CPOP, CPOPW:
          result_o = {{(CVA6Cfg.XLEN - ($clog2(CVA6Cfg.XLEN)+1)){1'b0}}, cpop};

        // Sign & zero extend
        SEXTB:
          result_o = {{(CVA6Cfg.XLEN-8){fu_data_i.operand_a[7]}}, fu_data_i.operand_a[7:0]};
        SEXTH:
          result_o = {{(CVA6Cfg.XLEN-16){fu_data_i.operand_a[15]}}, fu_data_i.operand_a[15:0]};
        ZEXTH:
          result_o = {{(CVA6Cfg.XLEN-16){1'b0}}, fu_data_i.operand_a[15:0]};

        // Bitwise Rotation
        ROL:
          if (L_IS_XLEN64) begin
            result_o = (fu_data_i.operand_a << fu_data_i.operand_b[5:0])
                     | (fu_data_i.operand_a >> (CVA6Cfg.XLEN - fu_data_i.operand_b[5:0]));
          end
          else begin
            result_o = (fu_data_i.operand_a << fu_data_i.operand_b[4:0])
                     | (fu_data_i.operand_a >> (CVA6Cfg.XLEN - fu_data_i.operand_b[4:0]));
          end

        ROR, RORI:
          if (L_IS_XLEN64) begin
            result_o = (fu_data_i.operand_a >> fu_data_i.operand_b[5:0])
                     | (fu_data_i.operand_a << (CVA6Cfg.XLEN - fu_data_i.operand_b[5:0]));
          end
          else begin
            result_o = (fu_data_i.operand_a >> fu_data_i.operand_b[4:0])
                     | (fu_data_i.operand_a << (CVA6Cfg.XLEN - fu_data_i.operand_b[4:0]));
          end

        ORCB: if (L_RVB) result_o = orcbw_result;
        REV8: if (L_RVB) result_o = rev8w_result;

        // 32-bit left shift
        default:
          if (fu_data_i.operation == SLLIUW && L_IS_XLEN64) begin
            result_o = {{(CVA6Cfg.XLEN-32){1'b0}}, fu_data_i.operand_a[31:0]}
                       << fu_data_i.operand_b[5:0];
          end
      endcase
    end 

    if (L_RVZiCond) begin
      unique case (fu_data_i.operation)
        CZERO_EQZ:
          result_o = (|fu_data_i.operand_b) ? fu_data_i.operand_a : '0;
        CZERO_NEZ:
          result_o = (|fu_data_i.operand_b) ? '0 : fu_data_i.operand_a;
        default: ;
      endcase
    end

    // ZKN instructions
    if (L_ZKN && L_RVB) begin
      unique case (fu_data_i.operation)
        PACK:
          if (L_IS_XLEN32) begin
            result_o = {fu_data_i.operand_b[15:0], fu_data_i.operand_a[15:0]};
          end
          else begin
            result_o = {fu_data_i.operand_b[31:0], fu_data_i.operand_a[31:0]};
          end

        PACK_H:
          if (L_IS_XLEN32) begin
            result_o = {16'b0, fu_data_i.operand_b[7:0], fu_data_i.operand_a[7:0]};
          end
          else begin
            result_o = {48'b0, fu_data_i.operand_b[7:0], fu_data_i.operand_a[7:0]};
          end

        BREV8:
          result_o = brev8_reversed;

        default: ;
      endcase

      if (fu_data_i.operation == PACK_W && L_IS_XLEN64) begin
        result_o = {
          {32{fu_data_i.operand_b[15]}},
          fu_data_i.operand_b[15:0],
          fu_data_i.operand_a[15:0]
        };
      end

      if (fu_data_i.operation == UNZIP && L_IS_XLEN32) begin
        result_o = unzip_gen;
      end

      if (fu_data_i.operation == ZIP && L_IS_XLEN32) begin
        result_o = zip_gen;
      end
    end // if (L_ZKN && L_RVB)
  end 

endmodule

// Module: branch_unit
// Description:
//   This module implements branch evaluation logic for the execute stage.
//   It takes in function unit data, a program counter, and branch prediction
//   signals, and outputs a computed branch target along with control signals
//   for branch resolution. It also provides an exception output if needed.
// Parameters:
//   CVA6Cfg             - Configuration structure for the CVA6 processor.
//   bp_resolve_t        - Type used for branch resolution data.
//   branchpredict_sbe_t - Type used for branch prediction information.
//   exception_t         - Exception type.
//   fu_data_t           - Type for function unit data.
module branch_unit #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  parameter type bp_resolve_t = logic,
  parameter type branchpredict_sbe_t = logic,
  parameter type exception_t = logic,
  parameter type fu_data_t = logic
) (
  input  logic clk_i,                          // Clock input.
  input  logic rst_ni,                         // Active-low reset input.
  input  logic v_i,                            // Valid signal indicating input data is active.
  input  logic debug_mode_i,                   // Debug mode flag.
  input  fu_data_t fu_data_i,                  // Function unit data input.
  input  logic [CVA6Cfg.VLEN-1:0] pc_i,          // Program counter input.
  input  logic is_zcmt_i,                      // Indicates a zero-commit instruction.
  input  logic is_compressed_instr_i,          // Indicates if the instruction is compressed.
  input  logic branch_valid_i,                 // Signal asserting the branch data is valid.
  input  logic branch_comp_res_i,              // Comparison result used in branch decision.
  output logic [CVA6Cfg.VLEN-1:0] branch_result_o, // Computed branch target address.
  input  branchpredict_sbe_t branch_predict_i, // Branch prediction input.
  output bp_resolve_t resolved_branch_o,       // Branch resolution data output.
  output logic resolve_branch_o,               // Control signal to trigger branch resolution.
  output exception_t branch_exception_o        // Exception output signal.
);
  // Stub implementation: All outputs are assigned default values.
  assign branch_result_o = '0;
  assign resolved_branch_o = '0;
  assign resolve_branch_o = 1'b0;
  assign branch_exception_o = '0;
endmodule

// Module: csr_buffer
// Description:
//   Implements a buffer for Control and Status Register operations.
//   The buffer accepts FU data related to CSR operations, provides a handshake
//   interface, and outputs the CSR result along with the accessed CSR address.
// Parameters:
//   CVA6Cfg   - Configuration structure for the CVA6 processor.
//   fu_data_t - Type for function unit data.
module csr_buffer #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  parameter type fu_data_t = logic
) (
  input  logic clk_i,                           // Clock input.
  input  logic rst_ni,                          // Active-low reset input.
  input  logic flush_i,                         // Flush signal to clear the buffer.
  input  fu_data_t fu_data_i,                   // FU data input containing CSR command data.
  input  logic csr_valid_i,                     // Valid signal for the CSR command.
  output logic csr_ready_o,                     // Ready handshake signal.
  output logic [CVA6Cfg.XLEN-1:0] csr_result_o,   // Output result from the CSR operation.
  input  logic csr_commit_i,                    // Commit signal for the CSR operation.
  output logic [11:0] csr_addr_o                // CSR address being accessed.
);
  assign csr_ready_o = 1'b1;
  assign csr_result_o = '0;
  assign csr_addr_o = '0;
endmodule

// Module: mult
// Description:
//   This module implements a multiplier for the execute stage. It accepts
//   multiplication requests with operands embedded in the FU data and produces
//   a multiplication result. It also provides handshake signals and passes a
//   transaction ID to track the operation.
// Parameters:
//   CVA6Cfg   - Configuration structure for the CVA6 processor.
//   fu_data_t - Type for function unit data.

module mult #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  parameter type fu_data_t = logic
) (
  input  logic clk_i,                            // Clock input.
  input  logic rst_ni,                           // Active-low reset.
  input  logic flush_i,                          // Flush signal to reset internal state.
  input  logic mult_valid_i,                     // Valid signal for multiplication operation.
  input  fu_data_t fu_data_i,                    // FU data input containing operands.
  output logic [CVA6Cfg.XLEN-1:0] result_o,        // Multiplication result output.
  output logic mult_valid_o,                     // Valid signal for the result.
  output logic mult_ready_o,                     // Ready signal indicating availability for new operations.
  output logic [CVA6Cfg.TRANS_ID_BITS-1:0] mult_trans_id_o // Transaction ID passed along with the operation.
);
  assign result_o = '0;
  assign mult_valid_o = 1'b0;
  assign mult_ready_o = 1'b1;
  assign mult_trans_id_o = '0;
endmodule

// Module: fpu_wrap
// Description:
//   This module wraps the Floating-Point Unit (FPU) interface. It accepts
//   FPU operations along with their operands and format/rounding parameters,
//   and outputs the computed floating-point result and any exceptions.
// Parameters:
//   CVA6Cfg      - Configuration structure for the CVA6 processor.
//   exception_t  - Exception type for reporting FPU errors.
//   fu_data_t    - Type for function unit data.

module fpu_wrap #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  parameter type exception_t = logic,
  parameter type fu_data_t = logic
) (
  input  logic clk_i,                             // Clock input.
  input  logic rst_ni,                            // Active-low reset.
  input  logic flush_i,                           // Flush signal to clear FPU state.
  input  logic fpu_valid_i,                       // Valid signal for an FPU operation.
  output logic fpu_ready_o,                       // Ready signal indicating FPU is ready.
  input  fu_data_t fu_data_i,                     // FU data input for FPU operation.
  input  logic [1:0] fpu_fmt_i,                   // Format specifier (e.g., single, double precision).
  input  logic [2:0] fpu_rm_i,                    // Rounding mode.
  input  logic [2:0] fpu_frm_i,                   // Additional rounding mode control.
  input  logic [6:0] fpu_prec_i,                  // Precision parameter for floating-point operations.
  output logic [CVA6Cfg.TRANS_ID_BITS-1:0] fpu_trans_id_o, // Transaction ID for the FPU operation.
  output logic [CVA6Cfg.XLEN-1:0] result_o,        // FPU result output.
  output logic fpu_valid_o,                       // Valid signal for the result.
  output exception_t fpu_exception_o              // Exception signal indicating FPU error.
);
  assign fpu_ready_o = 1'b1;
  assign fpu_trans_id_o = '0;
  assign result_o = '0;
  assign fpu_valid_o = 1'b0;
  assign fpu_exception_o = '0;
endmodule

// Module: load_store_unit
// Description:
//   Implements the load/store unit for the execute stage. This module
//   handles memory access requests, including address
//   translation, cache interfacing, and PMP (Physical Memory Protection)
//   checks. It also supports commit handshake signals for memory operations.
// Parameters:
//   CVA6Cfg            - Configuration structure for the CVA6 core.
//   dcache_req_i_t     - Data cache request input type.
//   dcache_req_o_t     - Data cache request output type.
//   exception_t        - Exception type.
//   fu_data_t          - Type for function unit data.
//   icache_areq_t      - Instruction cache address request type.
//   icache_arsp_t      - Instruction cache address response type.
//   icache_dreq_t      - Instruction cache data request type.
//   icache_drsp_t      - Instruction cache data response type.
//   lsu_ctrl_t         - LSU control type.
module load_store_unit #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  parameter type dcache_req_i_t = logic,
  parameter type dcache_req_o_t = logic,
  parameter type exception_t = logic,
  parameter type fu_data_t = logic,
  parameter type icache_areq_t = logic,
  parameter type icache_arsp_t = logic,
  parameter type icache_dreq_t = logic,
  parameter type icache_drsp_t = logic,
  parameter type lsu_ctrl_t = logic
) (
  input  logic clk_i,   // Clock input.
  input  logic rst_ni,  // Active-low reset.
  input  logic flush_i, // Reset internal buffers.
  input  logic stall_st_pending_i, // Indicates a stall.
  output logic no_st_pending_o,    // Indicates no store is pending.
  input  fu_data_t fu_data_i,      // FU data input.
  output logic lsu_ready_o,         // LSU ready for new memory operation.
  input  logic lsu_valid_i,         // Valid signal for the LSU request.
  output logic [CVA6Cfg.TRANS_ID_BITS-1:0] load_trans_id_o, // Transaction ID for load.
  output logic [CVA6Cfg.XLEN-1:0] load_result_o,           // Data loaded from memory.
  output logic load_valid_o,        // Valid signal for the load result.
  output exception_t load_exception_o, // Exceptions for load.
  output logic [CVA6Cfg.TRANS_ID_BITS-1:0] store_trans_id_o, // Transaction ID for store.
  output logic [CVA6Cfg.XLEN-1:0] store_result_o,          // Store operation result.
  output logic store_valid_o,       // Valid signal for store result.
  output exception_t store_exception_o, // Exception for store.
  input  logic commit_i,            // Commit signal for store operations.
  output logic commit_ready_o,      // Ready signal for commit.
  input  logic [CVA6Cfg.TRANS_ID_BITS-1:0] commit_tran_id_i, // Transaction ID for commit.
  input  logic enable_translation_i, // Enable virtual-to-physical translation.
  input  logic enable_g_translation_i, // Enable guest translation.
  input  logic en_ld_st_translation_i, // Enable translation for load/store.
  input  logic en_ld_st_g_translation_i, // Enable guest translation for load/store.
  input  icache_arsp_t icache_areq_i,  // Instruction cache address response input.
  output icache_areq_t icache_areq_o,  // Instruction cache address request output.
  input  riscv::priv_lvl_t priv_lvl_i, // Current privilege level.
  input  logic v_i,                   // Valid signal for vector instructions.
  input  riscv::priv_lvl_t ld_st_priv_lvl_i, // Privilege level for load/store.
  input  logic ld_st_v_i,             // Valid signal for load/store translation.
  output logic csr_hs_ld_st_inst_o,   // CSR handshake signal for load/store.
  input  logic sum_i,                 // Supervisor user memory access control.
  input  logic vs_sum_i,              // Virtual supervisor user memory access control.
  input  logic mxr_i,                 // Memory-execute-read flag.
  input  logic vmxr_i,                // Virtual memory-execute-read flag.
  input  logic [CVA6Cfg.PPNW-1:0] satp_ppn_i, // SATP physical page number.
  input  logic [CVA6Cfg.PPNW-1:0] vsatp_ppn_i, // VSATP physical page number.
  input  logic [CVA6Cfg.PPNW-1:0] hgatp_ppn_i, // HGATP physical page number.
  input  logic [CVA6Cfg.ASID_WIDTH-1:0] asid_i, // ASID for current address space.
  input  logic [CVA6Cfg.ASID_WIDTH-1:0] vs_asid_i, // Virtual ASID.
  input  logic [CVA6Cfg.ASID_WIDTH-1:0] asid_to_be_flushed_i, // ASID for which translations are to be flushed.
  input  logic [CVA6Cfg.VMID_WIDTH-1:0] vmid_i, // Virtual memory identifier.
  input  logic [CVA6Cfg.VMID_WIDTH-1:0] vmid_to_be_flushed_i, // VMID to be flushed.
  input  logic [CVA6Cfg.VLEN-1:0] vaddr_to_be_flushed_i, // Virtual address for TLB flush.
  input  logic [CVA6Cfg.GPLEN-1:0] gpaddr_to_be_flushed_i, // Guest physical address for TLB flush.
  input  logic flush_tlb_i,           // Global TLB flush signal.
  input  logic flush_tlb_vvma_i,      // TLB flush based on virtual addresses.
  input  logic flush_tlb_gvma_i,      // TLB flush for guest virtual addresses.
  output logic itlb_miss_o,           // Instruction TLB miss indicator.
  output logic dtlb_miss_o,           // Data TLB miss indicator.
  input  dcache_req_o_t [2:0] dcache_req_ports_i, // Data cache request inputs.
  output dcache_req_i_t [2:0] dcache_req_ports_o,  // Data cache request outputs.
  input  logic dcache_wbuffer_empty_i,  // Indicates data cache write buffer is empty.
  input  logic dcache_wbuffer_not_ni_i,   // Indicates write buffer is not in a non-interruptible state.
  input  logic amo_valid_commit_i,    // Valid signal for atomic memory operation commit.
  output amo_req_t amo_req_o,         // Atomic memory operation request output.
  input  amo_resp_t amo_resp_i,       // Atomic memory operation response input.
  input  logic [31:0] tinst_i,        // 32-bit encoded instruction.
  input  riscv::pmpcfg_t [(CVA6Cfg.NrPMPEntries>0 ? CVA6Cfg.NrPMPEntries-1 : 0):0] pmpcfg_i, // Array of PMP configuration entries.
  input  logic [(CVA6Cfg.NrPMPEntries>0 ? CVA6Cfg.NrPMPEntries-1 : 0):0][CVA6Cfg.PLEN-3:0] pmpaddr_i, // Array of PMP address values.
  output ex_stage_stub_pkg::lsu_ctrl_t rvfi_lsu_ctrl_o, // LSU control signals for RVFI (verification interface).
  output logic [CVA6Cfg.PLEN-1:0] rvfi_mem_paddr_o // Physical memory address output for RVFI.
);
  assign no_st_pending_o = 1'b1;
  assign lsu_ready_o = 1'b1;
  assign load_trans_id_o = '0;
  assign load_result_o = '0;
  assign load_valid_o = 1'b0;
  assign load_exception_o = '0;
  assign store_trans_id_o = '0;
  assign store_result_o = '0;
  assign store_valid_o = 1'b0;
  assign store_exception_o = '0;
  assign commit_ready_o = 1'b1;
  assign csr_hs_ld_st_inst_o = 1'b0;
  assign itlb_miss_o = 1'b0;
  assign dtlb_miss_o = 1'b0;
  assign dcache_req_ports_o = '{default:'0};
  assign amo_req_o = '{valid:1'b0};
  assign rvfi_lsu_ctrl_o = '{valid:1'b0};
  assign rvfi_mem_paddr_o = '0;
  assign icache_areq_o = '0;
endmodule

// Module: cvxif_fu
// Description:
//   This module implements the Custom Vector Extension Interface (CVXIF)
//   function unit. It accepts an operation and produces a result along with handshake
//   signals and a register write enable output.
// Parameters:
//   CVA6Cfg      - CVA6 configuration parameters.
//   exception_t  - Exception type for error reporting.
//   x_result_t   - Data type for the result produced by the unit.
module cvxif_fu #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  parameter type exception_t = logic,
  parameter type x_result_t = logic
) (
  input  logic clk_i,   // Clock input.
  input  logic rst_ni,  // Active-low reset.
  input  logic x_valid_i,  // Valid signal indicating input data is available.
  input  logic [CVA6Cfg.TRANS_ID_BITS-1:0] x_trans_id_i, // Input transaction ID.
  input  logic x_illegal_i, // Flag indicating an illegal operation.
  input  logic [31:0] x_off_instr_i, // Instruction offset for the operation.
  output logic x_ready_o, // Ready signal to accept new data.
  output logic [CVA6Cfg.TRANS_ID_BITS-1:0] x_trans_id_o, // Propagated transaction ID.
  output exception_t x_exception_o, // Exception output.
  output logic [CVA6Cfg.XLEN-1:0] x_result_o, // Function unit result.
  output logic x_valid_o, // Valid signal for the result.
  output logic x_we_o,    // Write-enable signal for writing the result.
  output logic [4:0] x_rd_o, // Destination register address.
  input  logic result_valid_i, // Signal indicating subsequent result validity.
  input  x_result_t result_i,  // Input result data from a later stage.
  output logic result_ready_o  // Ready signal for accepting the next result.
);
  assign x_ready_o = 1'b1;
  assign x_trans_id_o = '0;
  assign x_exception_o = '0;
  assign x_result_o = '0;
  assign x_valid_o = 1'b0;
  assign x_we_o = 1'b0;
  assign x_rd_o = 5'h0;
  assign result_ready_o = 1'b1;
endmodule
