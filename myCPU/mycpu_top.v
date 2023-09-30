`include "macro.vh"
module mycpu_top(
    input   wire        clk,
    input   wire        resetn,

    // inst sram interface
    output  wire        inst_sram_en,
    output  wire [3:0]  inst_sram_we,
    output  wire [31:0] inst_sram_wdata,
    output  wire [31:0] inst_sram_addr,
    input   wire [31:0] inst_sram_rdata,

    // data sram interface
    output  wire        data_sram_en,
    output  wire [3:0]  data_sram_we,
    output  wire [31:0] data_sram_wdata,
    output  wire [31:0] data_sram_addr,
    input   wire [31:0] data_sram_rdata,

    // trace debug interface
    output  wire [31:0] debug_wb_pc,
    output  wire [3:0]  debug_wb_rf_we,
    output  wire [4:0]  debug_wb_rf_wnum,
    output  wire [31:0] debug_wb_rf_wdata
);

// reset signal
    reg     reset;
    always @(posedge clk) begin
        reset <= ~resetn;
    end

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

// Data Harzard Detect
    wire    [4:0]   EX_rf_waddr, MEM_rf_waddr;
    wire            EX_rf_we, MEM_rf_we;
    wire            data_harzard_occur;

    data_harzard_detector u_dhd(
        .rf_raddr1(rf_raddr1),
        .rf_raddr2(rf_raddr2),
        .EX_rf_waddr(EX_rf_waddr),
        .EX_rf_we(EX_rf_we),
        .MEM_rf_waddr(MEM_rf_waddr),
        .MEM_rf_we(MEM_rf_we),
        .WB_rf_waddr(rf_waddr),
        .WB_rf_we(rf_we),
        .occur(data_harzard_occur)
    );  

// Pipeline states
    // IF
        IF  u_IF(
            .clk(clk),
            .reset(reset),
            .inst_sram_we(inst_sram_we),
            .inst_sram_en(inst_sram_en),
            .inst_sram_addr(inst_sram_addr),
            .inst_sram_wdata(inst_sram_wdata),
            .inst_sram_rdata(inst_sram_rdata),
            .IF_ready_go(IF_ready_go),
            .ID_allow_in(ID_allow_in),
            .IFreg_valid(toIFreg_valid_bus),
            .IFreg_bus(IFreg_bus),
            .BR_BUS(BR_BUS)
        );

    // ID
        ID  u_ID(
            .clk(clk),
            .reset(reset),
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
            .IDreg_valid(toIDreg_valid_bus),
            .IDreg_bus(IDreg_bus),
            .data_harzard_occur(data_harzard_occur),
            .BR_BUS(BR_BUS)
        );

    // EX
        EX  u_EX(
            .clk(clk),
            .reset(reset),
            .valid(IDreg_valid),
            .IDreg_bus(IDreg),
            .ID_ready_go(ID_ready_go),
            .MEM_allow_in(MEM_allow_in),
            .EX_allow_in(EX_allow_in),
            .EX_ready_go(EX_ready_go),
            .data_sram_en(data_sram_en),
            .data_sram_addr(data_sram_addr),
            .data_sram_wdata(data_sram_wdata),
            .data_sram_we(data_sram_we),
            .EX_rf_waddr(EX_rf_waddr),
            .EX_rf_we(EX_rf_we),
            .EXreg_valid(toEXreg_valid_bus),
            .EXreg_bus(EXreg_bus)
        );

    // MEM
        MEM u_MEM(
            .clk(clk),
            .reset(reset),
            .valid(EXreg_valid),
            .EXreg_bus(EXreg),
            .data_sram_rdata(data_sram_rdata),
            .EX_ready_go(EX_ready_go),
            .WB_allow_in(WB_allow_in),
            .MEM_allow_in(MEM_allow_in),
            .MEM_ready_go(MEM_ready_go),
            .MEM_rf_waddr(MEM_rf_waddr),
            .MEM_rf_we(MEM_rf_we),
            .MEMreg_valid(toMEMreg_valid_bus),
            .MEMreg_bus(MEMreg_bus)
        ); 

    // WB
        WB  u_WB(
            .clk(clk),
            .reset(reset),
            .valid(MEMreg_valid),
            .MEMreg_bus(MEMreg),
            .rf_wdata(rf_wdata),
            .rf_waddr(rf_waddr),
            .rf_we(rf_we),
            .debug_wb_pc(debug_wb_pc),
            .debug_wb_rf_we(debug_wb_rf_we),
            .debug_wb_rf_wnum(debug_wb_rf_wnum),
            .debug_wb_rf_wdata(debug_wb_rf_wdata),
            .MEM_ready_go(MEM_ready_go),
            .WB_ready_go(WB_ready_go),
            .WB_allow_in(WB_allow_in)
        );

// Pipeline update
    // IFreg
        always @(posedge clk) begin
            if (reset) begin
                IFreg_valid     <= 0;
                IFreg           <= 0;
            end
            else begin
                if (IF_ready_go & ID_allow_in) begin
                    IFreg_valid     <= toIFreg_valid_bus;
                    IFreg           <= IFreg_bus;
                end
                else begin
                    if (~IF_ready_go & ID_allow_in) begin
                        IFreg_valid <= 0;
                    end
                end
            end
        end

    // IDreg
        always @(posedge clk) begin
            if (reset) begin
                IDreg_valid     <= 0;
                IDreg           <= 0;
            end
            else begin
                if (ID_ready_go & EX_allow_in) begin
                    IDreg_valid     <= toIDreg_valid_bus;
                    IDreg           <= IDreg_bus;
                end
                else begin
                    if (~ID_ready_go & EX_allow_in) begin
                        IDreg_valid <= 0;
                    end
                end
            end
        end

    // EXreg
        always @(posedge clk) begin
            if (reset) begin
                EXreg_valid     <= 0;
                EXreg           <= 0;
            end
            else begin
                if (EX_ready_go & MEM_allow_in) begin
                    EXreg_valid     <= toEXreg_valid_bus;
                    EXreg           <= EXreg_bus;
                end
                else begin
                    if (~EX_ready_go & MEM_allow_in) begin
                        EXreg_valid <= 0;
                    end
                end
            end
        end

    // MEMreg
        always @(posedge clk) begin
            if (reset) begin
                MEMreg_valid    <= 0;
                MEMreg          <= 0;
            end
            else begin
                if (MEM_ready_go & WB_allow_in) begin
                    MEMreg_valid    <= toMEMreg_valid_bus;
                    MEMreg          <= MEMreg_bus;
                end
                else begin
                    if (~MEM_ready_go & WB_allow_in) begin
                        MEMreg_valid    <= 0;
                    end
                end
            end
        end

endmodule