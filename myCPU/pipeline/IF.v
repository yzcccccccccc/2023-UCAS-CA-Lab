`include "../macro.vh"

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
    output  wire        preIF_cancel,
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
    /***************************************************
        Hint:
        ebus is used to pass exception signals (one-hot 
        encoding ) along pipeline.
    ****************************************************/
    wire    [15:0]  ebus_init = 16'b0;
    wire    [15:0]  ebus_end;

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

    wire        preIF_cancel, to_IF_valid;

    reg         IF_cancel_r;
    wire        IF_cancel_tak;
    wire        IF_cancel;
    reg  [7:0]  unfinish_cnt;
    wire        recv_inst_from_sram;
    wire        recv_inst_from_buf;

    assign {br_target, br_taken, br_stall}  = BR_BUS;

//----------------------------------------------------Exception----------------------------------------------------
// ADEF detection(EXP13)
    /*********************************************************
        detect ADEF in pre-IF
        not set adef_ex until the wrong pc go to IF stage
    2023.11.10 yzcc
        IF_has_adef is for IF stage
    *********************************************************/
    reg     IF_has_adef;
    wire    preIF_has_adef;
    assign  preIF_has_adef  = pc_next[1:0] != 2'b0;

    always@(posedge clk)
    begin
        if(reset)
            IF_has_adef <= 1'b0;
        else
            if (preIF_ready_go & IF_allow_in)
                IF_has_adef <= preIF_has_adef;
    end
// ebus
    assign ebus_end = ebus_init | {{15-`EBUS_ADEF{1'b0}}, IF_has_adef, {`EBUS_ADEF{1'b0}}};

//------------------------------------------------------preIF------------------------------------------------------
    // preIF_ready_go
    /***********************************************************
    2023.11.10 yzcc
        About preIF_ready_go:
        1. successfully shake hands
        2. ADEF
    ************************************************************/
    /***********************************************************
    2023.11.12 czxx
        It's ok when preIF_cancel, the inst that will go to next
    stage would be invalidated.
    ************************************************************/
    assign preIF_ready_go           = inst_sram_req & inst_sram_addr_ok;// | preIF_has_adef;

    // to_IF_valid
    /***********************************************************
    2023.11.12 czxx
        to_IF_valid should be invalidated if addr request happen
    to be accepted when we need to cancel preIF 
    ************************************************************/
    assign preIF_cancel = (ertn_flush & except_valid | wb_ex & except_valid | br_taken);
    assign to_IF_valid  = preIF_ready_go & ~preIF_cancel;

    // Retaining cancel situation
    /***********************************************************
    2023.11.10 yzcc
        These regs are used for storing PCs when facing cancel
    situation. The reason of using regs is that these signals
    can only exist for 1 clock.
    ***********************************************************/
    reg             ertn_taken_r, ex_taken_r, br_taken_r;
    reg [31:0]      ertn_pc_r, ex_pc_r, br_pc_r;
    always @(posedge clk) begin
        /******************************************************
        2023.11.12 czxx
            When to reset?
            1. reset signal
            2. handshake after cancel( ~preIF_cancel means
        'after cancel')
        ******************************************************/
        if (reset | ~preIF_cancel & preIF_ready_go & IF_allow_in) begin
            {ertn_taken_r, ertn_pc_r}           <= 0;
            {ex_taken_r, ex_pc_r}               <= 0;
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
    assign  ertn_tak        = ertn_flush & except_valid | ertn_taken_r;
    assign  ertn_pc         = {32{ertn_flush & except_valid}} & era_pc
                            | {32{ertn_taken_r}} & ertn_pc_r;
    assign  ex_tak          = wb_ex & except_valid | ex_taken_r;
    assign  ex_pc           = {32{wb_ex & except_valid}} & ex_entry
                            | {32{ex_taken_r}} & ex_pc_r;
    assign  br_tak          = br_taken | br_taken_r;
    assign  br_pc           = {32{br_taken}} & br_target
                            | {32{br_taken_r}} & br_pc_r;

    // pc_next
    assign pc_seq           = pc + 32'h4;
    assign  pc_next         = ex_tak ? ex_pc
                            : ertn_tak ? ertn_pc
                            : br_tak ? br_pc
                            : pc_seq;

    // inst_sram_req
    /*************************************************************
    2023.11.10 yzcc
        About inst_sram_req:
        1. only pull up when IF is ready to accept (IF_allow_in).
        2. ADEF will not pull up a request.
    **************************************************************/
    assign inst_sram_req            = ~reset & ~br_stall & IF_allow_in;// & ~preIF_has_adef;
    assign inst_sram_addr           = pc_next;
    assign inst_sram_wr             = 0;
    assign inst_sram_wstrb          = 0;
    assign inst_sram_wdata          = 0;
    assign inst_sram_size           = 2'b10;            // 2 means 2^2 = 4 bytes.

