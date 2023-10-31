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
           output  wire        WB_allow_in,

           // CSR
           input wire [31:0] csr_rvalue,
           output wire [79:0] csr_ctrl,
           output wire [`WB2CSR_LEN-1:0] to_csr_in_bus
       );

// to CSR
wire wb_ex;
wire [31:0] wb_pc;
wire [5:0] wb_ecode;
wire [8:0] wb_esubcode;
wire ertn_flush;

// ebus
wire [15:0] ebus_init;
wire [15:0] ebus_end;

// MEMreg Decode
wire            res_from_csr;
wire    [31:0]  final_result, pc;
wire    [4:0]   rf_waddr_tmp;
wire            rf_we_tmp;
assign  {ebus_init, ertn_flush, csr_ctrl, res_from_csr, final_result, rf_we_tmp, rf_waddr_tmp, pc} = MEMreg_bus;

// Reg File
assign  rf_waddr    = rf_waddr_tmp;
assign  rf_wdata    = res_from_csr ? csr_rvalue : final_result;
assign  rf_we       = rf_we_tmp & valid & ~wb_ex;

// debug
assign debug_wb_pc          = pc;
assign debug_wb_rf_wdata    = rf_wdata;
assign debug_wb_rf_wnum     = rf_waddr;
assign debug_wb_rf_we       = {4{rf_we}};

// exception
assign ebus_end = ebus_init; 

// data harzard bypass
assign WB_bypass_bus    = {res_from_csr, rf_waddr, rf_we, rf_wdata};

// control signals
assign WB_ready_go          = 1;
assign WB_allow_in          = 1;

// CSR
assign wb_ex = |ebus_end;
assign wb_pc = pc;
assign wb_ecode =  ebus_end[`EBUS_SYS] ? `ECODE_SYS : 6'b0;
assign wb_esubcode = 0;
assign to_csr_in_bus = {ertn_flush, wb_ex, wb_ecode, wb_esubcode, wb_pc};

endmodule