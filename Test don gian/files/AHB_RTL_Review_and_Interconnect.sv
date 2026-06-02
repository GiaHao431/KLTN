// =============================================================================
//  AHB 2.0 Multi-Master Interconnect — Full RTL Review & Integration Package
//  Senior RTL Design & Integration Engineer Review
// =============================================================================
//
//  REVIEW SUMMARY
//  ══════════════
//  Module                   | Issues Found & Fixed
//  ─────────────────────────┼──────────────────────────────────────────────────
//  AHB_Arbiter              | OK — no changes needed
//  ahb_decoder              | OK — no changes needed
//  ahb_addr_ctrl_mux        | FIXED (3 bugs — see §R3)
//  ahb_write_data_mux       | FIXED (2 bugs — see §R4)
//  ahb_read_data_mux        | OK — no changes needed
//  ahb_resp_mux             | OK — no changes needed
//  ahb_ready_mux            | OK — no changes needed
//  AHB_Slave                | OK — no changes needed
//  AHB_Default_Slave        | OK — no changes needed
//  AHB_Interconnect (TOP)   | WRITTEN FROM SCRATCH (see §TOP)
// =============================================================================


// ─────────────────────────────────────────────────────────────────────────────
// §R1  AHB_Arbiter  ──  NO CHANGES REQUIRED
// ─────────────────────────────────────────────────────────────────────────────
//  • All always_ff use <=, all always_comb use =.
//  • unique case + explicit default in every comb block → no latches.
//  • Async reset via negedge HRESETn, consistent with the rest of the system.
//  • Race-condition mitigation is thoroughly documented in the module header.
//  → Source is production-ready as delivered.
// ─────────────────────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// §R2  ahb_decoder  ──  NO CHANGES REQUIRED
// ─────────────────────────────────────────────────────────────────────────────
//  • Pure combinational (always_comb), all outputs default-assigned at entry
//    → zero risk of inferred latches.
//  • No sequential elements → reset polarity not applicable.
//  • MUX_SEL[1:0] encoding matches the spec (2'b00–2'b11).
// ─────────────────────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// §R3  ahb_addr_ctrl_mux  ──  3 BUGS FIXED
// ─────────────────────────────────────────────────────────────────────────────
//
//  BUG 1 — WRONG MUX SELECTION LOGIC (CRITICAL)
//    The design specification §3.3 and the Yêu cầu 3 (Mux Selection Rule)
//    define:  HMASTER_SEL == 4'd1  → Master 1 drives the bus
//             HMASTER_SEL == 4'd2  → Master 2 drives the bus
//             HMASTER_SEL == 4'd0  → idle / no master (safe-state = M1 signals)
//    The original code had the channels SWAPPED:
//      if (HMASTER_SEL == 4'd0)  → routed M1 signals   ← wrong label for idle
//      else if (HMASTER_SEL == 4'd1) → routed M2 signals ← off-by-one error
//    Fixed: correct enumeration 1→M1, 2→M2, default→M1 idle-safe-state.
//
//  BUG 2 — INCOMPLETE CASE (POTENTIAL INFERRED LATCH)
//    The if-else chain had no final else branch. In synthesis, if HMASTER_SEL
//    holds a value ≠ 4'd0 and ≠ 4'd1 (e.g. 4'd2 during SPLIT unmasking), all
//    five output buses would be undriven → inferred multi-bit latches.
//    Fixed: added a default else clause that drives the idle safe-state.
//
//  BUG 3 — MISSING TIMESCALE DIRECTIVE
//    All other modules carry `timescale 1ns/1ps; the addr_ctrl_mux was missing
//    it, which would cause elaboration warnings in mixed-timescale simulations.
//    Fixed: directive added.
// ─────────────────────────────────────────────────────────────────────────────

