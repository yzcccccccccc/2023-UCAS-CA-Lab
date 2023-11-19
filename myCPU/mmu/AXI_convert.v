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
    output reg         rready,

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
                if(arvalid && arready)
                    ar_next_state <= ARACQUIRED;
                else if(arvalid || arready)
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
                // if(rready && rvalid)
                //     ar_next_state <= ARINIT;
                // else
                //     ar_next_state <= ARACQUIRED;
            end
            default:
                ;
        endcase
    end

    // read-responce
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
                if(rready && rvalid)
                    r_next_state <= RINIT;
                else
                    r_next_state <= RWAIT;
            end
            RDATA:
                r_next_state <= RINIT;
            default:
                ;
        endcase
    end    

    // write-acquire + write-data
    localparam WINIT    = 4'b0001;
    localparam AWREADY  = 4'b0010;
    localparam WREADY   = 4'b0100;
    localparam ALLREADY = 4'b1000;
    reg [3:0] w_current_state, w_next_state;
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
                if(awvalid && awready && wvalid && wready)
                    w_next_state <= ALLREADY;
                else if(awvalid && awready)
                    w_next_state <= AWREADY;
                else if(wvalid && wready)
                    w_next_state <= WREADY;
                else
                    w_next_state <= WINIT;
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

    assign read_harzard = (araddr == awaddr) && ((|w_current_state[3:1]) && !b_current_state[2]);
    assign arlen    = 8'b0;
    assign arburst  = 2'b01;
    assign arlock   = 2'b0;
    assign arcache  = 4'b0;
    assign arprot   = 3'b0;
    assign arvalid  = !reset && (data_sram_req && !data_sram_wr || inst_sram_req && !inst_sram_wr) && !read_harzard;
    assign arid     = data_sram_req && !data_sram_wr ? 4'b1 : 4'b0;
    assign arsize   = data_sram_req && !data_sram_wr ? data_sram_size : inst_sram_size;
    assign araddr   = data_sram_req && !data_sram_wr ? data_sram_addr : inst_sram_addr;
    
    always@(posedge aclk)begin
        if(reset)
            rready <= 0;
        else if(arvalid && arready)
            rready <= 1;
        else if(rready && rvalid)
            rready <= 0;
    end

    assign awid     = 4'b1;
    assign awlen    = 8'b0;
    assign awburst  = 2'b01;
    assign awlock   = 2'b0;
    assign awcache  = 4'b0;
    assign awprot   = 3'b0;
    assign awaddr   = data_sram_addr;
    assign awsize   = data_sram_size;
    assign awvalid  = !reset && (data_sram_req && data_sram_wr);

    assign wid      = 4'b1;
    assign wlast    = 1'b1;
    assign wdata    = data_sram_wdata;
    assign wstrb    = data_sram_wstrb;
    assign wvalid   = !reset && data_sram_req && data_sram_wr;

    assign bready   = !reset && w_current_state[3];
    
    assign inst_sram_addr_ok = !arid[0] && arready && arvalid;
    assign inst_sram_data_ok = !rid[0] && rvalid && rready;
    assign inst_sram_rdata   = !rid[0] ? rdata : 0;
    assign data_sram_addr_ok = arid[0] && arready && arvalid || 
                               wid[0] && (w_current_state[0] && awready && wready ||
                                          w_current_state[1] && wready ||
                                          w_current_state[2] && awready);
    assign data_sram_data_ok = rid[0] && rvalid && rready || 
                               bid[0] && bvalid && bready;
    assign data_sram_rdata   = rid[0] ? rdata : 0;
endmodule