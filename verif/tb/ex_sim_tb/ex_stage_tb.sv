`timescale 1ns/1ps
`include "rvfi_types.svh"
`include "cvxif_types.svh"

// ----------------------------------------------------------------------
// Module: ex_stage_tb
// Description:
//   Testbench for the ex_stage (execute stage) of the CVA6 processor.
//   Instantiates the DUT, sets up clock/reset, declares interface signals,
//   and applies a simple ALU operation as a stimulus.
// ----------------------------------------------------------------------
module ex_stage_tb;
  import ex_stage_stub_pkg::*;
  import config_pkg::*;
  import riscv::*;

  // ----------------------------------------------------------------------
  // Local Parameter: MY_EX_CFG
  //   Sets up the configuration for the DUT, including issue ports,
  //   data widths, transaction ID bits, and other flags. PMP entries are 0
  //   so PMP arrays are dummy.
  // ----------------------------------------------------------------------
  localparam cva6_cfg_t MY_EX_CFG = '{
    NrIssuePorts : 2,
    VLEN         : 64,
    XLEN         : 64,
    TRANS_ID_BITS: 5,
    PPNW         : 20,
    ASID_WIDTH   : 16,
    VMID_WIDTH   : 14,
    GPLEN        : 12,
    PLEN         : 54,
    NrPMPEntries : 0,
    SuperscalarEn: 0,
    FpPresent    : 0,
    RVS          : 0,
    RVH          : 0,
    CvxifEn      : 0
  };

  // Clock and reset
  logic clk;
  logic rst_ni;

  // Generate a 10 ns clock
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Hold reset low for 15 ns, then release
  initial begin
    rst_ni = 0;
    #15 rst_ni = 1;
  end

  // ----------------------------------------------------------------------
  // DUT Interface Signals
  // ----------------------------------------------------------------------
  logic flush_i;
  logic debug_mode_i;

  // Forwarding arrays
  logic [MY_EX_CFG.NrIssuePorts-1:0][MY_EX_CFG.VLEN-1:0] rs1_forwarding_i;
  logic [MY_EX_CFG.NrIssuePorts-1:0][MY_EX_CFG.VLEN-1:0] rs2_forwarding_i;

  // Function unit data inputs
  fu_data_t [MY_EX_CFG.NrIssuePorts-1:0] fu_data_i;

  // Program counter and instruction data
  logic [MY_EX_CFG.VLEN-1:0] pc_i;
  logic is_zcmt_i;
  logic is_compressed_instr_i;
  logic [MY_EX_CFG.NrIssuePorts-1:0][31:0] tinst_i;

  // Valid signals for various functional units
  logic [MY_EX_CFG.NrIssuePorts-1:0] alu_valid_i;
  logic [MY_EX_CFG.NrIssuePorts-1:0] branch_valid_i;
  branchpredict_sbe_t branch_predict_i;
  logic [MY_EX_CFG.NrIssuePorts-1:0] csr_valid_i;
  logic csr_commit_i;
  logic [MY_EX_CFG.NrIssuePorts-1:0] mult_valid_i;
  logic [MY_EX_CFG.NrIssuePorts-1:0] lsu_valid_i;
  logic lsu_commit_i;
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] commit_tran_id_i;
  logic stall_st_pending_i;
  logic amo_valid_commit_i;
  logic [MY_EX_CFG.NrIssuePorts-1:0] fpu_valid_i;
  logic [1:0] fpu_fmt_i;
  logic [2:0] fpu_rm_i;
  logic [2:0] fpu_frm_i;
  logic [6:0] fpu_prec_i;
  logic [MY_EX_CFG.NrIssuePorts-1:0] alu2_valid_i;
  logic [MY_EX_CFG.NrIssuePorts-1:0] x_valid_i;
  logic [31:0] x_off_instr_i;

  // CVXIF signals
  logic x_result_valid_i;
  x_result_t x_result_i;
  x_result_t x_result_o;
  logic x_transaction_rejected_i;
  logic acc_valid_i;

  // Translation and CSR signals
  logic enable_translation_i;
  logic enable_g_translation_i;
  logic en_ld_st_translation_i;
  logic en_ld_st_g_translation_i;
  logic flush_tlb_i;
  logic flush_tlb_vvma_i;
  logic flush_tlb_gvma_i;
  priv_lvl_t priv_lvl_i;
  logic v_i;
  priv_lvl_t ld_st_priv_lvl_i;
  logic ld_st_v_i;
  logic sum_i;
  logic vs_sum_i;
  logic mxr_i;
  logic vmxr_i;
  logic [MY_EX_CFG.PPNW-1:0] satp_ppn_i;
  logic [MY_EX_CFG.PPNW-1:0] vsatp_ppn_i;
  logic [MY_EX_CFG.PPNW-1:0] hgatp_ppn_i;
  logic [MY_EX_CFG.ASID_WIDTH-1:0] asid_i;
  logic [MY_EX_CFG.ASID_WIDTH-1:0] vs_asid_i;
  logic [MY_EX_CFG.VMID_WIDTH-1:0] vmid_i;

  // FLU outputs
  logic [MY_EX_CFG.XLEN-1:0] flu_result_o;
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] flu_trans_id_o;
  exception_t flu_exception_o;
  logic flu_ready_o, flu_valid_o;

  // Branch outputs
  bp_resolve_t resolved_branch_o;
  logic resolve_branch_o;
  logic [11:0] csr_addr_o;

  // LSU outputs
  logic lsu_ready_o;
  logic load_valid_o;
  logic [MY_EX_CFG.XLEN-1:0] load_result_o;
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] load_trans_id_o;
  exception_t load_exception_o;
  logic store_valid_o;
  logic [MY_EX_CFG.XLEN-1:0] store_result_o;
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] store_trans_id_o;
  exception_t store_exception_o;
  logic lsu_commit_ready_o;
  logic no_st_pending_o;

  // FPU outputs
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] fpu_trans_id_o;
  logic [MY_EX_CFG.XLEN-1:0] fpu_result_o;
  logic fpu_valid_o;
  exception_t fpu_exception_o;

  // CVXIF outputs
  logic x_ready_o;
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] x_trans_id_o;
  exception_t x_exception_o;
  logic x_we_o;
  logic [4:0] x_rd_o;
  logic x_result_ready_o;

  // CSR handshake for LSU
  logic csr_hs_ld_st_inst_o;
  logic [MY_EX_CFG.PLEN-1:0] rvfi_mem_paddr_o;
  lsu_ctrl_t rvfi_lsu_ctrl_o;

  // Cache interface signals
  icache_areq_t icache_areq_i;
  icache_areq_t icache_areq_o;
  dcache_req_o_t [2:0] dcache_req_ports_i;
  dcache_req_i_t [2:0] dcache_req_ports_o;
  logic dcache_wbuffer_empty_i;
  logic dcache_wbuffer_not_ni_i;
  amo_req_t amo_req_o;
  amo_resp_t amo_resp_i;
  logic itlb_miss_o;
  logic dtlb_miss_o;

  // PMP arrays (dummy if NrPMPEntries=0)
  riscv::pmpcfg_t [((MY_EX_CFG.NrPMPEntries > 0) ? MY_EX_CFG.NrPMPEntries-1 : 0) : 0] pmpcfg_i;
  logic [MY_EX_CFG.PLEN-3:0] [((MY_EX_CFG.NrPMPEntries > 0) ? MY_EX_CFG.NrPMPEntries-1 : 0) : 0] pmpaddr_i;

  // Zero out PMP arrays
  initial begin
    for (int i = 0; i < ((MY_EX_CFG.NrPMPEntries > 0) ? MY_EX_CFG.NrPMPEntries : 1); i++) begin
      pmpcfg_i[i] = 8'b0;
      pmpaddr_i[i] = '0;
    end
  end

  // ----------------------------------------------------------------------
  // Instantiate the ex_stage DUT
  // ----------------------------------------------------------------------
  ex_stage #(
    .CVA6Cfg(MY_EX_CFG),
    .bp_resolve_t(bp_resolve_t),
    .branchpredict_sbe_t(branchpredict_sbe_t),
    .dcache_req_i_t(dcache_req_i_t),
    .dcache_req_o_t(dcache_req_o_t),
    .exception_t(exception_t),
    .fu_data_t(fu_data_t),
    .icache_areq_t(icache_areq_t),
    .icache_arsp_t(icache_arsp_t),
    .icache_dreq_t(icache_dreq_t),
    .icache_drsp_t(icache_drsp_t),
    .lsu_ctrl_t(lsu_ctrl_t),
    .x_result_t(x_result_t)
  ) dut (
    .clk_i                (clk),
    .rst_ni               (rst_ni),
    .flush_i              (flush_i),
    .debug_mode_i         (debug_mode_i),
    .rs1_forwarding_i     (rs1_forwarding_i),
    .rs2_forwarding_i     (rs2_forwarding_i),
    .fu_data_i            (fu_data_i),
    .pc_i                 (pc_i),
    .is_zcmt_i            (is_zcmt_i),
    .is_compressed_instr_i(is_compressed_instr_i),
    .tinst_i              (tinst_i),
    .flu_result_o         (flu_result_o),
    .flu_trans_id_o       (flu_trans_id_o),
    .flu_exception_o      (flu_exception_o),
    .flu_ready_o          (flu_ready_o),
    .flu_valid_o          (flu_valid_o),
    .alu_valid_i          (alu_valid_i),
    .priv_lvl_i           (priv_lvl_i),
    .branch_valid_i       (branch_valid_i),
    .branch_predict_i     (branch_predict_i),
    .resolved_branch_o    (resolved_branch_o),
    .resolve_branch_o     (resolve_branch_o),
    .csr_valid_i          (csr_valid_i),
    .csr_addr_o           (csr_addr_o),
    .csr_commit_i         (csr_commit_i),
    .mult_valid_i         (mult_valid_i),
    .lsu_ready_o          (lsu_ready_o),
    .lsu_valid_i          (lsu_valid_i),
    .load_valid_o         (load_valid_o),
    .load_result_o        (load_result_o),
    .load_trans_id_o      (load_trans_id_o),
    .load_exception_o     (load_exception_o),
    .store_valid_o        (store_valid_o),
    .store_result_o       (store_result_o),
    .store_trans_id_o     (store_trans_id_o),
    .store_exception_o    (store_exception_o),
    .lsu_commit_i         (lsu_commit_i),
    .lsu_commit_ready_o   (lsu_commit_ready_o),
    .commit_tran_id_i     (commit_tran_id_i),
    .stall_st_pending_i   (stall_st_pending_i),
    .no_st_pending_o      (no_st_pending_o),
    .amo_valid_commit_i   (amo_valid_commit_i),
    .fpu_ready_o          (fpu_ready_o),
    .fpu_valid_i          (fpu_valid_i),
    .fpu_fmt_i            (fpu_fmt_i),
    .fpu_rm_i             (fpu_rm_i),
    .fpu_frm_i            (fpu_frm_i),
    .fpu_prec_i           (fpu_prec_i),
    .fpu_trans_id_o       (fpu_trans_id_o),
    .fpu_result_o         (fpu_result_o),
    .fpu_valid_o          (fpu_valid_o),
    .fpu_exception_o      (fpu_exception_o),
    .alu2_valid_i         (alu2_valid_i),
    .x_valid_i            (x_valid_i),
    .x_ready_o            (x_ready_o),
    .x_off_instr_i        (x_off_instr_i),
    .x_trans_id_o         (x_trans_id_o),
    .x_exception_o        (x_exception_o),
    .x_result_o           (x_result_o),
    .x_valid_o            (x_result_valid_i),
    .x_we_o               (x_we_o),
    .x_rd_o               (x_rd_o),
    .x_result_valid_i     (x_result_valid_i),
    .x_result_i           (x_result_i),
    .x_result_ready_o     (x_result_ready_o),
    .x_transaction_rejected_i(x_transaction_rejected_i),
    .acc_valid_i          (acc_valid_i),
    .enable_translation_i (enable_translation_i),
    .enable_g_translation_i(enable_g_translation_i),
    .en_ld_st_translation_i(en_ld_st_translation_i),
    .en_ld_st_g_translation_i(en_ld_st_g_translation_i),
    .flush_tlb_i          (flush_tlb_i),
    .flush_tlb_vvma_i     (flush_tlb_vvma_i),
    .flush_tlb_gvma_i     (flush_tlb_gvma_i),
    .v_i                  (v_i),
    .ld_st_priv_lvl_i     (ld_st_priv_lvl_i),
    .ld_st_v_i            (ld_st_v_i),
    .csr_hs_ld_st_inst_o  (csr_hs_ld_st_inst_o),
    .sum_i                (sum_i),
    .vs_sum_i             (vs_sum_i),
    .mxr_i                (mxr_i),
    .vmxr_i               (vmxr_i),
    .satp_ppn_i           (satp_ppn_i),
    .asid_i               (asid_i),
    .vsatp_ppn_i          (vsatp_ppn_i),
    .vs_asid_i            (vs_asid_i),
    .hgatp_ppn_i          (hgatp_ppn_i),
    .vmid_i               (vmid_i),
    .icache_areq_i        (icache_areq_i),
    .icache_areq_o        (icache_areq_o),
    .dcache_req_ports_i   (dcache_req_ports_i),
    .dcache_req_ports_o   (dcache_req_ports_o),
    .dcache_wbuffer_empty_i(dcache_wbuffer_empty_i),
    .dcache_wbuffer_not_ni_i(dcache_wbuffer_not_ni_i),
    .amo_req_o            (amo_req_o),
    .amo_resp_i           (amo_resp_i),
    .itlb_miss_o          (itlb_miss_o),
    .dtlb_miss_o          (dtlb_miss_o),
    .pmpcfg_i             (pmpcfg_i),
    .pmpaddr_i            (pmpaddr_i),
    .rvfi_lsu_ctrl_o      (rvfi_lsu_ctrl_o),
    .rvfi_mem_paddr_o     (rvfi_mem_paddr_o)
  );

  // ----------------------------------------------------------------------
  // Initialize inputs and drive a simple ALU operation
  // ----------------------------------------------------------------------
  initial begin
    // Zero everything, wait for reset
    @(posedge rst_ni);
    @(posedge clk);

    // Issue an ALU operation
    alu_valid_i[0]         = 1;
    fu_data_i[0].operation = ADD;
    fu_data_i[0].operand_a = 64'h10;
    fu_data_i[0].operand_b = 64'h7;

    // Check flu_valid_o in the same cycle
    #0;
    if (flu_valid_o) begin
      $display("Got FLU valid in the same cycle: result = %h", flu_result_o);
    end

    // Deassert after one cycle
    @(posedge clk);
    alu_valid_i[0] = 0;

    #5;
    $finish;
  end

endmodule
