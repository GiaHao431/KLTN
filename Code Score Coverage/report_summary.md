Questa Altera Starter FPGA Edition-64 vcover 2025.3 Coverage Utility 2025.09 Sep 15 2025
Start time: 09:46:27 on Jul 13,2026
vcover report ./merged_coverage.ucdb 
Coverage Report Summary Data by instance

=================================================================================
=== Instance: /tb_top/m1_if
=== Design Unit: work.ahb_master_if
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Statements                      26        26         0   100.00%
    Toggles                        226       215        11    95.13%

=================================================================================
=== Instance: /tb_top/m2_if
=== Design Unit: work.ahb_master_if
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Statements                      26        26         0   100.00%
    Toggles                        226       161        65    71.23%

=================================================================================
=== Instance: /tb_top/sys_if
=== Design Unit: work.ahb_sys_if
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Statements                      44        44         0   100.00%
    Toggles                        202        93       109    46.03%

=================================================================================
=== Instance: /tb_top/u_dut/u_intc/u_arbiter
=== Design Unit: work.AHB_Arbiter
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                        64        59         5    92.18%
    Conditions                      59        43        16    72.88%
    FSM States                       3         3         0   100.00%
    FSM Transitions                  6         6         0   100.00%
    Statements                      71        66         5    92.95%
    Toggles                        119        76        43    63.86%

=================================================================================
=== Instance: /tb_top/u_dut/u_intc/u_decoder
=== Design Unit: work.ahb_decoder
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                         5         5         0   100.00%
    Statements                      14        14         0   100.00%
    Toggles                         76        72         4    94.73%

=================================================================================
=== Instance: /tb_top/u_dut/u_intc/u_addr_ctrl_mux
=== Design Unit: work.ahb_addr_ctrl_mux
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                         3         3         0   100.00%
    Conditions                       2         1         1    50.00%
    Statements                      16        16         0   100.00%
    Toggles                        254       168        86    66.14%

=================================================================================
=== Instance: /tb_top/u_dut/u_intc/u_write_data_mux
=== Design Unit: work.ahb_write_data_mux
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                         6         6         0   100.00%
    Statements                       7         7         0   100.00%
    Toggles                        202       199         3    98.51%

=================================================================================
=== Instance: /tb_top/u_dut/u_intc/u_read_data_mux
=== Design Unit: work.ahb_read_data_mux
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                         8         8         0   100.00%
    Statements                       9         9         0   100.00%
    Toggles                        270       251        19    92.96%

=================================================================================
=== Instance: /tb_top/u_dut/u_intc/u_resp_mux
=== Design Unit: work.ahb_resp_mux
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                         8         8         0   100.00%
    Statements                       9         9         0   100.00%
    Toggles                         34        27         7    79.41%

=================================================================================
=== Instance: /tb_top/u_dut/u_intc/u_ready_mux
=== Design Unit: work.ahb_ready_mux
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                         8         8         0   100.00%
    Statements                       9         9         0   100.00%
    Toggles                         24        23         1    95.83%

=================================================================================
=== Instance: /tb_top/u_dut/u_intc
=== Design Unit: work.AHB_Interconnect
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Statements                       1         1         0   100.00%
    Toggles                        892       657       235    73.65%

=================================================================================
=== Instance: /tb_top/u_dut/u_slave1/u_bd
=== Design Unit: work.ahb_slave_bd_if
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Statements                      14        14         0   100.00%
    Toggles                        184       126        58    68.47%

=================================================================================
=== Instance: /tb_top/u_dut/u_slave1
=== Design Unit: work.AHB_Slave
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                        99        66        33    66.66%
    Conditions                      42        29        13    69.04%
    FSM States                       6         6         0   100.00%
    FSM Transitions                 12        11         1    91.66%
    Statements                     125        95        30    76.00%
    Toggles                        350       276        74    78.85%

=================================================================================
=== Instance: /tb_top/u_dut/u_slave2/u_bd
=== Design Unit: work.ahb_slave_bd_if
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Statements                      14        14         0   100.00%
    Toggles                        184       118        66    64.13%

=================================================================================
=== Instance: /tb_top/u_dut/u_slave2
=== Design Unit: work.AHB_Slave
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                        99        47        52    47.47%
    Conditions                      42        16        26    38.09%
    FSM States                       6         5         1    83.33%
    FSM Transitions                 12         7         5    58.33%
    Statements                     125        70        55    56.00%
    Toggles                        350       266        84    76.00%

=================================================================================
=== Instance: /tb_top/u_dut/u_slave3/u_bd
=== Design Unit: work.ahb_slave_bd_if
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Statements                      14        14         0   100.00%
    Toggles                        184        81       103    44.02%

=================================================================================
=== Instance: /tb_top/u_dut/u_slave3
=== Design Unit: work.AHB_Slave
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                        99        33        66    33.33%
    Conditions                      42         3        39     7.14%
    FSM States                       6         4         2    66.66%
    FSM Transitions                 12         5         7    41.66%
    Statements                     125        52        73    41.60%
    Toggles                        350       227       123    64.85%

=================================================================================
=== Instance: /tb_top/u_dut/u_default_slave/u_bd
=== Design Unit: work.ahb_default_slave_bd_if
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Statements                       7         7         0   100.00%
    Toggles                         22        19         3    86.36%

=================================================================================
=== Instance: /tb_top/u_dut/u_default_slave
=== Design Unit: work.AHB_Default_Slave
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                         8         8         0   100.00%
    FSM States                       3         3         0   100.00%
    FSM Transitions                  4         3         1    75.00%
    Statements                      21        21         0   100.00%
    Toggles                         26        23         3    88.46%

=================================================================================
=== Instance: /tb_top/u_dut
=== Design Unit: work.AHB_System_Top
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Toggles                       1066       745       321    69.88%

=================================================================================
=== Instance: /tb_top
=== Design Unit: work.tb_top
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                        12         5         7    41.66%
    Statements                      31        30         1    96.77%
    Toggles                          4         3         1    75.00%

=================================================================================
=== Instance: /ahb_pkg
=== Design Unit: work.ahb_pkg
=================================================================================
    Enabled Coverage              Bins      Hits    Misses  Coverage
    ----------------              ----      ----    ------  --------
    Branches                      3379       680      2699    20.12%
    Conditions                     623        80       543    12.84%
    Statements                    4129      2293      1836    55.53%


Total Coverage By Instance (filtered view): 54.97%

End time: 09:46:27 on Jul 13,2026, Elapsed time: 0:00:00
Errors: 0, Warnings: 0
