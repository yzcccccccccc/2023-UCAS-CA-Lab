`include "../macro.vh"
module MEM(
       input   wire        clk,
       input   wire        reset_real,
       input   wire        reset,

       // valid & EXreg_bus
       input   wire                        valid,
       input   wire [`EXReg_BUS_LEN - 1:0] EXreg_bus,

       // data mem interface
       input   wire        data_sram_req,
       input   wire        data_sram_addr_ok,
       input   wire        data_sram_data_ok,
       input   wire [31:0] data_sram_rdata,

       // control signals
       input   wire        EX_ready_go,
       input   wire        WB_allow_in,
       output  wire        MEM_allow_in,
       output  wire        MEM_ready_go,

       // data harzard bypass
       output  wire [`MEM_BYPASS_LEN - 1:0]    MEM_bypass_bus,

       // MEMReg bus
       output  wire                            MEMreg_valid,
       output  wire [`MEMReg_BUS_LEN - 1:0]    MEMreg_bus,

       output wire ertn_flush
);

// ebus
wire [15:0] ebus_init;
wire [15:0] ebus_end;

// EXreg_bus Decode
wire    [`EX2MEM_LEN - 1:0]     EX2MEM_bus;
wire    [`EX2WB_LEN - 1:0]      EX2WB_bus;
assign  {EX2MEM_bus, EX2WB_bus} = EXreg_bus;

wire    [31:0]  mul_result, EX_result, rkd_value;
wire    [4:0]   ld_ctrl;            // = {inst_ld_w, inst_ld_b, inst_ld_bu, inst_ld_h, inst_ld_hu}
wire            mul;
wire            wait_data_ok_r;
assign  {wait_data_ok_r, ebus_init, mul, mul_result, EX_result, rkd_value, ld_ctrl} = EX2MEM_bus;

wire [79:0]     csr_ctrl;
wire            res_from_csr;
wire            pause_int_detect;
wire            rf_we;
wire            res_from_mem;
wire    [4:0]   rf_waddr;
wire    [31:0]  pc;
assign  {pause_int_detect, ertn_flush, csr_ctrl, res_from_csr, rf_we, res_from_mem, rf_waddr, pc} = EX2WB_bus;

// Define Signals
wire [31:0]     data;
wire [31:0]     MEM_result, word_res, byte_res, hword_res;
wire [31:0]     MEM_final_result;
wire            is_sign_ext;
wire            recv_data_from_sram;

// MEM
assign data                 = data_sram_rdata;
assign is_sign_ext          = ~(ld_ctrl[0] | ld_ctrl[2]);
assign word_res             = data;
assign byte_res             = {32{~EX_result[1] & ~EX_result[0]}} & {{24{data[7] & is_sign_ext}}, data[7:0]}
       | {32{~EX_result[1] & EX_result[0]}} & {{24{data[15] & is_sign_ext}}, data[15:8]}
       | {32{EX_result[1] & ~EX_result[0]}} & {{24{data[23] & is_sign_ext}}, data[23:16]}
       | {32{EX_result[1] & EX_result[0]}} & {{24{data[31] & is_sign_ext}}, data[31:24]};
assign hword_res            = {32{~EX_result[1]}} & {{16{data[15] & is_sign_ext}}, data[15:0]}
       | {32{EX_result[1]}} & {{16{data[31] & is_sign_ext}}, data[31:16]};
assign MEM_result           = {32{ld_ctrl[4]}} & word_res
       | {32{ld_ctrl[3] | ld_ctrl[2]}} & byte_res
       | {32{ld_ctrl[1] | ld_ctrl[0]}} & hword_res;

// final_result
assign MEM_final_result     = mul ? mul_result :
       res_from_mem ? MEM_result :
       EX_result;

// exception
assign ebus_end = ebus_init;

// control signals
assign MEM_allow_in         = ~MEMreg_valid | WB_allow_in & MEM_ready_go;
assign MEM_ready_go         = (valid & recv_data_from_sram) ? data_sram_data_ok : 1;

// data harzard bypass
assign MEM_bypass_bus       = {pause_int_detect & MEMreg_valid, res_from_csr, rf_waddr, rf_we & valid, MEM_final_result};

// MEMreg_bus
reg     has_reset;
always @(posedge clk) begin
    if (EX_ready_go & MEM_allow_in)
        has_reset   <= 0;
    else
        if (reset)
            has_reset   <= 1;
end
assign MEMreg_valid         = valid  & ~(reset | has_reset);
assign MEMreg_bus           = {pause_int_detect, ebus_end, ertn_flush, csr_ctrl, res_from_csr, MEM_final_result, rf_we, rf_waddr, pc};

/*******************************************************************
2023.11.13 czxx
    similar to IF stage
********************************************************************/
reg [7:0] unfinish_data_cnt;
always @(posedge clk) begin
    if (reset_real)
        unfinish_data_cnt <= 0;
    else begin
        if (data_sram_req & data_sram_addr_ok & ~data_sram_data_ok)
            unfinish_data_cnt <= unfinish_data_cnt+8'b1;
        else
            if (~(data_sram_req & data_sram_addr_ok) & data_sram_data_ok)
                unfinish_data_cnt <= unfinish_data_cnt-8'b1;
    end
end
assign recv_data_from_sram = unfinish_data_cnt==8'b1;

endmodule