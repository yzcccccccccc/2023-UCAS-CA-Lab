`include "macro.vh"
module mycpu_top(
    input   wire        aclk,
    input   wire        aresetn,

    //AXI signals
    // read-acquire
    output wire [3:0]  arid,            //fs=0,ld=1
    output wire [31:0] araddr,
    output wire [7:0]  arlen,           //always=0
    output wire [2:0]  arsize,
    output wire [1:0]  arburst,         //always=2'b01
    output wire [1:0]  arlock,          //always=0
    output wire [3:0]  arcache,         //always=0
    output wire [2:0]  arprot,          //always=0
    output wire        arvalid,
    input  wire        arready,

    // read-responce
    input  wire [3:0]  rid,
    input  wire [31:0] rdata,
    input  wire [1:0]  rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,

    // write-acquire
    output wire [3:0]  awid,            //always=1
    output wire [31:0] awaddr,
    output wire [7:0]  awlen,           //always=0
    output wire [2:0]  awsize,
    output wire [1:0]  awburst,         //always=2'b01
    output wire [1:0]  awlock,          //always=0
    output wire [3:0]  awcache,         //always=0
    output wire [2:0]  awprot,          //always=0
    output wire        awvalid,
    input  wire        awready,

    // write-data
    output wire [3:0]  wid,             //always=1
    output wire [31:0] wdata,
    output wire [3:0]  wstrb,
    output wire        wlast,           //always=1
    output wire        wvalid,
    input  wire        wready,

    // write-responce
    input  wire [3:0]  bid,
    input  wire [1:0]  bresp,
    input  wire        bvalid,
    output wire        bready,

    // trace debug interface
    output  wire [31:0] debug_wb_pc,
    output  wire [3:0]  debug_wb_rf_we,
    output  wire [4:0]  debug_wb_rf_wnum,
    output  wire [31:0] debug_wb_rf_wdata
);

// reset signal
reg     reset;
always @(posedge aclk)
begin
    reset <= ~aresetn;
end

// timer (for rdcnt)
    reg [63:0]      timecnt;
    wire [31:0]     counter_value;
    wire [1:0]      rdcntv_op;
    always @(posedge aclk) begin
        if (reset)
            timecnt <= 0;
        else
            timecnt <= timecnt + 1'b1;
    end
    assign counter_value = {32{rdcntv_op[0]}} & timecnt[31:0] |
                           {32{rdcntv_op[1]}} & timecnt[63:32];

// Bus & piepeline control signals
// bus
wire    [`BR_BUS_LEN - 1:0]         BR_BUS;

wire                                toIFreg_valid_bus;
wire    [`IFReg_BUS_LEN - 1:0]      IFreg_bus;

wire                                toIDreg_valid_bus;
wire    [`IDReg_BUS_LEN - 1:0]      IDreg_bus;

wire                                toEXreg_valid_bus;
wire    [`EXReg_BUS_LEN - 1:0]      EXreg_bus;

wire                                toMEMreg_valid_bus;
wire    [`MEMReg_BUS_LEN - 1:0]     MEMreg_bus;

wire    [`EX_BYPASS_LEN - 1:0]      EX_bypass_bus;
wire    [`MEM_BYPASS_LEN - 1:0]     MEM_bypass_bus;
wire    [`WB_BYPASS_LEN - 1:0]      WB_bypass_bus;

wire    [`WB2CSR_LEN - 1:0]         CSR_in_bus;

// control signals
wire    IF_ready_go, ID_allow_in, ID_ready_go,
        EX_ready_go, EX_allow_in, MEM_allow_in,
        MEM_ready_go, WB_allow_in, WB_ready_go;

// Regs
// IFreg
reg                             IFreg_valid;
reg     [`IFReg_BUS_LEN - 1:0]  IFreg;

// IDreg
reg                             IDreg_valid;
reg     [`IDReg_BUS_LEN - 1:0]  IDreg;

// EXreg
reg                             EXreg_valid;
reg     [`EXReg_BUS_LEN - 1:0]  EXreg;

// MEMreg
reg                             MEMreg_valid;
reg     [`MEMReg_BUS_LEN - 1:0] MEMreg;

