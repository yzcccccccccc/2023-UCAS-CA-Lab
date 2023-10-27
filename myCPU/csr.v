/*****************************************************
            Control and State Reg File
    - version1.0
    - 2023.10.15, created by yzcc
******************************************************/
`include "macro.vh"
module csr(
    input   wire        clk,
    input   wire        reset,
    input   wire        csr_re,         // read enable
    input   wire [13:0] csr_num,        // addr
    output  wire [31:0] csr_rvalue,     // return value
    input   wire        csr_we,         // write enable
    input   wire [31:0] csr_wmask,      // mask
    input   wire [31:0] csr_wvalue,     // write value

    input   wire [`WB2CSR_LEN - 1:0]    CSR_in_bus,

    output  wire [31:0] ex_entry,       // entry vec ! (interrupt-handler addr)
    output  wire [31:0] ertn_entry,     // ertn entry ! (restore from interruption, epc)
    output  wire        has_int         // interrupt trigger ! (to ID)
);

// CSR bus decode
    wire        ertn_flush;     // ertn signal from WB
    wire        wb_ex;          // interrupt trigger from WB
    wire [5:0]  wb_ecode;
    wire [8:0]  wb_esubcode;
    wire [31:0] wb_pc;
    assign {ertn_flush, wb_ex, wb_ecode, wb_esubcode, wb_pc}    = CSR_in_bus;

// CSR regs
    // CRMD reg
        reg [1:0]       crmd_plv, crmd_datf, crmd_datm;
        reg             crmd_ie, crmd_da, crmd_pg;

    // PRMD reg
        reg [1:0]       prmd_pplv;
        reg             prmd_pie;

    // EUEN reg
        reg             euen_fpe;

    // ECFG reg
        reg [12:0]      ecfg_lie;

    // ESTAT reg
        reg [12:0]      estat_is;
        reg [5:0]       estat_ecode;
        reg [8:0]       estat_esubcode; 

    // ERA reg
        reg [31:0]      era;

    // EENTRY reg
        reg [25:0]      eentry_va;

    // SAVE0~3
        reg [31:0]      save0, save1, save2, save3;

// CRMD
    // plv & ie
    always @(posedge clk) begin
        if (reset) begin
            crmd_plv    <= 0;
            crmd_ie     <= 0; 
        end
        else begin
            if (wb_ex) begin
                crmd_plv    <= 0;
                crmd_ie     <= 0;
            end
            else
                if (ertn_flush) begin
                    crmd_plv    <= prmd_pplv;
                    crmd_ie     <= prmd_pie;
                end
                else
                    if (csr_we && csr_num == `CSR_CRMD) begin
                        crmd_plv    <= csr_wmask[`CSR_CRMD_PLV] & csr_wvalue[`CSR_CRMD_PLV]
                                    | ~csr_wmask[`CSR_CRMD_PLV] & crmd_plv;
                        crmd_ie     <= csr_wmask[`CSR_CRMD_IE] & csr_wvalue[`CSR_CRMD_IE]
                                    | ~csr_wmask[`CSR_CRMD_IE] & crmd_ie;
                    end
        end
    end

    // DA, PG, DATF and DATM (to be modified in Chapter 10)
    always @(posedge clk) begin
        if (reset) begin
            crmd_da     <= 1;
            crmd_pg     <= 0;
            crmd_datf   <= 0;
            crmd_datm   <= 0;
        end
    end


// PRMD
    always @(posedge clk) begin
        if (wb_ex) begin
            prmd_pplv   <= crmd_plv;
            prmd_pie    <= crmd_ie;
        end
        else
            if (csr_we && csr_num == `CSR_PRMD) begin
                prmd_pplv   <= csr_wmask[`CSR_PRMD_PPLV] & csr_wvalue[`CSR_PRMD_PPLV]
                            | ~csr_wmask[`CSR_PRMD_PPLV] & prmd_pplv;
                prmd_pie    <= csr_wmask[`CSR_PRMD_PIE] & csr_wvalue[`CSR_PRMD_PIE]
                            | ~csr_wmask[`CSR_PRMD_PIE] & prmd_pie;
            end
    end

// ECFG
    always @(posedge clk) begin
        if (reset) begin
            ecfg_lie    <= 0;
        end
        else
            if (csr_we && csr_num == `CSR_ECFG)
                ecfg_lie    <= csr_wmask[`CSR_ECFG_LIE] & csr_wvalue[`CSR_ECFG_LIE]
                            | ~csr_wmask[`CSR_ECFG_LIE] & ecfg_lie;
    end

