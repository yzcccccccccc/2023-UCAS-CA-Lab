`define BR_BUS_LEN      34

`define IFReg_BUS_LEN   81      /* IF2ID    = {ebus_end, inst, pc, refetch_tag} */

`define ID2EX_LEN       96      /* ID2EX    = {rdcntv_op, ebus_end, alu_op, alu_src1, alu_src2, mul, div} */
`define ID2MEM_LEN      41      /* ID2MEM   = {rkd_value, mem_en, st_ctrl, ld_ctrl} */
`define ID2WB_LEN       122     /* ID2WB    = {pause_int_detect, ertn_flush, csr_ctrl, res_from_csr, rf_we, res_from_mem, rf_waddr, pc} */
`define ID_TLB_LEN      15      /* IDTLB    = {tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, invtlb_valid, invtlb_op, refetch_detect, tlbsrch_pause_detect, refetch_tag}*/
`define IDReg_BUS_LEN   274     /* = {ID2EX, ID2MEM, ID2WB, ID_TLB} */

`define EX2MEM_LEN      119     /* EX2MEM   = {wait_data_ok, ebus_end, mul, mul_result, EX_result, rdk_value, ld_ctrl}*/
`define EX2WB_LEN       122
`define EX_TLB_LEN      12      /* EXTLB    = {tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, tlbsrch_hit, tlbsrch_index, refetch_detect, tlbsrch_pause_detect, refetch_tag} */
`define EXReg_BUS_LEN   253     /* = {EXreg_2MEM, EXreg_2WB, EXTLB}; */

`define MEM_TLB_LEN     12      /* MEMTLB   = {tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, tlbsrch_hit, tlbsrch_index, refetch_detect, tlbsrch_pause_detect, refetch_tag}*/
`define MEM2WB_LEN      169     /* MEM2WB   = {pause_int_detect, ebus_end, ertn_flush, csr_ctrl, res_from_csr, MEM_final_result, rf_we, rf_waddr, pc}*/
`define MEMReg_BUS_LEN  181     /* = {MEM2wb, MEMTLB} */

// Data Forward Bypass
`define EX_BYPASS_LEN   42
`define MEM_BYPASS_LEN  41
`define WB_BYPASS_LEN   40

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
`define CSR_CRMD_PLV        1:0
`define CSR_CRMD_IE         2
`define CSR_CRMD_DA         3
`define CSR_CRMD_PG         4
`define CSR_CRMD_DATF       6:5
`define CSR_CRMD_DATM       8:7
`define CSR_PRMD_PPLV       1:0
`define CSR_PRMD_PIE        2
`define CSR_ECFG_LIE        12:0
`define CSR_ESTAT_IS10      1:0
`define CSR_ERA_PC          31:0
`define CSR_EENTRY_VA       31:6
`define CSR_SAVE_DATA       31:0
`define CSR_TICLR_CLR       0
`define CSR_TID_TID         31:0
`define CSR_TCFG_EN         0
`define CSR_TCFG_PERIOD     1
`define CSR_TCFG_INITV      31:2
`define CSR_TLBIDX_INDEX    3:0                 // n = log2(TLBNUM) = log2(16) = 4
`define CSR_TLBIDX_PS       29:24
`define CSR_TLBIDX_NE       31
`define CSR_TLBEHI_VPPN     31:13
`define CSR_TLBELO_V        0
`define CSR_TLBELO_D        1
`define CSR_TLBELO_PLV      3:2
`define CSR_TLBELO_MAT      5:4
`define CSR_TLBELO_G        6
`define CSR_TLBELO_PPN      31:8
`define CSR_ASID_ASID       9:0
`define CSR_ASID_ASIDBITS   23:16
`define CSR_PGDH_BASE       31:12               // GRLEN - 1:12
`define CSR_PGD_BASE        31:12               // GRLEN - 1:12
`define CSR_TLBRENTRY_PA    31:6
`define CSR_DMW_PLV0        0
`define CSR_DMW_PLV3        3
`define CSR_DMW_MAT         5:4
`define CSR_DMW_PSEG        27:25
`define CSR_DMW_VSEG        31:29

// WB to CSR bus
`define WB2CSR_LEN      90          /* = {tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, tlbsrch_hit, tlbsrch_index, ertn_flush, wb_ex, wb_ecode[5:0], wb_esubcode[8:0], wb_pc[31:0], wb_vaddr[31:0]} */

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

// Exception Number in ebus
`define EBUS_INT          4'd0
`define EBUS_PIL          4'd1
`define EBUS_PIS          4'd2
`define EBUS_PIF          4'd3
`define EBUS_PME          4'd4
`define EBUS_PPI          4'd5
`define EBUS_ADEF         4'd6
`define EBUS_ADEM         4'd7
`define EBUS_ALE          4'd8
`define EBUS_SYS          4'd9
`define EBUS_BRK          4'd10
`define EBUS_INE          4'd11
`define EBUS_IPE          4'd12
`define EBUS_FPD          4'd13
`define EBUS_FPE          4'd14
`define EBUS_TLBR         4'd15

`define TLBNUM              16
