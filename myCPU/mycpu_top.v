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

// bus & piepeline control signals
    // bus
        wire    [`BR_BUS_LEN - 1:0]         BR_BUS;

        wire                                toIFreg_valid_bus;
        wire    [`IF2ID_pc - 1:0]           IF2ID_pc_bus;
        wire    [`IF2ID_inst - 1:0]         IF2ID_inst_bus;

        wire                                toIDreg_valid_bus;
        wire    [`ID2EX_LEN - 1:0]          ID2EX_bus;
        wire    [`ID2MEM_LEN - 1:0]         ID2MEM_bus;
        wire    [`ID2WB_LEN - 1:0]          ID2WB_bus;

        wire                                toEXreg_valid_bus;
        wire    [`EX2MEM_LEN - 1:0]         EX2MEM_bus;
        wire    [`EX2WB_LEN - 1:0]          EX2WB_bus;

        wire                                toMEMreg_valid_bus;
        wire    [`MEM2WB_LEN - 1:0]         MEM2WB_bus;

    // control signals
        wire    IF_ready_go, ID_allow_in, ID_ready_go,
                EX_ready_go, EX_allow_in, MEM_allow_in,
                MEM_ready_go, WB_allow_in, WB_ready_go;

// reg
    // IFreg
        reg                             IFreg_valid;
        reg     [`IF2ID_pc - 1:0]       IFreg_pc;
        reg     [`IF2ID_inst - 1:0]     IFreg_inst; 

    // IDreg
        reg                             IDreg_valid;
        reg     [`ID2EX_LEN - 1:0]      IDreg_2EX; 
        reg     [`ID2MEM_LEN - 1:0]     IDreg_2MEM;
        reg     [`ID2WB_LEN - 1:0]      IDreg_2WB;

    // EXreg
        reg                             EXreg_valid;
        reg     [`EX2MEM_LEN - 1:0]     EXreg_2MEM;
        reg     [`EX2WB_LEN - 1:0]      EXreg_2WB;

    // MEMreg
        reg                             MEMreg_valid;
        reg     [`MEM2WB_LEN - 1:0]     MEMreg_2WB;

// regfile
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

// pipeline states
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
            .IFreg_pc(IF2ID_pc_bus),
            .IFreg_inst(IF2ID_inst_bus),
            .BR_BUS(BR_BUS)
        );

    // ID
        ID  u_ID(
            .clk(clk),
            .reset(reset),
            .inst(IFreg_inst),
            .pc(IFreg_pc),
            .valid(IFreg_valid),
            .IF_ready_go(IF_ready_go),
            .EX_allow_in(EX_allow_in),
            .ID_ready_go(ID_ready_go),
            .ID_allow_in(ID_allow_in),
            .rf_raddr1(rf_raddr1),
            .rf_raddr2(rf_raddr2),
            .rf_rdata1(rf_rdata1),
            .rf_rdata2(rf_rdata2),
            .IDreg_valid(toIDreg_valid_bus),
            .IDreg_2EX(ID2EX_bus),
            .IDreg_2MEM(ID2MEM_bus),
            .IDreg_2WB(ID2WB_bus),
            .BR_BUS(BR_BUS)
        );

    // EX
        wire    [11:0]      EX_alu_op;
        wire    [31:0]      EX_alu_src1, EX_alu_src2;
        assign {EX_alu_op, EX_alu_src1, EX_alu_src2}            = IDreg_2EX;

        wire                EX_mem_en;
        wire    [31:0]      EX_rkd_value;
        wire                EX_mem_we;
        assign {EX_rkd_value, EX_mem_en, EX_mem_we}             = IDreg_2MEM;

        wire                EX_rf_we, EX_res_from_mem;
        wire    [4:0]       EX_rf_waddr;
        wire    [31:0]      EX_pc;
        assign {EX_rf_we, EX_res_from_mem, EX_rf_waddr, EX_pc}  = IDreg_2WB;

        EX  u_EX(
            .clk(clk),
            .reset(reset),
            .valid(IDreg_valid),
            .alu_op(EX_alu_op),
            .alu_src1(EX_alu_src1),
            .alu_src2(EX_alu_src2),
            .mem_en(EX_mem_en),
            .rkd_value(EX_rkd_value),
            .mem_we({4{EX_mem_we}}),
            .rf_we(EX_rf_we),
            .res_from_mem(EX_res_from_mem),
            .rf_waddr(EX_rf_waddr),
            .pc(EX_pc),
            .ID_ready_go(ID_ready_go),
            .MEM_allow_in(MEM_allow_in),
            .EX_allow_in(EX_allow_in),
            .EX_ready_go(EX_ready_go),
            .data_sram_en(data_sram_en),
            .data_sram_addr(data_sram_addr),
            .data_sram_wdata(data_sram_wdata),
            .data_sram_we(data_sram_we),
            .EXreg_valid(toEXreg_valid_bus),
            .EXreg_2MEM(EX2MEM_bus),
            .EXreg_2WB(EX2WB_bus)
        );

    // MEM
        wire    [31:0]      MEM_alu_result;
        wire    [31:0]      MEM_rkd_value;
        wire    [3:0]       MEM_mem_we;
        assign  {MEM_alu_result, MEM_rkd_value, MEM_mem_we}         = EXreg_2MEM;

        wire                MEM_rf_we, MEM_res_from_mem;
        wire    [4:0]       MEM_rf_waddr;
        wire    [31:0]      MEM_pc;
        assign  {MEM_rf_we, MEM_res_from_mem, MEM_rf_waddr, MEM_pc} = EXreg_2WB; 

        MEM u_MEM(
            .clk(clk),
            .reset(reset),
            .valid(EXreg_valid),
            .alu_result(MEM_alu_result),
            .rkd_value(MEM_rkd_value),
            .mem_we(MEM_mem_we),
            .data_sram_rdata(data_sram_rdata),
            .EX_ready_go(EX_ready_go),
            .WB_allow_in(WB_allow_in),
            .MEM_allow_in(MEM_allow_in),
            .MEM_ready_go(MEM_ready_go),
            .rf_we(MEM_rf_we),
            .res_from_mem(MEM_res_from_mem),
            .rf_waddr(MEM_rf_waddr),
            .pc(MEM_pc),
            .MEMreg_valid(toMEMreg_valid_bus),
            .MEMreg_2WB(MEM2WB_bus)
        ); 

    // WB
        wire    [4:0]       WB_rf_waddr;
        wire                WB_rf_we, WB_res_from_mem;
        wire    [31:0]      WB_data, WB_alu_result, WB_pc;
        assign  {WB_alu_result, WB_data, WB_rf_we, WB_res_from_mem, WB_rf_waddr, WB_pc} = MEMreg_2WB;

        WB  u_WB(
            .clk(clk),
            .reset(reset),
            .valid(MEMreg_valid),
            .waddr(rf_waddr),
            .wdata(rf_wdata),
            .we(rf_we),
            .rf_waddr(WB_rf_waddr),
            .rf_we(WB_rf_we),
            .res_from_mem(WB_res_from_mem),
            .data(WB_data),
            .alu_result(WB_alu_result),
            .pc(WB_pc),
            .debug_wb_pc(debug_wb_pc),
            .debug_wb_rf_we(debug_wb_rf_we),
            .debug_wb_rf_wnum(debug_wb_rf_wnum),
            .debug_wb_rf_wdata(debug_wb_rf_wdata),
            .MEM_ready_go(MEM_ready_go),
            .WB_ready_go(WB_ready_go),
            .WB_allow_in(WB_allow_in)
        );

// pipeline update
    // IFreg
        always @(posedge clk) begin
            if (reset) begin
                IFreg_valid     <= 0;
                IFreg_inst      <= 0;
                IFreg_pc        <= 0;
            end
            else begin
                if (IF_ready_go & ID_allow_in) begin
                    IFreg_valid     <= toIFreg_valid_bus;
                    IFreg_inst      <= IF2ID_inst_bus;
                    IFreg_pc        <= IF2ID_pc_bus;
                end
            end
        end

    // IDreg
        always @(posedge clk) begin
            if (reset) begin
                IDreg_valid     <= 0;
                IDreg_2EX       <= 0;
                IDreg_2MEM      <= 0;
                IDreg_2WB       <= 0;
            end
            else begin
                if (ID_ready_go & EX_allow_in) begin
                    IDreg_valid     <= toIDreg_valid_bus;
                    IDreg_2EX       <= ID2EX_bus;
                    IDreg_2MEM      <= ID2MEM_bus;
                    IDreg_2WB       <= ID2WB_bus;
                end
            end
        end

    // EXreg
        always @(posedge clk) begin
            if (reset) begin
                EXreg_valid     <= 0;
                EXreg_2MEM      <= 0;
                EXreg_2WB       <= 0;
            end
            else begin
                if (EX_ready_go & MEM_allow_in) begin
                    EXreg_valid     <= toEXreg_valid_bus;
                    EXreg_2MEM      <= EX2MEM_bus;
                    EXreg_2WB       <= EX2WB_bus;
                end
            end
        end

    // MEMreg
        always @(posedge clk) begin
            if (reset) begin
                MEMreg_valid    <= 0;
                MEMreg_2WB      <= 0;
            end
            else begin
                if (MEM_ready_go & WB_allow_in) begin
                    MEMreg_valid    <= toMEMreg_valid_bus;
                    MEMreg_2WB      <= MEM2WB_bus;
                end
            end
        end

endmodule