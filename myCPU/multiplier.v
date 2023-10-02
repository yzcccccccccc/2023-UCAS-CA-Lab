/******************************************************************
    Version 0.1:
        Using Xilinx ip
        Created By Yzcc
        2023.10.2

    Version 0.2:
        (to be continued :D)

*******************************************************************/


module multiplier(
    input   wire [31:0]     mul_src1,
    input   wire [31:0]     mul_src2,
    input   wire [2:0]      mul_op,         // 001 for mul.w, 010 for mulh.w, 100 for mulh.wu
    output  wire [31:0]     mul_res
);
    wire [63:0]     unsigned_prod, signed_prod;
    
    assign unsigned_prod    = mul_src1 * mul_src2;
    assign signed_prod      = $signed(mul_src1) * $signed(mul_src2);

    assign mul_res      = {32{mul_op[0]}} & signed_prod[31:0]
                        | {32{mul_op[1]}} & signed_prod[63:32]
                        | {32{mul_op[2]}} & unsigned_prod[63:32];

endmodule