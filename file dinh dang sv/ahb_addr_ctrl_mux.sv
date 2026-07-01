`timescale 1ns / 1ps

module ahb_addr_ctrl_mux (
    input  logic [3:0]  HMASTER_SEL, // 0: Chọn Master 1, 1: Chọn Master 2
    
    // Tín hiệu từ Master 1
    input  logic [31:0] HADDR_M1,
    input  logic [1:0]  HTRANS_M1,
    input  logic        HWRITE_M1,
    input  logic [2:0]  HSIZE_M1,
    input  logic [2:0]  HBURST_M1,
    
    // Tín hiệu từ Master 2
    input  logic [31:0] HADDR_M2,
    input  logic [1:0]  HTRANS_M2,
    input  logic        HWRITE_M2,
    input  logic [2:0]  HSIZE_M2,
    input  logic [2:0]  HBURST_M2,
    
    // Tín hiệu Broadcast tới tất cả Slaves (và Decoder)
    output logic [31:0] HADDR_S,
    output logic [1:0]  HTRANS_S,
    output logic        HWRITE_S,
    output logic [2:0]  HSIZE_S,
    output logic [2:0]  HBURST_S
);

    // Thuần tổ hợp - Phục vụ Pha Địa chỉ
    always_comb begin
	// ── Safe default: idle / no master granted → drive M1 bus-idle values
        // (Prevents inferred latches on all five output buses)
        HADDR_S  = HADDR_M1;
        HTRANS_S = HTRANS_M1;
        HWRITE_S = HWRITE_M1;
        HSIZE_S  = HSIZE_M1;
        HBURST_S = HBURST_M1;

        if (HMASTER_SEL == 4'd0) begin
            HADDR_S  = HADDR_M1;
            HTRANS_S = HTRANS_M1;
            HWRITE_S = HWRITE_M1;
            HSIZE_S  = HSIZE_M1;
            HBURST_S = HBURST_M1;
        end else if(HMASTER_SEL == 4'd1) begin
            HADDR_S  = HADDR_M2;
            HTRANS_S = HTRANS_M2;
            HWRITE_S = HWRITE_M2;
            HSIZE_S  = HSIZE_M2;
            HBURST_S = HBURST_M2;
        end
    end

endmodule