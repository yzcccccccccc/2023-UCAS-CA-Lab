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
    output wire         IFReg_valid,
    output wire [31:0]  IFreg_pc,
    output wire [31:0]  IFreg_inst

    // BR_BUS (={br_target, br_taken})
    input  wire [`BR_BUS_LEN - 1:0] BR_BUS
);

    reg     [31:0]  pc;
    wire    [31:0]  pc_next;
    wire    [31:0]  inst;

    wire    [31:0]  pc_seq;
    wire    [31:0]  br_target;
    wire            br_taken;

    reg             IF_valid;

    // PC
    always @(posedge clk) begin
        if (reset)
            pc <= 32'h1bfffffc;
        else
            if (ID_allow_in)
                pc <= pc_next;
    end

    // Pre IF
    assign pc_sec                   = pc + 32'h4;
    assign {br_taken, br_target}    = BR_BUS;
    assign pc_next                  = pc_sec;       // to be fixed in exp8

    // IF
    assign inst_sram_we     = 4'b0;
    assign inst_sram_en     = ID_allow_in & ~reset;
    assign inst_sram_addr   = ID_allow_in ? pc_next : pc;
    assign inst_sram_wdata  = 32'b0;
    assign inst             = inst_sram_rdata;

    // IF_valid
    always @(posedge clk) begin
        if (reset)
            IF_valid <= 0;
        else
            IF_valid <= 1;
    end

    // to IF_reg
    assign IFReg_valid      = IF_valid;
    assign IFreg_inst       = inst;
    assign IFreg_pc         = pc;

    // control signals
    assign IF_ready_go      = 1'b1;

endmodule