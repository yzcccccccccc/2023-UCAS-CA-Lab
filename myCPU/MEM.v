`include "macro.vh"
module MEM(
    input   wire        clk,
    input   wire        reset,

    // mem & valid
    input   wire [31:0] alu_result,
    input   wire [31:0] rkd_value,
    input   wire [3:0]  mem_we,
    input   wire        valid,

    // data mem interface
    input   wire [31:0] data_sram_rdata, 

    // control signals
    input   wire        EX_ready_go,
    input   wire        WB_allow_in,
    output  wire        MEM_allow_in,
    output  wire        MEM_ready_go,

    // to WB
    input   wire        rf_we,
    input   wire        res_from_mem,
    input   wire [4:0]  rf_waddr,
    input   wire [31:0] pc,

    // MEMReg bus
    output  wire                        MEMreg_valid,
    output  wire [`MEM2WB_LEN - 1:0]    MEMreg_2WB
    
);
    // Define Signals
        wire [31:0]     data;

    // MEM
        assign data                 = data_sram_rdata;

    // control signals
        assign MEM_allow_in         = 1;
        assign MEM_ready_go         = 1;

    // MEMreg
        assign MEMreg_valid         = valid;
        assign MEMreg_2WB           = {alu_result, data, rf_we, res_from_mem, rf_waddr, pc};

endmodule