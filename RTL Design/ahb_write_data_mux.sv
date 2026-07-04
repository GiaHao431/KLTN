`timescale 1ns / 1ps

module ahb_write_data_mux (
    input  logic        HCLK,
    input  logic        HRESETn,
    input  logic        HREADY,      // Tín hiệu Global Ready để sang chu kỳ mới
    
    input  logic [3:0]  HMASTER_SEL, // Tín hiệu chọn Master từ Pha Địa chỉ (0: M1, 1: M2)
    input  logic [31:0] HWDATA_M1,
    input  logic [31:0] HWDATA_M2,
    
    output logic [31:0] HWDATA_S
);

    logic [3:0] master_sel_data_phase; // Thanh ghi lưu trữ tín hiệu chọn cho Pha Dữ liệu

    // 1. Pipeline Register: Cập nhật tín hiệu chọn khi HREADY = 1
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            master_sel_data_phase <= 4'd0;
        end else if (HREADY) begin
            master_sel_data_phase <= HMASTER_SEL;
        end
    end

    // 2. Định tuyến dữ liệu Ghi (HWDATA) dựa trên tín hiệu đã được chốt
    always_comb begin
	HWDATA_S = HWDATA_M1;   // idle / unknown → M1 safe-state

        if (master_sel_data_phase == 4'd0) begin
            HWDATA_S = HWDATA_M1;
        end else if (master_sel_data_phase == 4'd1) begin
            HWDATA_S = HWDATA_M2;
        end
    end

endmodule