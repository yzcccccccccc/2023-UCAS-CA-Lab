`define BR_BUS_LEN      33

`define IF2ID_pc        32
`define IF2ID_inst      32
`define IFReg_BUS_LEN   64

`define ID2EX_LEN       78      /* ID2EX    = {alu_op, alu_src1, alu_src2, mul, div} */
`define ID2MEM_LEN      41      /* ID2MEM   = {rkd_value, mem_en, st_ctrl, ld_ctrl} */
`define ID2WB_LEN       122     /* ID2WB    = {has_sys, ertn_flush, csr_ctrl, res_from_csr, rf_we, res_from_mem, rf_waddr, pc} */
`define IDReg_BUS_LEN   241     /* = {ID2EX, ID2MEM, ID2WB} */

`define EX2MEM_LEN      102     /* EX2MEM   = {mul, mul_result, EX_result, rdk_value, ld_ctrl}*/
`define EX2WB_LEN       122
`define EXReg_BUS_LEN   224

`define MEMReg_BUS_LEN  153

// Data Forward Bypass
`define EX_BYPASS_LEN   41
`define MEM_BYPASS_LEN  39
`define WB_BYPASS_LEN   39

// CSR ADDR
`define CSR_CRMD        14'h00
`define CSR_PRMD        14'h01
`define CSR_EUEN        14'h02
`define CSR_ECFG        14'h04
`define CSR_ESTAT       14'h05
`define CSR_ERA         14'h06
`define CSR_BADV        14'h07
`define CSR_EENTRY      14'h0c
`define CSR_TLBIDX      14'h10
`define CSR_TLBEHI      14'h11
`define CSR_TLBELO0     14'h12
`define CSR_TLBELO1     14'h13
`define CSR_ASID        14'h18
`define CSR_PGDL        14'h19
`define CSR_PGDH        14'h1a
`define CSR_PGD         14'h1b
`define CSR_CPUID       14'h20
`define CSR_SAVE0       14'h30
`define CSR_SAVE1       14'h31
`define CSR_SAVE2       14'h32
`define CSR_SAVE3       14'h33
`define CSR_TID         14'h40 
`define CSR_TCFG        14'h41
`define CSR_TVAL        14'h42
`define CSR_TICLR       14'h44
`define CSR_LLBCTL      14'h60
`define CSR_TLBRENTRY   14'h88
`define CSR_CTAG        14'h98
`define CSR_DMW0        14'h180
`define CSR_DMW1        14'h181

// CSR bits
`define CSR_CRMD_PLV    1:0
`define CSR_CRMD_IE     2
`define CSR_CRMD_DA     3
`define CSR_CRMD_PG     4
`define CSR_CRMD_DATF   6:5
`define CSR_CRMD_DATM   8:7
`define CSR_PRMD_PPLV   1:0
`define CSR_PRMD_PIE    2
`define CSR_ECFG_LIE    12:0
`define CSR_ESTAT_IS10  1:0
`define CSR_ERA_PC      31:0
`define CSR_EENTRY_VA   31:6
`define CSR_SAVE_DATA   31:0
`define CSR_TICLR_CLR   0
`define CSR_TID_TID     31:0
`define CSR_TCFG_EN     0
`define CSR_TCFG_PERIOD 1
`define CSR_TCFG_INITV  31:2

// WB to CSR bus
`define WB2CSR_LEN      49          /* = {ertn_flush, wb_ex, wb_ecode[5:0], wb_esubcode[8:0], wb_pc[31:0]} */

// CSR Exception Code
`define ECODE_INT         6'h00
`define ECODE_PIL         6'h01
`define ECODE_PIS         6'h02
`define ECODE_PIF         6'h03
`define ECODE_PME         6'h04
`define ECODE_PPI         6'h07
`define ECODE_ADE         6'h08
`define ECODE_ALE         6'h09
`define ECODE_SYS         6'h0b
`define ECODE_BRK         6'h0c
`define ECODE_INE         6'h0d
`define ECODE_IPE         6'h0e
`define ECODE_FPD         6'h0f
`define ECODE_FPE         6'h12
`define ECODE_TLBR        6'h3f
`define ESUBCODE_ADEF     9'h00
`define ESUBCODE_ADEM     9'h01