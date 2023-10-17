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

    // data harzard bypass
    output  wire [`WB_BYPASS_LEN - 1:0] WB_bypass_bus,

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
        wire    [31:0]  final_result, pc;
        wire    [4:0]   rf_waddr_tmp;
        wire    rf_we_tmp;
        assign  {final_result, rf_we_tmp, rf_waddr_tmp, pc} = MEMreg_bus;

    // Reg File
        assign  rf_waddr    = rf_waddr_tmp;
        assign  rf_wdata    = final_result;
        assign  rf_we       = rf_we_tmp & valid;
        
    // debug
        assign debug_wb_pc          = pc;
        assign debug_wb_rf_wdata    = rf_wdata;
        assign debug_wb_rf_wnum     = rf_waddr;
        assign debug_wb_rf_we       = {4{rf_we}};
    
    // data harzard bypass
        assign WB_bypass_bus    = {rf_waddr, rf_we, rf_wdata};

    // control signals
        assign WB_ready_go          = 1;
        assign WB_allow_in          = 1;
endmodule