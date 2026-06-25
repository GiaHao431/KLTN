`timescale 1ns/1ps
//=============================================================================
// Interface : ahb_master_if
// Purpose   : Frontdoor interface for one AHB master.
//             Used for BOTH m1_if and m2_if (same class, distinguished by vif
//             passed via uvm_config_db). Generic signal names are mapped to
//             *_M1 / *_M2 ports of AHB_System_Top inside tb_top.
//
// Anti-race convention (per UVM_TB_Architecture §2):
//   default input #1step output #1
//     - input  #1step → sample value already settled (Postponed region)
//     - output #1     → drive 1 time unit after posedge → DUT samples next edge
//=============================================================================
interface ahb_master_if (
    input  logic HCLK,
    input  logic HRESETn
);

    // ── Drive direction (TB → DUT) ────────────────────────────────────────
    logic         HBUSREQ;
    logic         HLOCK;
    logic [31:0]  HADDR;
    logic [31:0]  HWDATA;
    logic [1:0]   HTRANS;
    logic         HWRITE;
    logic [2:0]   HSIZE;
    logic [2:0]   HBURST;

    // ── Sample direction (DUT → TB) ───────────────────────────────────────
    logic         HGRANT;
    logic [31:0]  HRDATA_M;
    logic [1:0]   HRESP_M;
    logic         HREADY;

    // ── Driver clocking block ─────────────────────────────────────────────
    clocking drv_cb @(posedge HCLK);
        default input #1step output #1;
        output HBUSREQ, HLOCK, HADDR, HWDATA, HTRANS, HWRITE, HSIZE, HBURST;
        input  HGRANT, HRDATA_M, HRESP_M, HREADY;
    endclocking

    // ── Monitor clocking block (samples everything) ───────────────────────
    clocking mon_cb @(posedge HCLK);
        default input #1step;
        input HBUSREQ, HLOCK, HADDR, HWDATA, HTRANS, HWRITE, HSIZE, HBURST;
        input HGRANT, HRDATA_M, HRESP_M, HREADY;
    endclocking

    // ── Modports ──────────────────────────────────────────────────────────
    modport drv_mp(clocking drv_cb, input HCLK, HRESETn);
    modport mon_mp(clocking mon_cb, input HCLK, HRESETn);

endinterface : ahb_master_if
