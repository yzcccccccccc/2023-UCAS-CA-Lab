module tlb
#(
    parameter TLBNUM = 16
)
(
    input   wire            clk,

    // Port 0 (For Fetch)
    input   wire [18:0]                 s0_vppn,
    input   wire                        s0_va_vit12,
    input   wire [9:0]                  s0_asid,
    output  wire                        s0_found,
    output  wire [$clog2(TLBNUM) - 1:0] s0_index,
    output  wire [19:0]                 s0_ppn,
    output  wire [5:0]                  s0_ps,
    output  wire [1:0]                  s0_plv,
    output  wire [1:0]                  s0_mat,
    output  wire                        s0_d,
    output  wire                        s0_v,

    // Port 1 (For Load/Store)
    input   wire [18:0]                 s1_vppn,
    input   wire                        s1_va_vit12,
    input   wire [9:0]                  s1_asid,
    output  wire                        s1_found,
    output  wire [$clog2(TLBNUM - 1):0] s1_index,
    output  wire [19:0]                 s1_ppn,
    output  wire [5:0]                  s1_ps,
    output  wire [1:0]                  s1_plv,
    output  wire [1:0]                  s1_mat,
    output  wire                        s1_d,
    output  wire                        s1_v,

    // InvTLB opcode
    input   wire                        invtlv_valid,
    input   wire [4:0]                  invtlv_op,

    // Write Port
    input   wire                        we,
    input   wire [$clog2(TLBNUM) - 1:0] w_index,
    input   wire                        w_e,
    input   wire [18:0]                 w_vppn,
    input   wire [5:0]                  w_ps,
    input   wire [9:0]                  w_asid,
    input   wire                        w_g,
    input   wire [19:0]                 w_ppn0,
    input   wire [1:0]                  w_plv0,
    input   wire [1:0]                  w_mat0,
    input   wire                        w_d0,
    input   wire                        w_v0,
    input   wire [19:0]                 w_ppn1,
    input   wire [1:0]                  w_plv1,
    input   wire [1:0]                  w_mat1,
    input   wire                        w_d1,
    input   wire                        w_v1,

    // Read Port
    input   wire [$clog2(TLBNUM) - 1:0] r_index,
    output  wire                        r_e,
    output  wire [18:0]                 r_vppn,
    output  wire [5:0]                  r_ps,
    output  wire [9:0]                  r_asid,
    output  wire                        r_g,
    output  wire [19:0]                 r_ppn0,
    output  wire [1:0]                  r_plv0,
    output  wire [1:0]                  r_mat0,
    output  wire                        r_d0,
    output  wire                        r_v0,
    output  wire [19:0]                 r_ppn1,
    output  wire [1:0]                  r_plv1,
    output  wire [1:0]                  r_mat1,
    output  wire                        r_d1,
    output  wire                        r_v1
);

reg [TLBNUM - 1:0]  tlb_e;
reg [TLBNUM - 1:0]  tlb_ps4MB;
reg [18:0]          tlb_vppn    [TLBNUM - 1:0];
reg [9:0]           tlb_asid    [TLBNUM - 1:0];
reg                 tlb_g       [TLBNUM - 1:0];
reg [19:0]          tlb_ppn0    [TLBNUM - 1:0];
reg [1:0]           tlb_plv0    [TLBNUM - 1:0];
reg [1:0]           tlb_mat0    [TLBNUM - 1:0];
reg                 tlb_d0      [TLBNUM - 1:0];
reg                 tlb_v0      [TLBNUM - 1:0];
reg [19:0]          tlb_ppn1    [TLBNUM - 1:0];
reg [1:0]           tlb_plv1    [TLBNUM - 1:0];
reg [1:0]           tlb_mat1    [TLBNUM - 1:0];
reg                 tlb_d1      [TLBNUM - 1:0];
reg                 tlb_v1      [TLBNUM - 1:0];

endmodule