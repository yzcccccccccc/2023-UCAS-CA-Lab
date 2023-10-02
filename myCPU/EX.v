`include "macro.vh"
module EX(
    input   wire        clk,
    input   wire        reset,

    // valid & IDreg_bus
    input   wire                        valid,
    input   wire [`IDReg_BUS_LEN - 1:0] IDreg_bus,

    // control signals
    input   wire        ID_ready_go,
    input   wire        MEM_allow_in,
    output  wire        EX_allow_in,
    output  wire        EX_ready_go,

    // data ram interface (Read)
    output  wire         data_sram_en,
    output  wire [31:0]  data_sram_addr,
    output  wire [31:0]  data_sram_wdata,
    output  wire [3:0]   data_sram_we, 

    // data harzard bypass
    output  wire [`EX_BYPASS_LEN - 1:0] EX_bypass_bus,

    // EXreg bus
    output  wire                        EXreg_valid,
    output  wire [`EXReg_BUS_LEN - 1:0] EXreg_bus

);

/************************************************************************************
    Hint:
        In EX state, we need to request data_ram for the data to be used
    in MEM state.
*************************************************************************************/

// IDreg_bus Decode
    wire    [`ID2EX_LEN - 1:0]  ID2EX_bus;
    wire    [`ID2MEM_LEN - 1:0] ID2MEM_bus;
    wire    [`ID2WB_LEN - 1:0]  ID2WB_bus;

    assign  {ID2EX_bus, ID2MEM_bus, ID2WB_bus} = IDreg_bus;

    wire    [11:0]  alu_op;
    wire    [31:0]  alu_src1, alu_src2;
    wire            mul, div;

    wire            mem_en;
    wire    [31:0]  rkd_value;
    wire    [3:0]   mem_we;

    wire            rf_we;
    wire            res_from_mem;
    wire    [4:0]   rf_waddr;
    wire    [31:0]  pc;

    assign  {alu_op, alu_src1, alu_src2, mul, div}      = ID2EX_bus;
    assign  {rkd_value, mem_en, mem_we}                 = ID2MEM_bus;
    assign  {rf_we, res_from_mem, rf_waddr, pc}         = ID2WB_bus;

// Define Signals
    wire [31:0]         alu_result;
    wire [31:0]         mul_result, div_result;
    wire                div_done;

    wire    [`EX2MEM_LEN - 1:0] EXreg_2MEM;
    wire    [`EX2WB_LEN - 1:0]  EXreg_2WB;

    wire    [4:0]       EX_rf_waddr;
    wire                EX_rf_we, EX_res_from_mem;
    wire    [31:0]      EX_result;

// ALU
    alu u_alu(
        .alu_op     (alu_op),
        .alu_src1   (alu_src1),
        .alu_src2   (alu_src2),
        .alu_result (alu_result)
    );

// Multiplier
    multiplier u_mul(
        .mul_src1   (alu_src1),
        .mul_src2   (alu_src2),
        .mul_op     (alu_op[2:0] & {3{valid}}),
        .mul_res    (mul_result)
    );

// Divider
    divider u_div(
        .clk        (clk),
        .reset      (reset),
        .div_src1   (alu_src1),
        .div_src2   (alu_src2),
        .div_op     (alu_op[3:0] & {4{valid & div}}),
        .div_res    (div_result),
        .div_done   (div_done)
    );

// Access MEM
    assign data_sram_en     = mem_en & valid;
    assign data_sram_addr   = alu_result;
    assign data_sram_wdata  = rkd_value;
    assign data_sram_we     = mem_we & {4{valid}};

// EXreg_bus
    assign EXreg_valid      = valid;
    assign EXreg_2MEM       = {EX_result, rkd_value, mem_we};
    assign EXreg_2WB        = {rf_we, res_from_mem, rf_waddr, pc};
    assign EXreg_bus        = {EXreg_2MEM, EXreg_2WB};

// Data Harzard Bypass
    assign  EX_rf_waddr         = rf_waddr;
    assign  EX_rf_we            = rf_we & valid;
    assign  EX_res_from_mem     = res_from_mem;
    assign  EX_result           =   mul ? mul_result :
                                    div ? div_result :
                                    alu_result;

    assign  EX_bypass_bus       = {EX_rf_waddr, EX_rf_we, EX_res_from_mem, EX_result};

// control signals
    assign EX_ready_go      = (div & valid) ? div_done : 1;
    assign EX_allow_in      = MEM_allow_in & EX_ready_go;

endmodule