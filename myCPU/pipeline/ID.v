`include "../macro.vh"

module ID(
           input   wire        clk,
           input   wire        reset,

           // timecnt
           input   wire [63:0] timecnt,

           // valid & IFreg_bus
           input   wire                        valid,
           input   wire [`IFReg_BUS_LEN - 1:0] IFreg_bus,

           // control sigals
           input   wire        IF_ready_go,
           input   wire        EX_allow_in,
           output  wire        ID_ready_go,
           output  wire        ID_allow_in,

           // Reg Files
           output  wire [4:0]  rf_raddr1,
           output  wire [4:0]  rf_raddr2,
           input   wire [31:0] rf_rdata1,
           input   wire [31:0] rf_rdata2,

           // Data Harzard
           input   wire        pause,
           input   wire        addr1_occur,
           input   wire        addr2_occur,
           input   wire [31:0] addr1_forward,
           input   wire [31:0] addr2_forward,

           // interupt from csr
           input   wire        has_int,

           // IDreg bus
           output  wire                        IDreg_valid,
           output  wire [`IDReg_BUS_LEN - 1:0] IDreg_bus,

           // BR bus
           output  wire [`BR_BUS_LEN - 1:0] BR_BUS
       );

// ebus
wire [15:0] ebus_init;
wire [15:0] ebus_end;
wire        has_sys;
wire        has_ine;
wire        has_brk;
wire [54:0] has_inst;

// IFreg_bus Decode
wire    [31:0]  inst, pc;
assign  {ebus_init, inst, pc}  = IFreg_bus;

// CSR
wire        res_from_csr;
wire        csr_re, csr_we;
wire [13:0] csr_num;
wire [31:0] csr_wvalue, csr_wmask;
wire [79:0] csr_ctrl;
wire        pause_int_detect;

// stable counter
wire [ 1:0] rdcntv_op;               // = {inst_rdcntvh_w,inst_rdcntvl_w}

// ertn
wire        ertn_flush;

wire        br_taken;
wire        br_cancel;
wire        br_stall;
wire [31:0] br_target;

wire [11:0] alu_op;
wire        load_op;
wire        src1_is_pc;
wire        src2_is_imm;
wire        res_from_mem;
wire        dst_is_r1;
wire        gr_we;
wire [2: 0] st_ctrl;
wire [4: 0] ld_ctrl;
wire        mem_en;
wire        src_reg_is_rd;
wire [4: 0] dest;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;

wire        rj_eq_rd;
wire        signed_rj_lt_rd;
wire        unsigned_rj_lt_rd;

wire        rf_we;
wire [4:0]  rf_waddr;

wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] op_14_10;
wire [ 4:0] op_9_5;
wire [ 4:0] op_4_0;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;
wire [31:0] op_14_10_d;
wire [31:0] op_9_5_d;
wire [31:0] op_4_0_d;

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_w;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_lu12i_w;

// User Operate Inst (exp10)
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll_w;
wire        inst_srl_w;
wire        inst_sra_w;
wire        inst_pcaddu12i;

// User Mul/Div Inst (exp10)
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_div_w;
wire        inst_mod_w;
wire        inst_div_wu;
wire        inst_mod_wu;
wire        mul, div;

// User Branch Inst (exp11)
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;

// User Load/Store Inst (exp11)
wire        inst_ld_b;
wire        inst_ld_h;
wire        inst_ld_bu;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;

wire        need_ui5;
wire        need_ui12;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

// CSR, syscall (exp12)
wire        inst_csrrd;
wire        inst_csrwr;
wire        inst_csrxchg;
wire        inst_ertn;
wire        inst_syscall;

// rdcn, break (exp13)
wire        inst_break;
wire        inst_rdcntvl_w;
wire        inst_rdcntvh_w;
wire        inst_rdcntid;

// tlbsrch, tlbrd, tlbwr, tlbfill, invtlb (exp18)
wire   inst_tlbsrch;
wire   inst_tlbrd;
wire   inst_tlbwr;
wire   inst_tlbfill;
wire   inst_invtlb;

wire [31:0] alu_src1   ;
wire [31:0] alu_src2   ;

// ID
assign op_31_26  = inst[31:26];
assign op_25_22  = inst[25:22];
assign op_21_20  = inst[21:20];
assign op_19_15  = inst[19:15];
assign op_14_10  = inst[14:10];
assign op_9_5    = inst[ 9: 5];
assign op_4_0    = inst[ 4: 0];