//-----------------------------------RegFile-----------------------------------
wire    [4:0]       rf_raddr1, rf_raddr2, rf_waddr;
wire    [31:0]      rf_rdata1, rf_rdata2, rf_wdata;
wire                rf_we;
regfile u_regfile(
            .clk(aclk),
            .raddr1(rf_raddr1),
            .raddr2(rf_raddr2),
            .rdata1(rf_rdata1),
            .rdata2(rf_rdata2),
            .we(rf_we),
            .waddr(rf_waddr),
            .wdata(rf_wdata)
        );

// Exception
    wire    WB_ex, ertn_flush, EX_ex, MEM_ex;

// Flush
// [2023.11.30] yzcc: flush the pipelines when: WB_ex, ertn_flush, refetch_flush
    wire        flush;
    wire        refetch_flush;

//-----------------------------------TLB-----------------------------------
    wire [18:0]                     s0_vppn;
    wire                            s0_va_bit12;
    wire [9:0]                      s0_asid;
    wire                            s0_found;
    wire [$clog2(`TLBNUM) - 1:0]    s0_index;
    wire [19:0]                     s0_ppn;
    wire [5:0]                      s0_ps;
    wire [1:0]                      s0_plv;
    wire [1:0]                      s0_mat;
    wire                            s0_d;
    wire                            s0_v;

    // Port 1 (For Load/Store/invtlb)
    wire [18:0]                     s1_vppn;
    wire                            s1_va_bit12;
    wire [9:0]                      s1_asid;
    wire                            s1_found;
    wire [$clog2(`TLBNUM)-1:0]      s1_index;
    wire [19:0]                     s1_ppn;
    wire [5:0]                      s1_ps;
    wire [1:0]                      s1_plv;
    wire [1:0]                      s1_mat;
    wire                            s1_d;
    wire                            s1_v;
    wire                            invtlb_valid;        // INVTLB opcode
    wire [4:0]                      invtlb_op;

    // Write Port 
    wire                            we;
    wire [$clog2(`TLBNUM) - 1:0]    w_index;
    wire                            w_e;
    wire [18:0]                     w_vppn;
    wire [5:0]                      w_ps;
    wire [9:0]                      w_asid;
    wire                            w_g;
    wire [19:0]                     w_ppn0;
    wire [1:0]                      w_plv0;
    wire [1:0]                      w_mat0;
    wire                            w_d0;
    wire                            w_v0;
    wire [19:0]                     w_ppn1;
    wire [1:0]                      w_plv1;
    wire [1:0]                      w_mat1;
    wire                            w_d1;
    wire                            w_v1;

    // Read Port
    wire [$clog2(`TLBNUM) - 1:0]    r_index;
    wire                            r_e;
    wire [18:0]                     r_vppn;
    wire [5:0]                      r_ps;
    wire [9:0]                      r_asid;
    wire                            r_g;
    wire [19:0]                     r_ppn0;
    wire [1:0]                      r_plv0;
    wire [1:0]                      r_mat0;
    wire                            r_d0;
    wire                            r_v0;
    wire [19:0]                     r_ppn1;
    wire [1:0]                      r_plv1;
    wire [1:0]                      r_mat1;
    wire                            r_d1;
    wire                            r_v1;

    tlb u_tlb(
        .clk(aclk),
        // Fetch
        .s0_vppn(s0_vppn),      .s0_va_bit12(s0_va_bit12),  .s0_asid(s0_asid),
        .s0_found(s0_found),    .s0_index(s0_index),        .s0_ppn(s0_ppn),
        .s0_ps(s0_ps),          .s0_plv(s0_plv),            .s0_mat(s0_mat),
        .s0_d(s0_d),            .s0_v(s0_v),
        // Load Store INVTLB
        .s1_vppn(s1_vppn),      .s1_va_bit12(s1_va_bit12),  .s1_asid(s1_asid),
        .s1_found(s1_found),    .s1_index(s1_index),        .s1_ppn(s1_ppn),
        .s1_ps(s1_ps),          .s1_plv(s1_plv),            .s1_mat(s1_mat),
        .s1_d(s1_d),            .s1_v(s1_v),
        .invtlb_valid(invtlb_valid),    .invtlb_op(invtlb_op),
        // Write Port
        .we(we),                .w_index(w_index),          .w_e(w_e),
        .w_vppn(w_vppn),        .w_ps(w_ps),                .w_asid(w_asid),
        .w_g(w_g),              .w_ppn0(w_ppn0),            .w_plv0(w_plv0),
        .w_mat0(w_mat0),        .w_d0(w_d0),                .w_v0(w_v0),
        .w_ppn1(w_ppn1),        .w_plv1(w_plv1),            .w_mat1(w_mat1),
        .w_d1(w_d1),            .w_v1(w_v1),
        // Read Port
        .r_index(r_index),      .r_e(r_e),                  .r_vppn(r_vppn),
        .r_ps(r_ps),            .r_asid(r_asid),            .r_g(r_g),
        .r_ppn0(r_ppn0),        .r_plv0(r_plv0),            .r_mat0(r_mat0),
        .r_d0(r_d0),            .r_v0(r_v0),                .r_ppn1(r_ppn1),
        .r_plv1(r_plv1),        .r_mat1(r_mat1),            .r_d1(r_d1),
        .r_v1(r_v1)
    );

