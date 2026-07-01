`timescale 1ns / 1ps

module ahb_ready_mux (
    input  logic        HCLK,
    input  logic        HRESETn,
    input  logic        HREADY,          // Tín hiệu HREADY_GLOBAL hồi tiếp lại chân EN
    
    input  logic [1:0]  MUX_SEL,         // Tín hiệu chọn từ khối Decoder
    
    input  logic        HREADYOUT_S1,
    input  logic        HREADYOUT_S2,
    input  logic        HREADYOUT_S3,
    input  logic        HREADYOUT_DEFAULT, // Luôn luôn bằng 1'b1
    
    output logic        HREADY_GLOBAL
);

    logic [1:0] mux_sel_data_phase;

    // 1. Pipeline Register
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            mux_sel_data_phase <= 2'b00;
        end else if (HREADY) begin
            mux_sel_data_phase <= MUX_SEL;
        end
    end

    // 2. Logic dồn kênh (Combinational)
    always_comb begin
        case (mux_sel_data_phase)
            2'b00: HREADY_GLOBAL = HREADYOUT_S1;
            2'b01: HREADY_GLOBAL = HREADYOUT_S2;
            2'b10: HREADY_GLOBAL = HREADYOUT_S3;
            2'b11: HREADY_GLOBAL = HREADYOUT_DEFAULT;
            default: HREADY_GLOBAL = 1'b1;  // Mặc định cho phép bus chạy
        endcase
    end

endmodule