// ESTAT
    // IS
    always @(posedge clk) begin
        // IS1_0, soft interrupt
        if (reset) begin
            estat_is[1:0]   <= 0;
        end
        else
            if (csr_we && csr_num == `CSR_ESTAT)
                estat_is[1:0]   <= csr_wmask[`CSR_ESTAT_IS10] & csr_wvalue[`CSR_ESTAT_IS10]
                                | ~csr_wmask[`CSR_ESTAT_IS10] & estat_is[1:0];
        // IS12_2, hardware inerrupt (to be fixed in exp13)
        estat_is[12:2]      <= 0;
    end

    // Ecode & Esubcode
    always @(posedge clk) begin
        if (wb_ex) begin
            estat_ecode     <= wb_ecode;
            estat_esubcode  <= wb_esubcode;
        end
    end

// ERA
    always @(posedge clk) begin
        if (wb_ex)
            era     <= wb_pc;
        else
            if (csr_we && csr_num == `CSR_ERA)
                era     <= csr_wmask[`CSR_ERA_PC] & csr_wvalue[`CSR_ERA_PC]
                        | ~csr_wmask[`CSR_ERA_PC] & era;
    end

// EENTRY
    always @(posedge clk) begin
        if (csr_we && csr_num == `CSR_EENTRY)
            eentry_va   <= csr_wmask[`CSR_EENTRY_VA] & csr_wvalue[`CSR_EENTRY_VA]
                        | ~csr_wmask[`CSR_EENTRY_VA] & eentry_va;

    end

// SAVE0~SAVE3
    always @(posedge clk) begin
        if (csr_we && csr_num == `CSR_SAVE0)
            save0   <= csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                    | ~csr_wmask[`CSR_SAVE_DATA] & save0;
        if (csr_we && csr_num == `CSR_SAVE1)
            save1   <= csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                    | ~csr_wmask[`CSR_SAVE_DATA] & save1;
        if (csr_we && csr_num == `CSR_SAVE2)
            save2   <= csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                    | ~csr_wmask[`CSR_SAVE_DATA] & save2;
        if (csr_we && csr_num == `CSR_SAVE3)
            save3   <= csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                    | ~csr_wmask[`CSR_SAVE_DATA] & save3;
    end

//  CSR Read Res
    wire    [31:0]      crmd_rvalue, prmd_rvalue, ecfg_rvalue, estat_rvalue, era_rvalue, eentry_rvalue;
    wire    [31:0]      save0_rvalue, save1_rvalue, save2_rvalue, save3_rvalue;

    assign crmd_rvalue      = {24'b0, crmd_datm, crmd_datf, crmd_pg, crmd_da, crmd_plv};
    assign prmd_rvalue      = {29'b0, prmd_pie, prmd_pplv};
    assign ecfg_rvalue      = {19'b0, ecfg_lie};
    assign estat_rvalue     = {1'b0, estat_esubcode, estat_ecode, 3'b0, estat_is};
    assign era_rvalue       = era;
    assign eentry_rvalue    = {eentry_va, 6'b0};
    assign save0_rvalue     = save0;
    assign save1_rvalue     = save1;
    assign save2_rvalue     = save2;
    assign save3_rvalue     = save3;

    assign csr_rvalue       = {32{csr_num == `CSR_CRMD}} & crmd_rvalue
                            | {32{csr_num == `CSR_PRMD}} & prmd_rvalue
                            | {32{csr_num == `CSR_ECFG}} & ecfg_rvalue
                            | {32{csr_num == `CSR_ESTAT}} & estat_rvalue
                            | {32{csr_num == `CSR_ERA}} & era_rvalue
                            | {32{csr_num == `CSR_EENTRY}} & eentry_rvalue
                            | {32{csr_num == `CSR_SAVE0}} & save0_rvalue
                            | {32{csr_num == `CSR_SAVE1}} & save1_rvalue
                            | {32{csr_num == `CSR_SAVE2}} & save2_rvalue
                            | {32{csr_num == `CSR_SAVE3}} & save3_rvalue;

// Output signals
    assign has_int      = crmd_ie & (|(ecfg_lie & estat_is));
    assign ertn_entry   = era_rvalue;
    assign ex_entry     = eentry_rvalue;

/************************************************************************
    Hint:
        About has_int: 
************************************************************************/

endmodule