//-----------------------------------CSR-----------------------------------
    wire [79:0] csr_ctrl;
    wire [31:0] csr_rvalue;
    wire [31:0] ex_entry;
    wire [31:0] era_pc;
    wire has_int;
    wire [31:0] csr_crmd, csr_asid, csr_tlbehi, csr_dmw0, csr_dmw1;
    
    csr u_csr(
            .clk(aclk),
            .reset(reset),
    
            // inst interface
            .csr_ctrl(csr_ctrl),
            .csr_rvalue(csr_rvalue),
            
            // Request inst valid
            .valid(MEMreg_valid & ~refetch_flush),
    
            // circuit interface
            .CSR_in_bus(CSR_in_bus),
            .ex_entry(ex_entry),
            .era_pc(era_pc),
            .has_int(has_int),
            .csr_asid(csr_asid),
            .csr_crmd(csr_crmd),
            .csr_tlbehi(csr_tlbehi),
            .csr_dmw0(csr_dmw0),
            .csr_dmw1(csr_dmw1),

            // TLB ports
            .r_index(r_index),          .r_e(r_e),
            .r_vppn(r_vppn),            .r_ps(r_ps),            .r_asid(r_asid),
            .r_g(r_g),                  .r_ppn0(r_ppn0),        .r_plv0(r_plv0),
            .r_mat0(r_mat0),            .r_d0(r_d0),            .r_v0(r_v0),
            .r_ppn1(r_ppn1),            .r_plv1(r_plv1),        .r_mat1(r_mat1),
            .r_d1(r_d1),                .r_v1(r_v1),
            .we(we),                    .w_index(w_index),      .w_e(w_e),
            .w_vppn(w_vppn),            .w_ps(w_ps),            .w_asid(w_asid),
            .w_g(w_g),                  .w_ppn0(w_ppn0),        .w_plv0(w_plv0),
            .w_mat0(w_mat0),            .w_d0(w_d0),            .w_v0(w_v0),
            .w_ppn1(w_ppn1),            .w_plv1(w_plv1),        .w_mat1(w_mat1),
            .w_d1(w_d1),                .w_v1(w_v1)
        );
    

//-----------------------------------AXI convert-----------------------------------
wire        icache_rd_req;
wire [2:0]  icache_rd_type;
wire [31:0] icache_rd_addr;
wire        icache_rd_rdy;
wire        icache_ret_valid;
wire        icache_ret_last;
wire [31:0] icache_ret_data;

wire        data_sram_req;
wire        data_sram_wr;
wire [1:0]  data_sram_size;
wire [31:0] data_sram_addr;
wire [3:0]  data_sram_wstrb;
wire [31:0] data_sram_wdata;
wire        data_sram_addr_ok;
wire        data_sram_data_ok;
wire [31:0] data_sram_rdata;

