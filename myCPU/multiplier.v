/******************************************************************
    Version 0.1:
        Using Xilinx ip
        Created By Yzcc
        2023.10.2
 
    Version 0.2:
        RTL ver multiplier
        Created By Czxx
        2023.10.16
 
*******************************************************************/

`timescale 1ns / 1ps

module booth(
           input [2:0] y_near,
           input [33:0] x_complement,
           output [33:0] partial_product,
           output carry
       );

wire S_posX = ~y_near[2]&&~y_near[1]&&y_near[0] || ~y_near[2]&&y_near[1]&&~y_near[0];
wire S_pos2X = ~y_near[2]&&y_near[1]&&y_near[0];
wire S_negX = y_near[2]&&~y_near[1]&&y_near[0] || y_near[2]&&y_near[1]&&~y_near[0];
wire S_neg2X = y_near[2]&&~y_near[1]&&~y_near[0];

assign carry = S_negX||S_neg2X;

wire [33:0] x_complement_reverse = ~x_complement;

assign partial_product = {34{S_posX}}&x_complement
       |{34{S_pos2X}}&{x_complement[32:0],1'b0}
       |{34{S_negX}}&x_complement_reverse
       |{34{S_neg2X}}&{x_complement_reverse[32:0],1'b1};

endmodule

    module wallace(
        input clk,
        input [16:0] N_array,
        input [14:0] Cin_array,
        output S,
        output C,
        output [14:0] Cout_array
    );

wire [16:0] N_array_f1;
wire [11:0] N_array_f2;
wire [7:0] N_array_f3;
wire [5:0] N_array_f4;
wire [3:0] N_array_f5;
wire [2:0] N_array_f6;

reg [5:0] N_array_f4_reg;
always @(posedge clk)
begin
    N_array_f4_reg <= N_array_f4;
end

assign N_array_f1 = N_array;
assign {Cout_array[0],N_array_f2[0]} = N_array_f1[0]+N_array_f1[1]+N_array_f1[2];
assign {Cout_array[1],N_array_f2[1]} = N_array_f1[3]+N_array_f1[4]+N_array_f1[5];
assign {Cout_array[2],N_array_f2[2]} = N_array_f1[6]+N_array_f1[7]+N_array_f1[8];
assign {Cout_array[3],N_array_f2[3]} = N_array_f1[9]+N_array_f1[10]+N_array_f1[11];
assign {Cout_array[4],N_array_f2[4]} = N_array_f1[12]+N_array_f1[13]+N_array_f1[14];
assign {Cout_array[14],N_array_f2[5]} = N_array_f1[15]+N_array_f1[16];

assign N_array_f2[10:6] = Cin_array[4:0];
assign N_array_f2[11] = Cin_array[14];
assign {Cout_array[5],N_array_f3[0]} = N_array_f2[0]+N_array_f2[1]+N_array_f2[2];
assign {Cout_array[6],N_array_f3[1]} = N_array_f2[3]+N_array_f2[4]+N_array_f2[5];
assign {Cout_array[7],N_array_f3[2]} = N_array_f2[6]+N_array_f2[7]+N_array_f2[8];
assign {Cout_array[8],N_array_f3[3]} = N_array_f2[9]+N_array_f2[10]+N_array_f2[11];

assign N_array_f3[7:4] = Cin_array[8:5];
assign {Cout_array[9],N_array_f4[0]} = N_array_f3[0]+N_array_f3[1]+N_array_f3[2];
assign {Cout_array[10],N_array_f4[1]} = N_array_f3[3]+N_array_f3[4]+N_array_f3[5];

assign N_array_f4[3:2] = N_array_f3[7:6];
assign N_array_f4[5:4] = Cin_array[10:9];

assign {Cout_array[11],N_array_f5[0]} = N_array_f4_reg[0]+N_array_f4_reg[1]+N_array_f4_reg[2];
assign {Cout_array[12],N_array_f5[1]} = N_array_f4_reg[3]+N_array_f4_reg[4]+N_array_f4_reg[5];

assign N_array_f5[3:2] = Cin_array[12:11];
assign {Cout_array[13],N_array_f6[0]} = N_array_f5[0]+N_array_f5[1]+N_array_f5[2];

assign N_array_f6[1] = N_array_f5[3];
assign N_array_f6[2] = Cin_array[13];
assign {C,S} = N_array_f6[0]+N_array_f6[1]+N_array_f6[2];

endmodule

    module multiplier_signed_34bits(
        input clk,
        input [33:0] x_complement,
        input [33:0] y_complement,
        output [67:0] mul_result
    );

wire [67:0] partial_products[16:0];
wire [16:0] partial_products_t[67:0];
wire [16:0] carries;
wire [34:0] y_complement_extended = {y_complement,1'b0};
wire [14:0] Cin_arrays[67:0];
wire [67:0] Add_src1;
wire [68:0] Add_src2;
reg [16:0] carries_reg;

always @(posedge clk)
begin
    carries_reg <= carries;
end

generate
    for(genvar i=0; i<17; i=i+1)
    begin : booth_gen
        wire [33:0] partial_product;
        booth booth(
                  .y_near(y_complement_extended[2*i+2:2*i]),
                  .x_complement(x_complement),
                  .partial_product(partial_product),
                  .carry(carries[i])
              );
        assign partial_products[i] = {{(34-2*i){partial_product[33]}},partial_product,{(2*i){carries[i]}}};
    end
endgenerate

wire [67:0] partial_products_0 = partial_products[0];
wire [67:0] partial_products_1 = partial_products[1];
wire [67:0] partial_products_2 = partial_products[2];
wire [67:0] partial_products_3 = partial_products[3];
wire [67:0] partial_products_4 = partial_products[4];
wire [67:0] partial_products_5 = partial_products[5];
wire [67:0] partial_products_6 = partial_products[6];
wire [67:0] partial_products_7 = partial_products[7];
wire [67:0] partial_products_8 = partial_products[8];
wire [67:0] partial_products_9 = partial_products[9];
wire [67:0] partial_products_10 = partial_products[10];
wire [67:0] partial_products_11 = partial_products[11];
wire [67:0] partial_products_12 = partial_products[12];
wire [67:0] partial_products_13 = partial_products[13];
wire [67:0] partial_products_14 = partial_products[14];
wire [67:0] partial_products_15 = partial_products[15];
wire [67:0] partial_products_16 = partial_products[16];

generate
    for (genvar j=0; j<68; j=j+1)
    begin : partial_products_t_init
        assign partial_products_t[j] = {partial_products_0[j],
                                        partial_products_1[j],
                                        partial_products_2[j],
                                        partial_products_3[j],
                                        partial_products_4[j],
                                        partial_products_5[j],
                                        partial_products_6[j],
                                        partial_products_7[j],
                                        partial_products_8[j],
                                        partial_products_9[j],
                                        partial_products_10[j],
                                        partial_products_11[j],
                                        partial_products_12[j],
                                        partial_products_13[j],
                                        partial_products_14[j],
                                        partial_products_15[j],
                                        partial_products_16[j]
                                       };
    end
endgenerate

assign Cin_arrays[0] = {carries[14],carries_reg[13:11],carries[10:0]};

generate
    for (genvar k=0; k<68; k=k+1)
    begin : wallace_gen
        wallace wallace(
                    .clk(clk),
                    .N_array(partial_products_t[k]),
                    .Cin_array(Cin_arrays[k]),
                    .S(Add_src1[k]),
                    .C(Add_src2[k+1]),
                    .Cout_array(Cin_arrays[k+1])
                );
    end
endgenerate

assign Add_src2[0] = carries_reg[15];
assign mul_result = Add_src1+Add_src2[67:0]+carries_reg[16];

endmodule


    module multiplier(
        input   wire            clk,
        input   wire [31:0]     mul_src1,
        input   wire [31:0]     mul_src2,
        input   wire [2:0]      mul_op,         // 001 for mul.w, 010 for mulh.w, 100 for mulh.wu
        output  wire [31:0]     mul_res
    );

wire is_unsigned;
wire [33:0] mul_src1_ext,mul_src2_ext;
wire [67:0] prod;
reg [2:0] mul_op_reg;

always @(posedge clk)
begin
    mul_op_reg <= mul_op;
end

assign is_unsigned = mul_op[2];

assign mul_src1_ext = {{2{is_unsigned?1'b0:mul_src1[31]}},mul_src1};
assign mul_src2_ext = {{2{is_unsigned?1'b0:mul_src2[31]}},mul_src2};


multiplier_signed_34bits u_multiplier_signed_34bits(
                             .clk(clk),
                             .x_complement(mul_src1_ext),
                             .y_complement(mul_src2_ext),
                             .mul_result(prod)
                         );

assign mul_res = {32{mul_op_reg[0]}} & prod[31:0]
       | {32{mul_op_reg[1]||mul_op_reg[2]}} & prod[63:32];

endmodule