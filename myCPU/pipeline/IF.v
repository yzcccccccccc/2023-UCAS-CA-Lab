`include "../macro.vh"

module IF(
    input  wire        clk,
    input  wire        reset,

    // ICache interface
    output  wire        icache_valid,
    output  wire [7:0]  icache_index,
    output  wire [19:0] icache_tag,
    output  wire [3:0]  icache_offset,
    input   wire        icache_addrok,
    input   wire        icache_dataok,
    input   wire [31:0] icache_rdata,

    // control signals
    output wire         IF_ready_go,
    input  wire         ID_allow_in,

    // IFreg bus
    output wire                         IFreg_valid,
    output wire [`IFReg_BUS_LEN - 1:0]  IFreg_bus,

    // BR_BUS (={br_target, br_taken})
    input  wire [`BR_BUS_LEN - 1:0] BR_BUS,

    // exception
    input   wire        except_valid,
    input   wire        WB_ex,
    input   wire [31:0] ex_entry,
    input   wire        ertn_flush,
    input   wire [31:0] era_pc,

    // refetch
    input   wire        refetch,
    input   wire        refetch_flush,
    input   wire [31:0] refetch_pc,

    // CSR value
    input   wire [31:0] csr_asid,
    input   wire [31:0] csr_crmd,
    input   wire [31:0] csr_dmw0,
    input   wire [31:0] csr_dmw1,

    // TLB ports (s0_)
    output  wire [18:0]     s0_vppn,
    output  wire            s0_va_bit12,
    output  wire [9:0]      s0_asid,
    input   wire            s0_found,
    input   wire [3:0]      s0_index,
    input   wire [19:0]     s0_ppn,
    input   wire [5:0]      s0_ps,
    input   wire [1:0]      s0_plv,
    input   wire [1:0]      s0_mat,
    input   wire            s0_d,
    input   wire            s0_v
);
    wire    [31:0]  pa;
    // data_sram interface convert
    wire        inst_sram_req;
    wire        inst_sram_wr;
    wire [1:0]  inst_sram_size;
    wire [31:0] inst_sram_addr;
    wire [3:0]  inst_sram_wstrb;
    wire [31:0] inst_sram_wdata;
    wire        inst_sram_addr_ok;
    wire        inst_sram_data_ok;
    wire [31:0] inst_sram_rdata;
    assign icache_valid = inst_sram_req;
    assign icache_tag = pa[31:12];
    assign icache_index = pc_next[11:4];
    assign icache_offset = pc_next[3:0];
    assign inst_sram_addr_ok = icache_addrok;
    assign inst_sram_data_ok = icache_dataok;
    assign inst_sram_rdata = icache_rdata;

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

    reg     [31:0]  IF_buf_inst;
    reg             IF_buf_valid;

    wire    [31:0]  pc_seq;
    wire    [31:0]  br_target;
    wire            br_taken, br_stall;

    reg             IF_valid;
    wire            IF_allow_in;
    wire            preIF_ready_go;

    wire        ertn_tak;
    wire        ex_tak;
    wire        br_tak;
    wire        refetch_flush_tak;
    wire [31:0] ertn_pc, ex_pc, br_pc, refetch_flush_pc;

    wire        to_IF_valid;

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

    2023.11.30 yzcc
        Include other Exception. (exp19)
    *********************************************************/
    wire    preIF_has_mem_except;           // PIL, PIS, PIF, PME, PPI, TLBR
    reg     IF_has_mem_except;
    
    wire [5:0]  mem_except;
    reg     IF_has_adef, IF_has_pil, IF_has_pis, IF_has_pif, IF_has_pme, IF_has_ppi, IF_has_tlbr;
    wire    preIF_has_adef, preIF_has_pil, preIF_has_pis, preIF_has_pif, preIF_has_pme, preIF_has_ppi, preIF_has_tlbr;

    assign  preIF_has_adef  = pc_next[1:0] != 2'b0;
    assign  {preIF_has_pil, preIF_has_pis, preIF_has_pif, preIF_has_pme, preIF_has_ppi, preIF_has_tlbr}    = mem_except;

    always@(posedge clk)
    begin
        if(reset) begin
            IF_has_adef <= 1'b0;
            IF_has_pil  <= 1'b0;
            IF_has_pis  <= 1'b0;
            IF_has_pif  <= 1'b0;
            IF_has_pme  <= 1'b0;
            IF_has_ppi  <= 1'b0;
            IF_has_tlbr <= 1'b0;
            IF_has_mem_except   <= 1'b0;
        end
        else
            if (preIF_ready_go & IF_allow_in) begin
                IF_has_adef <= preIF_has_adef;
                IF_has_pil  <= preIF_has_pil;
                IF_has_pis  <= preIF_has_pis;
                IF_has_pif  <= preIF_has_pif;
                IF_has_pme  <= preIF_has_pme;
                IF_has_ppi  <= preIF_has_ppi;
                IF_has_tlbr <= preIF_has_tlbr;
                IF_has_mem_except   <= preIF_has_mem_except;
            end
    end
// ebus
    assign ebus_end = ebus_init | {{15-`EBUS_ADEF{1'b0}}, IF_has_adef, {`EBUS_ADEF{1'b0}}}
                                | {{15-`EBUS_PIL{1'b0}}, IF_has_pil, {`EBUS_PIL{1'b0}}}
                                | {{15-`EBUS_PIS{1'b0}}, IF_has_pis, {`EBUS_PIS{1'b0}}}
                                | {{15-`EBUS_PIF{1'b0}}, IF_has_pif, {`EBUS_PIF{1'b0}}}
                                | {{15-`EBUS_PME{1'b0}}, IF_has_pme, {`EBUS_PME{1'b0}}}
                                | {{15-`EBUS_PPI{1'b0}}, IF_has_ppi, {`EBUS_PPI{1'b0}}}
                                | {{15-`EBUS_TLBR{1'b0}}, IF_has_tlbr, {`EBUS_TLBR{1'b0}}};

//------------------------------------------------------preIF------------------------------------------------------
    // preIF_refetch
    /***********************************************************
    2023.11.30 yzcc
        preIF_refetch_tag:
            mark whether the pc in preIF stage needs refetch
    ***********************************************************/
    wire    preIF_refetch_tag;
    reg     preIF_refetch_tag_r;
    always @(posedge clk) begin
        if (reset)
            preIF_refetch_tag_r <= 0;
        else begin
            if (preIF_ready_go && IF_allow_in)
                preIF_refetch_tag_r <= 0;
            else
                if (refetch)
                    preIF_refetch_tag_r <= 1;
        end
    end
    assign  preIF_refetch_tag   = preIF_refetch_tag_r | refetch;

    // preIF_ready_go
    /***********************************************************
    2023.11.10 yzcc
        About preIF_ready_go:
        1. successfully shake hands
        2. ADEF

    2023.11.30 yzcc
        also allow to go when preIF is tagged with 'refetch'
    ************************************************************/
    assign preIF_ready_go = (inst_sram_req & inst_sram_addr_ok) | preIF_has_adef | preIF_has_mem_except | preIF_refetch_tag;

    // to_IF_valid
    assign to_IF_valid  = preIF_ready_go;

    // Retaining cancel situation
    /***********************************************************
    2023.11.10 yzcc
        These regs are used for storing PCs when facing cancel
    situation. The reason of using regs is that these signals
    can only exist for 1 clock.

    2023.11.30 yzcc
        Also regard refetch_flush as a cancel situalion.
        (refetch_flush: pc in WB stage tagged with 'refetch')
    ***********************************************************/
    reg             ertn_taken_r, ex_taken_r, br_taken_r, refetch_flush_r;
    reg [31:0]      ertn_pc_r, ex_pc_r, br_pc_r, refetch_pc_r;
    always @(posedge clk) begin
        /******************************************************
        2023.11.12 czxx
            When to reset?
            1. reset signal
            2. handshake
        ******************************************************/
        if (reset | preIF_ready_go & IF_allow_in) begin
            {ertn_taken_r, ertn_pc_r}           <= 0;
            {ex_taken_r, ex_pc_r}               <= 0;
            {br_taken_r, br_pc_r}               <= 0;
            {refetch_flush_r, refetch_pc_r}     <= 0;
        end
        else begin
            if (ertn_flush & except_valid)
                {ertn_taken_r, ertn_pc_r}       <= {1'b1, era_pc};
            if (WB_ex & except_valid)
                {ex_taken_r, ex_pc_r}           <= {1'b1, ex_entry};
            if (br_taken)
                {br_taken_r, br_pc_r}           <= {1'b1, br_target};
            if (refetch_flush)
                {refetch_flush_r, refetch_pc_r} <= {1'b1, refetch_pc};
        end
    end
    assign  ertn_tak            = ertn_flush & except_valid | ertn_taken_r;
    assign  ertn_pc             = {32{ertn_flush & except_valid}} & era_pc
                                | {32{ertn_taken_r}} & ertn_pc_r;
    assign  ex_tak              = WB_ex & except_valid | ex_taken_r;
    assign  ex_pc               = {32{WB_ex & except_valid}} & ex_entry
                                | {32{ex_taken_r}} & ex_pc_r;
    assign  br_tak              = br_taken | br_taken_r;
    assign  br_pc               = {32{br_taken}} & br_target
                                | {32{br_taken_r}} & br_pc_r;
    assign  refetch_flush_tak   = refetch_flush | refetch_flush_r;
    assign  refetch_flush_pc    = {32{refetch_flush}} & refetch_pc
                                | {32{refetch_flush_r}} & refetch_pc_r;

    // pc_next
    assign  pc_seq          = pc + 32'h4;
    assign  pc_next         = refetch_flush_tak ? refetch_flush_pc
                            : ex_tak ? ex_pc
                            : ertn_tak ? ertn_pc
                            : br_tak ? br_pc
                            : pc_seq;

    // inst_sram_req
    /*************************************************************
    2023.11.10 yzcc
        About inst_sram_req:
        1. only pull up when IF is ready to accept (IF_allow_in).
        2. ADEF will not pull up a request.

    2023.11.30 yzcc
        3. pc tagged 'refetch' will not pull up a request

    2023.11.30 yzcc
        4. mem eceptions (PIL etc.) will not pull up a request
    **************************************************************/
    wire    [1:0]   mat;

    assign inst_sram_req            = ~reset & ~br_stall & IF_allow_in & ~preIF_has_adef & ~preIF_refetch_tag & ~preIF_has_mem_except;
    assign inst_sram_addr           = pa;
    assign inst_sram_wr             = 0;
    assign inst_sram_wstrb          = 0;
    assign inst_sram_wdata          = 0;
    assign inst_sram_size           = 2'b10;            // 2 means 2^2 = 4 bytes.

    // Translation
    wire    en;
    assign  en                      = ~reset & ~br_stall & IF_allow_in & ~preIF_has_adef & ~preIF_refetch_tag;

    assign  s0_vppn                 = pc_next[31:13];
    assign  s0_va_bit12             = pc_next[12];
    assign  s0_asid                 = csr_asid[`CSR_ASID_ASID];

    
    MMU_convert preIF_va_convertor(
        .en(en),
        .ope_type(3'b100),
        .va(pc_next),
        .csr_crmd(csr_crmd),
        .csr_dmw0(csr_dmw0),
        .csr_dmw1(csr_dmw1),
        .s_found(s0_found),
        .s_index(s0_index),
        .s_ppn(s0_ppn),
        .s_ps(s0_ps),
        .s_plv(s0_plv),
        .s_mat(s0_mat),
        .s_d(s0_d),
        .s_v(s0_v),
        .has_mem_except(preIF_has_mem_except),
        .except(mem_except),
        .pa(pa),
        .mat(mat)
    );

//------------------------------------------------------IF------------------------------------------------------
    // IF_refetch_tag
    /***********************************************************
    2023.11.30 yzcc
        IF_refetch_tag:
            Mark whether the pc in IF stage requires refetch.

        1) update from preIF
        2) update from top signal 'refetch'
    ***********************************************************/
    wire    IF_refetch_tag;
    reg     IF_refetch_tag_r;
    always @(posedge clk) begin
        if (reset)
            IF_refetch_tag_r    <= 0;
        else
            if (preIF_ready_go && IF_allow_in)
                IF_refetch_tag_r    <= preIF_refetch_tag;
            else
                if (refetch)
                    IF_refetch_tag_r    <= 1;
    end
    assign  IF_refetch_tag  = IF_refetch_tag_r | refetch;
    
    /*****************************************************************
    2023.11.12 czxx
        About IF_ready_go:
        1. Have acquired the data (data_ok or IF_buf_valid).
        2. ADEF
    
    2023.11.30 yzcc
        About IF_ready_go:
        3. haven't shaked hands and tagged with 'refetch' tag

        About IF_allow_in:
        allow in if '~IFreg_valid & ~IF_refetch_tag'
        (because refetch will invalidate the pc in IF, but
        it's possible that the pc has shaked hands for addr.)
    *****************************************************************/
    assign IF_ready_go      = recv_inst_from_sram & inst_sram_data_ok
                            | recv_inst_from_buf & IF_buf_valid
                            | IF_has_adef
                            | IF_has_mem_except
                            | (unfinish_cnt == 0 && IF_refetch_tag);
    assign IF_allow_in      = ~IFreg_valid & ~IF_refetch_tag | ID_allow_in & IF_ready_go;
    assign IFreg_valid      = IF_valid & ~IF_cancel_tak;

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

    // Retaining cancel situation
    /*****************************************************************
    2023.11.10 yzcc
        IF_cancel may only last for 1 clk, so we need to use a reg to
    record it. (IF_cancel_r)

    2023.11.12 czxx
        When to reset?
        a new inst has entered this stage
    *****************************************************************/
    assign IF_cancel    = (ertn_flush & except_valid | WB_ex & except_valid | br_taken | refetch_flush);
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
            if ((inst_sram_req & inst_sram_addr_ok) & ~inst_sram_data_ok)
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
    assign IFreg_bus        = {ebus_end, inst, pc, IF_refetch_tag};

endmodule