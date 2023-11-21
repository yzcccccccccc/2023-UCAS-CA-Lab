/************************************************************
    AXI-SRAM converter. For exp15 & exp16
*************************************************************/

module AXI_convert(
    //SRAM Signals
    input  wire        inst_sram_req,
    input  wire        inst_sram_wr,
    input  wire [1:0]  inst_sram_size,
    input  wire [31:0] inst_sram_addr,
    input  wire [3:0]  inst_sram_wstrb,
    input  wire [31:0] inst_sram_wdata,
    input  wire        preIF_cancel,
    output wire        inst_sram_addr_ok,
    output wire        inst_sram_data_ok,
    output wire [31:0] inst_sram_rdata,

    // data sram interface (SRAM, exp14+)
    input  wire        data_sram_req,
    input  wire        data_sram_wr,
    input  wire [1:0]  data_sram_size,
    input  wire [31:0] data_sram_addr,
    input  wire [3:0]  data_sram_wstrb,
    input  wire [31:0] data_sram_wdata,
    output wire        data_sram_addr_ok,
    output wire        data_sram_data_ok,
    output wire [31:0] data_sram_rdata,

    //AXI signals
    // clk and reset
    input  wire        aclk,
    input  wire        reset,

    // read-acquire
    output wire [3:0]  arid,            //fs=0,ld=1
    output wire [31:0] araddr,
    output wire [7:0]  arlen,           //always=0
    output wire [2:0]  arsize,
    output wire [1:0]  arburst,         //always=2'b01
    output wire [1:0]  arlock,          //always=0
    output wire [3:0]  arcache,         //always=0
    output wire [2:0]  arprot,          //always=0
    output wire        arvalid,
    input  wire        arready,

    // read-responce
    input  wire [3:0]  rid,
    input  wire [31:0] rdata,
    input  wire [1:0]  rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,

    // write-acquire
    output wire [3:0]  awid,            //always=1
    output wire [31:0] awaddr,
    output wire [7:0]  awlen,           //always=0
    output wire [2:0]  awsize,
    output wire [1:0]  awburst,         //always=2'b01
    output wire [1:0]  awlock,          //always=0
    output wire [3:0]  awcache,         //always=0
    output wire [2:0]  awprot,          //always=0
    output wire        awvalid,
    input  wire        awready,

    // write-data
    output wire [3:0]  wid,             //always=1
    output wire [31:0] wdata,
    output wire [3:0]  wstrb,
    output wire        wlast,           //always=1
    output wire        wvalid,
    input  wire        wready,

    // write-responce
    input  wire [3:0]  bid,
    input  wire [1:0]  bresp,
    input  wire        bvalid,
    output wire        bready
);
    wire read_harzard;
    reg [63:0] rdata_buff;
    reg [1:0] read_data_ok;
    reg [7:0] unfinish_cnt;
    // state machine
    // read-acquire
    localparam ARINIT = 3'b001;
    localparam ARWAIT = 3'b010;
    localparam ARACQUIRED = 3'b100;
    reg [2:0] ar_current_state, ar_next_state;
    always@(posedge aclk)begin
        if(reset)
            ar_current_state <= ARINIT;
        else
            ar_current_state <= ar_next_state;
    end
    always@(*)begin
        case(ar_current_state)
            ARINIT:
            begin
               if(read_harzard)
                   ar_next_state <= ARINIT;
               else if(data_sram_req && !data_sram_wr || inst_sram_req && !inst_sram_wr)
                    ar_next_state <= ARWAIT;
                else
                    ar_next_state <= ARINIT;
            end
            ARWAIT:
            begin
                if(arvalid && arready)
                    ar_next_state <= ARACQUIRED;
                else
                    ar_next_state <= ARWAIT;
            end
            ARACQUIRED:
            begin
                ar_next_state <= ARINIT;
            end
            default:
                ;
        endcase
    end

    // read-responce
    // localparam RINIT = 5'b00001;
    // localparam INST_WAIT = 5'b00010;
    // localparam DATA_WAIT = 5'b00100;
    // localparam ALL_WAIT = 5'b01000;
    // localparam RDATA = 5'b10000;
    localparam RINIT = 3'b001;
    localparam RWAIT = 3'b010;
    localparam RDATA = 3'b100;
    reg [2:0] r_current_state, r_next_state;
    always@(posedge aclk)begin
        if(reset)
            r_current_state <= RINIT;
        else
            r_current_state <= r_next_state;
    end
    always@(*)begin
        case(r_current_state)
            RINIT:
            begin
                if(arvalid && arready)
                    r_next_state <= RWAIT;
                else
                    r_next_state <= RINIT;
            end
            RWAIT:
            begin
                if(arvalid && arready && rready && rvalid)
                    r_next_state <= RWAIT;
                else if(rready && rvalid)begin
                    if(unfinish_cnt == 8'b1)
                        r_next_state <= RDATA;
                    else
                        r_next_state <= RWAIT;
                end
                else
                    r_next_state <= RWAIT;
            end
            RDATA:
            begin
                if(arvalid && arready)
                    r_next_state <= RWAIT;
                else
                    r_next_state <= RINIT;
            end
            default:
                ;
        endcase
    end
    // always@(*)begin
    //     case(r_current_state)
    //         RINIT:
    //         begin
    //             if(arvalid && arready && !arid[0])      // inst acquire
    //                 r_next_state <= INST_WAIT;
    //             else if(arvalid && arready && arid[0])  // data acquire
    //                 r_next_state <= DATA_WAIT;
    //             else
    //                 r_next_state <= RINIT;
    //         end
    //         INST_WAIT:
    //         begin
    //             if(arvalid && arready && arid[0] && rready && rvalid && !rid[0])   // 指令返回，同时数据读请求
    //                 r_next_state <= DATA_WAIT;
    //             else if(arvalid && arready && !arid[0] && rready && rvalid && !rid[0]) // 指令返回，同时指令读请求(不太可能)
    //                 r_next_state <= INST_WAIT;
    //             else if(arvalid && arready && arid[0])       // 指令未返回，同时数据读请�?
    //                 r_next_state <= ALL_WAIT;
    //             else if(rready && rvalid && !rid[0])                   // 指令返回
    //                 r_next_state <= RDATA;
    //             else
    //                 r_next_state <= INST_WAIT;
    //         end
    //         DATA_WAIT:
    //         begin
    //             if(arvalid && arready && !arid[0] && rready && rvalid && rid[0])  // 数据返回，同时指令读请求
    //                 r_next_state <= INST_WAIT;
    //             else if(arvalid && arready && arid[0] && rready && rvalid && rid[0])  // 数据返回，同时数据读请求(不太可能)
    //                 r_next_state <= DATA_WAIT;
    //             else if(arvalid && arready && !arid[0])     // 数据未返回，同时指令读请�?
    //                 r_next_state <= ALL_WAIT;
    //             else if(rready && rvalid && rid[0])
    //                 r_next_state <= RDATA;
    //             else
    //                 r_next_state <= DATA_WAIT;
    //         end
    //         ALL_WAIT:
    //         begin
    //             if(arvalid && arready && arid[0] && rready && rvalid && rid[0])  // 数据返回，同时数据读请求(不太可能)
    //                 r_next_state <= ALL_WAIT;
    //             else if(arvalid && arready && !arid[0] && rready && rvalid && !rid[0])  // 指令返回，同时指令读请求(不太可能)
    //                 r_next_state <= ALL_WAIT;
    //             else if(rready && rvalid && rid[0])              // 数据返回
    //                 r_next_state <= INST_WAIT;
    //             else if(rready && rvalid && !rid[0])        // 指令返回
    //                 r_next_state <= DATA_WAIT;
    //             else
    //                 r_next_state <= ALL_WAIT;
    //         end
    //         RDATA:
    //         begin
    //             if(arvalid && arready && !arid[0])      // inst acquire
    //                 r_next_state <= INST_WAIT;
    //             else if(arvalid && arready && arid[0])  // data acquire
    //                 r_next_state <= DATA_WAIT;
    //             else
    //                 r_next_state <= RINIT;
    //         end
    //         default:
    //             ;
    //     endcase
    // end    

    // write-acquire + write-data
    localparam WINIT    = 4'b00001;
    localparam WWAIT    = 4'b00010;
    localparam AWREADY  = 4'b00100;
    localparam WREADY   = 4'b01000;
    localparam ALLREADY = 5'b10000;
    reg [4:0] w_current_state, w_next_state;
    always@(posedge aclk)begin
        if(reset)
            w_current_state <= WINIT;
        else
            w_current_state <= w_next_state;
    end
    always@(*)begin
        case(w_current_state)
            WINIT:
            begin
                if(data_sram_req && data_sram_wr)
                    w_next_state <= WWAIT;
                else
                    w_next_state <= WINIT;
            end
            WWAIT:
            begin
                if(awvalid && awready && wvalid && wready)
                    w_next_state <= ALLREADY;
                else if(awvalid && awready)
                    w_next_state <= AWREADY;
                else if(wvalid && wready)
                    w_next_state <= WREADY;
                else
                    w_next_state <= WWAIT;
            end
            AWREADY:
            begin
                if(wvalid && wready)
                    w_next_state <= ALLREADY;
                else
                    w_next_state <= AWREADY;
            end
            WREADY:
            begin
                if(awvalid && awready)
                    w_next_state <= ALLREADY;
                else
                    w_next_state <= WREADY;
            end
            ALLREADY:
            begin
                if(bvalid && bready)
                    w_next_state <= WINIT;
                else
                    w_next_state <= ALLREADY;
            end
            default:
                ;
        endcase
    end

    // write-responce
    localparam BINIT = 3'b001;
    localparam BWAIT = 3'b010;
    localparam BDATA = 3'b100;
    reg [2:0] b_current_state, b_next_state;
    always@(posedge aclk)begin
        if(reset)
            b_current_state <= BINIT;
        else
            b_current_state <= b_next_state;
    end
    always@(*)begin
        case(b_current_state)
            BINIT:
            begin
                if(bready)
                    b_next_state <= BWAIT;
                else
                    b_next_state <= BINIT;
            end
            BWAIT:
            begin
                if(bready && bvalid)
                    b_next_state <= BDATA;
                else
                    b_next_state <= BWAIT;
            end
            BDATA:
                b_next_state <= BINIT;
            default:
                ;
        endcase
    end

    assign read_harzard = (araddr == awaddr) && ((|w_current_state[4:1]) && !b_current_state[2]);
    always@(posedge aclk)begin
        if(reset)
            unfinish_cnt <= 8'b0;
        else if(arready && arvalid && rvalid && rready)
            unfinish_cnt <= unfinish_cnt;
        else if(arvalid && arready)
            unfinish_cnt <= unfinish_cnt + 8'b1;
        else if(rready && rvalid)
            unfinish_cnt <= unfinish_cnt - 8'b1;
        else
            unfinish_cnt <= unfinish_cnt;
        
    end
    // [hint]�?要保证valid拉高且ready还未拉高时�?�道值不�?
    reg [31:0] araddr_pre;
    reg [2:0]  arsize_pre;
    reg [3:0]  arid_pre;
    always@(posedge aclk)begin
        araddr_pre  <= araddr;
        arid_pre    <= arid;
        arsize_pre  <= arsize;
    end
    assign arlen    = 8'b0;
    assign arburst  = 2'b01;
    assign arlock   = 2'b0;
    assign arcache  = 4'b0;
    assign arprot   = 3'b0;
    assign arvalid  = ar_current_state[1];
    wire ar_ready;
    assign ar_ready = ar_current_state[0] || ar_current_state[2];
    assign arid     = ar_ready ? 
                      (data_sram_req && !data_sram_wr ? 4'b1 : 4'b0) : 
                      (preIF_cancel ? 4'b0 : arid_pre);
    assign arsize   = ar_ready ? 
                      (data_sram_req && !data_sram_wr ? data_sram_size : inst_sram_size) : 
                      (preIF_cancel ? inst_sram_size : arsize_pre);
    assign araddr   = ar_ready ? 
                      ((data_sram_req && !data_sram_wr) ? data_sram_addr : inst_sram_addr) : 
                      (preIF_cancel ? inst_sram_addr : araddr_pre);
    
    assign rready   = !reset && r_current_state[1];

    always@(posedge aclk)begin
        if(reset)
            rdata_buff <= 64'b0;
        else if(rready && rvalid && rid[0])
            rdata_buff[63:32] <= rdata;
        else if(rready && rvalid && !rid[0])
            rdata_buff[31:0] <= rdata;
        else
            rdata_buff <= 64'b0;
    end
    always@(posedge aclk)begin
        read_data_ok <= {rid[0] && rready && rvalid, !rid[0] && rready && rvalid};
    end

    reg [31:0] awaddr_pre;
    reg [2:0]  awsize_pre;
    always@(posedge aclk)begin
        awaddr_pre <= awaddr;
        awsize_pre <= awsize;
    end
    assign awid     = 4'b1;
    assign awlen    = 8'b0;
    assign awburst  = 2'b01;
    assign awlock   = 2'b0;
    assign awcache  = 4'b0;
    assign awprot   = 3'b0;
    assign awaddr   = w_current_state[0] ? data_sram_addr : awaddr_pre;
    assign awsize   = w_current_state[0] ? data_sram_size : awsize_pre;
    assign awvalid  = !reset && (w_current_state[1] || w_current_state[3]);

    reg [31:0]  wdata_pre;
    reg [3:0]   wstrb_pre;
    always@(posedge aclk)begin
        wdata_pre <= wdata;
        wstrb_pre <= wstrb;
    end
    assign wid      = 4'b1;
    assign wlast    = 1'b1;
    assign wdata    = w_current_state[0] ? data_sram_wdata : wdata_pre;
    assign wstrb    = w_current_state[0] ? data_sram_wstrb : wstrb_pre;
    assign wvalid   = !reset && (w_current_state[1] || w_current_state[2]);

    assign bready   = !reset && w_current_state[4];
    
    assign inst_sram_addr_ok = !arid[0] && arready && arvalid;
    assign inst_sram_data_ok = read_data_ok[0];             // 由于rdata_buff的存在，�?要慢�?拍给出data_ok信号，再加上取数据相关阻塞，�?大可能慢两拍
    assign inst_sram_rdata   = rdata_buff[31:0];
    assign data_sram_addr_ok = arid[0] && arready && arvalid || 
                               wid[0] && (w_current_state[1] && (awready && wready || awvalid && wvalid && !awready && !wready) ||
                                          w_current_state[2] && wready ||
                                          w_current_state[3] && awready);
    assign data_sram_data_ok = read_data_ok[1] || 
                               bid[0] && bvalid && bready;
    assign data_sram_rdata   = rdata_buff[63:32];
endmodule