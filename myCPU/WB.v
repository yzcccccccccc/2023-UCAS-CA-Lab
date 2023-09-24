`include "macro.vh"

module WB(
    input   wire        clk,
    input   wire        reset,

    // valid
    input   wire        valid,

    // reg file
    output  wire [4:0]  waddr,
    output  wire [31:0] wdata,
    output  wire        we,

    input   wire [4:0]  rf_waddr,
    input   wire        rf_we,
    input   wire        res_from_mem,
    input   wire [31:0] data,
    input   wire [31:0] alu_result,

    // debug
    input   wire [31:0] pc,
    output  wire [31:0] debug_wb_pc,
    output  wire [3:0]  debug_wb_rf_we,
    output  wire [4:0]  debug_wb_rf_wnum,
    output  wire [31:0] debug_wb_rf_wdata,

    // control signal
    input   wire        MEM_ready_go,
    output  wire        WB_ready_go,
    output  wire        WB_allow_in
);
    // Reg File
        assign waddr        = rf_waddr;
        assign wdata        = res_from_mem ? data : alu_result;
        assign we           = rf_we & valid;

    // debug
        assign debug_wb_pc          = pc;
        assign debug_wb_rf_wdata    = wdata;
        assign debug_wb_rf_wnum     = waddr;
        assign debug_wb_rf_we       = {4{we & valid}};
    
    // control signals
        assign WB_ready_go          = 1;
        assign WB_allow_in          = 1;
endmodule