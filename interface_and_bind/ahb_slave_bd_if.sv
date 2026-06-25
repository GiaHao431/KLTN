`timescale 1ns/1ps
//=============================================================================
// Interface : ahb_slave_bd_if
// Purpose   : Backdoor probe into AHB_Slave internals. Connected via `bind`
//             (see ahb_bind.sv) so RTL is NEVER modified.
//
// All ports INPUT — read-only probe. Signal names below MUST match exactly
// the internal logic names declared inside AHB_Slave (ver4):
//   ps_slave, ns_slave            (FSM)
//   local_addr, local_addr_base   (burst address tracking)
//   local_write, local_burst, local_size (address-phase pipeline latch)
//   beat_cnt                      (burst beat down-counter)
//   split_master_reg              (HMASTER latched at SPLIT)
//   resp_abort                    (SPLIT/RETRY abort gate)
//   memory_slave[0:255]           (256×32 SRAM array)
//   HREADYOUT, HRESP, HSPLITx, HRDATA  (slave output ports)
//
// memory_slave is INTENTIONALLY NOT in the clocking block (256-entry array
// in cb would copy 8 KB per sample). It is read directly via vif.memory_slave
// — safe because memory_slave only changes in always_ff @(posedge HCLK) of
// SEQ BLOCK 4, so reading after `@(vif.mon_cb)` gets the pre-edge value.
//=============================================================================
interface ahb_slave_bd_if (
    input  logic              HCLK,
    input  logic              HRESETn,

    // FSM
    input  logic [2:0]        ps_slave,
    input  logic [2:0]        ns_slave,

    // Address-phase latch
    input  logic [7:0]        local_addr,
    input  logic [7:0]        local_addr_base,
    input  logic              local_write,
    input  logic [2:0]        local_burst,
    input  logic [2:0]        local_size,

    // Burst beat counter
    input  logic [5:0]        beat_cnt,

    // SPLIT support
    input  logic [3:0]        split_master_reg,
    input  logic              resp_abort,

    // 256 × 32-bit SRAM (unpacked array)
    input  logic [31:0]       memory_slave [0:255],

    // Slave output signals
    input  logic              HREADYOUT,
    input  logic [1:0]        HRESP,
    input  logic [15:0]       HSPLITx,
    input  logic [31:0]       HRDATA
);

    // ── Monitor clocking block (scalars + small vectors only) ─────────────
    clocking mon_cb @(posedge HCLK);
        default input #1step;
        input ps_slave, ns_slave;
        input local_addr, local_addr_base, local_write, local_burst, local_size;
        input beat_cnt;
        input split_master_reg, resp_abort;
        input HREADYOUT, HRESP, HSPLITx, HRDATA;
    endclocking

    // ── Modport — exposes mon_cb + memory_slave (direct access) ───────────
    modport mon_mp(
        clocking mon_cb,
        input HCLK, HRESETn,
        input memory_slave
    );

endinterface : ahb_slave_bd_if
