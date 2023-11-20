`include "../macro.vh"

module data_harzard_detector(
       input   wire                            reset,

       input   wire [`EX_BYPASS_LEN - 1:0]     EX_bypass_bus,
       input   wire [`MEM_BYPASS_LEN - 1:0]    MEM_bypass_bus,
       input   wire [`WB_BYPASS_LEN - 1:0]     WB_bypass_bus,
       input   wire [4:0]  rf_raddr1,
       input   wire [4:0]  rf_raddr2,

       output  wire        pause,
       output  wire        addr1_occur,
       output  wire [31:0] addr1_forward,
       output  wire        addr2_occur,
       output  wire [31:0] addr2_forward
);
// Bypass-Bus Decode
wire    [4:0]       EX_rf_waddr;
wire                EX_pause_int_detect, EX_res_from_csr, EX_rf_we, EX_mul, EX_res_from_mem;
wire    [31:0]      EX_result;
assign {EX_pause_int_detect, EX_res_from_csr, EX_rf_waddr, EX_rf_we, EX_mul, EX_res_from_mem, EX_result}          = EX_bypass_bus;

wire    [4:0]       MEM_rf_waddr;
wire                MEM_pause_int_detect, MEM_res_from_csr, MEM_rf_we, MEM_rfm;
wire    [31:0]      MEM_final_result;
assign {MEM_pause_int_detect, MEM_res_from_csr, MEM_rf_waddr, MEM_rf_we, MEM_res_from_mem, MEM_final_result}    = MEM_bypass_bus;

wire    [4:0]       WB_rf_waddr;
wire                WB_pause_int_detect, WB_res_from_csr, WB_rf_we;
wire    [31:0]      WB_result;
assign {WB_pause_int_detect, WB_res_from_csr, WB_rf_waddr, WB_rf_we, WB_result}   = WB_bypass_bus;

// detect and forward
assign addr1_occur  = ((rf_raddr1 == EX_rf_waddr && EX_rf_we == 1'b1)
                       | (rf_raddr1 == MEM_rf_waddr && MEM_rf_we == 1'b1)
                       | (rf_raddr1 == WB_rf_waddr && WB_rf_we == 1'b1))
       & (|rf_raddr1);            // non-zero reg

assign addr2_occur  = ((rf_raddr2 == EX_rf_waddr && EX_rf_we == 1'b1)
                       | (rf_raddr2 == MEM_rf_waddr && MEM_rf_we == 1'b1)
                       | (rf_raddr2 == WB_rf_waddr && WB_rf_we == 1'b1))
       & (|rf_raddr2);

assign addr1_forward = (rf_raddr1 == EX_rf_waddr && EX_rf_we == 1'b1) ? EX_result
       : ((rf_raddr1 == MEM_rf_waddr && MEM_rf_we == 1'b1) ? MEM_final_result : WB_result);

assign addr2_forward = (rf_raddr2 == EX_rf_waddr && EX_rf_we == 1'b1) ? EX_result
       : ((rf_raddr2 == MEM_rf_waddr && MEM_rf_we == 1'b1) ? MEM_final_result : WB_result);

/*********************************************************************
       pause(block) while harzard happens
                 and EX is a load-type or csr-type inst,
                 or MEM is a csr-type inst,
                 or WB is a csr-type inst.
2023.11.10 yzcc
       will not pause if reset arrives (ex or ertn).
2023.11.13 czxx
       pause interrupt detection
**********************************************************************/

assign pause        = ((|rf_raddr1) & EX_rf_we & (EX_mul | EX_res_from_mem | EX_res_from_csr) & (rf_raddr1 == EX_rf_waddr)
       | (|rf_raddr1) & MEM_rf_we & (MEM_res_from_csr | MEM_res_from_mem) & (rf_raddr1 == MEM_rf_waddr)
       | (|rf_raddr1) & WB_rf_we & (WB_res_from_csr) & (rf_raddr1 == WB_rf_waddr)
       | (|rf_raddr2) & EX_rf_we & (EX_mul | EX_res_from_mem | EX_res_from_csr) & (rf_raddr2 == EX_rf_waddr)
       | (|rf_raddr2) & MEM_rf_we & (MEM_res_from_csr | MEM_res_from_mem) & (rf_raddr2 == MEM_rf_waddr)
       | (|rf_raddr2) & WB_rf_we & (WB_res_from_csr) & (rf_raddr2 == WB_rf_waddr)
       | EX_pause_int_detect
       | MEM_pause_int_detect
       | WB_pause_int_detect)
       & ~reset;

endmodule