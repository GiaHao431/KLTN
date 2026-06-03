`timescale 1ns / 1ps
//=============================================================================
// Module   : tb_ahb_slave
// Purpose  : Layer 1 Unit Testbench — AHB_Slave standalone verification
//
// Test Cases:
//   TC1 — Single Write  (normal address)
//   TC2 — Single Read   (normal address, verify write-then-read)
//   TC3 — INCR4 Write Burst
//   TC4 — INCR4 Read  Burst (verify TC3 data)
//   TC5 — Single Read  addr=0x0 → SPLIT response trigger
//   TC6 — Default Slave ERROR response
//
// Pass/Fail tự động bằng $error() / $display()
// Scoreboard đơn giản: đếm PASS/FAIL in ra cuối simulation
//=============================================================================

module tb_ahb_slave;

    //=========================================================================
    // ❶  Clock generation
    //=========================================================================
    logic HCLK;
    initial HCLK = 0;
    always #5 HCLK = ~HCLK;   // chu kỳ 10 ns → 100 MHz

    //=========================================================================
    // ❷  Wire declarations — nối BFM ↔ DUT
    //=========================================================================

    // System
    logic        HRESETn;

    // Address & Control (BFM → Slave)
    logic [31:0] HADDR;
    logic [1:0]  HTRANS;
    logic        HWRITE;
    logic [2:0]  HSIZE;
    logic [2:0]  HBURST;
    logic [3:0]  HMASTER_ID;
    logic        HMASTLOCK;
    logic        HSELx;

    // Data
    logic [31:0] HWDATA;
    logic [31:0] HRDATA;

    // Response (Slave → BFM)
    logic        HREADYOUT;
    logic [1:0]  HRESP;

    // SPLIT
    logic [15:0] HSPLITx;

    //=========================================================================
    // ❸  BFM Instantiation
    //=========================================================================
    ahb_master_bfm u_bfm (
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        .HADDR      (HADDR),
        .HTRANS     (HTRANS),
        .HWRITE     (HWRITE),
        .HSIZE      (HSIZE),
        .HBURST     (HBURST),
        .HMASTER    (HMASTER_ID),
        .HMASTLOCK  (HMASTLOCK),
        .HWDATA     (HWDATA),
        .HRDATA     (HRDATA),
        .HREADYOUT  (HREADYOUT),
        .HRESP      (HRESP),
        .HSELx      (HSELx)
    );

    //=========================================================================
    // ❹  DUT Instantiation — AHB_Slave
    //
    // Trong Unit Test Layer 1, BFM kết nối TRỰC TIẾP với Slave,
    // không qua Interconnect. Do đó:
    //   HREADY_IN = HREADYOUT (self-feedback: slave tự báo sẵn sàng)
    //   Không cần Arbiter hay Decoder
    //=========================================================================
    AHB_Slave u_dut (
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        .HREADY_IN  (HREADYOUT),   // self-feedback cho unit test
        .HSELx      (HSELx),
        .HADDR      (HADDR),
        .HTRANS     (HTRANS),
        .HWRITE     (HWRITE),
        .HSIZE      (HSIZE),
        .HBURST     (HBURST),
        .HWDATA     (HWDATA),
        .HRDATA     (HRDATA),
        .HMASTER    (HMASTER_ID),
        .HMASTLOCK  (HMASTLOCK),
        .HSPLITx    (HSPLITx),
        .HREADYOUT  (HREADYOUT),
        .HRESP      (HRESP)
    );

    //=========================================================================
    // ❺  Scoreboard — biến đếm toàn cục
    //=========================================================================
    int pass_count = 0;
    int fail_count = 0;

    // Macro kiểm tra và in kết quả
    // Dùng task thay vì macro để tương thích tốt hơn trên EDA Playground
    task automatic check(
        input string    test_name,
        input logic     condition,
        input string    msg = ""
    );
        if (condition) begin
            $display("[PASS] %-35s %s", test_name, msg);
            pass_count++;
        end else begin
            $display("[FAIL] %-35s %s", test_name, msg);
            fail_count++;
        end
    endtask

    //=========================================================================
    // ❻  Waveform dump — EDA Playground dùng $dumpfile/$dumpvars
    //=========================================================================
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_ahb_slave);
    end

    //=========================================================================
    // ❼  Timeout watchdog — tránh simulation treo vô hạn
    //=========================================================================
    initial begin
        #50000;
        $display("\n[TIMEOUT] Simulation exceeded 50us — possible hang!");
        $finish;
    end

    //=========================================================================
    // ❽  Main Test Sequence
    //=========================================================================
    logic        ok;
    logic [31:0] rdata;
    logic [31:0] rdata_burst [0:3];
    logic [31:0] wdata_burst [0:3];

    initial begin
        $display("============================================================");
        $display(" AHB_Slave Unit Testbench — Layer 1");
        $display(" Simulator time unit: 1ns / precision: 1ps");
        $display("============================================================\n");

        //---------------------------------------------------------------------
        // PHASE 0: Reset
        //---------------------------------------------------------------------
        $display("--- PHASE 0: System Reset ---");
        u_bfm.ahb_reset(5);
        $display("    Reset released. Starting tests...\n");

        //=====================================================================
        // TC1 — Single Write (địa chỉ bình thường, word index != 0)
        //
        // Mục đích : Kiểm tra pipeline IDLE→ACTIVE→WBURST→IDLE
        //            và dữ liệu được ghi vào memory_slave[1] (HADDR=0x04)
        // Kỳ vọng  : HRESP=OKAY, HREADYOUT=1 sau 2 chu kỳ (1 wait state ACTIVE)
        //=====================================================================
        $display("--- TC1: Single Write ---");
        u_bfm.ahb_write_single(
            .addr (32'h0000_0004),   // word index = HADDR[9:2] = 1
            .data (32'hDEAD_BEEF),
            .ok   (ok)
        );
        check("TC1 Write OKAY",
              ok == 1'b1,
              "HADDR=0x04 data=0xDEADBEEF");
        $display("");

        //=====================================================================
        // TC2 — Single Read (đọc lại địa chỉ vừa ghi ở TC1)
        //
        // Mục đích : Kiểm tra pipeline IDLE→ACTIVE→RBURST→IDLE
        //            Verify dữ liệu đọc về khớp với dữ liệu đã ghi
        // Kỳ vọng  : HRDATA = 0xDEAD_BEEF, HRESP=OKAY
        //=====================================================================
        $display("--- TC2: Single Read (write-then-read verify) ---");
        u_bfm.ahb_read_single(
            .addr  (32'h0000_0004),
            .data  (rdata),
            .ok    (ok)
        );
        check("TC2 Read OKAY",
              ok == 1'b1,
              "HADDR=0x04");
        check("TC2 Data Integrity",
              rdata === 32'hDEAD_BEEF,
              $sformatf("Expected=0xDEADBEEF Got=0x%08X", rdata));
        $display("");

        //=====================================================================
        // TC3 — INCR4 Write Burst (ghi 4 word từ addr 0x10)
        //
        // Mục đích : Kiểm tra FSM ST_WBURST, beat_cnt countdown,
        //            địa chỉ tịnh tiến đúng (0x10, 0x14, 0x18, 0x1C)
        //            → word index 4, 5, 6, 7
        // Kỳ vọng  : Tất cả 4 beats HRESP=OKAY
        //=====================================================================
        $display("--- TC3: INCR4 Write Burst ---");
        wdata_burst[0] = 32'hAAAA_0001;
        wdata_burst[1] = 32'hBBBB_0002;
        wdata_burst[2] = 32'hCCCC_0003;
        wdata_burst[3] = 32'hDDDD_0004;

        u_bfm.ahb_write_burst_incr4(
            .base_addr (32'h0000_0010),
            .wdata     (wdata_burst),
            .ok        (ok)
        );
        check("TC3 INCR4 Write Burst OKAY",
              ok == 1'b1,
              "HADDR=0x10-0x1C, 4 beats");
        $display("");

        //=====================================================================
        // TC4 — INCR4 Read Burst (đọc lại 4 word từ addr 0x10)
        //
        // Mục đích : Kiểm tra FSM ST_RBURST, pipeline HRDATA đúng phase,
        //            và dữ liệu khớp với những gì đã ghi ở TC3
        // Kỳ vọng  : rdata[0..3] === wdata_burst[0..3]
        //=====================================================================
        $display("--- TC4: INCR4 Read Burst (verify TC3 data) ---");
        u_bfm.ahb_read_burst_incr4(
            .base_addr (32'h0000_0010),
            .rdata     (rdata_burst),
            .ok        (ok)
        );
        check("TC4 INCR4 Read Burst OKAY",
              ok == 1'b1,
              "HADDR=0x10-0x1C, 4 beats");
        check("TC4 Beat[0] Data",
              rdata_burst[0] === 32'hAAAA_0001,
              $sformatf("Expected=0xAAAA0001 Got=0x%08X", rdata_burst[0]));
        check("TC4 Beat[1] Data",
              rdata_burst[1] === 32'hBBBB_0002,
              $sformatf("Expected=0xBBBB0002 Got=0x%08X", rdata_burst[1]));
        check("TC4 Beat[2] Data",
              rdata_burst[2] === 32'hCCCC_0003,
              $sformatf("Expected=0xCCCC0003 Got=0x%08X", rdata_burst[2]));
        check("TC4 Beat[3] Data",
              rdata_burst[3] === 32'hDDDD_0004,
              $sformatf("Expected=0xDDDD0004 Got=0x%08X", rdata_burst[3]));
        $display("");

        //=====================================================================
        // TC5 — Single Read addr=0x000 → SPLIT trigger
        //
        // Mục đích : Kiểm tra chuỗi phản hồi SPLIT 2 chu kỳ:
        //   Chu kỳ 1: HREADYOUT=0, HRESP=SPLIT  (ST_RBURST → ST_LITTLE)
        //   Chu kỳ 2: HREADYOUT=1, HRESP=SPLIT  (ST_LITTLE)
        //   Sau đó  : HSPLITx[HMASTER_ID] = 1   (báo Arbiter mở mask)
        // Kỳ vọng  : HRESP=SPLIT (ok=0), HSPLITx[1]=1 trong 1 chu kỳ
        //
        // Lưu ý    : ok=0 là đúng ở đây — SPLIT không phải lỗi của thiết kế
        //=====================================================================
        $display("--- TC5: Single Read ADDR=0x0 → SPLIT Response ---");

        // Monitor HSPLITx trong background
        fork
            begin : split_monitor
                logic split_seen;
                split_seen = 1'b0;
                // Quan sát 20 chu kỳ sau khi bắt đầu TC5
                repeat (20) begin
                    @(posedge HCLK);
                    if (HSPLITx[1] === 1'b1) begin
                        split_seen = 1'b1;
                    end
                end
                check("TC5 HSPLITx[1] asserted",
                      split_seen,
                      "Slave must wake Arbiter via HSPLITx");
            end
            begin : split_transfer
                u_bfm.ahb_read_single(
                    .addr  (32'h0000_0000),  // word index 0 → SPLIT trigger
                    .data  (rdata),
                    .ok    (ok)
                );
                // SPLIT response → ok=0 là ĐÚNG theo spec
                check("TC5 SPLIT detected (ok=0 expected)",
                      ok == 1'b0,
                      $sformatf("HRESP=0x%0b (expect SPLIT=11)", HRESP));
            end
        join
        $display("");

        //=====================================================================
        // TC6 — Read từ địa chỉ đã pre-init trong memory (addr=0x04 = index 1)
        //
        // Mục đích : Cross-check với giá trị seed memory_slave[1]=20 và
        //            dữ liệu đã ghi đè bởi TC1 (0xDEAD_BEEF)
        //            Đảm bảo write thực sự persist trong SRAM
        // Kỳ vọng  : HRDATA = 0xDEAD_BEEF (TC1 đã ghi đè seed 20)
        //=====================================================================
        $display("--- TC6: Verify SRAM persistence (re-read TC1 address) ---");
        u_bfm.ahb_read_single(
            .addr  (32'h0000_0004),
            .data  (rdata),
            .ok    (ok)
        );
        check("TC6 SRAM Persistence OKAY",
              ok == 1'b1,
              "HADDR=0x04");
        check("TC6 Data matches TC1 write",
              rdata === 32'hDEAD_BEEF,
              $sformatf("Expected=0xDEADBEEF Got=0x%08X", rdata));
        $display("");

        //=====================================================================
        // TC7 — Verify seed values (địa chỉ chưa bị ghi đè)
        //
        // memory_slave[2] = 32'd30 (seed từ initial block)
        // Địa chỉ byte = word_index * 4 = 2 * 4 = 0x08
        // Kỳ vọng : HRDATA = 32'd30 = 32'h0000_001E
        //=====================================================================
        $display("--- TC7: Read pre-initialized seed value ---");
        u_bfm.ahb_read_single(
            .addr  (32'h0000_0008),   // word index 2 → seed = 30
            .data  (rdata),
            .ok    (ok)
        );
        check("TC7 Read Seed OKAY",
              ok == 1'b1,
              "HADDR=0x08");
        check("TC7 Seed value = 30",
              rdata === 32'd30,
              $sformatf("Expected=30 Got=%0d", rdata));
        $display("");

        //=====================================================================
        // Phần cuối: In tổng kết
        //=====================================================================
        #20;
        $display("============================================================");
        $display(" SIMULATION COMPLETE");
        $display("------------------------------------------------------------");
        $display(" PASS : %0d", pass_count);
        $display(" FAIL : %0d", fail_count);
        $display(" TOTAL: %0d", pass_count + fail_count);
        if (fail_count == 0)
            $display(" RESULT: *** ALL TESTS PASSED ***");
        else
            $display(" RESULT: *** %0d TEST(S) FAILED — Check waveform ***",
                     fail_count);
        $display("============================================================");
        $finish;
    end

endmodule : tb_ahb_slave
//=============================================================================
// End of tb_ahb_slave.sv
//=============================================================================
