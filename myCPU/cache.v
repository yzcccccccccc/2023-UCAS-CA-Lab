/*******************************************************************
    Cache module
    Authored by czxx, 2023.12.09
*******************************************************************/
`define WRITE 1 // op
`define READ 0  // op

module cache (
           input wire clk,
           input wire resetn,

           // cpu interface (design book - p234)
           input  wire        valid,
           input  wire        op,
           input  wire [ 7:0] index,    // virtual
           input  wire [19:0] tag,      // physical
           input  wire [ 3:0] offset,
           input  wire [ 3:0] wstrb,
           input  wire [31:0] wdata,
           output wire        addr_ok,
           output wire        data_ok,
           output wire [31:0] rdata,

           // bridge interface (design book - p235)
           // read
           output wire         rd_req,
           output wire [  2:0] rd_type,    // 3'b100 for page
           output wire [ 31:0] rd_addr,
           input  wire         rd_rdy,
           input  wire         ret_valid,
           input  wire         ret_last,
           input  wire [ 31:0] ret_data,
           // write
           output wire         wr_req,
           output wire [  2:0] wr_type,    // 3'b100 for page
           output wire [ 31:0] wr_addr,
           output wire [  3:0] wr_wstrb,
           output wire [127:0] wr_data,
           input  wire         wr_rdy
       );

genvar i;

wire rst = ~resetn;

// TAGV Ram Ports
wire way0_tagv_wen, way1_tagv_wen;
wire [7:0] way0_tagv_addr, way1_tagv_addr;
wire [20:0] way0_tagv_wdata, way1_tagv_wdata;
wire [20:0] way0_tagv_rdata, way1_tagv_rdata;
wire [19:0] way0_tag, way1_tag;
wire way0_v, way1_v;

localparam BANK_NUM = 4;
// Data Bank Ram Ports
wire [3:0] way0_data_wen, way1_data_wen;
wire [ 7:0] way0_data_addr [3:0];
wire [ 7:0] way1_data_addr [3:0];
wire [31:0] way0_data_wdata[3:0];
wire [31:0] way1_data_wdata[3:0];
wire [31:0] way0_data_rdata[3:0];
wire [31:0] way1_data_rdata[3:0];
wire [127:0] way0_data, way1_data;
wire [31:0] way0_data_refill[3:0];
wire [31:0] way1_data_refill[3:0];

// D array
reg [255:0] way0_d_array, way1_d_array;
reg way0_d, way1_d;  // d value of given index

// regs for Request Buffer
reg         rb_op;
reg  [ 7:0] rb_index;
reg  [19:0] rb_tag;
reg  [ 3:0] rb_offset;
reg  [ 3:0] rb_wstrb;
reg  [31:0] rb_wdata;
wire [31:0] rb_wstrb_ext;

// regs for Write Buffer
reg  [ 7:0] wb_index;
reg         wb_way;
reg  [ 3:0] wb_offset;
reg  [ 3:0] wb_wstrb;
wire [31:0] wb_wstrb_ext;
reg [31:0] wb_wdata, wb_odata;  // odata means "original data", for wstrb

// regs for Miss Buffer
// replace_way keep unchanged LOOKUP, don't need to store it.
reg [31:0] mb_cnt;  // cnt of receiving data num

reg [ 3:0] lfsr_reg;

wire way0_hit, way1_hit, cache_hit;

wire [127:0] replace_data;
reg          replace_way;
wire         relpace_d;
wire [ 19:0] replace_tag;

wire [31:0] way0_load_word, way1_load_word, load_res;

wire hit_write;

reg  wr_req_reg;

wire hit_write_hazard;
wire hit_write_hazard_lookup;
wire hit_write_hazard_write;

// perf cnt
reg [31:0] icache_hit_cnt, icache_miss_cnt;
always @(posedge clk)
begin
    if (rst)
    begin
        icache_hit_cnt  <= 32'b0;
        icache_miss_cnt <= 32'b0;
    end
    else if (m_current_state == M_LOOKUP & cache_hit)
    begin
        icache_hit_cnt <= icache_hit_cnt + 1;
    end
    else if (m_current_state == M_LOOKUP & ~cache_hit)
    begin
        icache_miss_cnt <= icache_miss_cnt + 1;
    end
end

// Main FSM
localparam M_IDLE = 5'b00001,
           M_LOOKUP = 5'b00010,
           M_MISS = 5'b00100,
           M_REPLACE = 5'b01000,
           M_REFILL = 5'b10000;
reg [4:0] m_current_state, m_next_state;
always @(posedge clk)
begin
    if (rst)
    begin
        m_current_state <= M_IDLE;
    end
    else
    begin
        m_current_state <= m_next_state;
    end
