`timescale 1ns/1ps
import ex_stage_stub_pkg::*;   // Definitions for stub types used by the execute stage.
import config_pkg::*;          
import riscv::*;               

// Module: alu
// Description:
//   This module represents a simple ALU for the execute stage.
//    It accepts function unit data and
//   produces a result and a branch resolution signal (OPTIONAL).
// Parameters:
//   CVA6Cfg      - A structure containing configuration parameters for
//                  the CVA6 processor (default is cva6_cfg_empty).
//   HasBranch    - A flag indicating whether branch logic is implemented.
//   fu_data_t    - The data type used for FU data (default is simple logic).
module alu #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  parameter bit HasBranch = 1'b0,
  parameter type fu_data_t = logic
) (
  input  logic clk_i,                           // Clock input.
  input  logic rst_ni,                          // Active-low reset input.
  input  fu_data_t fu_data_i,                   // Function unit data input.
  output logic [CVA6Cfg.XLEN-1:0] result_o,       // ALU result output.
  output logic alu_branch_res_o                 // Branch resolution output.
);
  assign result_o = '0;           // Result is statically 0.
  assign alu_branch_res_o = 1'b0;  // Branch resolution signal is deasserted.
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
