`timescale 1ns / 1ps
//=============================================================================
// Module      : AHB_Arbiter
// Project     : AHB 2.0 Multi-master Interconnect (2 Masters, 3 Slaves)
// Language    : SystemVerilog (IEEE 1800-2012)
// Revision    : 2.0  — HMASTER encoding changed to user convention (0=M1, 1=M2)
//
// Description :
//   Bus arbiter for an AMBA AHB 2.0 multi-master system. Implements a
//   3-state Moore FSM (ST_IDLE / ST_GNT_M1 / ST_GNT_M2) with:
//     • Round-Robin fairness via `last_master_q` register
//     • HREADY-gated handover synchronisation
//     • Locked-transfer (HMASTLOCK) enforcement
//     • SPLIT response handling with per-master mask registers
//
// HMASTER Encoding Convention (v2):
//   ┌─────────────────┬──────────────────────────────────────────────┐
//   │  HMASTER value  │  Meaning                                     │
//   ├─────────────────┼──────────────────────────────────────────────┤
//   │     4'd0        │  Master 1 owns bus  (also emitted at IDLE)   │
//   │     4'd1        │  Master 2 owns bus                           │
//   │  others (≥2)    │  Reserved / illegal — MUX defaults to M1     │
//   └─────────────────┴──────────────────────────────────────────────┘
//   Rationale: 0-based index (0=M1, 1=M2) is cleaner for small-N systems.
//   IDLE state outputs 4'd0 (same as M1-granted); the MUX treats them
//   identically — when idle, M1 holds HTRANS=IDLE so the shared bus
//   appears idle regardless.
//
// Race-Condition Mitigation:
//   - All combinational logic derived exclusively from registered signals.
//   - Non-blocking (<=) in always_ff; blocking (=) in always_comb.
//   - `unique case` throughout; explicit default in every case statement.
//
//=============================================================================

module AHB_Arbiter (
    input  logic        HCLK,
    input  logic        HRESETn,

    input  logic        HBUSREQ_M1,
    input  logic        HBUSREQ_M2,
    input  logic        HLOCK_M1,
    input  logic        HLOCK_M2,

    input  logic [1:0]  HTRANS_S,
    input  logic [2:0]  HBURST_S,
    input  logic        HREADY,
    input  logic [1:0]  HRESP_S,

    input  logic [15:0] HSPLIT_COMBINED,

    output logic        HGRANT_M1,
    output logic        HGRANT_M2,
    output logic [3:0]  HMASTER,
    output logic        HMASTLOCK
);

    localparam logic [1:0] RESP_OKAY  = 2'b00;
    localparam logic [1:0] RESP_ERROR = 2'b01;
    localparam logic [1:0] RESP_RETRY = 2'b10;
    localparam logic [1:0] RESP_SPLIT = 2'b11;

    localparam int unsigned SPLIT_BIT_M1 = 0;  // v2: HMASTER=0 for M1
    localparam int unsigned SPLIT_BIT_M2 = 1;  // v2: HMASTER=1 for M2

    typedef enum logic [1:0] {
        ST_IDLE   = 2'b00,
        ST_GNT_M1 = 2'b01,
        ST_GNT_M2 = 2'b10
    } arb_state_e;

    arb_state_e  state_q;
    logic [1:0]  last_master_q;
    logic        split_mask_m1_q;
    logic        split_mask_m2_q;

    arb_state_e  state_d;
    logic        eff_req_m1;
    logic        eff_req_m2;
    logic        split_confirmed;

    // ── FIX L3-7v2: Idle-grant counter (replaces premature grant_settled) ──
    //    Arbiter chỉ switch khi master idle >= 4 cycle liên tiếp.
    //    Tránh toggling mỗi 1-2 cycle gây mất transfer + corrupt pipeline.
    arb_state_e  prev_state_q;
    logic [2:0]  idle_grant_cnt;
    logic        idle_force_switch;

    // ── FIX L3-8: Burst protection (prevents mid-burst preemption) ──
    logic        burst_active;
    logic [5:0]  burst_remaining;

    assign eff_req_m1 = HBUSREQ_M1 & ~split_mask_m1_q;
    assign eff_req_m2 = HBUSREQ_M2 & ~split_mask_m2_q;
    assign split_confirmed = (HRESP_S == RESP_SPLIT) & HREADY;

    // idle_force_switch = 1 khi master được grant nhưng idle >= 4 cycle.
    // Override round-robin để break deadlock. Threshold 4 đủ cho BFM
    // drive NONSEQ (chỉ cần 2 cycle) mà không bị premature switch.
    assign idle_force_switch = (idle_grant_cnt >= 3'd4);

    always_comb begin : NEXT_STATE_PROC
        state_d = state_q;

        unique case (state_q)
            ST_IDLE: begin
                if (eff_req_m1 && (!eff_req_m2 || last_master_q == 2'd2))
                    state_d = ST_GNT_M1;
                else if (eff_req_m2 && (!eff_req_m1 || last_master_q == 2'd1))
                    state_d = ST_GNT_M2;
            end

            ST_GNT_M1: begin
                // ── FIX (priority correction, IHI0011A §3.11.5 / §3.12.3) ──
                // HLOCK (and an in-progress burst) MUST take priority over a
                // SPLIT response.  A locked master is never de-granted: per
                // §3.11.5 the arbiter keeps it granted until the locked
                // sequence completes, and §3.12.3 states a locked transfer
                // must complete before any other transfer continues.  Only an
                // UNLOCKED master may be split off the bus.
                if (HLOCK_M1 || burst_active) begin
                    state_d = ST_GNT_M1;
                end else if (split_confirmed) begin
                    state_d = eff_req_m2 ? ST_GNT_M2 : ST_IDLE;
                end else if (HREADY) begin
                    if (!eff_req_m1 && !eff_req_m2)
                        state_d = ST_IDLE;
                    else if (eff_req_m2 && (!eff_req_m1 || last_master_q == 2'd1 || idle_force_switch))
                        state_d = ST_GNT_M2;
                    else
                        state_d = ST_GNT_M1;
                end
            end

            ST_GNT_M2: begin
                // ── FIX (priority correction, IHI0011A §3.11.5 / §3.12.3) ──
                // Same rule as ST_GNT_M1: HLOCK/burst override SPLIT.
                if (HLOCK_M2 || burst_active) begin
                    state_d = ST_GNT_M2;
                end else if (split_confirmed) begin
                    state_d = eff_req_m1 ? ST_GNT_M1 : ST_IDLE;
                end else if (HREADY) begin
                    if (!eff_req_m1 && !eff_req_m2)
                        state_d = ST_IDLE;
                    else if (eff_req_m1 && (!eff_req_m2 || last_master_q == 2'd2 || idle_force_switch))
                        state_d = ST_GNT_M1;
                    else
                        state_d = ST_GNT_M2;
                end
            end

            default: state_d = ST_IDLE;
        endcase
    end : NEXT_STATE_PROC

    always_ff @(posedge HCLK or negedge HRESETn) begin : SEQ_PROC
        if (!HRESETn) begin
            state_q         <= ST_IDLE;
            last_master_q   <= 2'd2;
            split_mask_m1_q <= 1'b0;
            split_mask_m2_q <= 1'b0;
        end else begin
            state_q <= state_d;

            // Round-robin: ghi nhận master hiện tại KHI nó thực hiện transfer
            // (HTRANS_S != IDLE && HREADY = 1). KHÔNG update khi master idle.
            // Deadlock prevention nằm ở idle_force_switch (NEXT_STATE_PROC),
            // KHÔNG ở last_master_q — tránh premature update gây toggling.
            if      (state_q == ST_GNT_M1 && HTRANS_S != 2'b00 && HREADY)
                last_master_q <= 2'd1;
            else if (state_q == ST_GNT_M2 && HTRANS_S != 2'b00 && HREADY)
                last_master_q <= 2'd2;

            // ── FIX (§3.11.5/§3.12.3): never split-mask a LOCKED master ──
            // A master performing a locked sequence keeps full arbitration
            // priority even if its transfer receives SPLIT; it is not added to
            // the split-mask "blacklist".  Masking is therefore qualified with
            // !HLOCK_Mx.  (In ST_GNT_Mx, HMASTLOCK == HLOCK_Mx.)
            if (HSPLIT_COMBINED[SPLIT_BIT_M1])
                split_mask_m1_q <= 1'b0;
            else if (state_q == ST_GNT_M1 && HRESP_S == RESP_SPLIT && !HLOCK_M1)
                split_mask_m1_q <= 1'b1;

            if (HSPLIT_COMBINED[SPLIT_BIT_M2])
                split_mask_m2_q <= 1'b0;
            else if (state_q == ST_GNT_M2 && HRESP_S == RESP_SPLIT && !HLOCK_M2)
                split_mask_m2_q <= 1'b1;
        end
    end : SEQ_PROC

    // ── FIX L3-7v2: Idle-Grant Counter ──────────────────────────────
    //    Đếm số cycle liên tiếp mà master được grant nhưng idle (HTRANS=IDLE).
    //    Reset khi: (a) có transfer active, (b) bus ở IDLE state, hoặc
    //    (c) state vừa thay đổi (state_q ≠ prev_state_q).
    //    Khi counter >= 4: idle_force_switch = 1 → override round-robin.
    //    Threshold 4 cho BFM đủ thời gian drive NONSEQ (cần 2 cycle):
    //      Cycle 0: State change, ensure_grant exit. Counter = 0.
    //      Cycle 1: @posedge+#1 → BFM drives NONSEQ. Counter = 0 (state change detect).
    //      Cycle 2: HTRANS_S = NONSEQ → counter reset. Không bao giờ đạt 4.
    always_ff @(posedge HCLK or negedge HRESETn) begin : PREV_STATE_PROC
        if (!HRESETn)
            prev_state_q <= ST_IDLE;
        else
            prev_state_q <= state_q;
    end : PREV_STATE_PROC

    always_ff @(posedge HCLK or negedge HRESETn) begin : IDLE_GRANT_PROC
        if (!HRESETn) begin
            idle_grant_cnt <= 3'd0;
        end else begin
            if (HTRANS_S != 2'b00 || state_q == ST_IDLE || state_q != prev_state_q)
                idle_grant_cnt <= 3'd0;
            else if ((state_q == ST_GNT_M1 || state_q == ST_GNT_M2) &&
                     HREADY && idle_grant_cnt < 3'd7)
                idle_grant_cnt <= idle_grant_cnt + 3'd1;
        end
    end : IDLE_GRANT_PROC

    // ── FIX L3-8: Burst Protection Tracking ─────────────────────────────
    //    Theo AHB spec, fixed-length burst KHÔNG được preempt giữa chừng.
    //    burst_active = 1 khi đang trong burst (INCR4/8/16, WRAP4/8/16).
    //    burst_remaining đếm số beat còn lại (trừ beat NONSEQ đầu tiên).
    //    SINGLE và INCR (undefined) KHÔNG được bảo vệ (có thể preempt).
    always_ff @(posedge HCLK or negedge HRESETn) begin : BURST_TRACK_PROC
        if (!HRESETn) begin
            burst_active    <= 1'b0;
            burst_remaining <= 6'd0;
        end else if (HREADY) begin
            if (HTRANS_S == 2'b10) begin                          // NONSEQ → new transfer
                case (HBURST_S)
                    3'b010, 3'b011: begin                          // WRAP4 / INCR4
                        burst_active    <= 1'b1;
                        burst_remaining <= 6'd3;
                    end
                    3'b100, 3'b101: begin                          // WRAP8 / INCR8
                        burst_active    <= 1'b1;
                        burst_remaining <= 6'd7;
                    end
                    3'b110, 3'b111: begin                          // WRAP16 / INCR16
                        burst_active    <= 1'b1;
                        burst_remaining <= 6'd15;
                    end
                    default: begin                                  // SINGLE / INCR
                        burst_active    <= 1'b0;
                        burst_remaining <= 6'd0;
                    end
                endcase
            end else if (burst_active && HTRANS_S == 2'b11) begin  // SEQ → burst beat
                if (burst_remaining <= 6'd1) begin
                    burst_active    <= 1'b0;
                    burst_remaining <= 6'd0;
                end else begin
                    burst_remaining <= burst_remaining - 6'd1;
                end
            end else if (burst_active && HTRANS_S == 2'b00) begin  // IDLE → early termination
                burst_active    <= 1'b0;
                burst_remaining <= 6'd0;
            end
            // BUSY (2'b01) during burst → no action, keep protecting
        end
    end : BURST_TRACK_PROC

    always_comb begin : OUTPUT_PROC
        HGRANT_M1 = 1'b0;
        HGRANT_M2 = 1'b0;
        HMASTER   = 4'd0;
        HMASTLOCK = 1'b0;

        unique case (state_q)
            ST_GNT_M1: begin
                HGRANT_M1 = 1'b1;
                HGRANT_M2 = 1'b0;
                HMASTER   = 4'd0;   // 0 = M1 owns bus (user encoding)
                HMASTLOCK = HLOCK_M1;
            end
            ST_GNT_M2: begin
                HGRANT_M1 = 1'b0;
                HGRANT_M2 = 1'b1;
                HMASTER   = 4'd1;   // 1 = M2 owns bus (user encoding)
                HMASTLOCK = HLOCK_M2;
            end
            default: begin
                HGRANT_M1 = 1'b0;
                HGRANT_M2 = 1'b0;
                HMASTER   = 4'd0;
                HMASTLOCK = 1'b0;
            end
        endcase
    end : OUTPUT_PROC

endmodule : AHB_Arbiter