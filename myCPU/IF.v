`include "macro.vh"

module IF(
           input  wire        clk,
           input  wire        reset,

           // inst sram interface
           output wire [3:0]  inst_sram_we,
           output wire        inst_sram_en,
           output wire [31:0] inst_sram_addr,
           output wire [31:0] inst_sram_wdata,
           input  wire [31:0] inst_sram_rdata,

           // control signals
           output wire         IF_ready_go,
           input  wire         ID_allow_in,

           // IFreg bus
           output wire                         IFreg_valid,
           output wire [`IFReg_BUS_LEN - 1:0]  IFreg_bus,

           // BR_BUS (={br_target, br_taken})
           input  wire [`BR_BUS_LEN - 1:0] BR_BUS,

           // exception
           input wire except_valid,
           input wire wb_ex,
           input wire [31:0] ex_entry,
           input wire ertn_flush,
           input wire [31:0] era_pc
       );

reg     [31:0]  pc;
wire    [31:0]  pc_next;
wire    [31:0]  inst;

wire    [31:0]  pc_seq;
wire    [31:0]  br_target;
wire            br_taken;

reg             IF_valid;

/***************************************************
    Hint:
    ebus is used to pass exception signals (one-hot 
    encoding ) along pipeline.
****************************************************/
wire [15:0] ebus_init = 16'b0;
wire [15:0] ebus_end;

// PC
always @(posedge clk)
begin
    if (reset)
        pc <= 32'h1bfffffc;
    else
        if (ID_allow_in | wb_ex | ertn_flush)
            pc <= pc_next;
end

// Pre IF
assign pc_seq                   = pc + 32'h4;
assign {br_target, br_taken}    = BR_BUS;
assign pc_next                  = (ertn_flush&except_valid) ? era_pc :
                                    (wb_ex&except_valid) ? ex_entry :
                                    br_taken ? br_target : pc_seq;

// exp13 ADEF
// detect ADEF when pre-IF
// not set adef_ex until the wrong pc go to IF stage
reg has_adef;
always@(posedge clk)
begin
    if(reset)
        has_adef <= 1'b0;
    else
        has_adef <= pc_next[1:0] != 2'b0;
end

// IF
assign inst_sram_we     = 4'b0;
assign inst_sram_en     = ID_allow_in & ~reset | (wb_ex&except_valid) | (ertn_flush&except_valid);               // don't need to care about ID_allow_in when wb_ex or ertn_flush
assign inst_sram_addr   = (ID_allow_in | (wb_ex&except_valid) | (ertn_flush&except_valid)) ? pc_next : pc;       // kind of 'blocking pc (instruction) in IF'.
assign inst_sram_wdata  = 32'b0;
assign inst             = inst_sram_rdata;

// IF_valid
always @(posedge clk)
begin
    if (reset)
        IF_valid <= 0;
    else
        IF_valid <= 1;
end

// exception
assign ebus_end = ebus_init | {{15-`EBUS_ADEF{1'b0}}, has_adef, {`EBUS_ADEF{1'b0}}} & {16{IF_valid}};

// to IFreg_bus
assign IFreg_valid      = IF_valid & ~br_taken & ~(|ebus_end);
assign IFreg_bus        = {ebus_end, inst, pc};

// control signals
assign IF_ready_go      = 1'b1;

endmodule