assign rd   = inst[ 4: 0];
assign rj   = inst[ 9: 5];
assign rk   = inst[14:10];

assign i12  = inst[21:10];
assign i20  = inst[24: 5];
assign i16  = inst[25:10];
assign i26  = {inst[ 9: 0], inst[25:10]};

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));
decoder_5_32 u_dec4(.in(op_14_10 ), .out(op_14_10_d ));
decoder_5_32 u_dec5(.in(op_9_5   ), .out(op_9_5_d   ));
decoder_5_32 u_dec6(.in(op_4_0   ), .out(op_4_0_d   ));

assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~inst[25];

// User Operate Inst (exp10)
assign inst_slti        = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui       = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi        = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori         = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori        = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_sll_w       = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w       = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w       = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_pcaddu12i   = op_31_26_d[6'h07] & ~inst[25];

// User Mul/Div Inst (exp10)
assign inst_mul_w       = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w      = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_div_w       = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mod_w       = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu      = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu      = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];

// User Branch Inst (exp11)
assign inst_blt         = op_31_26_d[6'h18];
assign inst_bge         = op_31_26_d[6'h19];
assign inst_bltu        = op_31_26_d[6'h1a];
assign inst_bgeu        = op_31_26_d[6'h1b];

// User Load/Store Inst (exp11)
assign inst_ld_b        = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h        = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_st_b        = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h        = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_ld_bu       = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu       = op_31_26_d[6'h0a] & op_25_22_d[4'h9];

// CSR, syscall and break (exp12)
assign inst_csrrd       = op_31_26_d[6'h01] & ~(|op_25_22[3:2]) & (rj == 5'b0);
assign inst_csrwr       = op_31_26_d[6'h01] & ~(|op_25_22[3:2]) & (rj == 5'b1);
assign inst_csrxchg     = op_31_26_d[6'h01] & ~(|op_25_22[3:2]) & (|rj[4:1]);
assign inst_syscall     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h16];
assign inst_ertn        = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'h0e) & ~(|rj) & ~(|rd);

// rdcn, break (exp13)
assign inst_break       = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h14];
assign inst_rdcntvl_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & op_14_10_d[5'h18] & op_9_5_d[5'h00];
assign inst_rdcntvh_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & op_14_10_d[5'h19] & op_9_5_d[5'h00];
assign inst_rdcntid     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & op_14_10_d[5'h18] & op_4_0_d[5'h00];

// TLB instructions (exp18)
assign inst_tlbsrch  = op_31_26_d[6'd01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & op_14_10_d[5'h0a];
assign inst_tlbrd    = op_31_26_d[6'd01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & op_14_10_d[5'h0b];
assign inst_tlbwr    = op_31_26_d[6'd01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & op_14_10_d[5'h0c];
assign inst_tlbfill  = op_31_26_d[6'd01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & op_14_10_d[5'h0d];
assign inst_invtlb   = op_31_26_d[6'd01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h13 ];

/***************************************************************************
    alu_op[2:0] is also used as mul_op,
    alu_op[3:0] is also used as div_op
****************************************************************************/
assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
       | inst_jirl | inst_bl | inst_pcaddu12i | inst_mul_w
       | inst_div_w | inst_ld_b | inst_ld_bu | inst_ld_h
       | inst_ld_hu | inst_st_b | inst_st_h;
assign alu_op[ 1] = inst_sub_w | inst_mulh_w | inst_div_wu;
assign alu_op[ 2] = inst_slt | inst_slti | inst_mulh_wu | inst_mod_w;
assign alu_op[ 3] = inst_sltu | inst_sltui | inst_mod_wu;
assign alu_op[ 4] = inst_and | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or | inst_ori;
assign alu_op[ 7] = inst_xor | inst_xori;
assign alu_op[ 8] = inst_slli_w | inst_sll_w;
assign alu_op[ 9] = inst_srli_w | inst_srl_w;
assign alu_op[10] = inst_srai_w | inst_sra_w;
assign alu_op[11] = inst_lu12i_w;

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_ui12  =  inst_andi   | inst_ori    | inst_xori;
assign need_si12  =  inst_addi_w | inst_ld_w | inst_st_w | inst_slti | inst_sltui
       | inst_ld_b | inst_ld_bu | inst_ld_h | inst_ld_hu | inst_st_b | inst_st_h;
assign need_si16  =  inst_jirl | inst_beq | inst_bne;
assign need_si20  =  inst_lu12i_w | inst_pcaddu12i;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;

assign imm =    {32{src2_is_4}} & {32'h4}
       |   {32{need_si20}} & {i20[19:0], 12'b0}
       |   {32{need_si12}} & {{20{i12[11]}}, i12[11:0]}
       |   {32{need_ui5}} & {27'b0, rk[4:0]}
       |   {32{need_ui12}} & {20'b0, i12[11:0]};

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
       {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w | inst_blt | inst_bltu | inst_bge | inst_bgeu
       | inst_st_b | inst_st_h | inst_csrwr | inst_csrxchg;

assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;

assign src2_is_imm   = inst_slli_w |
       inst_srli_w |
       inst_srai_w |
       inst_addi_w |
       inst_ld_w   |
       inst_st_w   |
       inst_lu12i_w|
       inst_jirl   |
       inst_bl     |
       inst_slti   |
       inst_sltui  |
       inst_andi   |
       inst_ori    |
       inst_xori   |
       inst_pcaddu12i |
       inst_ld_b | inst_ld_bu | inst_ld_h | inst_ld_hu |
       inst_st_h | inst_st_b;

assign res_from_mem  = inst_ld_w | inst_ld_b | inst_ld_bu | inst_ld_h | inst_ld_hu;
assign dst_is_r1     = inst_bl;
assign gr_we         = ~inst_st_w         & ~inst_st_b  & ~inst_st_h
                     & ~inst_beq          & ~inst_bne   & ~inst_b            & ~inst_blt          & ~inst_bge 
                     & ~inst_bltu         & ~inst_bgeu  & ~inst_ertn         & ~inst_syscall      & ~inst_break
                     & ~inst_tlbfill      & ~inst_tlbrd & ~inst_tlbsrch      & ~inst_tlbwr        & ~inst_invtlb;
assign st_ctrl  = {inst_st_w, inst_st_h, inst_st_b};
assign ld_ctrl  = {inst_ld_w, inst_ld_b, inst_ld_bu, inst_ld_h, inst_ld_hu};
assign mem_en        = res_from_mem | inst_st_w | inst_st_h | inst_st_b;
assign mul      = inst_mul_w | inst_mulh_w | inst_mulh_wu;
assign div      = inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu;

assign dest          = dst_is_r1 ? 5'd1 : 
                       inst_rdcntid ? rj :
                       rd;

assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd :rk;

assign rj_value  = addr1_occur? addr1_forward : rf_rdata1;
assign rkd_value = addr2_occur? addr2_forward : rf_rdata2;

assign rj_eq_rd             = (rj_value == rkd_value);
assign signed_rj_lt_rd      = ($signed(rj_value) < $signed(rkd_value));
assign unsigned_rj_lt_rd    = (rj_value < rkd_value);

wire   type_bj;
assign type_bj       = inst_beq | inst_b | inst_bge | inst_bgeu | inst_bl | inst_blt | inst_bltu
                     | inst_bne | inst_jirl;
assign br_taken      = (   inst_beq  &&  rj_eq_rd
                      || inst_bne  && !rj_eq_rd
                      || inst_blt && signed_rj_lt_rd
                      || inst_bge && !signed_rj_lt_rd
                      || inst_bltu && unsigned_rj_lt_rd
                      || inst_bgeu && !unsigned_rj_lt_rd
                      || inst_jirl
                      || inst_bl
                      || inst_b
                     ) && valid && ~br_stall;
assign br_target     = (inst_beq || inst_bne || inst_bl || inst_b || inst_blt || inst_bltu || inst_bge || inst_bgeu) ? (pc + br_offs) :
                            /*inst_jirl*/ (rj_value + jirl_offs);
assign br_cancel     = br_taken;
assign br_stall      = pause & type_bj;

/*****************************************************************
        alu_src1 is also used as mul_src1 and div_src1
        alu_src2 is also used as mul_src2 and div_src2
*****************************************************************/
assign alu_src1 = src1_is_pc  ? pc[31:0] : rj_value;
assign alu_src2 = src2_is_imm ? imm : rkd_value;

assign rf_we    = gr_we && valid;
assign rf_waddr = dest;

// CSR
assign csr_num      = inst_rdcntid ? `CSR_TID : inst[23:10];
assign csr_re       = inst_csrrd | inst_csrxchg | inst_csrwr | inst_rdcntid;
assign csr_we       = inst_csrwr | inst_csrxchg;
assign csr_wvalue   = rkd_value;
assign csr_wmask    = inst_csrxchg ? rj_value : {32{1'b1}};
assign csr_ctrl = {csr_num, csr_re, csr_we, csr_wvalue, csr_wmask};
assign res_from_csr = inst_csrrd | inst_csrxchg | inst_csrwr | inst_rdcntid;
assign pause_int_detect = csr_we & (csr_num==`CSR_CRMD & csr_wmask[`CSR_CRMD_IE]
                                   |csr_num==`CSR_ECFG & |(csr_wmask[`CSR_ECFG_LIE]&13'h1bff)
                                   |csr_num==`CSR_ESTAT & |csr_wmask[`CSR_ESTAT_IS10]
                                   |csr_num==`CSR_TCFG & csr_wmask[`CSR_TCFG_EN]
                                   |csr_num==`CSR_TICLR & csr_wmask[`CSR_TICLR_CLR]);

// time counter
assign rdcntv_op = {inst_rdcntvh_w, inst_rdcntvl_w};

// exception
assign has_sys = inst_syscall;
assign ebus_end = (has_int & valid) ? {{15-`EBUS_INT{1'b0}}, has_int, {`EBUS_INT{1'b0}}}
              : (|ebus_init) ? ebus_init
              : ({{15-`EBUS_SYS{1'b0}}, has_sys, {`EBUS_SYS{1'b0}}}
              | {{15-`EBUS_INE{1'b0}}, has_ine, {`EBUS_INE{1'b0}}}
              | {{15-`EBUS_BRK{1'b0}}, has_brk, {`EBUS_BRK{1'b0}}});
assign ertn_flush = inst_ertn;

// exp13 ine
// [hint] add new instruction to this
assign has_inst = {inst_rdcntid, inst_rdcntvh_w, inst_rdcntvl_w, inst_break,
                   inst_ertn, inst_syscall, inst_csrxchg, inst_csrwr, inst_csrrd,
                   inst_ld_hu, inst_ld_bu, inst_st_h, inst_st_b, inst_ld_h, inst_ld_b,
                   inst_bgeu, inst_bltu, inst_bge, inst_blt,
                   inst_mod_wu, inst_div_wu, inst_mod_w, inst_div_w, inst_mulh_wu, inst_mulh_w, inst_mul_w,
                   inst_pcaddu12i, inst_sra_w, inst_srl_w, inst_sll_w,
                   inst_xori, inst_ori, inst_andi, inst_sltui, inst_slti,
                   inst_lu12i_w, inst_bne, inst_beq, inst_bl, inst_b, inst_jirl,
                   inst_st_w, inst_ld_w, inst_addi_w, inst_srai_w, inst_srli_w, inst_slli_w,
                   inst_xor, inst_or, inst_and, inst_nor, inst_sltu, inst_slt, inst_sub_w, inst_add_w};
assign has_ine = ~(|has_inst);

// exp13 brk
assign has_brk = inst_break;

// IDreg_bus
wire    [`ID2EX_LEN - 1:0]  IDreg_2EX;
wire    [`ID2MEM_LEN - 1:0] IDreg_2MEM;
wire    [`ID2WB_LEN - 1:0]  IDreg_2WB;

assign IDreg_valid      = valid;
assign IDreg_2EX        = {rdcntv_op, ebus_end, alu_op, alu_src1, alu_src2, mul, div};
assign IDreg_2MEM       = {rkd_value, mem_en, st_ctrl, ld_ctrl};
assign IDreg_2WB        = {pause_int_detect, ertn_flush, csr_ctrl, res_from_csr, rf_we, res_from_mem, rf_waddr, pc};

assign IDreg_bus        = {IDreg_2EX, IDreg_2MEM, IDreg_2WB};

// control signals
assign ID_ready_go      = ~pause;
assign ID_allow_in      = ~IDreg_valid | EX_allow_in & ID_ready_go;

// BR_BUS
// br_taken_last is used to ensure that br_taken only duration 1 clock
reg br_taken_last;
always@(posedge clk)
begin
    if(reset)
       br_taken_last <= 1'b0;
    else
       br_taken_last <= br_taken;
end
assign BR_BUS       = {br_target, br_taken & ~br_taken_last, br_stall};

endmodule