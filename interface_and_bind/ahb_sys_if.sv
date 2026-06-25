`timescale 1ns/1ps
//=============================================================================
// Interface : ahb_sys_if
// Purpose   : System-level interface for slv_rsp_agent (force hooks) and
//             bus_mon_agent (bus observation outputs from AHB_System_Top).
//
// Signal names match AHB_System_Top port names EXACTLY:
//   - force_split_sN / force_retry_sN  (driven by slv_rsp_agent → DUT)
//   - HMASTER_o, HSEL_*_o, HSPLIT_*_o, HADDR_S_o, ... (observed only)
//
// Two clocking blocks (architecture §2.4):
//   - ctrl_cb : slv_rsp driver uses force_* outputs
//   - mon_cb  : bus_mon samples everything for future coverage
//=============================================================================
interface ahb_sys_if (
    input  logic HCLK,
    input  logic HRESETn
);

    // ── Drive direction (TB → DUT) : Force hooks ──────────────────────────
    logic force_split_s1, force_retry_s1;
    logic force_split_s2, force_retry_s2;
    logic force_split_s3, force_retry_s3;

    // ── Observe direction (DUT → TB) : Bus observation outputs ────────────
    logic [3:0]  HMASTER_o;
    logic        HMASTLOCK_o;
    logic        HREADY_GLOBAL_o;
    logic        HSEL_S1_o;
    logic        HSEL_S2_o;
    logic        HSEL_S3_o;
    logic        HSEL_DEFAULT_o;
    logic [15:0] HSPLIT_S1_o;
    logic [15:0] HSPLIT_S2_o;
    logic [15:0] HSPLIT_S3_o;
    logic [31:0] HADDR_S_o;
    logic [1:0]  HTRANS_S_o;
    logic        HWRITE_S_o;
    logic [2:0]  HSIZE_S_o;
    logic [2:0]  HBURST_S_o;

    // ── Control clocking block (slv_rsp driver) ───────────────────────────
    clocking ctrl_cb @(posedge HCLK);
        default input #1step output #1;
        output force_split_s1, force_retry_s1;
        output force_split_s2, force_retry_s2;
        output force_split_s3, force_retry_s3;
        input  HMASTER_o, HMASTLOCK_o, HREADY_GLOBAL_o;
        input  HSEL_S1_o, HSEL_S2_o, HSEL_S3_o, HSEL_DEFAULT_o;
        input  HSPLIT_S1_o, HSPLIT_S2_o, HSPLIT_S3_o;
        input  HADDR_S_o, HTRANS_S_o, HWRITE_S_o, HSIZE_S_o, HBURST_S_o;
    endclocking

    // ── Monitor clocking block (bus_mon — samples everything) ─────────────
    clocking mon_cb @(posedge HCLK);
        default input #1step;
        input force_split_s1, force_retry_s1;
        input force_split_s2, force_retry_s2;
        input force_split_s3, force_retry_s3;
        input HMASTER_o, HMASTLOCK_o, HREADY_GLOBAL_o;
        input HSEL_S1_o, HSEL_S2_o, HSEL_S3_o, HSEL_DEFAULT_o;
        input HSPLIT_S1_o, HSPLIT_S2_o, HSPLIT_S3_o;
        input HADDR_S_o, HTRANS_S_o, HWRITE_S_o, HSIZE_S_o, HBURST_S_o;
    endclocking

    // ── Modports ──────────────────────────────────────────────────────────
    modport ctrl_mp(clocking ctrl_cb, input HCLK, HRESETn);
    modport mon_mp (clocking mon_cb,  input HCLK, HRESETn);

endinterface : ahb_sys_if
