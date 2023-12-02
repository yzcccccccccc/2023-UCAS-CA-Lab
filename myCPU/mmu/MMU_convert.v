/***************************************************
    MMU address convertor
    Authored by yzcc, 2023.11.30
    Description:
        Given virtual address, return the physical
    address or exception info.
****************************************************/
`include "../macro.vh"
module MMU_convert(
    input   wire        en,                 // enable
    input   wire [2:0]  ope_type,           // {Fetch, Load, Store}

    input   wire [31:0] va,
    input   wire [31:0] csr_crmd,
    input   wire [31:0] csr_dmw0,
    input   wire [31:0] csr_dmw1,

    // TLB port
    input   wire                            s_found,
    input   wire [$clog2(`TLBNUM)-1:0]      s_index,
    input   wire [19:0]                     s_ppn,
    input   wire [5:0]                      s_ps,
    input   wire [1:0]                      s_plv,
    input   wire [1:0]                      s_mat,
    input   wire                            s_d,
    input   wire                            s_v,

    output  wire        has_mem_except,
    output  wire [5:0]  except,             //  {PIL, PIS, PIF, PME, PPI, TLBR}
    output  wire [31:0] pa,
    output  wire [1:0]  mat
);

// CSR
wire    [1:0]       crmd_plv;
wire                crmd_da, crmd_pg;
assign  crmd_plv    = csr_crmd[`CSR_CRMD_PLV];
assign  crmd_da     = csr_crmd[`CSR_CRMD_DA];
assign  crmd_pg     = csr_crmd[`CSR_CRMD_PG];

wire                dmw0_plv0, dmw0_plv3;
wire    [2:0]       dmw0_pseg, dmw0_vseg;
wire                dmw1_plv0, dmw1_plv3;
wire    [2:0]       dmw1_pseg, dmw1_vseg;
wire    [1:0]       dmw0_mat;
wire    [1:0]       dmw1_mat;
assign  dmw0_plv0   = csr_dmw0[`CSR_DMW_PLV0];
assign  dmw0_plv3   = csr_dmw0[`CSR_DMW_PLV3];
assign  dmw0_mat    = csr_dmw0[`CSR_DMW_MAT];
assign  dmw0_pseg   = csr_dmw0[`CSR_DMW_PSEG];
assign  dmw0_vseg   = csr_dmw0[`CSR_DMW_VSEG];
assign  dmw1_plv0   = csr_dmw1[`CSR_DMW_PLV0];
assign  dmw1_plv3   = csr_dmw1[`CSR_DMW_PLV3];
assign  dmw1_mat    = csr_dmw1[`CSR_DMW_MAT];
assign  dmw1_pseg   = csr_dmw1[`CSR_DMW_PSEG];
assign  dmw1_vseg   = csr_dmw1[`CSR_DMW_VSEG];

// type
wire    type_fetch, type_load, type_store;
assign  {type_fetch, type_load, type_store}     = ope_type;

//------------------------ Exceptions ------------------------
wire    plv_cmp;
assign  plv_cmp     = $unsigned(crmd_plv) > $unsigned(s_plv);

wire    has_PIL, has_PIS, has_PIF, has_PME, has_PPI, has_TLBR;
assign  has_TLBR    = en & ~s_found;
assign  has_PIF     = en & s_found & ~s_v & type_fetch;
assign  has_PIL     = en & s_found & ~s_v & type_load;
assign  has_PIS     = en & s_found & ~s_v & type_store;
assign  has_PPI     = en & s_found & s_v & plv_cmp;
assign  has_PME     = en & s_found & s_v & ~plv_cmp & type_store & ~s_d;

//------------------------ Direct Map Window ------------------------
wire            in_dmw0, in_dmw1, dmw_hit;
wire    [31:0]  dmw0_addr, dmw1_addr;

assign  in_dmw0     = (va[31:29] == dmw0_vseg) & (dmw0_plv0 & (crmd_plv == 2'd0) | dmw0_plv3 & (crmd_plv == 2'd3));
assign  in_dmw1     = (va[31:29] == dmw1_vseg) & (dmw1_plv0 & (crmd_plv == 2'd0) | dmw1_plv3 & (crmd_plv == 2'd3));
assign  dmw0_addr   = {dmw0_pseg, va[28:0]};
assign  dmw1_addr   = {dmw1_pseg, va[28:0]};
assign  dmw_hit     = in_dmw0 | in_dmw1;


//------------------------ Translation ------------------------
wire            page_size;                      // 1 for 4MB, 0 for 4KB (22bit vs 12bit)
wire    [31:0]  TLBMAP_pa, DIRMAP_pa, DIR_pa;   // TLB map pa, Directly map pa, Direct pa

assign  page_size   = (s_ps == 6'd21);
assign  TLBMAP_pa   = page_size ? {s_ppn[19:10], va[21:0]} : {s_ppn, va[11:0]};
assign  DIRMAP_pa   = {32{in_dmw0}} & dmw0_addr
                    | {32{in_dmw1}} & dmw1_addr;
assign  DIR_pa      = va;

wire    [1:0]   TLBMAP_mat, DIRMAP_mat, DIR_mat;
assign  TLBMAP_mat  = s_mat;
assign  DIRMAP_mat  = {2{in_dmw0}} & dmw0_mat
                    | {2{in_dmw1}} & dmw1_mat;
assign  DIR_mat     = 2'b00;

//------------------------ Output ------------------------
wire            use_TLBMAP, use_DIRMAP, use_DIR;
assign  use_TLBMAP  = ~crmd_da & crmd_pg & ~dmw_hit;
assign  use_DIRMAP  = ~crmd_da & crmd_pg & dmw_hit;
assign  use_DIR     = crmd_da & ~crmd_pg;

assign  except      = {has_PIL, has_PIS, has_PIF, has_PME, has_PPI, has_TLBR} & {6{use_TLBMAP & en}};
assign  pa          = {32{use_TLBMAP}} & TLBMAP_pa
                    | {32{use_DIRMAP}} & DIRMAP_pa
                    | {32{use_DIR}} & DIR_pa;
assign  mat         = {2{use_TLBMAP}} & TLBMAP_mat
                    | {2{use_DIRMAP}} & DIRMAP_mat
                    | {2{use_DIR}} & DIR_mat;
assign  has_mem_except  = |except;

endmodule