/*******************************************************************
    TLB based on LoongArch32
    Authored by yzcc, 2023.11.27

TLB format:
1) comparing part
    |       VPPN        |   PS  |   G   |   ASID    |   E   |
    35                  18      12      11          1       0

    E:      1 bit, mark the existence of the PTE
    ASID:   10 bits, kinda like pid?
    G:      1 bit, global, set to 1 to avoid checking ASID
    PS:     6 bits, size. In LA32, only 4MB and 4KB are available, so
            it's either 12 or 22
    VPPN:   18 bits (if VALEN = 32), one PTE manages 2 virtual pages,
            VPPN = VPN / 2.

2) converting part
    |       PPN0        |   PLV0    |   MAT0    |   D0  |   V0  |
    |       PPN1        |   PLV1    |   MAT1    |   D1  |   V1  |
    25                  6           4           2       1       0

    V:      1 bit. valid. 1 stands for valid and accessed
    D:      1 bit. dirty. 1 stands for existing dirty data within
            the page.
    MAT:    2 bits. Acceess type 
            (0: Coherent Cached, 1: Strongly-ordered Uncached, 
            2/3: reserved)
    PLV:    2 bits. Privilege. This page can be accessed with
            privilege not lower than PLV
    PPN:    physical page num
*******************************************************************/
module tlb
#(
    parameter TLBNUM = 16
)
(
    input   wire            clk,

    // Port 0 (For Fetch)
    input   wire [18:0]                 s0_vppn,
    input   wire                        s0_va_bit12,
    input   wire [9:0]                  s0_asid,
    output  wire                        s0_found,
    output  wire [$clog2(TLBNUM) - 1:0] s0_index,
    output  wire [19:0]                 s0_ppn,
    output  wire [5:0]                  s0_ps,
    output  wire [1:0]                  s0_plv,
    output  wire [1:0]                  s0_mat,
    output  wire                        s0_d,
    output  wire                        s0_v,

    // Port 1 (For Load/Store/invtlb)
    input   wire [18:0]                 s1_vppn,
    input   wire                        s1_va_bit12,
    input   wire [9:0]                  s1_asid,
    output  wire                        s1_found,
    output  wire [$clog2(TLBNUM)-1:0]   s1_index,
    output  wire [19:0]                 s1_ppn,
    output  wire [5:0]                  s1_ps,
    output  wire [1:0]                  s1_plv,
    output  wire [1:0]                  s1_mat,
    output  wire                        s1_d,
    output  wire                        s1_v,
    input   wire                        invtlb_valid,        // INVTLB opcode
    input   wire [4:0]                  invtlb_op,

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
reg [TLBNUM - 1:0]  tlb_ps4MB;                          // 0 for 4KB, 1 for 4MB
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

genvar  i;

//--------------------------- TLB Look-up ---------------------------
    wire [TLBNUM - 1:0]     match0, match1;
    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin : Look_up_wire_gen
            assign match0[i]    = (s0_vppn[18:10] == tlb_vppn[i][18:10])
                                && (tlb_ps4MB[i] || s0_vppn[9:0] == tlb_vppn[i][9:0])           // 4MB only has to check the high 9 bits
                                && (tlb_g[i] || s0_asid == tlb_asid[i]);
            assign match1[i]    = (s1_vppn[18:10] == tlb_vppn[i][18:10])
                                && (tlb_ps4MB[i] || s1_vppn[9:0] == tlb_vppn[i][9:0])
                                && (tlb_g[i] || s1_asid == tlb_asid[i]);
        end
    endgenerate

    assign s0_found = |match0;
    assign s1_found = |match1;

    assign s0_index = {4{match0[0]}} & 4'd0     | {4{match0[1]}} & 4'd1     | {4{match0[2]}} & 4'd2     | {4{match0[3]}} & 4'd3
                    | {4{match0[4]}} & 4'd4     | {4{match0[5]}} & 4'd5     | {4{match0[6]}} & 4'd6     | {4{match0[7]}} & 4'd7
                    | {4{match0[8]}} & 4'd8     | {4{match0[9]}} & 4'd9     | {4{match0[10]}} & 4'd10   | {4{match0[11]}} & 4'd11
                    | {4{match0[12]}} & 4'd12   | {4{match0[13]}} & 4'd13   | {4{match0[14]}} & 4'd14   | {4{match0[15]}} & 4'd15;
    assign s1_index = {4{match1[0]}} & 4'd0     | {4{match1[1]}} & 4'd1     | {4{match1[2]}} & 4'd2     | {4{match1[3]}} & 4'd3
                    | {4{match1[4]}} & 4'd4     | {4{match1[5]}} & 4'd5     | {4{match1[6]}} & 4'd6     | {4{match1[7]}} & 4'd7
                    | {4{match1[8]}} & 4'd8     | {4{match1[9]}} & 4'd9     | {4{match1[10]}} & 4'd10   | {4{match1[11]}} & 4'd11
                    | {4{match1[12]}} & 4'd12   | {4{match1[13]}} & 4'd13   | {4{match1[14]}} & 4'd14   | {4{match1[15]}} & 4'd15;

    wire    s0_page_dec_bit, s1_page_dec_bit;              // 0 for even page, 1 for odd page
    assign s0_page_dec_bit  = tlb_ps4MB[s0_index] ? s0_vppn[9] : s0_va_bit12;               // 4KB and 4MB are different at the position of the bit
    assign s1_page_dec_bit  = tlb_ps4MB[s1_index] ? s1_vppn[9] : s1_va_bit12;

    assign s0_ppn   = s0_page_dec_bit ? tlb_ppn1[s0_index] : tlb_ppn0[s0_index];
    assign s0_plv   = s0_page_dec_bit ? tlb_plv1[s0_index] : tlb_plv0[s0_index];
    assign s0_mat   = s0_page_dec_bit ? tlb_mat1[s0_index] : tlb_mat0[s0_index];
    assign s0_d     = s0_page_dec_bit ? tlb_d1[s0_index] : tlb_d0[s0_index];
    assign s0_v     = s0_page_dec_bit ? tlb_v1[s0_index] : tlb_v0[s0_index];
    assign s0_ps    = tlb_ps4MB[s0_index] ? 6'd22 : 6'd12;

    assign s1_ppn   = s1_page_dec_bit ? tlb_ppn1[s1_index] : tlb_ppn0[s1_index];
    assign s1_plv   = s1_page_dec_bit ? tlb_plv1[s1_index] : tlb_plv0[s1_index];
    assign s1_mat   = s1_page_dec_bit ? tlb_mat1[s1_index] : tlb_mat0[s1_index];
    assign s1_d     = s1_page_dec_bit ? tlb_d1[s1_index] : tlb_d0[s1_index];
    assign s1_v     = s1_page_dec_bit ? tlb_v1[s1_index] : tlb_v0[s1_index];
    assign s1_ps    = tlb_ps4MB[s1_index] ? 6'd22 : 6'd12;

//--------------------------- TLB Read ---------------------------
    assign r_vppn   = tlb_vppn[r_index];
    assign r_e      = tlb_e[r_index];
    assign r_ps     = tlb_ps4MB[r_index] ? 6'd22 : 6'd12;
    assign r_asid   = tlb_asid[r_index];
    assign r_g      = tlb_g[r_index];

    assign r_ppn0   = tlb_ppn0[r_index];
    assign r_plv0   = tlb_plv0[r_index];
    assign r_mat0   = tlb_mat0[r_index];
    assign r_d0     = tlb_d0[r_index];
    assign r_v0     = tlb_v0[r_index];

    assign r_ppn1   = tlb_ppn1[r_index];
    assign r_plv1   = tlb_plv1[r_index];
    assign r_mat1   = tlb_mat1[r_index];
    assign r_d1     = tlb_d1[r_index];
    assign r_v1     = tlb_v1[r_index];

//--------------------------- INVTLB ---------------------------
    wire [TLBNUM - 1:0] cond1, cond2, cond3, cond4;                 // cond1: G=0, cond2: G=1, cond3:asid=given asid, cond4:vppn=given vppn and ps
    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin : cond_wire_gen
            assign cond1[i] = ~tlb_g[i];
            assign cond2[i] = tlb_g[i];
            assign cond3[i] = tlb_asid[i] == s1_asid;
            assign cond4[i] = (s1_vppn[18:10] == tlb_vppn[i][18:10])
                            && (tlb_ps4MB[i] || s1_vppn[9:0] == tlb_vppn[i][9:0]);
        end
    endgenerate

    wire [TLBNUM - 1:0] mask;
    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin : mask_wire_gen
            assign mask[i]  = (invtlb_op == 5'd0 || invtlb_op == 5'd1) & (cond1[i] || cond2[i])
                            | (invtlb_op == 5'd2) & (cond2[i])
                            | (invtlb_op == 5'd3) & (cond1[i])
                            | (invtlb_op == 5'd4) & (cond1[i] && cond3[i])
                            | (invtlb_op == 5'd5) & (cond1[i] && cond3[i] && cond4[i])
                            | (invtlb_op == 5'd6) & ((cond2[i] || cond3[i]) && cond4[i]);
        end
    endgenerate

//--------------------------- TLB Write ---------------------------
    always @(posedge clk) begin
        if (we) begin
            tlb_e[w_index]      <= w_e;
            tlb_vppn[w_index]   <= w_vppn;
            tlb_ps4MB[w_index]  <= (w_ps == 6'd22) ? 1 : 0;
            tlb_asid[w_index]   <= w_asid;
            tlb_g[w_index]      <= w_g;

            tlb_ppn0[w_index]   <= w_ppn0;
            tlb_plv0[w_index]   <= w_plv0;
            tlb_mat0[w_index]   <= w_mat0;
            tlb_d0[w_index]     <= w_d0;
            tlb_v0[w_index]     <= w_v0;
            
            tlb_ppn1[w_index]   <= w_ppn1;
            tlb_plv1[w_index]   <= w_plv1;
            tlb_mat1[w_index]   <= w_mat1;
            tlb_d1[w_index]     <= w_d1;
            tlb_v1[w_index]     <= w_v1;
        end
        if (invtlb_valid)
            tlb_e               <= tlb_e & ~mask;
    end

endmodule