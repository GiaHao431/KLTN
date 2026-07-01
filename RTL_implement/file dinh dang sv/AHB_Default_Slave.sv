`timescale 1ns / 1ps
//=============================================================================
// Module   : AHB_Default_Slave
// Language : SystemVerilog
// Standard : AMBA AHB Rev 2.0 (IHI0011A)
//
// Description:
//   Bắt tất cả các giao dịch Master truy cập vào vùng nhớ không hợp lệ
//   (0xC000_0000 – 0xFFFF_FFFF, được Decoder kích hoạt qua HSEL_DEFAULT).
//
//   Theo IHI0011A §3.8 & §3.9.3:
//     • Giao dịch IDLE / BUSY đến Default Slave → phản hồi OKAY tức thì
//       (zero wait-state) để tránh làm nghẽn pipeline.
//     • Giao dịch NONSEQ / SEQ → kích hoạt chuỗi phản hồi lỗi 2 chu kỳ:
//         Chu kỳ 1 (ERROR_CYC1): HREADYOUT=0, HRESP=ERROR
//           → Master nhận diện lỗi, chuẩn bị hủy pipeline.
//         Chu kỳ 2 (ERROR_CYC2): HREADYOUT=1, HRESP=ERROR
//           → Kết thúc giao dịch lỗi an toàn; bus được giải phóng.
//
//   Không có bộ nhớ, không có data bus, không hỗ trợ SPLIT.
//
// Port Mapping (per Design Specification §VIII & §X):
//   HSEL_DEFAULT      – từ Decoder (địa chỉ nằm ngoài 3 vùng nhớ hợp lệ)
//   HTRANS_S[1:0]       – loại giao dịch hiện tại (chuẩn AHB: 00=IDLE, 10=NONSEQ…)
//   HREADYOUT_DEFAULT – cờ sẵn sàng gửi về Interconnect
//   HRESP_DEFAULT     – mã phản hồi gửi về Interconnect
//=============================================================================

module AHB_Default_Slave (
    //── System Signals ────────────────────────────────────────────────────────
    input  logic        HCLK,
    input  logic        HRESETn,

    //── Control Signals (từ Decoder / Interconnect) ───────────────────────────
    input  logic        HSEL_DEFAULT,   // 1 = Master đang truy cập vùng không hợp lệ
    input  logic [1:0]  HTRANS_S,         // Loại giao dịch

    //── Response Signals (trả về Interconnect / Ready MUX) ───────────────────
    output logic        HREADYOUT_DEFAULT,
    output logic [1:0]  HRESP_DEFAULT
);

//=============================================================================
// ── AHB Protocol Constants ────────────────────────────────────────────────────
//=============================================================================

// HTRANS – IHI0011A Table 3-1
localparam logic [1:0]
    T_IDLE   = 2'b00,
    T_BUSY   = 2'b01,
    T_NONSEQ = 2'b10,
    T_SEQ    = 2'b11;

// HRESP – IHI0011A Table 3-5
localparam logic [1:0]
    R_OKAY  = 2'b00,
    R_ERROR = 2'b01;

//=============================================================================
// ── FSM State Declaration (typedef enum) ─────────────────────────────────────
//
//   ST_IDLE       – Slave nghỉ; không có giao dịch tích cực.
//   ST_ERROR_CYC1 – Chu kỳ 1 của chuỗi ERROR 2 chu kỳ:
//                     HREADYOUT=0, HRESP=ERROR  (penultimate cycle, AHB §3.9.3)
//   ST_ERROR_CYC2 – Chu kỳ 2 của chuỗi ERROR 2 chu kỳ:
//                     HREADYOUT=1, HRESP=ERROR  (final cycle, kết thúc an toàn)
//=============================================================================
typedef enum logic [1:0] {
    ST_IDLE       = 2'b00,
    ST_ERROR_CYC1 = 2'b01,
    ST_ERROR_CYC2 = 2'b10
} ahb_def_state_t;

ahb_def_state_t ps, ns;   // present state, next state

//=============================================================================
// ── Convenience Wire ─────────────────────────────────────────────────────────
// Phát hiện giao dịch tích cực: NONSEQ hoặc SEQ được chọn bởi Default Slave.
// IDLE và BUSY phải trả về OKAY ngay lập tức (IHI0011A §3.5 Table 3-1).
//=============================================================================
logic active_transfer;
assign active_transfer = HSEL_DEFAULT &&
                         (HTRANS_S == T_NONSEQ || HTRANS_S == T_SEQ);

//=============================================================================
// ══ SEQUENTIAL BLOCK : FSM State Register ════════════════════════════════════
//=============================================================================
always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn)
        ps <= ST_IDLE;
    else
        ps <= ns;
end

//=============================================================================
// ══ COMBINATIONAL BLOCK : Next-State & Output Logic ══════════════════════════
//
// Mọi nhánh của case đều được phủ kín, kể cả default, để tránh Latch.
// Mọi output đều có giá trị mặc định an toàn khai báo đầu khối.
//=============================================================================
always_comb begin : fsm_comb

    //── Safe defaults (ngăn Latch) ─────────────────────────────────────────────
    ns                 = ps;       // giữ nguyên trạng thái nếu không có điều kiện
    HREADYOUT_DEFAULT  = 1'b1;    // slave sẵn sàng
    HRESP_DEFAULT      = R_OKAY;  // không có lỗi

    case (ps)

        //======================================================================
        // ST_IDLE
        // Default Slave không được chọn hoặc chỉ nhận IDLE/BUSY.
        // Phải giữ HREADYOUT=1 và HRESP=OKAY để pipeline không bị nghẽn.
        //======================================================================
        ST_IDLE : begin
            HREADYOUT_DEFAULT = 1'b1;
            HRESP_DEFAULT     = R_OKAY;

            if (active_transfer)
                ns = ST_ERROR_CYC1;   // NONSEQ/SEQ → bắt đầu chuỗi lỗi
            else
                ns = ST_IDLE;         // IDLE/BUSY hoặc không được chọn
        end

        //======================================================================
        // ST_ERROR_CYC1 — Chu kỳ 1 (Penultimate Cycle per IHI0011A §3.9.3)
        //
        // Kéo HREADYOUT=0 để chèn Wait-state.
        // Master nhận HRESP=ERROR nhưng chưa kết thúc giao dịch (HREADY còn thấp).
        // Đây là tín hiệu để Master chuẩn bị hủy bỏ địa chỉ pipeline tiếp theo
        // và đặt HTRANS = IDLE ở chu kỳ kế.
        //======================================================================
        ST_ERROR_CYC1 : begin
            HREADYOUT_DEFAULT = 1'b0;   // chèn wait-state
            HRESP_DEFAULT     = R_ERROR;
            ns                = ST_ERROR_CYC2; // luôn chuyển sang chu kỳ 2
        end

        //======================================================================
        // ST_ERROR_CYC2 — Chu kỳ 2 (Final Cycle per IHI0011A §3.9.3)
        //
        // Kéo ngược HREADYOUT=1 để kết thúc giao dịch, duy trì HRESP=ERROR.
        // Master xác nhận lỗi và giao dịch được đóng an toàn.
        // Quay về ST_IDLE để sẵn sàng bắt giao dịch tiếp theo.
        //======================================================================
        ST_ERROR_CYC2 : begin
            HREADYOUT_DEFAULT = 1'b1;   // kết thúc giao dịch lỗi
            HRESP_DEFAULT     = R_ERROR;
            ns                = ST_IDLE; // trở về nghỉ; master sẽ gửi IDLE tiếp theo
        end

        //── Catch-all: trạng thái mã hóa bất hợp lệ → phục hồi về IDLE ───────
        default : begin
            HREADYOUT_DEFAULT = 1'b1;
            HRESP_DEFAULT     = R_OKAY;
            ns                = ST_IDLE;
        end

    endcase
end : fsm_comb

endmodule
//=============================================================================
// End of AHB_Default_Slave.sv
//=============================================================================