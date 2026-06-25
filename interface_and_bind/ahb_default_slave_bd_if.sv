`timescale 1ns/1ps
//=============================================================================
// Interface : ahb_default_slave_bd_if
// Purpose   : Backdoor probe into AHB_Default_Slave internals via `bind`.
//
// Signal name mapping (all INPUT):
//   ps, ns                  — FSM state (ST_IDLE / ST_ERROR_CYC1 / ST_ERROR_CYC2)
//                             declared as ahb_def_state_t (enum logic [1:0])
//                             in RTL — port-connects to logic [1:0] here.
//   active_transfer         — wire: HSEL_DEFAULT & (HTRANS==NONSEQ|SEQ)
//   HREADYOUT_DEFAULT       — slave ready output
//   HRESP_DEFAULT           — 2-bit transfer response
//=============================================================================
interface ahb_default_slave_bd_if (
    input  logic       HCLK,
    input  logic       HRESETn,
    input  logic [1:0] ps,
    input  logic [1:0] ns,
    input  logic       active_transfer,
    input  logic       HREADYOUT_DEFAULT,
    input  logic [1:0] HRESP_DEFAULT
);

    // ── Monitor clocking block ────────────────────────────────────────────
    clocking mon_cb @(posedge HCLK);
        default input #1step;
        input ps, ns, active_transfer;
        input HREADYOUT_DEFAULT, HRESP_DEFAULT;
    endclocking

    // ── Modport ───────────────────────────────────────────────────────────
    modport mon_mp(clocking mon_cb, input HCLK, HRESETn);

endinterface : ahb_default_slave_bd_if
