`timescale 1ns / 1ps

module ahb_resp_mux (
    input  logic        HCLK,
    input  logic        HRESETn,
    input  logic        HREADY,          // Tín hiệu Global Ready của hệ thống
    
    input  logic [1:0]  MUX_SEL,         // Tín hiệu chọn từ khối Decoder
    
    input  logic [1:0]  HRESP_S1,
    input  logic [1:0]  HRESP_S2,
    input  logic [1:0]  HRESP_S3,
    input  logic [1:0]  HRESP_DEFAULT,   // Trạng thái từ Default Slave (luôn là 2'b01 ERROR)
    
    output logic [1:0]  HRESP_M
);

    logic [1:0] mux_sel_data_phase;

    // 1. Pipeline Register: Trì hoãn tín hiệu chọn sang Pha Dữ liệu
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
            2'b00: HRESP_M = HRESP_S1;
            2'b01: HRESP_M = HRESP_S2;
            2'b10: HRESP_M = HRESP_S3;
            2'b11: HRESP_M = HRESP_DEFAULT;
            default: HRESP_M = 2'b00;    // OKAY (Safe-state)
        endcase
    end

endmodule