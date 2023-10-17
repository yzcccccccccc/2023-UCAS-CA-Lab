`define BR_BUS_LEN      33

`define IF2ID_pc        32
`define IF2ID_inst      32
`define IFReg_BUS_LEN   64

`define ID2EX_LEN       78      /* ID2EX    = {alu_op, alu_src1, alu_src2, mul, div} */
`define ID2MEM_LEN      41      /* ID2MEM   = {rkd_value, mem_en, st_ctrl, ld_ctrl} */
`define ID2WB_LEN       39      /* ID2WB    = {rf_we, res_from_mem, rf_waddr, pc} */
`define IDReg_BUS_LEN   158     /* = {ID2EX, ID2MEM, ID2WB} */

`define EX2MEM_LEN      102      /* EX2MEM   = {mul, mul_result, EX_result, rdk_value, ld_ctrl}*/
`define EX2WB_LEN       39
`define EXReg_BUS_LEN   141

`define MEM2WB_LEN      103
`define MEMReg_BUS_LEN  70

// Data Forward Bypass
`define EX_BYPASS_LEN   40
`define MEM_BYPASS_LEN  38
`define WB_BYPASS_LEN   38