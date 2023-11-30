`include "../macro.vh"

module WB(
        input   wire        clk,

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
        input   wire [31:0] csr_rvalue,
        output  wire [79:0] csr_ctrl,
        output  wire [`WB2CSR_LEN-1:0] to_csr_in_bus,

        output  wire        refetch,
        output  wire        tlbsrch_pause,
        output  wire        refetch_flush,
        output  wire [31:0] refetch_pc,

        output  wire    except,
        output  wire    ertn_flush,
        output  wire    excep_valid
    );

// to CSR
wire wb_ex;
wire [31:0] wb_pc;
wire [5:0] wb_ecode;
wire [8:0] wb_esubcode;

// ebus
wire [15:0] ebus_init;
wire [15:0] ebus_end;

// MEMreg Decode
wire    [`MEM_TLB_LEN - 1:0]    MEM_TLB_bus;
wire    [`MEM2WB_LEN - 1:0]     MEM2WB_bus;
assign  {MEM2WB_bus, MEM_TLB_bus}   = MEMreg_bus;

wire            res_from_csr;
wire    [31:0]  final_result, pc;
wire    [4:0]   rf_waddr_tmp;
wire            rf_we_tmp;
wire            pause_int_detect;
assign  {pause_int_detect, ebus_init, ertn_flush, csr_ctrl, res_from_csr, final_result, rf_we_tmp, rf_waddr_tmp, pc} = MEM2WB_bus;

wire            tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, tlbsrch_hit;
wire    [3:0]   tlbsrch_index;
wire            refetch_detect, tlbsrch_pause_detect, refetch_tag;
assign  {tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, tlbsrch_hit, tlbsrch_index, refetch_detect, tlbsrch_pause_detect, refetch_tag}  = MEM_TLB_bus;

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
assign ebus_end     = ebus_init;
assign excep_valid  = valid | ebus_end[`EBUS_ADEF];

// exp13 adef
wire [31:0] wb_vaddr;
assign wb_vaddr = final_result;

// data harzard bypass
assign WB_bypass_bus    = {pause_int_detect & valid, res_from_csr, rf_waddr, rf_we, rf_wdata};

// control signals
assign WB_ready_go          = 1;
assign WB_allow_in          = 1;

// refetch & tlbsrch_pause
assign refetch          = refetch_detect & valid;
assign tlbsrch_pause    = tlbsrch_pause_detect & valid;
assign refetch_flush    = refetch_tag;
assign refetch_pc       = pc;

// Exception
assign except           = wb_ex;

// CSR
assign wb_ex = |ebus_end & valid;
assign wb_pc = pc;
assign wb_ecode =  {6{ebus_end[`EBUS_INT]}} & `ECODE_INT |
                   {6{ebus_end[`EBUS_PIL]}} & `ECODE_PIL |
                   {6{ebus_end[`EBUS_PIS]}} & `ECODE_PIS |
                   {6{ebus_end[`EBUS_PIF]}} & `ECODE_PIF |
                   {6{ebus_end[`EBUS_PME]}} & `ECODE_PME |
                   {6{ebus_end[`EBUS_PPI]}} & `ECODE_PPI |
                   {6{ebus_end[`EBUS_ADEF]}} & `ECODE_ADE |
                   {6{ebus_end[`EBUS_ADEM]}} & `ECODE_ADE |
                   {6{ebus_end[`EBUS_ALE]}} & `ECODE_ALE |
                   {6{ebus_end[`EBUS_SYS]}} & `ECODE_SYS |
                   {6{ebus_end[`EBUS_BRK]}} & `ECODE_BRK |
                   {6{ebus_end[`EBUS_INE]}} & `ECODE_INE |
                   {6{ebus_end[`EBUS_IPE]}} & `ECODE_IPE |
                   {6{ebus_end[`EBUS_FPD]}} & `ECODE_FPD |
                   {6{ebus_end[`EBUS_FPE]}} & `ECODE_FPE |
                   {6{ebus_end[`EBUS_TLBR]}} & `ECODE_TLBR;
assign wb_esubcode = {9{ebus_end[7]}} & `ESUBCODE_ADEM;
assign to_csr_in_bus = {tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, tlbsrch_hit, tlbsrch_index, ertn_flush&valid, wb_ex, wb_ecode, wb_esubcode, wb_pc, wb_vaddr};

endmodule