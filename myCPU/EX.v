`include "macro.vh"
module EX(
    input   wire        clk,
    input   wire        reset,

    // alu_op & alu_src & valid
    input   wire [11:0] alu_op,
    input   wire [31:0] alu_src1,
    input   wire [31:0] alu_src2,
    input   wire        valid,

    // MEM
    input   wire        mem_en,
    input   wire [31:0] rkd_value,
    input   wire [3:0]  mem_we,

    // to WB
    input   wire        rf_we,
    input   wire        res_from_mem,
    input   wire [4:0]  rf_waddr,
    input   wire [31:0] pc,

    // control signals
    input   wire        ID_ready_go,
    input   wire        MEM_allow_in,
    output  wire        EX_allow_in,
    output  wire        EX_ready_go,

    // data ram interface (Read)
    output  wire         data_sram_en,
    output  wire [31:0]  data_sram_addr,

    // EXreg bus
    output  wire         EXreg_valid,
    output  wire [`EX2MEM_LEN - 1:0]    EXreg_2MEM,
    output  wire [`EX2WB_LEN - 1:0]     EXreg_2WB

);

/************************************************************************************
    Hint:
        In EX state, we need to request data_ram for the data to be used
    in MEM state.
*************************************************************************************/

// Define Signals
    wire [31:0]         alu_result;

// ALU
    alu u_alu(
        .alu_op     (alu_op),
        .alu_src1   (alu_src1),
        .alu_src2   (alu_src2),
        .alu_result (alu_result)
    );

// Access MEM
    assign data_sram_en     = mem_en;
    assign data_sram_addr   = alu_result;

// EXreg
    assign EXreg_valid      = valid;
    assign EXreg_2MEM       = {alu_result, rkd_value, mem_we};
    assign EXreg_2WB        = {rf_we, res_from_mem, rf_waddr, pc};

// control signals
    assign EX_ready_go      = 1;
    assign EX_allow_in      = 1;

endmodule