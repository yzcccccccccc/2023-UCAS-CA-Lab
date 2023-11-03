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
           output  wire [`EXReg_BUS_LEN - 1:0] EXreg_bus,

           input wire st_disable,

           // rdcntv
           input wire [31:0] counter_value,
           output wire [1:0] rdcntv_op
       );

/************************************************************************************
    Hint:
        In EX state, we need to request data_ram for the data to be used
    in MEM state.
*************************************************************************************/

// ebus
wire [15:0] ebus_init;
wire [15:0] ebus_end;

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
wire    [2:0]   st_ctrl;            // = {inst_st_w, inst_st_h, inst_st_b}
wire    [4:0]   ld_ctrl;

wire ertn_flush;
wire [79:0]     csr_ctrl;
wire res_from_csr;
wire            rf_we;
wire            res_from_mem;
wire    [4:0]   rf_waddr;
wire    [31:0]  pc;

wire       res_from_rdcntv;

assign  {rdcntv_op, ebus_init, alu_op, alu_src1, alu_src2, mul, div}      = ID2EX_bus;
assign  {rkd_value, mem_en, st_ctrl, ld_ctrl}       = ID2MEM_bus;
assign  {ertn_flush, csr_ctrl, res_from_csr, rf_we, res_from_mem, rf_waddr, pc}         = ID2WB_bus;

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
               .clk        (clk),
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
wire    [3:0]       mem_we;
wire    [31:0]      st_data;
assign mem_we   = {4{st_ctrl[0] & ~alu_result[0] & ~alu_result[1]}} & {4'b0001}
       | {4{st_ctrl[0] & alu_result[0] & ~alu_result[1]}} & {4'b0010}
       | {4{st_ctrl[0] & ~alu_result[0] & alu_result[1]}} & {4'b0100}
       | {4{st_ctrl[0] & alu_result[0] & alu_result[1]}} & {4'b1000}
       | {4{st_ctrl[1] & ~alu_result[1]}} & {4'b0011}
       | {4{st_ctrl[1] & alu_result[1]}} & {4'b1100}
       | {4{st_ctrl[2]}} & {4'b1111};
assign st_data  = {32{st_ctrl[0]}} & {4{rkd_value[7:0]}}
       | {32{st_ctrl[1]}} & {2{rkd_value[15:0]}}
       | {32{st_ctrl[2]}} & {rkd_value[31:0]};

// exp13 ale
wire has_ale;
assign has_ale = st_ctrl[1] && alu_result[0]                    ||
                 st_ctrl[2] && (alu_result[0] || alu_result[1]) ||
                 ld_ctrl[0] && alu_result[0]                    ||
                 ld_ctrl[1] && alu_result[0]                    ||
                 ld_ctrl[4] && (alu_result[0] || alu_result[1]);

assign data_sram_en     = mem_en & valid & !has_ale;
assign data_sram_addr   = {alu_result[31:2], 2'b0};
assign data_sram_wdata  = st_data;
assign data_sram_we     = mem_we & {4{valid & ~st_disable}};

// exp13 rdcntv
assign res_from_rdcntv = |rdcntv_op;

// exception
assign ebus_end = ebus_init | {{15-`EBUS_ALE{1'b0}}, has_ale, {`EBUS_ALE{1'b0}}} & {16{valid}};

// EXreg_bus
assign EXreg_valid      = valid;
assign EXreg_2MEM       = {ebus_end, mul, mul_result, EX_result, rkd_value, ld_ctrl};
assign EXreg_2WB        = {ertn_flush, csr_ctrl, res_from_csr, rf_we, res_from_mem, rf_waddr, pc};
assign EXreg_bus        = {EXreg_2MEM, EXreg_2WB};

// Data Harzard Bypass
assign  EX_rf_waddr         = rf_waddr;
assign  EX_rf_we            = rf_we & valid;
assign  EX_res_from_mem     = res_from_mem;
assign  EX_result           =   div ? div_result :
                                res_from_rdcntv ? counter_value :
                                alu_result;

assign  EX_bypass_bus       = {res_from_csr, EX_rf_waddr, EX_rf_we, mul, EX_res_from_mem, EX_result};

// control signals
assign EX_ready_go      = (div & valid) ? div_done : 1;
assign EX_allow_in      = MEM_allow_in & EX_ready_go;

endmodule