end
always @(*)
begin
    case (m_current_state)
        M_IDLE:
        begin
            if (valid & ~hit_write_hazard)
            begin
                m_next_state = M_LOOKUP;
            end
            else
            begin
                m_next_state = M_IDLE;
            end
        end
        M_LOOKUP:
        begin
            if (cache_hit & (~valid | valid & hit_write_hazard))
            begin
                m_next_state = M_IDLE;
            end
            else if (cache_hit & valid & ~hit_write_hazard)
            begin
                m_next_state = M_LOOKUP;
            end
            else if (~cache_hit)
            begin
                m_next_state = M_MISS;
            end
            else
            begin
                m_next_state = M_LOOKUP;
            end
        end
        M_MISS:
        begin
            if (wr_rdy)
            begin
                m_next_state = M_REPLACE;
            end
            else
            begin
                m_next_state = M_MISS;
            end
        end
        M_REPLACE:
            if (rd_rdy)
            begin
                m_next_state = M_REFILL;
            end
            else
            begin
                m_next_state = M_REPLACE;
            end
        M_REFILL:
        begin
            if (ret_valid & ret_last)
            begin
                m_next_state = M_IDLE;
            end
            else
            begin
                m_next_state = M_REFILL;
            end
        end
        default:
        begin
            m_next_state = M_IDLE;
        end
    endcase
end

// Write Buffer FSM
localparam WB_IDLE = 2'b01, WB_WRITE = 2'b10;
reg [1:0] wb_current_state, wb_next_state;
always @(posedge clk)
begin
    if (rst)
    begin
        wb_current_state <= WB_IDLE;
    end
    else
    begin
        wb_current_state <= wb_next_state;
    end
end
always @(*)
begin
    case (wb_current_state)
        WB_IDLE:
        begin
            if (hit_write)
            begin
                wb_next_state = WB_WRITE;
            end
            else
            begin
                wb_next_state = WB_IDLE;
            end
        end
        WB_WRITE:
        begin
            if (hit_write)
            begin
                wb_next_state = WB_WRITE;
            end
            else
            begin
                wb_next_state = WB_IDLE;
            end
        end
        default:
        begin
            wb_next_state = WB_IDLE;
        end
    endcase
end

// Cache Table
// TAGV
tagv_ram way0_tagv_ram (
             .clka (clk),
             .wea  (way0_tagv_wen),
             .addra(way0_tagv_addr),
             .dina (way0_tagv_wdata),
             .douta(way0_tagv_rdata)
         );
tagv_ram way1_tagv_ram (
             .clka (clk),
             .wea  (way1_tagv_wen),
             .addra(way1_tagv_addr),
             .dina (way1_tagv_wdata),
             .douta(way1_tagv_rdata)
         );
// TAGV
assign way0_tagv_wen      = (m_current_state == M_REFILL) & ~replace_way;
assign way1_tagv_wen      = (m_current_state == M_REFILL) & replace_way;
assign way0_tagv_addr     = {8{m_current_state == M_IDLE}} & index
                            | {8{m_current_state == M_LOOKUP}} & index
                            | {8{m_current_state == M_MISS}} & rb_index
                            | {8{m_current_state == M_REFILL}} & rb_index;
assign way1_tagv_addr     = {8{m_current_state == M_IDLE}} & index
                            | {8{m_current_state == M_LOOKUP}} & index
                            | {8{m_current_state == M_MISS}} & rb_index
                            | {8{m_current_state == M_REFILL}} & rb_index;
