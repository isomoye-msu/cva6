`timescale 1ns/1ps 

// Module: ex_stage_tb
// Description: 
//   Testbench for the execute stage (ex_stage.sv) of the CVA6 processor.
//   Testbench instantiates the DUT, generates a clock and reset,
//   declares all required interface signals, and applies a stimulus to
//   exercise a simple ALU operation.
module ex_stage_tb;
  import ex_stage_stub_pkg::*; 
  import config_pkg::*;        
  import riscv::*;             

  // 1) Configuration: Define MY_EX_CFG.
  // Description:
  //   Create a local parameter that sets the configuration for the DUT.
  //   This includes the number of issue ports, vector/data widths, transaction ID
  //   bits, and various control flags. The NrPMPEntries field is set to 0 so that
  //   the PMP arrays are dummy-up.
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
  // 2) Clock and Reset Generation
  // Description:
  //   Generate a periodic clock signal and an active-low reset signal.
  logic clk;      // Clock signal
  logic rst_ni;   // Active-low reset signal

  // Clock generation block: initialize clock to 0 and toggle every 5 time units.
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // Clock period = 10 ns
  end

  // Reset generation block: hold reset low for 15 time units, then deassert.
  initial begin
    rst_ni = 0;
    #15 rst_ni = 1;
  end

  // 3) Declare DUT Interface Signals
  // Description:
  //   Declare all signals that interface to the DUT (ex_stage).
  //   Ensure the signal dimensions and packing match exactly those expected by the DUT.
  // Pipeline control and data inputs:
  logic flush_i;             // Flush signal to clear pipeline stages
  logic debug_mode_i;        // Debug mode flag

  // Forwarding arrays: two arrays for the first and second source operands.
  // These arrays are declared as packed arrays with the leftmost dimension
  // representing the issue port index.
  logic [MY_EX_CFG.NrIssuePorts-1:0][MY_EX_CFG.VLEN-1:0] rs1_forwarding_i;
  logic [MY_EX_CFG.NrIssuePorts-1:0][MY_EX_CFG.VLEN-1:0] rs2_forwarding_i;

  // Function unit data input: an array of structures (one per issue port).
  fu_data_t [MY_EX_CFG.NrIssuePorts-1:0] fu_data_i;

  // Program counter and instruction data:
  logic [MY_EX_CFG.VLEN-1:0] pc_i;  // Program counter input
  logic is_zcmt_i;                // Flag indicating a "zero commit" (or similar) condition
  logic is_compressed_instr_i;    // Flag indicating if the instruction is compressed
  // Instruction bits for each issue port, 32 bits wide.
  logic [MY_EX_CFG.NrIssuePorts-1:0][31:0] tinst_i;

  // Valid signals for various functional units:
  logic [MY_EX_CFG.NrIssuePorts-1:0] alu_valid_i;     
  logic [MY_EX_CFG.NrIssuePorts-1:0] branch_valid_i;   
  branchpredict_sbe_t branch_predict_i;               
  logic [MY_EX_CFG.NrIssuePorts-1:0] csr_valid_i;      
  logic csr_commit_i;                                
  logic [MY_EX_CFG.NrIssuePorts-1:0] mult_valid_i;      
  logic [MY_EX_CFG.NrIssuePorts-1:0] lsu_valid_i;        
  logic lsu_commit_i;                                 
  // Transaction identifier for commit (width defined by configuration)
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] commit_tran_id_i;
  logic stall_st_pending_i;                            // Signal indicating a store is pending (stall)
  logic amo_valid_commit_i;                            // Valid signal for atomic memory commit
  logic [MY_EX_CFG.NrIssuePorts-1:0] fpu_valid_i;        // Floating-point unit valid signals
  logic [1:0] fpu_fmt_i;                               // FPU format specifier
  logic [2:0] fpu_rm_i;                                // FPU rounding mode
  logic [2:0] fpu_frm_i;                               // Additional FPU rounding mode control
  logic [6:0] fpu_prec_i;                              // FPU precision parameter
  logic [MY_EX_CFG.NrIssuePorts-1:0] alu2_valid_i;      // Secondary ALU valid signals
  logic [MY_EX_CFG.NrIssuePorts-1:0] x_valid_i;         // Vector unit valid signals
  logic [31:0] x_off_instr_i;                          // Instruction offset for the vector unit

  // CVXIF (Custom Vector Extension Interface) signals:
  // x_result_valid_i is an output from the DUT and must not be driven procedurally.
  logic x_result_valid_i;
  x_result_t x_result_i;       // Intermediate result signal from vector operations
  x_result_t x_result_o;       // The result produced by the DUT (driven structurally)
  logic x_transaction_rejected_i;  // Flag indicating transaction rejection in CVXIF
  logic acc_valid_i;         // Access valid flag for the CVXIF interface

  // Translation and CSR control signals:
  logic enable_translation_i;    // Enable address translation
  logic enable_g_translation_i;  // Enable guest address translation
  logic en_ld_st_translation_i;  // Enable translation for load/store
  logic en_ld_st_g_translation_i; // Enable guest translation for load/store
  logic flush_tlb_i;             // Global flush signal for the TLB
  logic flush_tlb_vvma_i;        // TLB flush signal for virtual addresses
  logic flush_tlb_gvma_i;        // TLB flush signal for guest virtual addresses
  priv_lvl_t priv_lvl_i;         // Current privilege level (from riscv package)
  logic v_i;                     // Valid signal for vector operations
  priv_lvl_t ld_st_priv_lvl_i;   // Privilege level for load/store operations
  logic ld_st_v_i;               // Valid signal for load/store translation
  // Additional control signals for memory accesses:
  logic sum_i;                   // Supervisor use flag for memory accesses
  logic vs_sum_i;                // Virtual supervisor use flag
  logic mxr_i;                   // Memory-execute-read flag
  logic vmxr_i;                  // Virtual memory-execute-read flag
  // SATP and related physical page number signals:
  logic [MY_EX_CFG.PPNW-1:0] satp_ppn_i;
  logic [MY_EX_CFG.PPNW-1:0] vsatp_ppn_i;
  logic [MY_EX_CFG.PPNW-1:0] hgatp_ppn_i;
  // ASID signals for current and virtual address spaces:
  logic [MY_EX_CFG.ASID_WIDTH-1:0] asid_i;
  logic [MY_EX_CFG.ASID_WIDTH-1:0] vs_asid_i;
  // Virtual Memory Identifier signal:
  logic [MY_EX_CFG.VMID_WIDTH-1:0] vmid_i;

  // DUT-Driven Output Signals
  // These signals are driven by the DUT and observed by the TB.

  // Results from the Functional Logic Unit (FLU)
  logic [MY_EX_CFG.XLEN-1:0] flu_result_o;    // Computed result from the FLU
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] flu_trans_id_o; // Transaction ID associated with the result
  exception_t flu_exception_o;                // Exception information from the FLU
  logic flu_ready_o, flu_valid_o;               // Handshake signals for the FLU

  // Branch unit outputs
  bp_resolve_t resolved_branch_o;             // Branch resolution information
  logic resolve_branch_o;                       // Signal to trigger branch resolution
  logic [11:0] csr_addr_o;                      // CSR address output from the branch unit (if applicable)

  // Load/Store Unit (LSU) outputs
  logic lsu_ready_o;                            // LSU ready signal
  logic load_valid_o;                           // Valid signal for load data
  logic [MY_EX_CFG.XLEN-1:0] load_result_o;       // Data read from memory (load result)
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] load_trans_id_o; // Load transaction ID
  exception_t load_exception_o;               // Exception information from a load operation
  logic store_valid_o;                          // Valid signal for store result
  logic [MY_EX_CFG.XLEN-1:0] store_result_o;      // Store operation result
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] store_trans_id_o; // Store transaction ID
  exception_t store_exception_o;              // Exception information from a store operation
  logic lsu_commit_ready_o;                     // Ready signal for commit operation
  logic no_st_pending_o;                        // Indicates no store operations are pending

  // FPU outputs
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] fpu_trans_id_o; // FPU transaction ID
  logic [MY_EX_CFG.XLEN-1:0] fpu_result_o;       // Result from the FPU
  logic fpu_valid_o;                            // FPU result valid signal
  exception_t fpu_exception_o;                  // FPU exception output

  // CVXIF unit outputs
  logic x_ready_o;                              // CVXIF ready signal
  logic [MY_EX_CFG.TRANS_ID_BITS-1:0] x_trans_id_o; // CVXIF transaction ID
  exception_t x_exception_o;                    // CVXIF exception output
  logic x_we_o;                                 // Write-enable for CVXIF result
  logic [4:0] x_rd_o;                           // Destination register address for CVXIF result
  logic x_result_ready_o;                       // CVXIF result ready signal

  // CSR handshake output for LSU operations
  logic csr_hs_ld_st_inst_o;                    // Handshake signal for CSR load/store instructions
  // RVFI (RISC-V Formal Interface) outputs
  logic [MY_EX_CFG.PLEN-1:0] rvfi_mem_paddr_o;   // Physical memory address output for formal verification
  lsu_ctrl_t rvfi_lsu_ctrl_o;                   // LSU control signals for formal verification

  // Other Signals (Interfacing with caches, PMP, etc.)

  // Instruction Cache Interface:
  // These signals are declared using the typedef so that assignment patterns work.
  icache_areq_t icache_areq_i;                  // Instruction cache request input
  icache_areq_t icache_areq_o;                  // Instruction cache request output

  // Data Cache Interface:
  // The DUT expects:
  //   - dcache_req_ports_i: input of type dcache_req_o_t [2:0]
  //   - dcache_req_ports_o: output of type dcache_req_i_t [2:0]
  // We declare these as packed arrays with the same fixed range.
  dcache_req_o_t [2:0] dcache_req_ports_i;      // Data cache request inputs (from cache)
  dcache_req_i_t [2:0] dcache_req_ports_o;      // Data cache request outputs (to cache)

  // Additional Dcache Signals:
  logic dcache_wbuffer_empty_i;                 // Indicates if the data cache write buffer is empty
  logic dcache_wbuffer_not_ni_i;                // Indicates if the write buffer is not in a non-interruptible state
  amo_req_t amo_req_o;                          // Atomic memory operation request signal (output)
  amo_resp_t amo_resp_i;                        // Atomic memory operation response signal (input)
  logic itlb_miss_o;                            // Instruction TLB miss indicator
  logic dtlb_miss_o;                            // Data TLB miss indicator

  // Physical Memory Protection (PMP) Arrays:
  // The DUT expects these arrays with a range that depends on the configuration.
  // When NrPMPEntries > 0, the range is [NrPMPEntries-1:0]; when it is 0, a dummy element [0:0] is created.
  riscv::pmpcfg_t [((MY_EX_CFG.NrPMPEntries > 0) ? MY_EX_CFG.NrPMPEntries-1 : 0) : 0] pmpcfg_i;
  logic [MY_EX_CFG.PLEN-3:0] [((MY_EX_CFG.NrPMPEntries > 0) ? MY_EX_CFG.NrPMPEntries-1 : 0) : 0] pmpaddr_i;
  // Initialize PMP arrays to zero. If NrPMPEntries == 0, one dummy element is created.
  initial begin
    for (int i = 0; i < ((MY_EX_CFG.NrPMPEntries > 0) ? MY_EX_CFG.NrPMPEntries : 1); i++) begin
      pmpcfg_i[i] = 8'b0;
      pmpaddr_i[i] = '0;
    end
  end

  // 4) Instantiate the ex_stage DUT.
  // Description:
  //   Instantiate the DUT (execute stage) using the parameters defined earlier.
  //   All interface signals are connected by name.
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

  // 5) Initial Stimulus: Drive DUT inputs.
  // Description:
  //   Initialize all input signals to known states, then apply a simple stimulus.
  //   This stimulus performs an ALU-like operation on issue port 0.
  //   Note: DUT outputs are not driven by the testbench.
  initial begin
    // Initialize control signals.
    flush_i                 = 0;
    debug_mode_i            = 0;
    
    // Initialize forwarding data to zero.
    rs1_forwarding_i        = '{default:'0};
    rs2_forwarding_i        = '{default:'0};
    
    // Initialize function unit data structures to zero for all issue ports.
    fu_data_i               = '{default:'0};
    
    // Set the initial program counter value.
    pc_i                    = 64'h80000000;
    
    // Initialize instruction control signals.
    is_zcmt_i               = 0;
    is_compressed_instr_i   = 0;
    // Set all instruction words to zero.
    tinst_i                 = '{default:32'h0};

    // Initialize valid signals for ALU, branch, CSR, etc.
    alu_valid_i             = '{default:0};
    branch_valid_i          = '{default:0};
    branch_predict_i        = '{default:0};
    csr_valid_i             = '{default:0};
    csr_commit_i            = 0;
    mult_valid_i            = '{default:0};
    lsu_valid_i             = '{default:0};
    lsu_commit_i            = 0;
    commit_tran_id_i        = '0;
    stall_st_pending_i      = 0;
    amo_valid_commit_i      = 0;
    fpu_valid_i             = '{default:0};
    fpu_fmt_i               = 2'b0;
    fpu_rm_i                = 3'b0;
    fpu_frm_i               = 3'b0;
    fpu_prec_i              = 7'd0;
    alu2_valid_i            = '{default:0};
    x_valid_i               = '{default:0};
    x_off_instr_i           = 32'h0;
    
    // Do not drive x_result_valid_i as it is driven by the DUT.
    x_result_i              = '{data:64'h0};
    x_transaction_rejected_i = 0;
    acc_valid_i             = 0;

    // Initialize translation and CSR control signals.
    enable_translation_i    = 0;
    enable_g_translation_i  = 0;
    en_ld_st_translation_i  = 0;
    en_ld_st_g_translation_i = 0;
    flush_tlb_i             = 0;
    flush_tlb_vvma_i        = 0;
    flush_tlb_gvma_i        = 0;
    priv_lvl_i              = riscv::PRIV_LVL_M; // Set current privilege level to machine mode.
    v_i                     = 0;
    ld_st_priv_lvl_i        = riscv::PRIV_LVL_M; // Load/store operations execute in machine mode.
    ld_st_v_i               = 0;
    sum_i                   = 0;
    vs_sum_i                = 0;
    mxr_i                   = 0;
    vmxr_i                  = 0;
    satp_ppn_i              = '0;
    asid_i                  = '0;
    vsatp_ppn_i             = '0;
    vs_asid_i               = '0;
    hgatp_ppn_i             = '0;
    vmid_i                  = '0;
    
    // Initialize the instruction cache request signal.
    icache_areq_i           = '{valid:1'b0};
    
    // Initialize data cache request ports to default (zero).
    dcache_req_ports_i      = '{default:'0};
    
    // Set the data cache write buffer status signals.
    dcache_wbuffer_empty_i  = 1;
    dcache_wbuffer_not_ni_i = 0;
    
    // Initialize atomic memory operation response.
    amo_resp_i              = '{valid:1'b0};
  end

  // 6) Test Stimulus: A simple ALU–like operation on issue port 0.
  // Description:
  //   After reset deassertion, wait a brief period then drive an ALU operation.
  //   The stimulus sets up the transaction identifier, operation code (e.g., ADD),
  //   and two operand values on issue port 0. It then asserts the alu_valid signal,
  //   waits for a brief period, and finally deasserts the signal. The DUT output is
  //   then displayed.
  initial begin
    // Wait for the reset to be deasserted.
    @(posedge rst_ni);
    #10;  // Wait an additional 10 time units for stable operation
    
    // Drive stimulus on issue port 0:
    fu_data_i[0].trans_id  = 32'hA;    // Set transaction ID to 0xA
    fu_data_i[0].operation = 5'h01;      // Set operation code (ADD)
    fu_data_i[0].operand_a = 64'h10;      // Set first operand to 0x10
    fu_data_i[0].operand_b = 64'h7;       // Set second operand to 0x7
    
    alu_valid_i[0]         = 1;          // Assert ALU valid signal for issue port 0
    #10;                                // Maintain valid for 10 time units
    alu_valid_i[0]         = 0;          // Deassert ALU valid signal
    
    #50;                                // Wait 50 time units for the DUT to process the operation
    
    // Display the DUT's output results (result and transaction ID)
    $display("[TB] FLU result   = 0x%08h", flu_result_o);
    $display("[TB] FLU trans_id = 0x%08h", flu_trans_id_o);
    
    $finish;  // End simulation
  end

endmodule
