`timescale 1ns/1ps
// Package: ariane_pkg
// Description:
//   This package provides local parameters used in the Ariane
//   RISC-V processor. In particular, it defines constants for
//   various TLB and cache flush operations (SFENCE and HFENCE).
package ariane_pkg;
  // SFENCE_VMA: TLB flush for virtual memory addresses.
  localparam SFENCE_VMA  = 16'h10;
  // HFENCE_VVMA: TLB flush for virtual-to-virtual memory addresses.
  localparam HFENCE_VVMA = 16'h11;
  // HFENCE_GVMA: TLB flush for global virtual-to-virtual memory addresses.
  localparam HFENCE_GVMA = 16'h12;
endpackage : ariane_pkg

// Package: riscv
// Description:
//   This package contains fundamental RISC-V type definitions,
//   including an enumeration for privilege levels and a typedef
//   for the Physical Memory Protection (PMP) configuration.
package riscv;
  // Define an enumerated type for RISC-V privilege levels.
  typedef enum logic [1:0] {
    PRIV_LVL_U = 2'd0, // User mode
    PRIV_LVL_S = 2'd1, // Supervisor mode
    PRIV_LVL_M = 2'd3  // Machine mode
  } priv_lvl_t;
  
  // Define a type for PMP configuration as an 8-bit logic vector.
  typedef logic [7:0] pmpcfg_t;
endpackage : riscv

// Package: config_pkg
// Description:
//   This package provides the configuration parameters for the
//   CVA6 processor. It defines a configuration structure (cva6_cfg_t)
//   containing various parameters such as issue port count, data widths,
//   and memory protection settings.
package config_pkg;
  // Default number of PMP entries (physical memory protection).
  localparam int NrPMPEntries_default = 0;
  
  // Configuration structure for the CVA6 processor.
  // The structure is defined as packed to ensure a deterministic layout.
  typedef struct packed {
    int NrIssuePorts;    // Number of instruction issue ports
    int VLEN;            // Vector length (bits)
    int XLEN;            // Data width (bits)
    int TRANS_ID_BITS;   // Width of the transaction identifier
    int PPNW;            // Width of the Physical Page Number
    int ASID_WIDTH;      // Width of the Address Space Identifier
    int VMID_WIDTH;      // Width of the Virtual Memory Identifier
    int GPLEN;           // Guest Physical Length (bits)
    int PLEN;            // Physical address length (bits)
    int NrPMPEntries;    // Number of PMP entries
    bit SuperscalarEn;   // Superscalar execution enable flag
    bit FpPresent;       // Presence of a floating-point unit
    bit RVS;             // RISC-V standard flag (RV32/64)
    bit RVH;             // RISC-V hypervisor extension flag
    bit CvxifEn;         // Enable CVXIF interface flag
  } cva6_cfg_t;
  
  // default configuration instance.
  localparam cva6_cfg_t cva6_cfg_empty = '{
    NrIssuePorts : 1,
    VLEN         : 64,
    XLEN         : 64,
    TRANS_ID_BITS: 5,
    PPNW         : 20,
    ASID_WIDTH   : 16,
    VMID_WIDTH   : 14,
    GPLEN        : 12,
    PLEN         : 54,
    NrPMPEntries : NrPMPEntries_default,
    SuperscalarEn: 0,
    FpPresent    : 0,
    RVS          : 0,
    RVH          : 0,
    CvxifEn      : 0
  };
endpackage : config_pkg

// Package: ex_stage_stub_pkg
// Description:
//   This package defines stub types for the execute stage of the
//   CVA6 processor. These definitions include types for exceptions,
//   branch prediction, function unit data, atomic operations, load/store
//   control, and cache request/response interfaces.
package ex_stage_stub_pkg;
  // Exception type structure.
  typedef struct packed {
    logic valid;          // Exception validity flag
    logic [31:0] cause;   // Exception cause code
  } exception_t;
  
  // Branch prediction structure.
  typedef struct packed {
    logic valid;          // Branch prediction valid flag
  } branchpredict_sbe_t;
  
  // Branch resolve structure.
  typedef struct packed {
    logic valid;          // Branch resolve valid flag
  } bp_resolve_t;
  
  // Function unit data structure.
  typedef struct packed {
    logic [31:0] trans_id;   // Transaction identifier
    logic [6:0]  operation;  // Operation code (e.g., ADD, SUB)
    logic [63:0] operand_a;  // First operand
    logic [63:0] operand_b;  // Second operand
    logic [63:0] imm;        // Immediate value
  } fu_data_t;
  
  // Atomic memory operation request structure.
  typedef struct packed {
    logic valid;          // Atomic operation request valid flag
  } amo_req_t;
  
  // Atomic memory operation response structure.
  typedef struct packed {
    logic valid;          // Atomic operation response valid flag
  } amo_resp_t;
  
  // Load/Store unit control structure.
  typedef struct packed {
    logic valid;          // Load/Store control valid flag
  } lsu_ctrl_t;
  
  // Dcache request interface type (I).
  typedef struct packed {
    logic valid;          // Dcache request valid flag (I)
  } dcache_req_i_t;
  
  // Dcache request interface type (output).
  typedef struct packed {
    logic valid;          // Dcache request valid flag (O)
  } dcache_req_o_t;
  
  // Icache request interface type.
  typedef struct packed {
    logic valid;          // Icache request valid flag
  } icache_areq_t;
  
  // Aliases for icache response and data request/response types,
  // which share the same structure as icache_areq_t.
  typedef icache_areq_t icache_arsp_t;
  typedef icache_areq_t icache_dreq_t;
  typedef icache_areq_t icache_drsp_t;
  
  // Extended result type structure.
  typedef struct packed {
    logic [63:0] data;    // 64-bit result data
  } x_result_t;
endpackage : ex_stage_stub_pkg