assign way0_tagv_wdata    = {21{m_current_state == M_REFILL}} & {rb_tag, 1'b1};
assign way1_tagv_wdata    = {21{m_current_state == M_REFILL}} & {rb_tag, 1'b1};
assign {way0_tag, way0_v} = way0_tagv_rdata;
assign {way1_tag, way1_v} = way1_tagv_rdata;

// Data Bank
generate
    for (i = 0; i < BANK_NUM; i = i + 1)
    begin : data_bank_gen
        data_bank_ram way0_data_bank_ram (
                          .clka (clk),
                          .wea  (way0_data_wen[i]),
                          .addra(way0_data_addr[i]),
                          .dina (way0_data_wdata[i]),
                          .douta(way0_data_rdata[i])
                      );
        data_bank_ram way1_data_bank_ram (
                          .clka (clk),
                          .wea  (way1_data_wen[i]),
                          .addra(way1_data_addr[i]),
                          .dina (way1_data_wdata[i]),
                          .douta(way1_data_rdata[i])
                      );
    end
endgenerate
assign wb_wstrb_ext = {{8{wb_wstrb[3]}}, {8{wb_wstrb[2]}}, {8{wb_wstrb[1]}}, {8{wb_wstrb[0]}}};
assign rb_wstrb_ext = {{8{rb_wstrb[3]}}, {8{rb_wstrb[2]}}, {8{rb_wstrb[1]}}, {8{rb_wstrb[0]}}};
generate
    for (i = 0; i < BANK_NUM; i = i + 1)
    begin : data_bank_IO_gen
        assign way0_data_wen[i]    = (wb_current_state == WB_WRITE) & wb_offset[3:2] == i
                                     | (m_current_state == M_REFILL) & ~replace_way & mb_cnt == i;
        assign way1_data_wen[i]    = (wb_current_state == WB_WRITE) & wb_offset[3:2] == i
                                     | (m_current_state == M_REFILL) & replace_way & mb_cnt == i;
        assign way0_data_addr[i]   = {8{m_current_state == M_IDLE}} & index
                                     | {8{m_current_state == M_LOOKUP}} & index
                                     | {8{m_current_state == M_MISS}} & rb_index
                                     | {8{m_current_state == M_REFILL}} & rb_index
                                     | {8{wb_current_state == WB_WRITE}} & wb_index;
        assign way1_data_addr[i]   = {8{m_current_state == M_IDLE}} & index
                                     | {8{m_current_state == M_LOOKUP}} & index
                                     | {8{m_current_state == M_MISS}} & rb_index
                                     | {8{m_current_state == M_REFILL}} & rb_index
                                     | {8{wb_current_state == WB_WRITE}} & wb_index;
        assign way0_data_refill[i] = ((rb_op == `WRITE & rb_offset[3:2] == i) ? (ret_data & ~rb_wstrb_ext | rb_wdata & rb_wstrb_ext) : ret_data);
        assign way0_data_wdata[i]  = {32{wb_current_state == WB_WRITE}} & (wb_odata & ~wb_wstrb_ext | wb_wdata & wb_wstrb_ext)
                                     | {32{m_current_state == M_REFILL}} & way0_data_refill[i];
        assign way1_data_refill[i] = ((rb_op == `WRITE & rb_offset[3:2] == i) ? (ret_data & ~rb_wstrb_ext | rb_wdata & rb_wstrb_ext) : ret_data);
        assign way1_data_wdata[i]  = {32{wb_current_state == WB_WRITE}} & (wb_odata & ~wb_wstrb_ext | wb_wdata & wb_wstrb_ext)
                                     | {32{m_current_state == M_REFILL}} & way1_data_refill[i];
        assign way0_data[i*32+:32] = way0_data_rdata[i];
        assign way1_data[i*32+:32] = way1_data_rdata[i];
    end
endgenerate

// D
always @(posedge clk)
begin
    if (rst)
    begin
        way0_d_array <= 256'b0;
    end
    else if (wb_current_state == `WRITE & ~wb_way)
    begin
        way0_d_array[wb_index] <= 1'b0;
    end
    else if (m_current_state == M_REFILL & ~replace_way)
    begin
        if (rb_op == `WRITE)
        begin
            way0_d_array[rb_index] <= 1'b1;
        end
        else
        begin
            way0_d_array[rb_index] <= 1'b0;
        end
    end
end
always @(posedge clk)
begin
    if (rst)
    begin
        way1_d_array <= 256'b0;
    end
    else if (wb_current_state == `WRITE & wb_way)
    begin
        way1_d_array[wb_index] <= 1'b0;
    end
    else if (m_current_state == M_REFILL & replace_way)
    begin
        if (rb_op == `WRITE)
        begin
            way1_d_array[rb_index] <= 1'b1;
        end
        else
        begin
            way1_d_array[rb_index] <= 1'b0;
        end
    end
end
always @(posedge clk)
begin
    if (rst)
    begin
        way0_d <= 1'b0;
    end
    else if (m_current_state == M_MISS & m_next_state == M_REPLACE)
    begin
        way0_d <= way0_d_array[rb_index];
    end
end
always @(posedge clk)
begin
    if (rst)
    begin
        way1_d <= 1'b0;
    end
    else if (m_current_state == M_MISS & m_next_state == M_REPLACE)
    begin
        way1_d <= way1_d_array[rb_index];
    end
end

// Request Buffer
always @(posedge clk)
begin
    if (rst)
    begin
        rb_op     <= 1'b0;
        rb_index  <= 8'b0;
        rb_tag    <= 20'b0;
        rb_offset <= 4'b0;
        rb_wstrb  <= 4'b0;
        rb_wdata  <= 32'b0;
    end
    else if (m_next_state == M_LOOKUP)
    begin
        rb_op     <= op;
        rb_index  <= index;
        rb_tag    <= tag;
        rb_offset <= offset;
        rb_wstrb  <= wstrb;
        rb_wdata  <= wdata;
    end
end

// Tag Compare
assign way0_hit       = way0_v && (way0_tag == rb_tag);
assign way1_hit       = way1_v && (way1_tag == rb_tag);
assign cache_hit      = way0_hit || way1_hit;

// Data Select
assign way0_load_word = way0_data[rb_offset[3:2]*32+:32];
assign way1_load_word = way1_data[rb_offset[3:2]*32+:32];
assign load_res       = (m_current_state == M_REFILL) ? ret_data
                        : {32{way0_hit}} & way0_load_word | {32{way1_hit}} & way1_load_word;

// Miss Buffer
always @(posedge clk)
begin
    if (rst)
    begin
        mb_cnt <= 32'b0;
    end
    else if (ret_valid & ret_last)
    begin
        mb_cnt <= 32'b0;
    end
    else if (ret_valid)
    begin
        mb_cnt <= mb_cnt + 1;
    end
end

// Replace
always @(posedge clk)
begin
    if (rst)
    begin
        replace_way <= 1'b0;
    end
    else if (m_current_state == M_LOOKUP & ~cache_hit)
    begin
        replace_way <= lfsr_reg[0];
    end
end
// block_ram returns at next clock
// read req at M_MISS & return at M_REPLACE
assign replace_data = replace_way ? way1_data : way0_data;
assign replace_tag  = replace_way ? way1_tag : way0_tag;
assign relpace_d    = replace_way ? (way1_v & way1_d) : (way0_v & way0_d);

// LFSR (design book hasn't specify the design of LFSR?)
always @(posedge clk)
begin
    if (rst)
    begin
        lfsr_reg <= 4'b1111;
    end
    else
    begin
        lfsr_reg <= {lfsr_reg[2:0], lfsr_reg[3] ^ lfsr_reg[0]};
    end
end

// Write Buffer
assign hit_write = m_current_state == M_LOOKUP & cache_hit & rb_op == `WRITE;
always @(posedge clk)
begin
    if (rst)
    begin
        wb_index  <= 8'b0;
        wb_way    <= 1'b0;
        wb_offset <= 4'b0;
        wb_wstrb  <= 4'b0;
        wb_wdata  <= 32'b0;
    end
    else if (hit_write)
    begin
        wb_index  <= rb_index;
        wb_way    <= way1_hit;
        wb_offset <= rb_offset;
        wb_wstrb  <= rb_wstrb;
        wb_wdata  <= rb_wdata;
        wb_odata  <= load_res;
    end
end

// Output Signals
assign addr_ok = m_current_state == M_IDLE & ~hit_write_hazard
       | m_current_state == M_LOOKUP & cache_hit & ~hit_write_hazard;
assign data_ok = m_current_state == M_LOOKUP & cache_hit
       | m_current_state == M_REFILL & ret_valid & mb_cnt == rb_offset[3:2];
assign rdata   = {32{m_current_state == M_LOOKUP}} & load_res
       | {32{m_current_state == M_REFILL}} & ret_data;
assign rd_req  = m_current_state == M_REPLACE;
assign rd_type = 3'b100;
assign rd_addr = {rb_tag, rb_index, 4'b0};
always @(posedge clk)
begin
    if (rst)
    begin
        wr_req_reg <= 1'b0;
    end
    else if (m_current_state == M_MISS & m_next_state == M_REPLACE)
    begin
        wr_req_reg <= 1'b1;
    end
    else if (wr_rdy)
    begin
        wr_req_reg <= 1'b0;
    end
end
assign wr_req = wr_req_reg & relpace_d;
assign wr_type = 3'b100;
assign wr_addr = {replace_tag, rb_index, 4'b0};
assign wr_wstrb = 4'b0;  // actually useless
assign wr_data = replace_data;

// Hit Write Hazard
assign hit_write_hazard_lookup = (m_current_state == M_LOOKUP)
                                 & (rb_op == `WRITE)
                                 & cache_hit & valid
                                 & (op == `READ)
                                 & (rb_tag == tag)
                                 & (rb_index == index)
                                 & (rb_offset[3:2] == offset[3:2]);
assign hit_write_hazard_write = (wb_current_state == WB_WRITE)
                                & valid & (op == `READ)
                                & (wb_index == index)
                                & (wb_offset[3:2] == offset[3:2]);
assign hit_write_hazard = hit_write_hazard_lookup | hit_write_hazard_write;

endmodule
