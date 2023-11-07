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

    output  wire        inst_sram_req,
    output  wire        inst_sram_wr,
    output  wire [1:0]  inst_sram_size,
    output  wire [31:0] inst_sram_addr,
    output  wire [3:0]  inst_sram_wstrb,
    output  wire [31:0] inst_sram_wdata,
    input   wire        inst_sram_addr_ok,
    input   wire        inst_sram_data_ok,
    input   wire [31:0] inst_sram_rdata,

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

// Signal definitions
reg     [31:0]  pc;
wire    [31:0]  pc_next;
wire    [31:0]  inst;

reg     [31:0]  preIF_buf_inst, IF_buf_inst;
reg             preIF_buf_valid, IF_buf_valid;

wire    [31:0]  pc_seq;
wire    [31:0]  br_target;
wire            br_taken;

reg             IF_valid;
wire            IF_allow_in;
wire            preIF_ready_go;

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
        if (preIF_ready_go & IF_allow_in)
            pc <= pc_next;
end

// FSM control
    reg [2:0]   preIF_current, preIF_next, IF_current, IF_next;

    localparam INIT     = 3'b001;
    localparam SEND     = 3'b010;
    localparam WAIT     = 3'b100;
    localparam isINIT   = 0;
    localparam isSEND   = 1;
    localparam isWAIT   = 2;

// ADEF (EXP13)
    /*********************************************************
        detect ADEF in pre-IF
        not set adef_ex until the wrong pc go to IF stage
    *********************************************************/
    reg     has_adef;
    wire    preIF_has_adef;
    assign  preIF_has_adef  = pc_next[1:0] != 2'b0;

    always@(posedge clk)
    begin
        if(reset)
            has_adef <= 1'b0;
        else
            has_adef <= preIF_has_adef;
    end

// Pre IF
    assign pc_seq                   = pc + 32'h4;
    assign {br_target, br_taken}    = BR_BUS;
    assign pc_next                  = (ertn_flush&except_valid) ? era_pc :
                                    (wb_ex&except_valid) ? ex_entry :
                                    br_taken ? br_target : pc_seq;

    assign inst_sram_req            = IF_current[isSEND] & (~reset | (wb_ex&except_valid) | (ertn_flush&except_valid)) & ~preIF_has_adef;
    assign inst_sram_addr           = pc_next;
    assign inst_sram_wr             = 0;
    assign inst_sram_wstrb          = 0;
    assign inst_sram_wdata          = 0;
    assign inst_sram_size           = 2'b10;            // 2 means 2^2 = 4 bytes.

    assign preIF_ready_go           = inst_sram_req & inst_sram_addr_ok | preIF_has_adef;

    always @(posedge clk) begin
        if (reset)
            preIF_current   <= INIT;
        else
            preIF_current   <= preIF_next;
    end

    always @(*) begin
        case(preIF_current)
            INIT:
                preIF_next  <= SEND;
            SEND: begin
                if (!IF_allow_in & preIF_ready_go)
                    preIF_next  <= WAIT;
                else
                    preIF_next  <= SEND;
            end
            WAIT: begin
                if (IF_allow_in)
                    preIF_next  <= SEND;
                else
                    preIF_next  <= WAIT;
            end
            default: preIF_next <= INIT;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            preIF_buf_valid         <= 0;
            preIF_buf_inst          <= 0;
        end 
        else begin
            if (preIF_current[isSEND])
                preIF_buf_valid     <= 0;
            if (preIF_current[isWAIT] & inst_sram_data_ok & ~IF_allow_in) begin
                preIF_buf_valid     <= 1;
                preIF_buf_inst      <= inst_sram_rdata;
            end 
        end
    end

// IF
    assign IF_ready_go      = inst_sram_data_ok;
    assign IF_allow_in      = ID_allow_in & IF_ready_go;

    always @(posedge clk) begin
        if (reset)
            IF_current      <= INIT;
        else
            IF_current      <= IF_next;
    end

    always @(*) begin
        case(IF_current)
            INIT:
                IF_next     <= SEND;
            SEND:
                if (!ID_allow_in & IF_ready_go)
                    IF_next     <= WAIT;
                else
                    IF_next     <= SEND;
            WAIT:
                if (ID_allow_in)
                    IF_next     <= SEND;
                else
                    IF_next     <= WAIT;
            default:
                IF_next     <= INIT;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            IF_buf_valid    <= 0;
            IF_buf_inst     <= 0;
        end
        else begin
            if (IF_current[isSEND])
                IF_buf_valid    <= 0;
            if (IF_current[isWAIT] & IF_ready_go & ~ID_allow_in) begin
                IF_buf_valid    <= 1;
                IF_buf_inst     <= preIF_buf_valid ? preIF_buf_inst : inst_sram_rdata;
            end
        end
    end

    assign inst     = preIF_buf_valid ? preIF_buf_inst : inst_sram_rdata;

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


endmodule