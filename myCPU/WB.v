`include "macro.vh"

module WB(
    input   wire        clk,
    input   wire        reset,

    // valid & MEMreg_bus
    input   wire                            valid,
    input   wire [`MEMReg_BUS_LEN - 1:0]    MEMreg_bus,

    // reg file
    output  wire [4:0]  rf_waddr,
    output  wire [31:0] rf_wdata,
    output  wire        rf_we,

    // debug
    output  wire [31:0] debug_wb_pc,
    output  wire [3:0]  debug_wb_rf_we,
    output  wire [4:0]  debug_wb_rf_wnum,
    output  wire [31:0] debug_wb_rf_wdata,

    // control signal
    input   wire        MEM_ready_go,
    output  wire        WB_ready_go,
    output  wire        WB_allow_in
);
    // MEMreg Decode
        wire    [31:0]  alu_result, mem_result, pc;
        wire    [4:0]   rf_waddr_tmp;
        wire    res_from_mem, rf_we_tmp;
        assign  {alu_result, mem_result, rf_we_tmp, res_from_mem, rf_waddr_tmp, pc} = MEMreg_bus;

    // Reg File
        assign  rf_waddr    = rf_waddr_tmp;
        assign  rf_wdata    = res_from_mem ? mem_result : alu_result;
        assign  rf_we       = rf_we_tmp & valid;
        
    // debug
        assign debug_wb_pc          = pc;
        assign debug_wb_rf_wdata    = rf_wdata;
        assign debug_wb_rf_wnum     = rf_waddr;
        assign debug_wb_rf_we       = {4{rf_we & valid}};
    
    // control signals
        assign WB_ready_go          = 1;
        assign WB_allow_in          = 1;
endmodule