//------------------------------------------------------IF------------------------------------------------------
    /*****************************************************************
    2023.11.12 czxx
        About IF_ready_go:
        1. Have acquired the data (data_ok or IF_buf_valid).
        2. ADEF
    *****************************************************************/
    assign IF_ready_go      = recv_inst_from_sram & inst_sram_data_ok
                            | recv_inst_from_buf & IF_buf_valid
                            | IF_has_adef;
    assign IF_allow_in      = ~IFreg_valid | ID_allow_in & IF_ready_go;
    assign IFreg_valid      = IF_valid & ~IF_cancel_tak;

    // IF_valid
    // Old
    /***********************************************************
    2023.11.10 yzcc
        Update IF_valid when preIF is ready to push a PC into
    IF stage. Pay attention that IF_valid only stands for part
    of the validity of the PC(or inst) in IF stage, because
    IF_cancel will also affect the validity when pushing to ID.
    ************************************************************/
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

    // Retaining cancel situation
    /*****************************************************************
    2023.11.10 yzcc
        IF_cancel may only last for 1 clk, so we need to use a reg to
    record it. (IF_cancel_r)
    *****************************************************************/
    /*****************************************************************
    2023.11.12 czxx
        When to reset?
        a new inst has entered this stage
    *****************************************************************/
    assign IF_cancel    = (ertn_flush & except_valid | wb_ex & except_valid | br_taken);
    always @(posedge clk) begin
        if (reset)
            IF_cancel_r  <= 0;
        else
            if (preIF_ready_go & IF_allow_in) begin
                IF_cancel_r  <= 0; 
            end
            else
                if (IF_cancel)
                    IF_cancel_r  <= 1;
    end
    assign IF_cancel_tak = IF_cancel | IF_cancel_r;

    // recv_inst
    /*******************************************************************
    2023.11.12 czxx
        unfinish_cnt is used to record the num of inst req that have
    handshakes but still haven't return rdata.
    ********************************************************************/
    always @(posedge clk) begin
        if (reset)
            unfinish_cnt <= 0;
        else begin
            if (inst_sram_req & inst_sram_addr_ok & ~inst_sram_data_ok)
                unfinish_cnt <= unfinish_cnt+8'b1;
            else
                if (~(inst_sram_req & inst_sram_addr_ok) & inst_sram_data_ok)
                    unfinish_cnt <= unfinish_cnt-8'b1;
        end
    end
    /*******************************************************************
    2023.11.12 czxx
        only receive inst when IF_valid. (if ~IF_valid it just ignore
    rdata from inst ram, but unfinish_cnt still works).
        when IF_valid, unfinish_cnt>8'b1 means there are unfinished inst
    req, we should ignore rdata from inst ram.
        when IF_valid, unfinish_cnt==8'b1 means we should receive rdata
    from inst ram.
        when IF_valid, unfinish_cnt==8'b0 means inst ram has already
    return rdata and it was stored in IF_buf.
    ********************************************************************/
    assign recv_inst_from_sram = IF_valid & unfinish_cnt==8'b1;
    assign recv_inst_from_buf = IF_valid & unfinish_cnt==8'b0;

    // IF_buf
    /*******************************************************************
    2023.11.12 czxx
        IF_buf is used to store inst temporarily when:
      current inst is valid
    & we should receive rdata from inst ram
    & data_ok
    & couldn't enter ID stage immediately
    ********************************************************************/
    always @(posedge clk) begin
        if (reset) begin
            IF_buf_valid    <= 0;
            IF_buf_inst     <= 0;
        end
        else begin
            if (IFreg_valid & recv_inst_from_sram & inst_sram_data_ok & ~(IF_ready_go & ID_allow_in)) begin
                IF_buf_valid    <= 1;
                IF_buf_inst     <= inst_sram_rdata;
            end
            else
                if (ID_allow_in & IF_ready_go)
                    IF_buf_valid    <= 0;
        end
    end

    // pc
    always @(posedge clk)
    begin
        if (reset)
            pc <= 32'h1bfffffc;
        else
            if (preIF_ready_go & IF_allow_in)
                pc <= pc_next;
    end

    // inst
    assign inst     = IF_buf_valid ? IF_buf_inst 
                    : inst_sram_rdata;

// to IFreg_bus
    assign IFreg_bus        = {ebus_end, inst, pc};

endmodule