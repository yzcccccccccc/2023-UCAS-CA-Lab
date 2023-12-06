`include "../macro.vh"
module EX(
    input   wire        clk,
    input   wire        reset,
    input   wire        flush,

    // valid & IDreg_bus
    input   wire                        valid,
    input   wire [`IDReg_BUS_LEN - 1:0] IDreg_bus,

    // control signals
    input   wire        ID_ready_go,
    input   wire        MEM_allow_in,
    output  wire        EX_allow_in,
    output  wire        EX_ready_go,

    // data ram interface
    output  wire        data_sram_req,
    output  wire        data_sram_wr,
    output  wire [1:0]  data_sram_size,
    output  wire [31:0] data_sram_addr,
    output  wire [3:0]  data_sram_wstrb,
    output  wire [31:0] data_sram_wdata,
    input   wire        data_sram_addr_ok,

    // data harzard bypass
    output  wire [`EX_BYPASS_LEN - 1:0] EX_bypass_bus,

    // EXreg bus
    output  wire                        EXreg_valid,
    output  wire [`EXReg_BUS_LEN - 1:0] EXreg_bus,

    input   wire st_disable,

    // rdcntv
    input   wire [31:0]     counter_value,
    output  wire [1:0]      rdcntv_op,

    output  wire            except,
    input   wire            ertn_cancel,
    output  wire            refetch,
    input   wire            tlbsrch_pause,

    // CSR value
    input   wire [31:0]     csr_asid,
    input   wire [31:0]     csr_tlbehi,

    // TLB ports (s1_ && invtlb_)
    output  wire [18:0]     s1_vppn,
    output  wire            s1_va_bit12,
    output  wire [9:0]      s1_asid,
    input   wire            s1_found,
    input   wire [3:0]      s1_index,
    input   wire [19:0]     s1_ppn,
    input   wire [5:0]      s1_ps,
    input   wire [1:0]      s1_plv,
    input   wire [1:0]      s1_mat,
    input   wire            s1_d,
    input   wire            s1_v,
    output  wire            invtlb_valid,
    output  wire [4:0]      invtlb_op
);

/************************************************************************************
    Hint:
        In EX state, we need to request data_ram for the data to be used
    in MEM state.
*************************************************************************************/

// ebus
wire [15:0] ebus_init;
wire [15:0] ebus_end;

// IDreg_bus Decode
wire    [`ID2EX_LEN - 1:0]  ID2EX_bus;
wire    [`ID2MEM_LEN - 1:0] ID2MEM_bus;
wire    [`ID2WB_LEN - 1:0]  ID2WB_bus;
wire    [`ID_TLB_LEN - 1:0] ID_TLB_bus;

assign  {ID2EX_bus, ID2MEM_bus, ID2WB_bus, ID_TLB_bus} = IDreg_bus;

wire    [11:0]  alu_op;
wire    [31:0]  alu_src1, alu_src2;
wire            mul, div;

wire            mem_en;
wire    [31:0]  rkd_value;
wire    [2:0]   st_ctrl;            // = {inst_st_w, inst_st_h, inst_st_b}
wire    [4:0]   ld_ctrl;

wire            ertn_flush;
wire [79:0]     csr_ctrl;
wire            pause_int_detect;
wire            res_from_csr;
wire            rf_we;
wire            res_from_mem;
wire    [4:0]   rf_waddr;
wire    [31:0]  pc;

wire            res_from_rdcntv;
wire            tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, tlbsrch_hit;
wire            invtlb_valid_tmp;
wire            refetch_detect, tlbsrch_pause_detect, refetch_tag;

assign  {rdcntv_op, ebus_init, alu_op, alu_src1, alu_src2, mul, div}      = ID2EX_bus;
assign  {rkd_value, mem_en, st_ctrl, ld_ctrl}       = ID2MEM_bus;
assign  {pause_int_detect, ertn_flush, csr_ctrl, res_from_csr, rf_we, res_from_mem, rf_waddr, pc}         = ID2WB_bus;
assign  {tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, invtlb_valid_tmp, invtlb_op, refetch_detect, tlbsrch_pause_detect, refetch_tag}    = ID_TLB_bus;

