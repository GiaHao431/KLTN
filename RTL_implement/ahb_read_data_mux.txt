`timescale 1ns / 1ps

module ahb_read_data_mux (
    input  logic        HCLK,
    input  logic        HRESETn,
    input  logic        HREADY,
    
    input  logic [1:0]  MUX_SEL,     // Tín hiệu chọn Slave từ Decoder (Pha Địa chỉ)
    
    input  logic [31:0] HRDATA_S1,
    input  logic [31:0] HRDATA_S2,
    input  logic [31:0] HRDATA_S3,
    // (Default Slave không gửi HRDATA có nghĩa, thường mặc định trả về 0)
    
    output logic [31:0] HRDATA_M
);

    logic [1:0] mux_sel_data_phase;

    // 1. Pipeline Register: Cập nhật tín hiệu chọn Slave khi HREADY = 1
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            mux_sel_data_phase <= 2'b00;
        end else if (HREADY) begin
            mux_sel_data_phase <= MUX_SEL;
        end
    end

    // 2. Định tuyến dữ liệu Đọc (HRDATA) về Master
    always_comb begin
        case (mux_sel_data_phase)
            2'b00: HRDATA_M = HRDATA_S1;
            2'b01: HRDATA_M = HRDATA_S2;
            2'b10: HRDATA_M = HRDATA_S3;
            2'b11: HRDATA_M = 32'h0000_0000; // Trỏ về Default Slave (Dữ liệu an toàn)
            default: HRDATA_M = 32'h0000_0000;
        endcase
    end

endmodule