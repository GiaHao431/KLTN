`timescale 1ns / 1ps

module ahb_decoder (
    input  logic [31:0] HADDR_S,
    
    output logic        HSEL_S1,
    output logic        HSEL_S2,
    output logic        HSEL_S3,
    output logic        HSEL_DEFAULT,
    output logic [1:0]  MUX_SEL
);

    always_comb begin
        // Gán giá trị mặc định để chống rò rỉ Latch (Inferred Latch)
        HSEL_S1      = 1'b0;
        HSEL_S2      = 1'b0;
        HSEL_S3      = 1'b0;
        HSEL_DEFAULT = 1'b0;
        MUX_SEL      = 2'b00;

        // Định tuyến dựa vào 2 bit MSB của HADDR
        case (HADDR_S[31:30])
            2'b00: begin
                HSEL_S1 = 1'b1;       // 0x0000_0000 to 0x3FFF_FFFF
                MUX_SEL = 2'b00;
            end
            2'b01: begin
                HSEL_S2 = 1'b1;       // 0x4000_0000 to 0x7FFF_FFFF
                MUX_SEL = 2'b01;
            end
            2'b10: begin
                HSEL_S3 = 1'b1;       // 0x8000_0000 to 0xBFFF_FFFF
                MUX_SEL = 2'b10;
            end
            2'b11: begin
                HSEL_DEFAULT = 1'b1;  // 0xC000_0000 to 0xFFFF_FFFF
                MUX_SEL      = 2'b11;
            end
        endcase
    end

endmodule