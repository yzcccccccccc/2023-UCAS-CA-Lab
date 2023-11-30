`include "../macro.vh"
`timescale 1ns / 1ps
module csr(
    input   wire        clk,
    input   wire        reset,

    // inst interface
    input   wire [79:0] csr_ctrl,
    output  wire [31:0] csr_rvalue,

    // Request inst valid
    input   wire        valid,

    // circuit interface
    input   wire [`WB2CSR_LEN-1:0]  CSR_in_bus,
    output  wire [31:0]             ex_entry,
    output  wire [31:0]             era_pc,
    output  wire                    has_int,
    output  wire [31:0]             csr_crmd,
    output  wire [31:0]             csr_asid,
    output  wire [31:0]             csr_tlbehi,

    // TLB ports
    input   wire            r_e,
    input   wire [3:0]      r_index,
    input   wire [18:0]     r_vppn,
    input   wire [5:0]      r_ps,
    input   wire [9:0]      r_asid,
    input   wire            r_g,
    input   wire [19:0]     r_ppn0,
    input   wire [1:0]      r_plv0,
    input   wire [1:0]      r_mat0,
    input   wire            r_d0,
    input   wire            r_v0,
    input   wire [19:0]     r_ppn1,
    input   wire [1:0]      r_plv1,
    input   wire [1:0]      r_mat1,
    input   wire            r_d1,
    input   wire            r_v1,

    output  wire            we,
    output  wire [3:0]      w_index,
    output  wire            w_e,
    output  wire [18:0]     w_vppn,
    output  wire [5:0]      w_ps,
    output  wire [9:0]      w_asid,
    output  wire            w_g,
    output  wire [19:0]     w_ppn0,
    output  wire [1:0]      w_plv0,
    output  wire [1:0]      w_mat0,
    output  wire            w_d0,
    output  wire            w_v0,
    output  wire [19:0]     w_ppn1,
    output  wire [1:0]      w_plv1,
    output  wire [1:0]      w_mat1,
    output  wire            w_d1,
    output  wire            w_v1
);

// exp13 (maybe need to be ports?)
    wire [7:0]      hw_int_in;
    wire            ipi_int_in;

// Decode
wire        ertn_flush;
wire        wb_ex;
wire [5:0]  wb_ecode;
wire [8:0]  wb_esubcode;
wire [31:0] wb_pc;
wire [31:0] wb_vaddr;
wire        tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, tlbsrch_hit;
wire [3:0]  tlbsrch_index;
assign {tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, tlbsrch_hit, tlbsrch_index, ertn_flush, wb_ex, wb_ecode, wb_esubcode, wb_pc, wb_vaddr} = CSR_in_bus;

wire        csr_re_tmp, csr_we_tmp, csr_re, csr_we;
wire [13:0] csr_num;
wire [31:0] csr_wvalue, csr_wmask;
assign {csr_num,csr_re_tmp,csr_we_tmp,csr_wvalue,csr_wmask} = csr_ctrl;
assign csr_re   = csr_re_tmp & valid;
assign csr_we   = csr_we_tmp & valid;

// CSR regs
// CRMD reg
reg [1:0]       csr_crmd_plv;
wire [1:0]      csr_crmd_datf, csr_crmd_datm;
reg             csr_crmd_ie;
wire            csr_crmd_da, csr_crmd_pg;

// PRMD reg
reg [1:0]       csr_prmd_pplv;
reg             csr_prmd_pie;

// EUEN reg
reg             csr_euen_fpe;

// ECFG reg
reg [12:0]      csr_ecfg_lie;

// ESTAT reg
reg [12:0]      csr_estat_is;
reg [5:0]       csr_estat_ecode;
reg [8:0]       csr_estat_esubcode;

// ERA reg
reg [31:0]      csr_era_pc;

// EENTRY reg
reg [25:0]      csr_eentry_va;

// SAVE0~3
reg [31:0]      csr_save0, csr_save1, csr_save2, csr_save3;

// TID reg
reg [31:0]      csr_tid_tid;

// BADV reg
reg [31:0]      csr_badv_vaddr;

// TCFG regs
reg             csr_tcfg_en;
reg             csr_tcfg_periodic;
reg [29:0]      csr_tcfg_initval;

// TLBIDX
reg [3:0]       csr_tlbidx_index;
reg [5:0]       csr_tlbidx_ps;
reg             csr_tlbidx_ne;

// TLBEHI
reg [18:0]      csr_tlbehi_vppn;

// TLBELO0 & TLBELO1
reg             csr_tlbelo0_v, csr_tlbelo1_v;
reg             csr_tlbelo0_d, csr_tlbelo1_d;
reg [1:0]       csr_tlbelo0_plv, csr_tlbelo1_plv;
reg [1:0]       csr_tlbelo0_mat, csr_tlbelo1_mat;
reg             csr_tlbelo0_g, csr_tlbelo1_g;
reg [23:0]      csr_tlbelo0_ppn, csr_tlbelo1_ppn;

// ASID
reg [9:0]       csr_asid_asid;
reg [7:0]       csr_asid_asidbits;

// TLBRENTRY
reg [25:0]      csr_tlbrentry_pa;

// Count Down
reg [31:0]      timer_cnt;

// has_int
assign has_int = ((csr_estat_is[12:0] & csr_ecfg_lie[12:0]) != 13'b0)
                && (csr_crmd_ie == 1'b1);

// ex_entry
assign ex_entry = {csr_eentry_va,6'b0};

// era_pc
assign era_pc = csr_era_pc;

// crmd_plv
    always @(posedge clk)
    begin
        if (reset)
            csr_crmd_plv <= 2'b0;
        else if (wb_ex)
            csr_crmd_plv <= 2'b0;
        else if (ertn_flush)
            csr_crmd_plv <= csr_prmd_pplv;
        else if (csr_we && csr_num==`CSR_CRMD)
            csr_crmd_plv <= csr_wmask[`CSR_CRMD_PLV]&csr_wvalue[`CSR_CRMD_PLV]
                        | ~csr_wmask[`CSR_CRMD_PLV]&csr_crmd_plv;
    end

// crmd_ie
    always @(posedge clk)
    begin
        if (reset)
            csr_crmd_ie <= 1'b0;
        else if (wb_ex)
            csr_crmd_ie <= 1'b0;
        else if (ertn_flush)
            csr_crmd_ie <= csr_prmd_pie;
        else if (csr_we && csr_num==`CSR_CRMD)
            csr_crmd_ie <= csr_wmask[`CSR_CRMD_IE]&csr_wvalue[`CSR_CRMD_IE]
                        | ~csr_wmask[`CSR_CRMD_IE]&csr_crmd_ie;
    end

assign csr_crmd_da = 1'b1;
assign csr_crmd_pg = 1'b0;
assign csr_crmd_datf = 2'b00;
assign csr_crmd_datm = 2'b00;

// prmd_pplv & prmd_pie
    always @(posedge clk)
    begin
        if (wb_ex)
        begin
            csr_prmd_pplv <= csr_crmd_plv;
            csr_prmd_pie <= csr_crmd_ie;
        end
        else if (csr_we && csr_num==`CSR_PRMD)
        begin
            csr_prmd_pplv <= csr_wmask[`CSR_PRMD_PPLV]&csr_wvalue[`CSR_PRMD_PPLV]
                        | ~csr_wmask[`CSR_PRMD_PPLV]&csr_prmd_pplv;
            csr_prmd_pie <= csr_wmask[`CSR_PRMD_PIE]&csr_wvalue[`CSR_PRMD_PIE]
                        | ~csr_wmask[`CSR_PRMD_PIE]&csr_prmd_pie;
        end
    end

// ecfg_lie
    always @(posedge clk)
    begin
        if (reset)
            csr_ecfg_lie <= 13'b0;
        else if (csr_we && csr_num==`CSR_ECFG)
            csr_ecfg_lie <= csr_wmask[`CSR_ECFG_LIE]&13'h1bff&csr_wvalue[`CSR_ECFG_LIE]
                        | ~csr_wmask[`CSR_ECFG_LIE]&13'h1bff&csr_ecfg_lie;
    end

// estat_is
    assign hw_int_in    = 0;
    assign ipi_int_in   = 0;
    always @(posedge clk)
    begin
        if (reset)
            csr_estat_is[1:0] <= 2'b0;
        else if (csr_we && csr_num==`CSR_ESTAT)
            csr_estat_is[1:0] <= csr_wmask[`CSR_ESTAT_IS10]&csr_wvalue[`CSR_ESTAT_IS10]
                        | ~csr_wmask[`CSR_ESTAT_IS10]&csr_estat_is[1:0];
        
        //csr_estat_is[12:2] <= 11'b0; // temporarily zero in exp 12

        csr_estat_is[9:2] <= hw_int_in[7:0];

        csr_estat_is[10] <= 1'b0;

        if (timer_cnt[31:0]==32'b0)
            csr_estat_is[11] <= 1'b1;
        else 
            if (csr_we && csr_num==`CSR_TICLR && csr_wmask[`CSR_TICLR_CLR]
                && csr_wvalue[`CSR_TICLR_CLR])
            csr_estat_is[11] <= 1'b0;

        csr_estat_is[12] <= ipi_int_in;
    end

// estat_ecode & estat_esubcode
    always @(posedge clk)
    begin
        if (wb_ex)
        begin
            csr_estat_ecode <= wb_ecode;
            csr_estat_esubcode <= wb_esubcode;
        end
    end

// era_pc
    always @(posedge clk)
    begin
        if (wb_ex)
            csr_era_pc <= wb_pc;
        else if (csr_we && csr_num==`CSR_ERA)
            csr_era_pc <= csr_wmask[`CSR_ERA_PC] & csr_wvalue[`CSR_ERA_PC] |
                          ~csr_wmask[`CSR_ERA_PC] & csr_era_pc;
    end


// badv_vaddr
    wire wb_ex_addr_err;
    assign wb_ex_addr_err = wb_ecode==`ECODE_ADE || wb_ecode==`ECODE_ALE;
    always @(posedge clk)
    begin
        if (wb_ex && wb_ex_addr_err)
            csr_badv_vaddr <= (wb_ecode==`ECODE_ADE &&
                            wb_esubcode==`ESUBCODE_ADEF) ? wb_pc : wb_vaddr;
    end

// eentry_va
    always @(posedge clk)
    begin
        if (csr_we && csr_num==`CSR_EENTRY)
            csr_eentry_va <= csr_wmask[`CSR_EENTRY_VA]&csr_wvalue[`CSR_EENTRY_VA]
                        | ~csr_wmask[`CSR_EENTRY_VA]&csr_eentry_va;
    end

// save0~4
    always @(posedge clk)
    begin
        if (csr_we && csr_num==`CSR_SAVE0)
            csr_save0 <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                    | ~csr_wmask[`CSR_SAVE_DATA]&csr_save0;
        if (csr_we && csr_num==`CSR_SAVE1)
            csr_save1 <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                    | ~csr_wmask[`CSR_SAVE_DATA]&csr_save1;
        if (csr_we && csr_num==`CSR_SAVE2)
            csr_save2 <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                    | ~csr_wmask[`CSR_SAVE_DATA]&csr_save2;
        if (csr_we && csr_num==`CSR_SAVE3)
            csr_save3 <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                    | ~csr_wmask[`CSR_SAVE_DATA]&csr_save3;
    end

// timer
    always @(posedge clk)
    begin
        if (reset)
            csr_tid_tid <= 32'b0;
        else if (csr_we && csr_num==`CSR_TID)
            csr_tid_tid <= csr_wmask[`CSR_TID_TID]&csr_wvalue[`CSR_TID_TID]
                        | ~csr_wmask[`CSR_TID_TID]&csr_tid_tid;
    end

    wire [31:0] tcfg_next_value;
    wire [31:0] csr_tval;
    wire        csr_ticlr_clr;

// tcfg
    always @(posedge clk)
    begin
        if (reset)
            csr_tcfg_en <= 1'b0;
        else if (csr_we && csr_num==`CSR_TCFG)
                csr_tcfg_en <= csr_wmask[`CSR_TCFG_EN]&csr_wvalue[`CSR_TCFG_EN]
                            | ~csr_wmask[`CSR_TCFG_EN]&csr_tcfg_en;

        if (csr_we && csr_num==`CSR_TCFG)
        begin
            csr_tcfg_periodic <= csr_wmask[`CSR_TCFG_PERIOD]&csr_wvalue[`CSR_TCFG_PERIOD]
                            | ~csr_wmask[`CSR_TCFG_PERIOD]&csr_tcfg_periodic;
            csr_tcfg_initval <= csr_wmask[`CSR_TCFG_INITV]&csr_wvalue[`CSR_TCFG_INITV]
                            | ~csr_wmask[`CSR_TCFG_INITV]&csr_tcfg_initval;
        end
    end

    assign tcfg_next_value = csr_wmask[31:0]&csr_wvalue[31:0]
                            | ~csr_wmask[31:0]&{csr_tcfg_initval,csr_tcfg_periodic, csr_tcfg_en};


// Count down reg
    always @(posedge clk)
    begin
        if (reset)
            timer_cnt <= 32'hffffffff;
        else if (csr_we && csr_num==`CSR_TCFG && tcfg_next_value[`CSR_TCFG_EN])
            timer_cnt <= {tcfg_next_value[`CSR_TCFG_INITV], 2'b0};
        else if (csr_tcfg_en && timer_cnt!=32'hffffffff)
        begin
            if (timer_cnt[31:0]==32'b0 && csr_tcfg_periodic)
                timer_cnt <= {csr_tcfg_initval, 2'b0};
            else
                timer_cnt <= timer_cnt - 1'b1;
        end
    end

    assign csr_tval = timer_cnt[31:0];

    assign csr_ticlr_clr = 1'b0;

// TLBIDX
    always @(posedge clk) begin
        if (reset) begin
            csr_tlbidx_index    <= 0;
            csr_tlbidx_ps       <= 0;
            csr_tlbidx_ne       <= 1;
        end
        else begin
            if (csr_we && csr_num == `CSR_TLBIDX) begin
                csr_tlbidx_index    <= csr_wmask[`CSR_TLBIDX_INDEX] & csr_wvalue[`CSR_TLBIDX_INDEX]
                                    | ~csr_wmask[`CSR_TLBIDX_INDEX] & csr_tlbidx_index;
                csr_tlbidx_ps       <= csr_wmask[`CSR_TLBIDX_PS] & csr_wvalue[`CSR_TLBIDX_PS]
                                    | ~csr_wmask[`CSR_TLBIDX_PS] & csr_tlbidx_ps;
                csr_tlbidx_ne       <= csr_wmask[`CSR_TLBIDX_NE] & csr_wvalue[`CSR_TLBIDX_NE]
                                    | ~csr_wmask[`CSR_TLBIDX_NE] & csr_tlbidx_ne;
            end
            else begin
                if (tlbsrch_req) begin
                    csr_tlbidx_ne       <= ~tlbsrch_hit;
                    csr_tlbidx_index    <= tlbsrch_hit ? tlbsrch_index : csr_tlbidx_index;
                end
                else begin
                    if (tlbrd_req) begin
                        csr_tlbidx_ne       <= ~r_e;
                        csr_tlbidx_index    <= r_e ? r_index : csr_tlbidx_index;
                        csr_tlbidx_ps       <= r_e ? r_ps : 0;
                    end
                end
            end
        end
    end

// TLBEHI
    wire page_excep;
    assign page_excep   = (wb_ecode == `ECODE_PIL) || (wb_ecode == `ECODE_PIS) || (wb_ecode == `ECODE_PIF) || (wb_ecode == `ECODE_PPI)
                        || (wb_ecode == `ECODE_PME) || (wb_ecode == `ECODE_TLBR);
    
    always @(posedge clk) begin
        if (reset)
            csr_tlbehi_vppn <= 0;
        else begin
            if (csr_we && csr_num == `CSR_TLBEHI)
                csr_tlbehi_vppn <= csr_wmask[`CSR_TLBEHI_VPPN] & csr_wvalue[`CSR_TLBEHI_VPPN]
                                | ~csr_wmask[`CSR_TLBEHI_VPPN] & csr_tlbehi_vppn;
            else
                if (wb_ex && page_excep)
                    csr_tlbehi_vppn     <= wb_vaddr[31:13];
                else
                    if (tlbrd_req)
                        csr_tlbehi_vppn <= r_e ? r_vppn : 0;
        end
    end

// TLBELO0&1
    always @(posedge clk) begin
        if (reset) begin
            csr_tlbelo0_d   <= 0;
            csr_tlbelo0_g   <= 0;
            csr_tlbelo0_v   <= 0;
            csr_tlbelo0_mat <= 0;
            csr_tlbelo0_plv <= 0;
            csr_tlbelo0_ppn <= 0;
        end
        else begin
            if (csr_we && csr_num == `CSR_TLBELO0) begin
                csr_tlbelo0_d   <= csr_wmask[`CSR_TLBELO_D] & csr_wvalue[`CSR_TLBELO_D]
                                | ~csr_wmask[`CSR_TLBELO_D] & csr_tlbelo0_d;
                csr_tlbelo0_g   <= csr_wmask[`CSR_TLBELO_G] & csr_wvalue[`CSR_TLBELO_G]
                                | ~csr_wmask[`CSR_TLBELO_G] & csr_tlbelo0_g;
                csr_tlbelo0_v   <= csr_wmask[`CSR_TLBELO_V] & csr_wvalue[`CSR_TLBELO_V]
                                | ~csr_wmask[`CSR_TLBELO_V] & csr_tlbelo0_v;
                csr_tlbelo0_mat <= csr_wmask[`CSR_TLBELO_MAT] & csr_wvalue[`CSR_TLBELO_MAT]
                                | ~csr_wmask[`CSR_TLBELO_MAT] & csr_tlbelo0_mat;
                csr_tlbelo0_plv <= csr_wmask[`CSR_TLBELO_PLV] & csr_wvalue[`CSR_TLBELO_PLV]
                                | ~csr_wmask[`CSR_TLBELO_PLV] & csr_tlbelo0_plv;
                csr_tlbelo0_ppn <= csr_wmask[`CSR_TLBELO_PPN] & csr_wvalue[`CSR_TLBELO_PPN]
                                | ~csr_wmask[`CSR_TLBELO_PPN] & csr_tlbelo0_ppn;
            end
            else begin
                if (tlbrd_req) begin
                    csr_tlbelo0_d   <= r_e ? r_d0 : 0;
                    csr_tlbelo0_g   <= r_e ? r_g : 0;
                    csr_tlbelo0_v   <= r_e ? r_v0 : 0;
                    csr_tlbelo0_mat <= r_e ? r_mat0 : 0;
                    csr_tlbelo0_plv <= r_e ? r_plv0 : 0;
                    csr_tlbelo0_ppn <= r_e ? r_ppn0 : 0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            csr_tlbelo1_d   <= 0;
            csr_tlbelo1_g   <= 0;
            csr_tlbelo1_v   <= 0;
            csr_tlbelo1_mat <= 0;
            csr_tlbelo1_plv <= 0;
            csr_tlbelo1_ppn <= 0;
        end
        else begin
            if (csr_we && csr_num == `CSR_TLBELO1) begin
                csr_tlbelo1_d   <= csr_wmask[`CSR_TLBELO_D] & csr_wvalue[`CSR_TLBELO_D]
                                | ~csr_wmask[`CSR_TLBELO_D] & csr_tlbelo1_d;
                csr_tlbelo1_g   <= csr_wmask[`CSR_TLBELO_G] & csr_wvalue[`CSR_TLBELO_G]
                                | ~csr_wmask[`CSR_TLBELO_G] & csr_tlbelo1_g;
                csr_tlbelo1_v   <= csr_wmask[`CSR_TLBELO_V] & csr_wvalue[`CSR_TLBELO_V]
                                | ~csr_wmask[`CSR_TLBELO_V] & csr_tlbelo1_v;
                csr_tlbelo1_mat <= csr_wmask[`CSR_TLBELO_MAT] & csr_wvalue[`CSR_TLBELO_MAT]
                                | ~csr_wmask[`CSR_TLBELO_MAT] & csr_tlbelo1_mat;
                csr_tlbelo1_plv <= csr_wmask[`CSR_TLBELO_PLV] & csr_wvalue[`CSR_TLBELO_PLV]
                                | ~csr_wmask[`CSR_TLBELO_PLV] & csr_tlbelo1_plv;
                csr_tlbelo1_ppn <= csr_wmask[`CSR_TLBELO_PPN] & csr_wvalue[`CSR_TLBELO_PPN]
                                | ~csr_wmask[`CSR_TLBELO_PPN] & csr_tlbelo1_ppn;
            end
            else begin
                if (tlbrd_req) begin
                    csr_tlbelo1_d   <= r_e ? r_d1 : 0;
                    csr_tlbelo1_g   <= r_e ? r_g : 0;
                    csr_tlbelo1_v   <= r_e ? r_v1 : 0;
                    csr_tlbelo1_mat <= r_e ? r_mat1 : 0;
                    csr_tlbelo1_plv <= r_e ? r_plv1 : 0;
                    csr_tlbelo1_ppn <= r_e ? r_ppn1 : 0;
                end
            end
        end
    end

// ASID
    always @(posedge clk) begin
        if (reset) begin
            csr_asid_asid       <= 0;
            csr_asid_asidbits   <= 8'd10;
        end
        else begin
            if (csr_we && csr_num == `CSR_ASID)
                csr_asid_asid   <= csr_wmask[`CSR_ASID_ASID] & csr_wvalue[`CSR_ASID_ASID]
                                | ~csr_wmask[`CSR_ASID_ASID] & csr_asid_asid;
            else
                if (tlbrd_req)
                    csr_asid_asid   <= r_e ? r_asid : 0;
        end
    end

// TLBRENTRY
    always @(posedge clk) begin
        if (reset)
            csr_tlbrentry_pa    <= 0;
        else begin
            if (csr_we && csr_num == `CSR_TLBRENTRY)
                csr_tlbrentry_pa    <= csr_wmask[`CSR_TLBRENTRY_PA] & csr_wvalue[`CSR_TLBRENTRY_PA]
                                    | ~csr_wmask[`CSR_TLBRENTRY_PA] & csr_tlbrentry_pa;
        end
    end

// TLB ports
    // TLB Read (TLB search will be handled in EX stage)
    assign  r_index     = csr_tlbidx_index;

    // TLB Write
    assign  we          = tlbfill_req | tlbwr_req;
    assign  w_index     = csr_tlbidx_index;
    assign  w_e         = ~csr_tlbidx_ne || (csr_estat_ecode == 6'h3f);
    assign  w_vppn      = csr_tlbehi_vppn;
    assign  w_ps        = csr_tlbidx_ps;
    assign  w_asid      = csr_asid_asid;
    assign  w_g         = csr_tlbelo0_g & csr_tlbelo1_g;
    assign  w_ppn0      = csr_tlbelo0_ppn;
    assign  w_plv0      = csr_tlbelo0_plv;
    assign  w_mat0      = csr_tlbelo0_mat;
    assign  w_d0        = csr_tlbelo0_d;
    assign  w_v0        = csr_tlbelo0_v;
    assign  w_ppn1      = csr_tlbelo1_ppn;
    assign  w_plv1      = csr_tlbelo1_plv;
    assign  w_mat1      = csr_tlbelo1_mat;
    assign  w_d1        = csr_tlbelo1_d;
    assign  w_v1        = csr_tlbelo1_v;

// return value
wire [31:0] csr_crmd_rvalue = {23'b0, csr_crmd_datm, csr_crmd_datf, csr_crmd_pg, csr_crmd_da, csr_crmd_ie, csr_crmd_plv};
wire [31:0] csr_prmd_rvalue = {29'b0, csr_prmd_pie, csr_prmd_pplv};
wire [31:0] csr_estat_rvalue = {1'b0,csr_estat_esubcode,csr_estat_ecode,3'b0,csr_estat_is};
wire [31:0] csr_era_rvalue = {csr_era_pc};
wire [31:0] csr_eentry_rvalue = {csr_eentry_va,6'b0};
wire [31:0] csr_save0_rvalue = {csr_save0};
wire [31:0] csr_save1_rvalue = {csr_save1};
wire [31:0] csr_save2_rvalue = {csr_save2};
wire [31:0] csr_save3_rvalue = {csr_save3};

wire [31:0] csr_ecfg_rvalue     = {18'b0, csr_ecfg_lie};
wire [31:0] csr_badv_rvalue     = {csr_badv_vaddr};
wire [31:0] csr_tid_rvalue      = {csr_tid_tid};
wire [31:0] csr_tcfg_rvalue     = {csr_tcfg_initval, csr_tcfg_periodic, csr_tcfg_en};
wire [31:0] csr_tval_rvalue     = {csr_tval};
wire [31:0] csr_ticlr_rvalue    = {31'b0, csr_ticlr_clr};

wire [31:0] csr_tlbidx_rvalue       = {csr_tlbidx_ne, 1'b0, csr_tlbidx_ps, 8'b0, 12'b0, csr_tlbidx_index};
wire [31:0] csr_tlbehi_rvalue       = {csr_tlbehi_vppn, 13'b0};
wire [31:0] csr_tlbelo0_rvalue      = {csr_tlbelo0_ppn, 1'b0, csr_tlbelo0_g, csr_tlbelo0_mat, csr_tlbelo0_plv, csr_tlbelo0_d, csr_tlbelo0_v};
wire [31:0] csr_tlbelo1_rvalue      = {csr_tlbelo1_ppn, 1'b0, csr_tlbelo1_g, csr_tlbelo1_mat, csr_tlbelo1_plv, csr_tlbelo1_d, csr_tlbelo1_v};
wire [31:0] csr_asid_rvalue         = {8'b0, csr_asid_asidbits, 6'b0, csr_asid_asid};
wire [31:0] csr_tlbrentry_rvalue    = {csr_tlbrentry_pa, 6'b0};

assign csr_rvalue = {32{csr_num==`CSR_CRMD}} & csr_crmd_rvalue
       | {32{csr_num==`CSR_PRMD}} & csr_prmd_rvalue
       | {32{csr_num==`CSR_ESTAT}} & csr_estat_rvalue
       | {32{csr_num == `CSR_ERA}} & csr_era_rvalue
       | {32{csr_num == `CSR_EENTRY}} & csr_eentry_rvalue
       | {32{csr_num == `CSR_SAVE0}} & csr_save0_rvalue
       | {32{csr_num == `CSR_SAVE1}} & csr_save1_rvalue
       | {32{csr_num == `CSR_SAVE2}} & csr_save2_rvalue
       | {32{csr_num == `CSR_SAVE3}} & csr_save3_rvalue
       | {32{csr_num == `CSR_ECFG}} & csr_ecfg_rvalue
       | {32{csr_num == `CSR_BADV}} & csr_badv_rvalue
       | {32{csr_num == `CSR_TID}} & csr_tid_rvalue
       | {32{csr_num == `CSR_TCFG}} & csr_tcfg_rvalue
       | {32{csr_num == `CSR_TVAL}} & csr_tval_rvalue
       | {32{csr_num == `CSR_TICLR}} & csr_ticlr_rvalue
       | {32{csr_num == `CSR_TLBIDX}} & csr_tlbidx_rvalue
       | {32{csr_num == `CSR_TLBEHI}} & csr_tlbehi_rvalue
       | {32{csr_num == `CSR_TLBELO0}} & csr_tlbelo0_rvalue
       | {32{csr_num == `CSR_TLBELO1}} & csr_tlbelo1_rvalue
       | {32{csr_num == `CSR_ASID}} & csr_asid_rvalue
       | {32{csr_num == `CSR_TLBRENTRY}} & csr_tlbrentry_rvalue;

// TLB CSR values
assign csr_asid     = csr_asid_rvalue;
assign csr_crmd     = csr_crmd_rvalue;
assign csr_tlbehi   = csr_tlbehi_rvalue;

endmodule
