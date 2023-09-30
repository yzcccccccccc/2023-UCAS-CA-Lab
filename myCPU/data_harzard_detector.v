`include "macro.vh"

module data_harzard_detector(
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
        wire                EX_rf_we, EX_res_from_mem;
        wire    [31:0]      EX_result;
        assign {EX_rf_waddr, EX_rf_we, EX_res_from_mem, EX_result}          = EX_bypass_bus;

        wire    [4:0]       MEM_rf_waddr;
        wire                MEM_rf_we, MEM_rfm;
        wire    [31:0]      MEM_exres, MEM_memres, MEM_result;
        assign {MEM_rf_waddr, MEM_rf_we, MEM_rfm, MEM_exres, MEM_memres}    = MEM_bypass_bus;
        assign MEM_result   = MEM_rfm ? MEM_memres : MEM_exres;

        wire    [4:0]       WB_rf_waddr;
        wire                WB_rf_we;
        wire    [31:0]      WB_result;
        assign {WB_rf_waddr, WB_rf_we, WB_result}   = WB_bypass_bus;

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
                        : ((rf_raddr1 == MEM_rf_waddr && MEM_rf_we == 1'b1) ? MEM_result : WB_result);
    
    assign addr2_forward = (rf_raddr2 == EX_rf_waddr && EX_rf_we == 1'b1) ? EX_result
                        : ((rf_raddr2 == MEM_rf_waddr && MEM_rf_we == 1'b1) ? MEM_result : WB_result);
    
    // pause(block) while EX is a load-type inst and harzard happen.
    assign pause        = (|rf_raddr1) & EX_rf_we & EX_res_from_mem & (rf_raddr1 == EX_rf_waddr)
                        | (|rf_raddr2) & EX_rf_we & EX_res_from_mem & (rf_raddr2 == EX_rf_waddr);
endmodule