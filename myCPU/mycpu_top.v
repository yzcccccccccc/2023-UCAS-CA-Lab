`include "macro.vh"
module mycpu_top(
    input   wire        clk,
    input   wire        resetn,

    // inst sram interface (SRAM, exp14+)
    output  wire        inst_sram_req,
    output  wire        inst_sram_wr,
    output  wire [1:0]  inst_sram_size,
    output  wire [31:0] inst_sram_addr,
    output  wire [3:0]  inst_sram_wstrb,
    output  wire [31:0] inst_sram_wdata,
    input   wire        inst_sram_addr_ok,
    input   wire        inst_sram_data_ok,
    input   wire [31:0] inst_sram_rdata,

    // data sram interface (SRAM, exp14+)
    output  wire        data_sram_req,
    output  wire        data_sram_wr,
    output  wire [1:0]  data_sram_size,
    output  wire [31:0] data_sram_addr,
    output  wire [3:0]  data_sram_wstrb,
    output  wire [31:0] data_sram_wdata,
    input   wire        data_sram_addr_ok,
    input   wire        data_sram_data_ok,
    input   wire [31:0] data_sram_rdata,

    // trace debug interface
    output  wire [31:0] debug_wb_pc,
    output  wire [3:0]  debug_wb_rf_we,
    output  wire [4:0]  debug_wb_rf_wnum,
    output  wire [31:0] debug_wb_rf_wdata
);

// reset signal
reg     reset;
always @(posedge clk)
begin
    reset <= ~resetn;
end

// timer (for rdcnt)
    reg [63:0]      timecnt;
    wire [31:0]     counter_value;
    wire [1:0]      rdcntv_op;
    always @(posedge clk) begin
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

// RegFile
wire    [4:0]       rf_raddr1, rf_raddr2, rf_waddr;
wire    [31:0]      rf_rdata1, rf_rdata2, rf_wdata;
wire                rf_we;
regfile u_regfile(
            .clk(clk),
            .raddr1(rf_raddr1),
            .raddr2(rf_raddr2),
            .rdata1(rf_rdata1),
            .rdata2(rf_rdata2),
            .we(rf_we),
            .waddr(rf_waddr),
            .wdata(rf_wdata)
        );

// Exception
    wire    wb_ex, ertn_flush;

// CSR
wire [79:0] csr_ctrl;
wire [31:0] csr_rvalue;
wire [31:0] ex_entry;
wire [31:0] era_pc;
wire has_int;

csr u_csr(
        .clk(clk),
        .reset(reset),

        // inst interface
        .csr_ctrl(csr_ctrl),
        .csr_rvalue(csr_rvalue),
        
        // Request inst valid
        .valid(MEMreg_valid),

        // circuit interface
        .CSR_in_bus(CSR_in_bus),
        .ex_entry(ex_entry),
        .era_pc(era_pc),
        .has_int(has_int)
    );

// Data Harzard Detect
wire    [31:0]  addr1_forward, addr2_forward;
wire            pause, addr1_occur, addr2_occur;

data_harzard_detector u_dhd(
                          .reset(reset || wb_ex || ertn_flush),
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
wire ex_ex = | EXreg_bus[238:223];
wire mem_ex = | MEMreg_bus[167:152];
wire st_disable = ex_ex | mem_ex | wb_ex;

// Pipeline states

/***************************************************
    Hint:
    clean pipeline when wb_ex or ertn_reflush:
    reset stages besides IF stage.
****************************************************/

// IF
IF  u_IF(
        .clk(clk),
        .reset(reset),
        .inst_sram_req(inst_sram_req),
        .inst_sram_wr(inst_sram_wr),
        .inst_sram_size(inst_sram_size),
        .inst_sram_addr(inst_sram_addr),
        .inst_sram_wstrb(inst_sram_wstrb),
        .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_addr_ok(inst_sram_addr_ok),
        .inst_sram_data_ok(inst_sram_data_ok),
        .inst_sram_rdata(inst_sram_rdata),

        .IF_ready_go(IF_ready_go),
        .ID_allow_in(ID_allow_in),

        .IFreg_valid(toIFreg_valid_bus),
        .IFreg_bus(IFreg_bus),
        .BR_BUS(BR_BUS),

        .except_valid(excep_valid),
        .wb_ex(wb_ex),
        .ex_entry(ex_entry),
        .ertn_flush(ertn_flush),
        .era_pc(era_pc)
    );

// ID
ID  u_ID(
        .clk(clk),
        .reset(reset||wb_ex||ertn_flush),
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

        .pause(pause),
        .addr1_forward(addr1_forward),
        .addr1_occur(addr1_occur),
        .addr2_forward(addr2_forward),
        .addr2_occur(addr2_occur),
        .BR_BUS(BR_BUS)
    );

// EX
EX  u_EX(
        .clk(clk),
        .reset(reset||wb_ex||ertn_flush),
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

        .ertn_cancel(MEM_ertn||WB_ertn)
    );

// MEM
MEM u_MEM(
        .clk(clk),
        .reset_real(reset),
        .reset(reset||wb_ex||ertn_flush),
        .valid(EXreg_valid),
        /***************************************************
            Hint:
            EXreg_bus[`EXReg_BUS_LEN-19:`EXReg_BUS_LEN-50] is
            the result of multiplier.
            directly from EX stage.
            Kinda like mul for 2 clks.
        ****************************************************/
        .EXreg_bus({EXreg[`EXReg_BUS_LEN-1:`EXReg_BUS_LEN-18],EXreg_bus[`EXReg_BUS_LEN-19:`EXReg_BUS_LEN-50],EXreg[`EXReg_BUS_LEN-51:0]}),
        .data_sram_req(data_sram_req),
        .data_sram_addr_ok(data_sram_addr_ok),
        .data_sram_data_ok(data_sram_data_ok),
        .data_sram_rdata(data_sram_rdata),
        .EX_ready_go(EX_ready_go),
        .WB_allow_in(WB_allow_in),
        .MEM_allow_in(MEM_allow_in),
        .MEM_ready_go(MEM_ready_go),
        .MEM_bypass_bus(MEM_bypass_bus),
        .MEMreg_valid(toMEMreg_valid_bus),
        .MEMreg_bus(MEMreg_bus),
        .ertn_flush(MEM_ertn)
    );

// WB
WB  u_WB(
        .clk(clk),
        .reset(reset||wb_ex||ertn_flush),
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
        .MEM_ready_go(MEM_ready_go),
        .WB_ready_go(WB_ready_go),
        .WB_allow_in(WB_allow_in),
        .csr_ctrl(csr_ctrl),
        .csr_rvalue(csr_rvalue),
        .to_csr_in_bus(CSR_in_bus),
        .ertn_flush(WB_ertn),
        .excep_valid(excep_valid)
    );
assign wb_ex = CSR_in_bus[79];
assign ertn_flush = CSR_in_bus[80];

// Pipeline update
// IFreg
always @(posedge clk)
begin
    if (reset||wb_ex||ertn_flush)
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
always @(posedge clk)
begin
    if (reset||wb_ex||ertn_flush)
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
always @(posedge clk)
begin
    if (reset||wb_ex||ertn_flush)
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
always @(posedge clk)
begin
    if (reset||wb_ex||ertn_flush)
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