`include "macro.vh"

module IF(
    input  wire        clk,
    input  wire        reset,

    // inst sram interface
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
    wire            br_taken, br_stall;

    reg             IF_valid;
    wire            IF_allow_in;
    wire            preIF_ready_go;

    wire        ertn_tak;
    wire        ex_tak;
    wire        br_tak;
    wire [31:0] ertn_pc, ex_pc, br_pc;

    reg         preIF_invalid_req;              // whether need to invalid the inst in preIF
    wire        preIF_cancel, to_IF_valid;

    reg         IF_invalid_req;
    wire        IF_cancel;

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
            if (preIF_ready_go & IF_allow_in)
                has_adef <= preIF_has_adef;
    end

// Pre IF
    reg             ertn_valid, ex_valid, br_valid;
    reg             ertn_taken_r, ex_taken_r, br_taken_r;
    reg [31:0]      ertn_pc_r, ex_pc_r, br_pc_r;
    always @(posedge clk) begin
        if (reset | preIF_ready_go & IF_allow_in & to_IF_valid) begin          // reset after a req has been sent
            {ertn_taken_r, ertn_pc_r}           <= 0;
            {ex_taken_r, ex_pc_r}              <= 0;
            {br_taken_r, br_pc_r}               <= 0;
        end
        else begin
            if (ertn_flush & except_valid)
                {ertn_taken_r, ertn_pc_r}   <= {1'b1, era_pc};
            if (wb_ex & except_valid)
                {ex_taken_r, ex_pc_r}       <= {1'b1, ex_entry};
            if (br_taken)
                {br_taken_r, br_pc_r}       <= {1'b1, br_target};
        end
    end
    assign pc_seq                           = pc + 32'h4;
    assign {br_target, br_taken, br_stall}  = BR_BUS;

    assign  ertn_tak        = ertn_flush & except_valid | ertn_taken_r;
    assign  ertn_pc         = {32{ertn_flush & except_valid}} & era_pc
                            | {32{ertn_taken_r}} & ertn_pc_r;
    assign  ex_tak          = wb_ex & except_valid | ex_taken_r;
    assign  ex_pc           = {32{wb_ex & except_valid}} & ex_entry
                            | {32{ex_taken_r}} & ex_pc_r;
    assign  br_tak          = br_taken | br_taken_r;
    assign  br_pc           = {32{br_taken}} & br_target
                            | {32{br_taken_r}} & br_pc_r;

    assign  pc_next         = ex_tak ? ex_pc
                            : ertn_tak ? ertn_pc
                            : br_tak ? br_pc
                            : pc_seq;

    assign inst_sram_req            = ~reset & ~preIF_has_adef & ~br_stall & IF_allow_in;
    assign inst_sram_addr           = pc_next;
    assign inst_sram_wr             = 0;
    assign inst_sram_wstrb          = 0;
    assign inst_sram_wdata          = 0;
    assign inst_sram_size           = 2'b10;            // 2 means 2^2 = 4 bytes.

    assign preIF_ready_go           = inst_sram_req & inst_sram_addr_ok | preIF_has_adef;

// to_IF_valid
    assign preIF_cancel = ertn_flush & except_valid | wb_ex & except_valid | br_taken | preIF_has_adef;
    always @(posedge clk) begin
        if (reset)
            preIF_invalid_req     <= 0;
        else
            if (preIF_cancel) begin
                if (preIF_ready_go & ~IF_allow_in)         // addr handshake has succeeded ...
                    preIF_invalid_req   <= 1;
            end
            else
                if (preIF_ready_go)
                    preIF_invalid_req   <= 0;
    end
    assign to_IF_valid  = preIF_ready_go & ~preIF_invalid_req & ~preIF_cancel;

// IF
    assign IF_cancel    = ertn_flush & except_valid | wb_ex & except_valid | br_taken;
    always @(posedge clk) begin
        if (reset)
            IF_invalid_req  <= 0;
        else
            if (IF_cancel) begin
                IF_invalid_req  <= 1; 
            end
            else
                if (IF_ready_go)
                    IF_invalid_req  <= 0;
    end

    reg preIF_has_handshake;
    always @(posedge clk) begin
        if (reset)
            preIF_has_handshake <= 0;
        else begin
            if (inst_sram_req & inst_sram_addr_ok)
                preIF_has_handshake <= 1;
            else
                if (IF_ready_go & ID_allow_in)
                    preIF_has_handshake <= 0;
        end
    end

    assign IF_ready_go      = inst_sram_data_ok | IF_buf_valid | ~IF_valid & ~preIF_has_handshake;
    assign IF_allow_in      = ID_allow_in & IF_ready_go;

    always @(posedge clk) begin
        if (reset) begin
            IF_buf_valid    <= 0;
            IF_buf_inst     <= 0;
        end
        else begin
            if (IF_ready_go & ~ID_allow_in & ~IF_cancel) begin
                IF_buf_valid    <= 1;
                IF_buf_inst     <= inst_sram_rdata;
            end
            else
                IF_buf_valid    <= 0;
        end
    end

    assign inst     = IF_buf_valid ? IF_buf_inst 
                    : inst_sram_rdata;

// IF_valid
    always @(posedge clk)
    begin
        if (reset)
            IF_valid <= 0;
        else begin
            if (preIF_ready_go & IF_allow_in)
                IF_valid    <= to_IF_valid;
            else
                if (IF_ready_go & ID_allow_in)
                    IF_valid    <= 0;
        end
    end

// exception
assign ebus_end = ebus_init | {{15-`EBUS_ADEF{1'b0}}, has_adef, {`EBUS_ADEF{1'b0}}};

// to IFreg_bus
assign IFreg_valid      = IF_valid & ~IF_cancel & ~IF_invalid_req;
assign IFreg_bus        = {ebus_end, inst, pc};


endmodule