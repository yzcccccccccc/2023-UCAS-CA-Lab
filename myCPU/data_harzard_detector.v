module data_harzard_detector(
    input   wire [4:0]  rf_raddr1,
    input   wire [4:0]  rf_raddr2,

    input   wire [4:0]  EX_rf_waddr,
    input   wire        EX_rf_we,

    input   wire [4:0]  MEM_rf_waddr,
    input   wire        MEM_rf_we,

    input   wire [4:0]  WB_rf_waddr,
    input   wire        WB_rf_we,

    output  wire        occur
);
    wire    addr1_occur, addr2_occur;

    assign addr1_occur  = (rf_raddr1 == EX_rf_waddr && EX_rf_we == 1'b1)
                        | (rf_raddr1 == MEM_rf_waddr && MEM_rf_we == 1'b1)
                        | (rf_raddr1 == WB_rf_waddr && WB_rf_we == 1'b1);

    assign addr2_occur  = (rf_raddr2 == EX_rf_waddr && EX_rf_we == 1'b1)
                        | (rf_raddr2 == MEM_rf_waddr && MEM_rf_we == 1'b1)
                        | (rf_raddr2 == WB_rf_waddr && WB_rf_we == 1'b1);
    
    assign occur        = addr1_occur | addr2_occur;
endmodule