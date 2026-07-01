//  INTEGRATION NOTES
//  ─────────────────
//  1. HMASTER (4-bit) from the Arbiter is used DIRECTLY as the select signal
//     for ahb_addr_ctrl_mux (HMASTER_SEL) and ahb_write_data_mux (HMASTER_SEL).
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
    //     HMASTER (4-bit) from Arbiter: 3=idle, 0=M1, 1=M2.
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
 
endmodule