AXI_convert AXI_convert(
                .icache_rd_req(icache_rd_req),
                .icache_rd_type(icache_rd_type),
                .icache_rd_addr(icache_rd_addr),
                .icache_rd_rdy(icache_rd_rdy),
                .icache_ret_valid(icache_ret_valid),
                .icache_ret_last(icache_ret_last),
                .icache_ret_data(icache_ret_data),

                .data_sram_req(data_sram_req),
                .data_sram_wr(data_sram_wr),
                .data_sram_size(data_sram_size),
                .data_sram_addr(data_sram_addr),
                .data_sram_wstrb(data_sram_wstrb),
                .data_sram_wdata(data_sram_wdata),
                .data_sram_addr_ok(data_sram_addr_ok),
                .data_sram_data_ok(data_sram_data_ok),
                .data_sram_rdata(data_sram_rdata),

                .aclk(aclk),
                .reset(reset),

                .arid(arid),
                .araddr(araddr),
                .arlen(arlen),
                .arsize(arsize),
                .arburst(arburst),
                .arlock(arlock),
                .arcache(arcache),
                .arprot(arprot),
                .arvalid(arvalid),
                .arready(arready),

                .rid(rid),
                .rdata(rdata),
                .rlast(rlast),
                .rvalid(rvalid),
                .rready(rready),

                .awid(awid),
                .awaddr(awaddr),
                .awlen(awlen),
                .awsize(awsize),
                .awburst(awburst),
                .awlock(awlock),
                .awcache(awcache),
                .awprot(awprot),
                .awvalid(awvalid),
                .awready(awready),

                .wid(wid),
                .wdata(wdata),
                .wstrb(wstrb),
                .wlast(wlast),
                .wvalid(wvalid),
                .wready(wready),

                .bid(bid),
                .bresp(bresp),
                .bvalid(bvalid),
                .bready(bready)
            );