// Define Signals
wire [31:0]         alu_result;
wire [31:0]         mul_result, div_result;
wire                div_done;

wire    [`EX2MEM_LEN - 1:0] EXreg_2MEM;
wire    [`EX2WB_LEN - 1:0]  EXreg_2WB;
wire    [`EX_TLB_LEN - 1:0] EXreg_TLB;

wire    [4:0]       EX_rf_waddr;
wire                EX_rf_we, EX_res_from_mem;
wire    [31:0]      EX_result;

// ALU
alu u_alu(
        .alu_op     (alu_op),
        .alu_src1   (alu_src1),
        .alu_src2   (alu_src2),
        .alu_result (alu_result)
    );

// Multiplier
multiplier u_mul(
               .clk        (clk),
               .mul_src1   (alu_src1),
               .mul_src2   (alu_src2),
               .mul_op     (alu_op[2:0] & {3{valid}}),
               .mul_res    (mul_result)
           );

// Divider
divider u_div(
            .clk        (clk),
            .reset      (reset | flush),
            .div_src1   (alu_src1),
            .div_src2   (alu_src2),
            .div_op     (alu_op[3:0] & {4{valid & div}}),
            .div_res    (div_result),
            .div_done   (div_done)
        );

// Access MEM
wire    [3:0]       mem_we;
wire    [31:0]      st_data;
assign mem_we   = {4{st_ctrl[0] & ~alu_result[0] & ~alu_result[1]}} & {4'b0001}
       | {4{st_ctrl[0] & alu_result[0] & ~alu_result[1]}} & {4'b0010}
       | {4{st_ctrl[0] & ~alu_result[0] & alu_result[1]}} & {4'b0100}
       | {4{st_ctrl[0] & alu_result[0] & alu_result[1]}} & {4'b1000}
       | {4{st_ctrl[1] & ~alu_result[1]}} & {4'b0011}
       | {4{st_ctrl[1] & alu_result[1]}} & {4'b1100}
       | {4{st_ctrl[2]}} & {4'b1111};
assign st_data  = {32{st_ctrl[0]}} & {4{rkd_value[7:0]}}
       | {32{st_ctrl[1]}} & {2{rkd_value[15:0]}}
       | {32{st_ctrl[2]}} & {rkd_value[31:0]};

// exp13 ale
wire has_ale;
assign has_ale = st_ctrl[1] && alu_result[0]                    ||
                 st_ctrl[2] && (alu_result[0] || alu_result[1]) ||
                 ld_ctrl[0] && alu_result[0]                    ||
                 ld_ctrl[1] && alu_result[0]                    ||
                 ld_ctrl[4] && (alu_result[0] || alu_result[1]);

// MEM Access
reg     cancel_or_diable;
always @(posedge clk) begin
    if (EX_ready_go & MEM_allow_in)
        cancel_or_diable    <= 0;
    else begin
        if (ertn_cancel)
            cancel_or_diable    <= 1;
        if (st_disable)
            cancel_or_diable    <= 1;
    end
end
assign data_sram_req    = mem_en & valid & ~has_ale & MEM_allow_in & ~(cancel_or_diable | ertn_cancel | st_disable) & ~(|ebus_init) & ~refetch_tag;
assign data_sram_addr   = alu_result;
assign data_sram_size   = {2{st_ctrl[2] | ld_ctrl[4]}} & 2'd2
                        | {2{st_ctrl[1] | ld_ctrl[1] | ld_ctrl[0]}} & 2'd1
                        | {2{st_ctrl[1] | ld_ctrl[2] | ld_ctrl[3]}} & 2'd0;
assign data_sram_wr     = (|st_ctrl) & ~(|ld_ctrl);
assign data_sram_wdata  = st_data;
assign data_sram_wstrb  = mem_we & {4{valid}};

// exp18 TLB
wire [9:0]  invtlb_asid;
wire [18:0] invtlb_vppn, tlbsrch_vppn, ls_vppn;
wire        invtlb_vabit12, tlbsrch_vabit12, ls_vabit12;
wire [3:0]  tlbsrch_index;

assign      invtlb_asid     = alu_src1[9:0];                        // rj[9:0]
assign      invtlb_vppn     = alu_src2[31:13];                      // rk[31:13]
assign      invtlb_vabit12  = alu_src2[12];
assign      invtlb_valid    = invtlb_valid_tmp & valid;

assign      tlbsrch_vppn    = csr_tlbehi[`CSR_TLBEHI_VPPN];
assign      tlbsrch_vabit12 = csr_tlbehi[12];