`timescale 1ns / 1ps

module ahb_addr_ctrl_mux (
    // Arbiter output: 0=idle, 1=Master1, 2=Master2
    input  logic [3:0]  HMASTER_SEL,

    // Master 1 address & control
    input  logic [31:0] HADDR_M1,
    input  logic [1:0]  HTRANS_M1,
    input  logic        HWRITE_M1,
    input  logic [2:0]  HSIZE_M1,
    input  logic [2:0]  HBURST_M1,

    // Master 2 address & control
    input  logic [31:0] HADDR_M2,
    input  logic [1:0]  HTRANS_M2,
    input  logic        HWRITE_M2,
    input  logic [2:0]  HSIZE_M2,
    input  logic [2:0]  HBURST_M2,

    // Broadcast to all Slaves (and Decoder)
    output logic [31:0] HADDR_S,
    output logic [1:0]  HTRANS_S,
    output logic        HWRITE_S,
    output logic [2:0]  HSIZE_S,
    output logic [2:0]  HBURST_S
);

    always_comb begin
        // ── Safe default: idle / no master granted → drive M1 bus-idle values
        // (Prevents inferred latches on all five output buses)
        HADDR_S  = HADDR_M1;
        HTRANS_S = HTRANS_M1;
        HWRITE_S = HWRITE_M1;
        HSIZE_S  = HSIZE_M1;
        HBURST_S = HBURST_M1;

        // ── BUG 1 FIX: correct mapping 1→M1, 2→M2 ─────────────────────────
        if (HMASTER_SEL == 4'd1) begin          // Master 1 owns the bus
            HADDR_S  = HADDR_M1;
            HTRANS_S = HTRANS_M1;
            HWRITE_S = HWRITE_M1;
            HSIZE_S  = HSIZE_M1;
            HBURST_S = HBURST_M1;
        end else if (HMASTER_SEL == 4'd2) begin // Master 2 owns the bus
            HADDR_S  = HADDR_M2;
            HTRANS_S = HTRANS_M2;
            HWRITE_S = HWRITE_M2;
            HSIZE_S  = HSIZE_M2;
            HBURST_S = HBURST_M2;
        end
        // else: idle (4'd0) or illegal encoding → retains the safe default above
        // ── BUG 2 FIX: implicit else + top-of-block defaults = no latches ──
    end

endmodule : ahb_addr_ctrl_mux


// ─────────────────────────────────────────────────────────────────────────────
// §R4  ahb_write_data_mux  ──  2 BUGS FIXED
// ─────────────────────────────────────────────────────────────────────────────
//
//  BUG 1 — WRONG PORT WIDTH FOR HMASTER_SEL (CRITICAL)
//    The spec (§6.2) says HMASTER_SEL is driven by the Arbiter output HMASTER
//    which is 4 bits wide.  The original module declared it as `logic` (1-bit),
//    causing a silent truncation: only bit[0] of the 4-bit HMASTER was sampled,
//    making Master 2 (4'd2 = 4'b0010) look identical to idle (4'd0 = all-zero
//    bit[0] = 0) → HWDATA was always routed from Master 1 regardless of grant.
//    Fixed: port widened to logic [3:0] HMASTER_SEL.
//
//  BUG 2 — MATCHING LATCH RISK IN COMBINATIONAL MUX
//    The if-else chain for HWDATA_S had no default clause and no top-of-block
//    default assignment. If HMASTER_SEL carried an unexpected value (e.g. 4'd0
//    idle), HWDATA_S would be undriven → 32-bit inferred latch.
//    Fixed: top-of-block default assignment (safe-state = HWDATA_M1).
//
//  NOTE: The pipeline register correctly uses <= (non-blocking) and the
//  combinational mux correctly uses = (blocking). No race-condition issues.
// ─────────────────────────────────────────────────────────────────────────────

`timescale 1ns / 1ps