//-----------------------------------ICache------------------------------------------------
wire        icache_valid;
wire [7:0]  icache_index;
wire [19:0] icache_tag;
wire [3:0]  icache_offset;
wire        icache_addrok;
wire        icache_dataok;
wire [31:0] icache_rdata;
cache icache(
           .clk(aclk),
           .resetn(aresetn),

           .valid(icache_valid),
           .op(1'b0), // read
           .index(icache_index),
           .tag(icache_tag),
           .offset(icache_offset),
           .wstrb(4'b0),
           .wdata(32'b0),
           .addr_ok(icache_addrok),
           .data_ok(icache_dataok),
           .rdata(icache_rdata),

           .rd_req(icache_rd_req),
           .rd_type(icache_rd_type),
           .rd_addr(icache_rd_addr),
           .rd_rdy(icache_rd_rdy),
           .ret_valid(icache_ret_valid),
           .ret_last(icache_ret_last),
           .ret_data(icache_ret_data),

           .wr_rdy(1'b1)
       );

//-----------------------------------Data Harzard Detect-----------------------------------
wire    [31:0]  addr1_forward, addr2_forward;
wire            pause, addr1_occur, addr2_occur;

data_harzard_detector u_dhd(
                          .reset(reset | flush),
                          .rf_raddr1(rf_raddr1),
                          .rf_raddr2(rf_raddr2),
                          .EX_bypass_bus(EX_bypass_bus),
                          .MEM_bypass_bus(MEM_bypass_bus),
                          .WB_bypass_bus(WB_bypass_bus),
                          .pause(pause),
                          .addr1_forward(addr1_forward),
                          .addr1_occur(addr1_occur),
                          .addr2_forward(addr2_forward),
                          .addr2_occur(addr2_occur)
                      );

// store when exception occur in EX/MEM/WB
wire excep_valid;
wire st_disable = MEM_ex | WB_ex;

//-----------------------------------Refetch and TLBSRCH pause-----------------------------------
// exp18
wire            to_IF_refetch, from_ID_refetch, from_EX_refetch, from_MEM_refetch, from_WB_refetch;
wire    [31:0]  refetch_pc;
wire            to_EX_tlbsrch_pause, from_MEM_tlbsrch_pause, from_WB_tlbsrch_pause;

assign  to_IF_refetch       = (from_ID_refetch | from_EX_refetch | from_MEM_refetch | from_WB_refetch) & ~flush;
assign  to_EX_tlbsrch_pause = from_MEM_tlbsrch_pause | from_WB_tlbsrch_pause;

// Flush
assign  flush       = reset | WB_ex | ertn_flush | refetch_flush;

//-----------------------------------Pipeline states-----------------------------------

/***************************************************
    Hint:
    clean pipeline when WB_ex or ertn_reflush:
    reset stages besides IF stage.
****************************************************/

// IF
IF  u_IF(
        .clk(aclk),
        .reset(reset),
        
        .icache_valid(icache_valid),
        .icache_index(icache_index),
        .icache_tag(icache_tag),
        .icache_offset(icache_offset),
        .icache_addrok(icache_addrok),
        .icache_dataok(icache_dataok),
        .icache_rdata(icache_rdata),

        .IF_ready_go(IF_ready_go),
        .ID_allow_in(ID_allow_in),

        .IFreg_valid(toIFreg_valid_bus),
        .IFreg_bus(IFreg_bus),
        .BR_BUS(BR_BUS),

        .except_valid(excep_valid),
        .WB_ex(WB_ex),
        .ex_entry(ex_entry),
        .ertn_flush(ertn_flush),
        .era_pc(era_pc),

        // CSR valud
        .csr_asid(csr_asid),
        .csr_crmd(csr_crmd),
        .csr_dmw0(csr_dmw0),
        .csr_dmw1(csr_dmw1),

        // refetch
        .refetch(to_IF_refetch),
        .refetch_flush(refetch_flush),
        .refetch_pc(refetch_pc),

        // TLB ports
        .s0_vppn(s0_vppn),      .s0_va_bit12(s0_va_bit12),
        .s0_asid(s0_asid),      .s0_found(s0_found),        .s0_index(s0_index),
        .s0_ppn(s0_ppn),        .s0_ps(s0_ps),              .s0_plv(s0_plv),
        .s0_mat(s0_mat),        .s0_d(s0_d),                .s0_v(s0_v)
    );

// ID
ID  u_ID(
        .clk(aclk),
        .reset(reset),
        .flush(flush),
        .timecnt(timecnt),
        .valid(IFreg_valid),
        .IFreg_bus(IFreg),
        .IF_ready_go(IF_ready_go),
        .EX_allow_in(EX_allow_in),
        .ID_ready_go(ID_ready_go),
        .ID_allow_in(ID_allow_in),
        .rf_raddr1(rf_raddr1),
        .rf_raddr2(rf_raddr2),
        .rf_rdata1(rf_rdata1),
        .rf_rdata2(rf_rdata2),

        .has_int(has_int),

        .IDreg_valid(toIDreg_valid_bus),
        .IDreg_bus(IDreg_bus),

        .refetch(from_ID_refetch),

        .pause(pause),
        .addr1_forward(addr1_forward),
        .addr1_occur(addr1_occur),
        .addr2_forward(addr2_forward),
        .addr2_occur(addr2_occur),
        .BR_BUS(BR_BUS)
    );

// EX
EX  u_EX(
        .clk(aclk),
        .reset(reset),
        .flush(flush),
        .valid(IDreg_valid),
        .IDreg_bus(IDreg),
        .ID_ready_go(ID_ready_go),
        .MEM_allow_in(MEM_allow_in),
        .EX_allow_in(EX_allow_in),
        .EX_ready_go(EX_ready_go),

        .data_sram_req(data_sram_req),
        .data_sram_wr(data_sram_wr),
        .data_sram_size(data_sram_size),
        .data_sram_addr(data_sram_addr),
        .data_sram_wstrb(data_sram_wstrb),
        .data_sram_wdata(data_sram_wdata),
        .data_sram_addr_ok(data_sram_addr_ok),

        .EX_bypass_bus(EX_bypass_bus),

        .EXreg_valid(toEXreg_valid_bus),
        .EXreg_bus(EXreg_bus),

        .st_disable(st_disable),

        .rdcntv_op(rdcntv_op),
        .counter_value(counter_value),

        .except(EX_ex),
        .ertn_cancel(MEM_ertn||WB_ertn),
        .refetch(from_EX_refetch),
        .tlbsrch_pause(to_EX_tlbsrch_pause),
        .csr_asid(csr_asid),
        .csr_tlbehi(csr_tlbehi),
        .csr_crmd(csr_crmd),
        .csr_dmw0(csr_dmw0),
        .csr_dmw1(csr_dmw1),

        // TLB ports
        .s1_vppn(s1_vppn),  .s1_va_bit12(s1_va_bit12),
        .s1_asid(s1_asid),  .s1_found(s1_found),    .s1_index(s1_index),
        .s1_ppn(s1_ppn),    .s1_ps(s1_ps),          .s1_plv(s1_plv),
        .s1_mat(s1_mat),    .s1_d(s1_d),            .s1_v(s1_v),
        .invtlb_valid(invtlb_valid),                .invtlb_op(invtlb_op)
    );

// MEM
MEM u_MEM(
        .clk(aclk),
        .reset(reset),
        .flush(flush),
        .valid(EXreg_valid),
        /*********************************************************
            Hint:
            EXreg_bus[`EXReg_BUS_LEN-18:`EXReg_BUS_LEN-49] is
            the result of multiplier.
            directly from EX stage.
            Kinda like mul for 2 clks.
        
        2023.12.1 yzcc:
            This segment of code is just a piece of shit. Cutting 
        EXreg into several slices is bullshit. Too inconvenient.
        Need to fix in the future version.
        *********************************************************/
        .EXreg_bus({EXreg[`EXReg_BUS_LEN-1:`EXReg_BUS_LEN-17],EXreg_bus[`EXReg_BUS_LEN-18:`EXReg_BUS_LEN-49],EXreg[`EXReg_BUS_LEN-50:0]}),
        .data_sram_req(data_sram_req),
        .data_sram_addr_ok(data_sram_addr_ok),
        .data_sram_data_ok(data_sram_data_ok),
        .data_sram_rdata(data_sram_rdata),
        
        .refetch(from_MEM_refetch),
        .tlbsrch_pause(from_MEM_tlbsrch_pause),

        .EX_ready_go(EX_ready_go),
        .WB_allow_in(WB_allow_in),
        .MEM_allow_in(MEM_allow_in),
        .MEM_ready_go(MEM_ready_go),
        .MEM_bypass_bus(MEM_bypass_bus),
        .MEMreg_valid(toMEMreg_valid_bus),
        .MEMreg_bus(MEMreg_bus),
        .except(MEM_ex),
        .ertn_flush(MEM_ertn)
    );

// WB
WB  u_WB(
        .clk(aclk),
        .valid(MEMreg_valid),
        .MEMreg_bus(MEMreg),
        .rf_wdata(rf_wdata),
        .rf_waddr(rf_waddr),
        .rf_we(rf_we),
        .WB_bypass_bus(WB_bypass_bus),
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_we(debug_wb_rf_we),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata),

        .refetch(from_WB_refetch),
        .tlbsrch_pause(from_WB_tlbsrch_pause),
        .refetch_flush(refetch_flush),
        .refetch_pc(refetch_pc),

        .MEM_ready_go(MEM_ready_go),
        .WB_ready_go(WB_ready_go),
        .WB_allow_in(WB_allow_in),
        .csr_ctrl(csr_ctrl),
        .csr_rvalue(csr_rvalue),
        .to_csr_in_bus(CSR_in_bus),
        .ertn_flush(WB_ertn),
        .except(WB_ex),
        .excep_valid(excep_valid)
    );
assign ertn_flush = CSR_in_bus[80];

// Pipeline update
// IFreg
always @(posedge aclk)
begin
    if (reset | flush)
    begin
        IFreg_valid     <= 0;
        IFreg           <= 0;
    end
    else
    begin
        if (IF_ready_go & ID_allow_in)
        begin
            IFreg_valid     <= toIFreg_valid_bus;
            IFreg           <= IFreg_bus;
        end
        else
        begin
            if (~IF_ready_go & ID_allow_in)
            begin
                IFreg_valid <= 0;
            end
        end
    end
end

// IDreg
always @(posedge aclk)
begin
    if (reset | flush)
    begin
        IDreg_valid     <= 0;
        IDreg           <= 0;
    end
    else
    begin
        if (ID_ready_go & EX_allow_in)
        begin
            IDreg_valid     <= toIDreg_valid_bus;
            IDreg           <= IDreg_bus;
        end
        else
        begin
            if (~ID_ready_go & EX_allow_in)
            begin
                IDreg_valid <= 0;
            end
        end
    end
end

// EXreg
always @(posedge aclk)
begin
    if (reset | flush)
    begin
        EXreg_valid     <= 0;
        EXreg           <= 0;
    end
    else
    begin
        if (EX_ready_go & MEM_allow_in)
        begin
            EXreg_valid     <= toEXreg_valid_bus;
            EXreg           <= EXreg_bus;
        end
        else
        begin
            if (~EX_ready_go & MEM_allow_in)
            begin
                EXreg_valid <= 0;
            end
        end
    end
end

// MEMreg
always @(posedge aclk)
begin
    if (reset | flush)
    begin
        MEMreg_valid    <= 0;
        MEMreg          <= 0;
    end
    else
    begin
        if (MEM_ready_go & WB_allow_in)
        begin
            MEMreg_valid    <= toMEMreg_valid_bus;
            MEMreg          <= MEMreg_bus;
        end
        else
        begin
            if (~MEM_ready_go & WB_allow_in)
            begin
                MEMreg_valid    <= 0;
            end
        end
    end
end

endmodule