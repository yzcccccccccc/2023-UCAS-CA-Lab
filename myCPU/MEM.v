`include "macro.vh"
module MEM(
    input   wire        clk,
    input   wire        reset,

    // valid & EXreg_bus
    input   wire                        valid,
    input   wire [`EXReg_BUS_LEN - 1:0] EXreg_bus,

    // data mem interface
    input   wire [31:0] data_sram_rdata, 

    // control signals
    input   wire        EX_ready_go,
    input   wire        WB_allow_in,
    output  wire        MEM_allow_in,
    output  wire        MEM_ready_go,

    // MEMReg bus
    output  wire                            MEMreg_valid,
    output  wire [`MEMReg_BUS_LEN - 1:0]    MEMreg_bus
);
    // EXreg_bus Decode
        wire    [`EX2MEM_LEN - 1:0]     EX2MEM_bus;
        wire    [`EX2WB_LEN - 1:0]      EX2WB_bus;
        assign  {EX2MEM_bus, EX2WB_bus} = EXreg_bus;

        wire    [31:0]  alu_result, rkd_value;
        wire    [3:0]   mem_we;
        assign  {alu_result, rkd_value, mem_we} = EX2MEM_bus;

        wire            rf_we;
        wire            res_from_mem;
        wire    [4:0]   rf_waddr;
        wire    [31:0]  pc;
        assign  {rf_we, res_from_mem, rf_waddr, pc} = EX2WB_bus;

    // Define Signals
        wire [31:0]     data;

    // MEM
        assign data                 = data_sram_rdata;

    // control signals
        assign MEM_allow_in         = 1;
        assign MEM_ready_go         = 1;

    // MEMreg_bus
        assign MEMreg_valid         = valid;
        assign MEMreg_bus           = {alu_result, data, rf_we, res_from_mem, rf_waddr, pc};

endmodule