assign      ls_vppn         = alu_result[31:13];
assign      ls_vabit12      = alu_result[12];

assign  s1_vppn         = tlbsrch_req ? tlbsrch_vppn
                        : invtlb_valid ? invtlb_vppn
                        : ls_vppn;
assign  s1_va_bit12     = tlbsrch_req ? tlbsrch_vabit12 
                        : invtlb_valid ? invtlb_vabit12
                        : ls_vabit12;
assign  s1_asid         = invtlb_valid ? invtlb_asid : csr_asid[`CSR_ASID_ASID];

assign  tlbsrch_index   = s1_index;


// exp13 rdcntv
assign res_from_rdcntv = |rdcntv_op;

// exception
assign ebus_end = (|ebus_init) ? ebus_init
              : {{15-`EBUS_ALE{1'b0}}, has_ale, {`EBUS_ALE{1'b0}}} & {16{valid}};

// EXreg_bus
reg     has_flush;
always @(posedge clk) begin
    if (EX_ready_go & MEM_allow_in)
        has_flush   <= 0;
    else
        if (flush)
            has_flush   <= 1;
end

wire   wait_data_ok;
assign wait_data_ok     = data_sram_req;
assign tlbsrch_hit      = s1_found;

assign EXreg_valid      = valid & ~(flush | has_flush);
assign EXreg_2MEM       = {wait_data_ok, ebus_end, mul, mul_result, EX_result, rkd_value, ld_ctrl};
assign EXreg_2WB        = {pause_int_detect, ertn_flush & EXreg_valid, csr_ctrl, res_from_csr, rf_we, EX_res_from_mem, rf_waddr, pc};
assign EXreg_TLB        = {tlbsrch_req, tlbwr_req, tlbfill_req, tlbrd_req, tlbsrch_hit, tlbsrch_index, refetch_detect, tlbsrch_pause_detect, refetch_tag};
assign EXreg_bus        = {EXreg_2MEM, EXreg_2WB, EXreg_TLB};

// refetch (to IF)
assign refetch          = refetch_detect & valid;

// Data Harzard Bypass
assign  EX_rf_waddr         = rf_waddr;
assign  EX_rf_we            = rf_we & valid;
assign  EX_res_from_mem     = res_from_mem & !has_ale;
assign  EX_result           =   div ? div_result :
                                res_from_rdcntv ? counter_value :
                                alu_result;

assign  EX_bypass_bus       = {pause_int_detect & EXreg_valid, res_from_csr, EX_rf_waddr, EX_rf_we, mul, EX_res_from_mem, EX_result};

// Exception
assign  except              = |ebus_end & valid;

// control signals
assign EX_ready_go      = (div & valid) ? div_done
                        : data_sram_req ? data_sram_addr_ok
                        : tlbsrch_req ? ~tlbsrch_pause
                        : 1;
assign EX_allow_in      = ~EXreg_valid | MEM_allow_in & EX_ready_go;

endmodule