module ahb_write_data_mux (
    input  logic        HCLK,
    input  logic        HRESETn,
    input  logic        HREADY,          // Global ready → pipeline register enable

    // ── BUG 1 FIX: widened from 1-bit to 4-bit to match HMASTER from Arbiter
    input  logic [3:0]  HMASTER_SEL,

    input  logic [31:0] HWDATA_M1,
    input  logic [31:0] HWDATA_M2,

    output logic [31:0] HWDATA_S
);

    logic [3:0] master_sel_data_phase;   // widened to match port

    // ── Sequential: pipeline register (non-blocking — correct) ──────────────
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            master_sel_data_phase <= 4'd0;
        else if (HREADY)
            master_sel_data_phase <= HMASTER_SEL;
    end

    // ── Combinational: data routing (blocking — correct) ─────────────────────
    always_comb begin
        // ── BUG 2 FIX: safe default at top of block → no inferred latch ─────
        HWDATA_S = HWDATA_M1;   // idle / unknown → M1 safe-state

        if (master_sel_data_phase == 4'd1)
            HWDATA_S = HWDATA_M1;
        else if (master_sel_data_phase == 4'd2)
            HWDATA_S = HWDATA_M2;
        // else (4'd0 idle or illegal): retains default above
    end

endmodule : ahb_write_data_mux


// ─────────────────────────────────────────────────────────────────────────────
// §R5  ahb_read_data_mux  ──  NO CHANGES REQUIRED
// ─────────────────────────────────────────────────────────────────────────────
//  • Pipeline register uses <=, comb mux uses =. Correct.
//  • case statement has explicit default → no latches.
//  • MUX_SEL / mux_sel_data_phase are 2-bit, matching the Decoder output.
//  • HRDATA buses are 32-bit, consistent with the SoC specification.
// ─────────────────────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// §R6  ahb_resp_mux  ──  NO CHANGES REQUIRED
// ─────────────────────────────────────────────────────────────────────────────
//  • Pipeline register uses <=, comb mux uses =. Correct.
//  • All four case arms covered + default → no latches.
//  • HRESP buses are 2-bit, consistent with AHB spec Table 3-5.
// ─────────────────────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// §R7  ahb_ready_mux  ──  NO CHANGES REQUIRED
// ─────────────────────────────────────────────────────────────────────────────
//  • Pipeline register uses <=, comb mux uses =. Correct.
//  • All four case arms covered + default → no latches.
//  • Self-feedback (HREADY = HREADY_GLOBAL) is intentional per AHB spec §3.8
//    and is handled correctly at the Top level (see §TOP wire connections).
// ─────────────────────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// §R8  AHB_Slave  ──  NO CHANGES REQUIRED
// ─────────────────────────────────────────────────────────────────────────────
//  • Five sequential blocks all use <=. Comb FSM uses =. Correct.
//  • Safe defaults at top of comb block → no latches.
//  • Async reset (negedge HRESETn) consistent with the system.
// ─────────────────────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// §R9  AHB_Default_Slave  ──  NO CHANGES REQUIRED
// ─────────────────────────────────────────────────────────────────────────────
//  • FSM sequential uses <=, comb uses =. Correct.
//  • All three FSM states + default covered → no latches.
//  • Async reset (negedge HRESETn) consistent with the system.
// ─────────────────────────────────────────────────────────────────────────────


// =============================================================================
// §TOP  AHB_Interconnect  ──  TOP-LEVEL MODULE (FULL IMPLEMENTATION)
// =============================================================================
//
//  INTEGRATION NOTES
//  ─────────────────
//  1. HMASTER (4-bit) from the Arbiter is used DIRECTLY as the select signal
//     for ahb_addr_ctrl_mux (HMASTER_SEL) and ahb_write_data_mux (HMASTER_SEL).
//     This is consistent with the R3 / R4 fixes above (1→M1, 2→M2).
//
//  2. MUX_SEL (2-bit) from the Decoder is shared by ahb_read_data_mux,
//     ahb_resp_mux, and ahb_ready_mux.  Each of those modules registers it
//     internally on HREADY, providing the mandatory 1-cycle pipeline delay
//     between Address Phase and Data Phase.
//
//  3. HREADY feedback loop:
//       HREADY_GLOBAL (output of ahb_ready_mux)
//         ↳ feeds back into every Registered Mux's HREADY enable port
//         ↳ also broadcast to all Slaves as HREADY_IN (= HREADY_GLOBAL)
//         ↳ also connected to top output port HREADY (Master feedback)
//     This single wire implements the AHB §3.8 HREADY synchronisation point.
//
//  4. SPLIT aggregation:
//       HSPLIT_COMBINED = HSPLIT_S1 | HSPLIT_S2 | HSPLIT_S3
//     Only three functional Slaves can issue SPLIT; Default Slave cannot.
//
//  5. The top-level HREADY_GLOBAL port is exposed so an external testbench
//     can observe it; it is the same wire as HREADY driven to Masters.
//
//  6. Port HRESP_M and HRDATA_M are routed only to the active Master; since
//     both Masters share the same return bus (per spec §1.5.2), they are
//     broadcast identically. Each Master uses its own HGRANT to know when
//     the data is valid for it.
// =============================================================================

`timescale 1ns / 1ps

module AHB_Interconnect (
    // ── 1. System Signals ────────────────────────────────────────────────────
    input  wire        HCLK,
    input  wire        HRESETn,

    // ── 2. Master 1 Interface ────────────────────────────────────────────────
    input  wire        HBUSREQ_M1,
    input  wire        HLOCK_M1,
    input  wire [31:0] HADDR_M1,
    input  wire [31:0] HWDATA_M1,
    input  wire [1:0]  HTRANS_M1,
    input  wire        HWRITE_M1,
    input  wire [2:0]  HSIZE_M1,
    input  wire [2:0]  HBURST_M1,
    output wire        HGRANT_M1,

    // ── 3. Master 2 Interface ────────────────────────────────────────────────
    input  wire        HBUSREQ_M2,
    input  wire        HLOCK_M2,
    input  wire [31:0] HADDR_M2,
    input  wire [31:0] HWDATA_M2,
    input  wire [1:0]  HTRANS_M2,
    input  wire        HWRITE_M2,
    input  wire [2:0]  HSIZE_M2,
    input  wire [2:0]  HBURST_M2,
    output wire        HGRANT_M2,

    // ── 4. Shared Master Feedback ────────────────────────────────────────────
    output wire [31:0] HRDATA_M,
    output wire [1:0]  HRESP_M,
    output wire        HREADY,          // = HREADY_GLOBAL (master-facing)

    // ── 5. Slave Broadcast Signals ───────────────────────────────────────────
    output wire [31:0] HADDR_S,
    output wire [31:0] HWDATA_S,
    output wire [1:0]  HTRANS_S,
    output wire        HWRITE_S,
    output wire [2:0]  HSIZE_S,
    output wire [2:0]  HBURST_S,
    output wire [3:0]  HMASTER,
    output wire        HMASTLOCK,
    output wire        HREADY_GLOBAL,   // = HREADY; also broadcast to Slaves

    // ── 6. Slave Individual Select Signals (from Decoder) ────────────────────
    output wire        HSEL_S1,
    output wire        HSEL_S2,
    output wire        HSEL_S3,
    output wire        HSEL_DEFAULT,

    // ── 7. Slave Functional Feedback ─────────────────────────────────────────
    input  wire [31:0] HRDATA_S1,
    input  wire [31:0] HRDATA_S2,
    input  wire [31:0] HRDATA_S3,
    input  wire [1:0]  HRESP_S1,
    input  wire [1:0]  HRESP_S2,
    input  wire [1:0]  HRESP_S3,
    input  wire        HREADYOUT_S1,
    input  wire        HREADYOUT_S2,
    input  wire        HREADYOUT_S3,
    input  wire [15:0] HSPLIT_S1,
    input  wire [15:0] HSPLIT_S2,
    input  wire [15:0] HSPLIT_S3,

    // ── 8. Default Slave Feedback ─────────────────────────────────────────────
    input  wire        HREADYOUT_DEFAULT,
    input  wire [1:0]  HRESP_DEFAULT
);

    // =========================================================================
    // ❶  Internal Wires
    // =========================================================================

    // ── Arbiter outputs ───────────────────────────────────────────────────────
    // HMASTER and HMASTLOCK are declared as module output ports; they are driven
    // by the Arbiter and broadcast directly to Slaves and the addr/ctrl mux.
    // HGRANT_M1 / HGRANT_M2 are also module output ports driven by the Arbiter.

    // ── Decoder outputs ───────────────────────────────────────────────────────
    // HSEL_S1/S2/S3/DEFAULT are module output ports driven by the Decoder.
    wire [1:0] MUX_SEL;            // Slave-select code (Address Phase)

    // ── SPLIT aggregation ─────────────────────────────────────────────────────
    wire [15:0] HSPLIT_COMBINED;

    // ── Ready global (internal alias) ─────────────────────────────────────────
    // HREADY_GLOBAL is a top-level output port. It is also looped back into every
    // Registered Mux's enable input and into the Arbiter's HREADY port.
    // The continuous assignment below ties the two top-level output ports together.
    assign HREADY = HREADY_GLOBAL;  // Master-facing HREADY ≡ global ready signal

    // =========================================================================
    // ❷  SPLIT Aggregator  (§TOP Note 4)
    //     Bitwise OR of all three SPLIT-capable Slave buses.
    //     Default Slave does NOT participate → not included.
    // =========================================================================
    assign HSPLIT_COMBINED = HSPLIT_S1 | HSPLIT_S2 | HSPLIT_S3;

    // =========================================================================
    // ❸  Arbiter Instantiation
    // =========================================================================
    AHB_Arbiter u_arbiter (
        // System
        .HCLK             (HCLK),
        .HRESETn          (HRESETn),

        // Master bus-request and lock inputs
        .HBUSREQ_M1       (HBUSREQ_M1),
        .HBUSREQ_M2       (HBUSREQ_M2),
        .HLOCK_M1         (HLOCK_M1),
        .HLOCK_M2         (HLOCK_M2),

        // Bus status (from shared bus, after addr/ctrl mux)
        .HTRANS_S         (HTRANS_S),       // looped back from addr/ctrl mux output
        .HBURST_S         (HBURST_S),       // looped back from addr/ctrl mux output

        // Global ready and response (from Ready/Response Mux)
        .HREADY           (HREADY_GLOBAL),
        .HRESP_S          (HRESP_M),        // response seen by Arbiter = same bus as Masters

        // SPLIT completion (aggregated)
        .HSPLIT_COMBINED  (HSPLIT_COMBINED),

        // Arbiter outputs → top-level ports
        .HGRANT_M1        (HGRANT_M1),
        .HGRANT_M2        (HGRANT_M2),
        .HMASTER          (HMASTER),
        .HMASTLOCK        (HMASTLOCK)
    );

    // =========================================================================
    // ❹  Decoder Instantiation
    //     Pure combinational, no clock/reset ports.
    // =========================================================================
    ahb_decoder u_decoder (
        // Input: shared address bus (after addr/ctrl mux)
        .HADDR_S          (HADDR_S),

        // Outputs: individual slave selects → top-level ports
        .HSEL_S1          (HSEL_S1),
        .HSEL_S2          (HSEL_S2),
        .HSEL_S3          (HSEL_S3),
        .HSEL_DEFAULT     (HSEL_DEFAULT),

        // Output: pipeline-registered Mux select code (shared by 3 Muxes)
        .MUX_SEL          (MUX_SEL)
    );

    // =========================================================================
    // ❺  Address & Control Multiplexer
    //     Pure combinational. Selects the active Master's address and control
    //     signals to drive the shared slave bus.
    //     HMASTER (4-bit) from Arbiter: 0=idle, 1=M1, 2=M2.
    // =========================================================================
    ahb_addr_ctrl_mux u_addr_ctrl_mux (
        // Select from Arbiter (4-bit HMASTER, fixed in §R3)
        .HMASTER_SEL      (HMASTER),

        // Master 1 address & control
        .HADDR_M1         (HADDR_M1),
        .HTRANS_M1        (HTRANS_M1),
        .HWRITE_M1        (HWRITE_M1),
        .HSIZE_M1         (HSIZE_M1),
        .HBURST_M1        (HBURST_M1),

        // Master 2 address & control
        .HADDR_M2         (HADDR_M2),
        .HTRANS_M2        (HTRANS_M2),
        .HWRITE_M2        (HWRITE_M2),
        .HSIZE_M2         (HSIZE_M2),
        .HBURST_M2        (HBURST_M2),

        // Broadcast outputs → top-level Slave broadcast ports
        .HADDR_S          (HADDR_S),
        .HTRANS_S         (HTRANS_S),
        .HWRITE_S         (HWRITE_S),
        .HSIZE_S          (HSIZE_S),
        .HBURST_S         (HBURST_S)
    );

    // =========================================================================
    // ❻  Write Data Multiplexer  (Registered Mux)
    //     Delays HMASTER_SEL by 1 cycle (gated by HREADY) to align with the
    //     AHB Data Phase. Selects HWDATA from the previously-granted Master.
    // =========================================================================
    ahb_write_data_mux u_write_data_mux (
        .HCLK             (HCLK),
        .HRESETn          (HRESETn),
        .HREADY           (HREADY_GLOBAL),  // pipeline enable (§TOP Note 3)

        // Select: 4-bit HMASTER from Arbiter (fixed in §R4)
        .HMASTER_SEL      (HMASTER),

        // Write data from both Masters
        .HWDATA_M1        (HWDATA_M1),
        .HWDATA_M2        (HWDATA_M2),

        // Output: broadcast write data bus → top-level port
        .HWDATA_S         (HWDATA_S)
    );

    // =========================================================================
    // ❼  Read Data Multiplexer  (Registered Mux)
    //     Delays MUX_SEL from Decoder by 1 cycle (gated by HREADY) to align
    //     read data returned from the Slave with the AHB Data Phase.
    // =========================================================================
    ahb_read_data_mux u_read_data_mux (
        .HCLK             (HCLK),
        .HRESETn          (HRESETn),
        .HREADY           (HREADY_GLOBAL),  // pipeline enable

        // Slave select code from Decoder (Address Phase)
        .MUX_SEL          (MUX_SEL),

        // Read data from three functional Slaves
        .HRDATA_S1        (HRDATA_S1),
        .HRDATA_S2        (HRDATA_S2),
        .HRDATA_S3        (HRDATA_S3),

        // Output: shared read data bus to all Masters → top-level port
        .HRDATA_M         (HRDATA_M)
    );

    // =========================================================================
    // ❽  Response Multiplexer  (Registered Mux)
    //     Same pipeline-delay structure as the read-data mux.
    //     Routes HRESP from the selected Slave to the shared Master return bus.
    // =========================================================================
    ahb_resp_mux u_resp_mux (
        .HCLK             (HCLK),
        .HRESETn          (HRESETn),
        .HREADY           (HREADY_GLOBAL),  // pipeline enable

        // Slave select code from Decoder (Address Phase)
        .MUX_SEL          (MUX_SEL),

        // Slave response codes
        .HRESP_S1         (HRESP_S1),
        .HRESP_S2         (HRESP_S2),
        .HRESP_S3         (HRESP_S3),
        .HRESP_DEFAULT    (HRESP_DEFAULT),

        // Output: shared response bus to all Masters → top-level port
        .HRESP_M          (HRESP_M)
    );

    // =========================================================================
    // ❾  Ready Multiplexer  (Registered Mux)
    //     Routes HREADYOUT from the currently-active Slave to the global
    //     HREADY_GLOBAL wire.  Its own output is fed back to its HREADY enable
    //     input, closing the synchronisation feedback loop (§TOP Note 3).
    // =========================================================================
    ahb_ready_mux u_ready_mux (
        .HCLK              (HCLK),
        .HRESETn           (HRESETn),
        // Self-feedback: HREADY_GLOBAL is the output of this module and is
        // simultaneously its own pipeline-register enable. This is correct and
        // intentional — it is the AHB §3.8 handshake point.
        .HREADY            (HREADY_GLOBAL),

        // Slave select code from Decoder (Address Phase)
        .MUX_SEL           (MUX_SEL),

        // Individual ready signals from all four Slave ports
        .HREADYOUT_S1      (HREADYOUT_S1),
        .HREADYOUT_S2      (HREADYOUT_S2),
        .HREADYOUT_S3      (HREADYOUT_S3),
        .HREADYOUT_DEFAULT (HREADYOUT_DEFAULT),

        // Output: global ready signal → top-level port
        // (also looped back to all Registered Mux enables and to Arbiter)
        .HREADY_GLOBAL     (HREADY_GLOBAL)
    );

endmodule : AHB_Interconnect

// =============================================================================
// End of AHB RTL Review & Integration Package
// =============================================================================
