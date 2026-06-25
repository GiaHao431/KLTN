`timescale 1ns/1ps
//=============================================================================
// File    : ahb_bind.sv
// Purpose : Bind backdoor probe interfaces into every AHB_Slave and
//           AHB_Default_Slave instance at elaboration time. RTL is NOT
//           modified — `bind` inserts an instance named u_bd inside each
//           target module.
//
// Resulting hierarchy after bind:
//   dut.u_slave1.u_bd       ← ahb_slave_bd_if for slave 1
//   dut.u_slave2.u_bd       ← ahb_slave_bd_if for slave 2
//   dut.u_slave3.u_bd       ← ahb_slave_bd_if for slave 3
//   dut.u_default_slave.u_bd ← ahb_default_slave_bd_if
//
// COMPILE ORDER REQUIREMENT
//   This file must compile AFTER both AHB_Slave / AHB_Default_Slave (RTL)
//   AND ahb_slave_bd_if / ahb_default_slave_bd_if (interfaces) have been
//   compiled. See run.f / EDA Playground README for the canonical order.
//=============================================================================

bind AHB_Slave ahb_slave_bd_if u_bd (
    .HCLK             (HCLK),
    .HRESETn          (HRESETn),
    .ps_slave         (ps_slave),
    .ns_slave         (ns_slave),
    .local_addr       (local_addr),
    .local_addr_base  (local_addr_base),
    .local_write      (local_write),
    .local_burst      (local_burst),
    .local_size       (local_size),
    .beat_cnt         (beat_cnt),
    .split_master_reg (split_master_reg),
    .resp_abort       (resp_abort),
    .memory_slave     (memory_slave),
    .HREADYOUT        (HREADYOUT),
    .HRESP            (HRESP),
    .HSPLITx          (HSPLITx),
    .HRDATA           (HRDATA)
);

bind AHB_Default_Slave ahb_default_slave_bd_if u_bd (
    .HCLK              (HCLK),
    .HRESETn           (HRESETn),
    .ps                (ps),
    .ns                (ns),
    .active_transfer   (active_transfer),
    .HREADYOUT_DEFAULT (HREADYOUT_DEFAULT),
    .HRESP_DEFAULT     (HRESP_DEFAULT)
);

//=============================================================================
// End of ahb_bind.sv
//=============================================================================
