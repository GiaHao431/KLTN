`timescale 1ns / 1ps
//=============================================================================
// Module   : AHB_System_Top
// Language : SystemVerilog
//
// Full DUT wrapper for the 2-master / 3-slave (+ default) AHB system.
// Instantiates the fabric (AHB_Interconnect) together with the three
// AHB_Slave instances and the AHB_Default_Slave, and performs all the
// fabric<->slave wiring internally.
//
// Purpose of this wrapper:
//   • AHB_Interconnect is the bus FABRIC only (Arbiter + Decoder + 5 Muxes);
//     it broadcasts the shared bus and consumes slave feedback but does NOT
//     contain the slaves.  This wrapper closes that loop so the whole system
//     is a single port-based DUT.
//   • Exposes the verification-control hooks force_split_sN / force_retry_sN
//     on real PORTS (chosen over hierarchical TB references), one pair per
//     slave, so the eventual testbench/UVM agent connects them through the
//     instance port list — no `dut.u_slaveN.force_*` pokes.
//   • Re-exports the key internal bus-observation signals as outputs so the
//     testbench and coverage can still sample fabric state (HMASTER, HSEL_*,
//     HSPLIT_*, MUX-side bus) without hierarchical access.
//
// NOTE: This wrapper contains NO stimulus/BFM/testbench logic — pure RTL
// structural integration only.
//=============================================================================
module AHB_System_Top #(
    parameter int SEED_S1 = 10,
    parameter int SEED_S2 = 20,
    parameter int SEED_S3 = 30
) (
    //── System ────────────────────────────────────────────────────────────────
    input  wire        HCLK,
    input  wire        HRESETn,

    //── Master 1 Interface (driven by external master/BFM) ────────────────────
    input  wire        HBUSREQ_M1,
    input  wire        HLOCK_M1,
    input  wire [31:0] HADDR_M1,
    input  wire [31:0] HWDATA_M1,
    input  wire [1:0]  HTRANS_M1,
    input  wire        HWRITE_M1,
    input  wire [2:0]  HSIZE_M1,
    input  wire [2:0]  HBURST_M1,
    output wire        HGRANT_M1,

    //── Master 2 Interface ────────────────────────────────────────────────────
    input  wire        HBUSREQ_M2,
    input  wire        HLOCK_M2,
    input  wire [31:0] HADDR_M2,
    input  wire [31:0] HWDATA_M2,
    input  wire [1:0]  HTRANS_M2,
    input  wire        HWRITE_M2,
    input  wire [2:0]  HSIZE_M2,
    input  wire [2:0]  HBURST_M2,
    output wire        HGRANT_M2,

    //── Shared Master Feedback (fabric → masters) ─────────────────────────────
    output wire [31:0] HRDATA_M,
    output wire [1:0]  HRESP_M,
    output wire        HREADY,            // master-facing global ready

    //── Response-Control Test Hooks (verification-only, per slave) ────────────
    // Tie LOW for normal operation.  Drive HIGH on a beat's data phase to make
    // the corresponding slave issue a 2-cycle SPLIT / RETRY (any address, any
    // beat — including mid-burst).  Directed or randomized from the testbench.
    input  wire        force_split_s1,
    input  wire        force_retry_s1,
    input  wire        force_split_s2,
    input  wire        force_retry_s2,
    input  wire        force_split_s3,
    input  wire        force_retry_s3,

    //── Bus-Observation Outputs (for TB / functional coverage) ────────────────
    output wire [31:0] HADDR_S_o,
    output wire [1:0]  HTRANS_S_o,
    output wire        HWRITE_S_o,
    output wire [2:0]  HSIZE_S_o,
    output wire [2:0]  HBURST_S_o,
    output wire [3:0]  HMASTER_o,
    output wire        HMASTLOCK_o,
    output wire        HREADY_GLOBAL_o,
    output wire        HSEL_S1_o,
    output wire        HSEL_S2_o,
    output wire        HSEL_S3_o,
    output wire        HSEL_DEFAULT_o,
    output wire [15:0] HSPLIT_S1_o,
    output wire [15:0] HSPLIT_S2_o,
    output wire [15:0] HSPLIT_S3_o
);

    //=========================================================================
    // Internal fabric <-> slave wiring
    //=========================================================================
    wire [31:0] HADDR_S, HWDATA_S;
    wire [1:0]  HTRANS_S;
    wire        HWRITE_S;
    wire [2:0]  HSIZE_S, HBURST_S;
    wire [3:0]  HMASTER;
    wire        HMASTLOCK;
    wire        HREADY_GLOBAL;
    wire        HSEL_S1, HSEL_S2, HSEL_S3, HSEL_DEFAULT;

    wire [31:0] HRDATA_S1, HRDATA_S2, HRDATA_S3;
    wire [1:0]  HRESP_S1, HRESP_S2, HRESP_S3;
    wire        HREADYOUT_S1, HREADYOUT_S2, HREADYOUT_S3;
    wire [15:0] HSPLIT_S1, HSPLIT_S2, HSPLIT_S3;
    wire        HREADYOUT_DEFAULT;
    wire [1:0]  HRESP_DEFAULT;

    //=========================================================================
    // Bus-observation output taps
    //=========================================================================
    assign HADDR_S_o       = HADDR_S;
    assign HTRANS_S_o      = HTRANS_S;
    assign HWRITE_S_o      = HWRITE_S;
    assign HSIZE_S_o       = HSIZE_S;
    assign HBURST_S_o      = HBURST_S;
    assign HMASTER_o       = HMASTER;
    assign HMASTLOCK_o     = HMASTLOCK;
    assign HREADY_GLOBAL_o = HREADY_GLOBAL;
    assign HSEL_S1_o       = HSEL_S1;
    assign HSEL_S2_o       = HSEL_S2;
    assign HSEL_S3_o       = HSEL_S3;
    assign HSEL_DEFAULT_o  = HSEL_DEFAULT;
    assign HSPLIT_S1_o     = HSPLIT_S1;
    assign HSPLIT_S2_o     = HSPLIT_S2;
    assign HSPLIT_S3_o     = HSPLIT_S3;

    //=========================================================================
    // Fabric: Arbiter + Decoder + 5 Muxes
    //=========================================================================
    AHB_Interconnect u_intc (
        .HCLK(HCLK), .HRESETn(HRESETn),
        .HBUSREQ_M1(HBUSREQ_M1), .HLOCK_M1(HLOCK_M1),
        .HADDR_M1(HADDR_M1), .HWDATA_M1(HWDATA_M1),
        .HTRANS_M1(HTRANS_M1), .HWRITE_M1(HWRITE_M1),
        .HSIZE_M1(HSIZE_M1), .HBURST_M1(HBURST_M1),
        .HGRANT_M1(HGRANT_M1),
        .HBUSREQ_M2(HBUSREQ_M2), .HLOCK_M2(HLOCK_M2),
        .HADDR_M2(HADDR_M2), .HWDATA_M2(HWDATA_M2),
        .HTRANS_M2(HTRANS_M2), .HWRITE_M2(HWRITE_M2),
        .HSIZE_M2(HSIZE_M2), .HBURST_M2(HBURST_M2),
        .HGRANT_M2(HGRANT_M2),
        .HRDATA_M(HRDATA_M), .HRESP_M(HRESP_M),
        .HREADY(HREADY), .HREADY_GLOBAL(HREADY_GLOBAL),
        .HADDR_S(HADDR_S), .HWDATA_S(HWDATA_S),
        .HTRANS_S(HTRANS_S), .HWRITE_S(HWRITE_S),
        .HSIZE_S(HSIZE_S), .HBURST_S(HBURST_S),
        .HMASTER(HMASTER), .HMASTLOCK(HMASTLOCK),
        .HSEL_S1(HSEL_S1), .HSEL_S2(HSEL_S2),
        .HSEL_S3(HSEL_S3), .HSEL_DEFAULT(HSEL_DEFAULT),
        .HRDATA_S1(HRDATA_S1), .HRESP_S1(HRESP_S1),
        .HREADYOUT_S1(HREADYOUT_S1), .HSPLIT_S1(HSPLIT_S1),
        .HRDATA_S2(HRDATA_S2), .HRESP_S2(HRESP_S2),
        .HREADYOUT_S2(HREADYOUT_S2), .HSPLIT_S2(HSPLIT_S2),
        .HRDATA_S3(HRDATA_S3), .HRESP_S3(HRESP_S3),
        .HREADYOUT_S3(HREADYOUT_S3), .HSPLIT_S3(HSPLIT_S3),
        .HREADYOUT_DEFAULT(HREADYOUT_DEFAULT),
        .HRESP_DEFAULT(HRESP_DEFAULT)
    );

    //=========================================================================
    // 3 functional slaves (ver3: force_split / force_retry on ports)
    //=========================================================================
    AHB_Slave #(.SEED_VALUE(SEED_S1)) u_slave1 (
        .HCLK(HCLK), .HRESETn(HRESETn), .HREADY_IN(HREADY_GLOBAL),
        .HSELx(HSEL_S1), .HADDR(HADDR_S), .HTRANS(HTRANS_S),
        .HWRITE(HWRITE_S), .HSIZE(HSIZE_S), .HBURST(HBURST_S),
        .HWDATA(HWDATA_S), .HRDATA(HRDATA_S1),
        .HMASTER(HMASTER), .HMASTLOCK(HMASTLOCK),
        .force_split(force_split_s1), .force_retry(force_retry_s1),
        .HSPLITx(HSPLIT_S1), .HREADYOUT(HREADYOUT_S1), .HRESP(HRESP_S1)
    );
    AHB_Slave #(.SEED_VALUE(SEED_S2)) u_slave2 (
        .HCLK(HCLK), .HRESETn(HRESETn), .HREADY_IN(HREADY_GLOBAL),
        .HSELx(HSEL_S2), .HADDR(HADDR_S), .HTRANS(HTRANS_S),
        .HWRITE(HWRITE_S), .HSIZE(HSIZE_S), .HBURST(HBURST_S),
        .HWDATA(HWDATA_S), .HRDATA(HRDATA_S2),
        .HMASTER(HMASTER), .HMASTLOCK(HMASTLOCK),
        .force_split(force_split_s2), .force_retry(force_retry_s2),
        .HSPLITx(HSPLIT_S2), .HREADYOUT(HREADYOUT_S2), .HRESP(HRESP_S2)
    );
    AHB_Slave #(.SEED_VALUE(SEED_S3)) u_slave3 (
        .HCLK(HCLK), .HRESETn(HRESETn), .HREADY_IN(HREADY_GLOBAL),
        .HSELx(HSEL_S3), .HADDR(HADDR_S), .HTRANS(HTRANS_S),
        .HWRITE(HWRITE_S), .HSIZE(HSIZE_S), .HBURST(HBURST_S),
        .HWDATA(HWDATA_S), .HRDATA(HRDATA_S3),
        .HMASTER(HMASTER), .HMASTLOCK(HMASTLOCK),
        .force_split(force_split_s3), .force_retry(force_retry_s3),
        .HSPLITx(HSPLIT_S3), .HREADYOUT(HREADYOUT_S3), .HRESP(HRESP_S3)
    );

    //=========================================================================
    // Default slave (unmapped-region ERROR responder)
    //=========================================================================
    AHB_Default_Slave u_default_slave (
        .HCLK(HCLK), .HRESETn(HRESETn),
        .HTRANS(HTRANS_S), .HSEL_DEFAULT(HSEL_DEFAULT),
        .HREADYOUT_DEFAULT(HREADYOUT_DEFAULT), .HRESP_DEFAULT(HRESP_DEFAULT)
    );

endmodule : AHB_System_Top
