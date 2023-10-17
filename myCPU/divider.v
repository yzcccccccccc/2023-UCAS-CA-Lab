/******************************************************************
    Version 0.1:
        Using Xilinx ip
        Created By Yzcc
        2023.10.2

    Version 0.2:
        Reduce FSM states.
        Created By Yzcc
        2023.10.17

*******************************************************************/
module divider(
    input   wire            clk,
    input   wire            reset,

    input   wire [31:0]     div_src1,
    input   wire [31:0]     div_src2,
    input   wire [3:0]      div_op,         // 0001 for div.w, 0010 for div.wu, 0100 for mod.w, 1000 for mod.wu
    output  wire [31:0]     div_res,
    output  wire            div_done        // foperation done signal
);
    wire    [63:0]          signed_res, unsigned_res;

    wire    signed_enable, unsigned_enable;
    assign signed_enable    = div_op[0] | div_op[2];
    assign unsigned_enable  = div_op[1] | div_op[3];

    localparam INIT     = 3'b001;
    localparam WAIT     = 3'b010;      // handshaking state
    localparam EXE      = 3'b100;      

    localparam isINIT   = 0;
    localparam isWAIT   = 1;
    localparam isEXE    = 2;

// AXI_Stream Control Signals for Xilinx ip
    wire        signed_divisor_tvalid;
    wire        signed_divisor_tready;
    wire        signed_dividend_tvalid;
    wire        signed_dividend_tready;
    wire        signed_dout_tvalid;

    wire        unsigned_divisor_tvalid;
    wire        unsigned_divisor_tready;
    wire        unsigned_dividend_tvalid;
    wire        unsigned_dividend_tready;
    wire        unsigned_dout_tvalid;  

// Signed Divider FSM
    reg     [2:0]       signed_current, signed_next;
    always @(posedge clk) begin
        if (reset) begin
            signed_current  <= INIT;
        end
        else begin
            signed_current  <= signed_next;
        end
    end

    always @(*) begin
        case (signed_current)
            INIT: signed_next <= WAIT;
            WAIT: begin
                if (signed_enable & signed_dividend_tready & signed_divisor_tready) begin
                    signed_next <= EXE;
                end
                else begin
                    signed_next <= WAIT;
                end
            end
            EXE: begin
                if (signed_dout_tvalid)
                    signed_next <= WAIT;
                else
                    signed_next <= EXE; 
            end
            default: signed_next <= INIT;
        endcase
    end


// Signed Divider
    assign signed_dividend_tvalid   = signed_current[isWAIT] & signed_enable;
    assign signed_divisor_tvalid    = signed_current[isWAIT] & signed_enable;
    signed_div u_signed_div (
    .aclk(clk),                                         // input wire aclk
    .s_axis_divisor_tvalid(signed_divisor_tvalid),      // input wire s_axis_divisor_tvalid
    .s_axis_divisor_tready(signed_divisor_tready),     // output wire s_axis_divisor_tready
    .s_axis_divisor_tdata(div_src2),                    // input wire [31 : 0] s_axis_divisor_tdata

    .s_axis_dividend_tvalid(signed_dividend_tvalid),  // input wire s_axis_dividend_tvalid
    .s_axis_dividend_tready(signed_dividend_tready),  // output wire s_axis_dividend_tready
    .s_axis_dividend_tdata(div_src1),                 // input wire [31 : 0] s_axis_dividend_tdata

    .m_axis_dout_tvalid(signed_dout_tvalid),          // output wire m_axis_dout_tvalid
    .m_axis_dout_tdata(signed_res)                    // output wire [63 : 0] m_axis_dout_tdata
    );

// Unsigned Divisor FSM
    reg     [3:0]       unsigned_current, unsigned_next;
    always @(posedge clk) begin
        if (reset) begin
            unsigned_current <= INIT;
        end
        else begin
            unsigned_current <= unsigned_next;
        end
    end

    always @(*) begin
        case (unsigned_current)
            INIT: unsigned_next <= WAIT;
            WAIT: begin
                if (unsigned_enable & unsigned_dividend_tready & unsigned_divisor_tready) begin
                    unsigned_next <= EXE;
                end
                else begin
                    unsigned_next <= WAIT;
                end
            end
            EXE: begin
                if (unsigned_dout_tvalid)
                    unsigned_next <= WAIT;
                else
                    unsigned_next <= EXE;
            end
            default: unsigned_next <= INIT;
        endcase
    end

// Unsigned Divisor
    assign unsigned_divisor_tvalid      = unsigned_current[isWAIT] & unsigned_enable;
    assign unsigned_dividend_tvalid     = unsigned_current[isWAIT] & unsigned_enable;
    unsigned_div u_unsigned_div (
        .aclk(clk),                                      // input wire aclk
        .s_axis_divisor_tvalid(unsigned_divisor_tvalid),    // input wire s_axis_divisor_tvalid
        .s_axis_divisor_tready(unsigned_divisor_tready),    // output wire s_axis_divisor_tready
        .s_axis_divisor_tdata(div_src2),                    // input wire [31 : 0] s_axis_divisor_tdata

        .s_axis_dividend_tvalid(unsigned_dividend_tvalid),  // input wire s_axis_dividend_tvalid
        .s_axis_dividend_tready(unsigned_dividend_tready),  // output wire s_axis_dividend_tready
        .s_axis_dividend_tdata(div_src1),                   // input wire [31 : 0] s_axis_dividend_tdata

        .m_axis_dout_tvalid(unsigned_dout_tvalid),          // output wire m_axis_dout_tvalid
        .m_axis_dout_tdata(unsigned_res)                    // output wire [63 : 0] m_axis_dout_tdata
      );

// Res Select
    assign div_res  = {32{div_op[0]}} & signed_res[63:32]
                    | {32{div_op[1]}} & unsigned_res[63:32]
                    | {32{div_op[2]}} & signed_res[31:0]
                    | {32{div_op[3]}} & unsigned_res[31:0];
    assign div_done = signed_enable & signed_dout_tvalid | unsigned_enable & unsigned_dout_tvalid;

endmodule