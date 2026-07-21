#!/bin/bash
# ================================================================
# run_all_coverage.sh  (FINAL — phien ban duy nhat)
# Regression Code Coverage cho AHB 2.0 Multi-Master Interconnect
# ----------------------------------------------------------------
# Gop tat ca: 52 test goc + 18 test S2/S3 + 22 test +MASTER=2
#           = 92 test tong cong
# ----------------------------------------------------------------
# Chay tu:  cd ~/questa_uvm && bash run_all_coverage.sh
# Yeu cau:  tb_top_opt da san sang (compile xong truoc khi chay)
# Ket qua:  merged_coverage_final.ucdb + report text/PDF
# ================================================================

# --- Cau hinh ---
UCDB_DIR="./ucdb_all"
MERGED_UCDB="./merged_coverage_final.ucdb"
REPORT_FULL="./coverage_summary_final.txt"
REPORT_RTL="./coverage_rtl_only_final.txt"
REPORT_PDF="./coverage_report_final.pdf"
LOG_DIR="./logs_coverage"

# Co vsim co dinh (3 flag bat buoc: -onfinish stop, -suppress 7061, -suppress 3009)
VSIM_FLAGS="-64 -c -coverage -onfinish stop -suppress 7061 -suppress 3009"

# Bo dem
TOTAL=0
PASSED=0
FAILED=0
UVM_ERR_COUNT=0
FAIL_LIST=""
START_TIME=$(date +%s)

# ================================================================
# XOA DU LIEU CU
# ================================================================
echo "========================================================"
echo " CLEAN — xoa du lieu coverage/report cu"
echo "========================================================"
rm -rf "${UCDB_DIR}"
rm -f  ./merged_coverage*.ucdb
rm -f  ./coverage_summary*.txt ./coverage_detail*.txt ./coverage_rtl_only*.txt
rm -f  ./coverage_report*.pdf
rm -rf "${LOG_DIR}"
echo "  Done — da xoa ucdb_all/, logs_coverage/, cac file report cu."

# Tao thu muc moi
mkdir -p "${UCDB_DIR}" "${LOG_DIR}"

# ================================================================
# Ham chay 1 test (co kiem tra UVM_ERROR / UVM_FATAL)
# ================================================================
run_test() {
    local id="$1"
    shift
    local ucdb="${UCDB_DIR}/${id}.ucdb"
    local log="${LOG_DIR}/${id}.log"
    TOTAL=$((TOTAL + 1))

    printf "\n[%03d] %-30s " "${TOTAL}" "${id}"

    vsim ${VSIM_FLAGS} tb_top_opt "$@" \
         -do "run -all; coverage save ${ucdb}; quit -f" \
         > "${log}" 2>&1

    # Kiem tra UCDB
    if [ ! -f "${ucdb}" ]; then
        printf "FAIL (no UCDB)"
        FAILED=$((FAILED + 1))
        FAIL_LIST="${FAIL_LIST}  - ${id} : khong tao duoc UCDB\n"
        return
    fi

    # Kiem tra UVM_FATAL
    local n_fatal
    n_fatal=$(grep -c "UVM_FATAL" "${log}" 2>/dev/null || echo 0)
    # Loai bo dong summary "UVM_FATAL :    0" — chi dem dong FATAL that su
    local real_fatal
    real_fatal=$(grep "UVM_FATAL" "${log}" | grep -cv "UVM_FATAL :    0" 2>/dev/null || echo 0)

    if [ "${real_fatal}" -gt 0 ]; then
        printf "FAIL (UVM_FATAL)"
        FAILED=$((FAILED + 1))
        FAIL_LIST="${FAIL_LIST}  - ${id} : UVM_FATAL detected\n"
        return
    fi

    # Kiem tra UVM_ERROR count tu dong summary cuoi log
    # Dong summary co dang: "UVM_ERROR :    N"
    local err_count
    err_count=$(grep -oP 'UVM_ERROR\s*:\s*\K[0-9]+' "${log}" | tail -1)
    if [ -z "${err_count}" ]; then
        err_count=0
    fi

    if [ "${err_count}" -gt 0 ]; then
        printf "FAIL (UVM_ERROR=%s)" "${err_count}"
        FAILED=$((FAILED + 1))
        UVM_ERR_COUNT=$((UVM_ERR_COUNT + err_count))
        FAIL_LIST="${FAIL_LIST}  - ${id} : UVM_ERROR = ${err_count}\n"
        return
    fi

    printf "PASS"
    PASSED=$((PASSED + 1))
}

# ================================================================
echo ""
echo "========================================================"
echo " AHB Code Coverage Regression — FINAL"
echo " $(date '+%Y-%m-%d %H:%M')"
echo " Tong so test: 92"
echo "========================================================"

# ======================== SMOKE ================================
run_test "smoke"    +UVM_TESTNAME=ahb_smoke_test

# ======================== LAYER 1 ==============================
run_test "T1_1"     +UVM_TESTNAME=ahb_single_test +DIR=W +BASE=4
run_test "T1_2"     +UVM_TESTNAME=ahb_single_test +DIR=R +BASE=4 +EXP_INIT=14
run_test "T1_3"     +UVM_TESTNAME=ahb_single_test +MASTER=1 +DIR=WR +BASE=8
run_test "T1_4_5"   +UVM_TESTNAME=ahb_burst_test +BURST=INCR4 +DIR=WR +BASE=10 +PATTERN=DEAD
run_test "T1_6_7"   +UVM_TESTNAME=ahb_burst_test +BURST=WRAP4 +DIR=WR +BASE=14 +PATTERN=INDEX
run_test "T1_8"     +UVM_TESTNAME=ahb_burst_test +MASTER=1 +BURST=INCR8 +DIR=WR +BASE=20 +PATTERN=DEAD
run_test "T1_9"     +UVM_TESTNAME=ahb_force_test +OP=SPLIT +DIR=R +BASE=40
run_test "T1_10"    +UVM_TESTNAME=ahb_force_test +OP=SPLIT +DIR=W +BASE=80 +LOCK=1
run_test "T1_11a"   +UVM_TESTNAME=ahb_single_test +DIR=R +BASE=0 +EXP_INIT=0A
run_test "T1_11b"   +UVM_TESTNAME=ahb_single_test +DIR=R +BASE=8 +EXP_INIT=1E
run_test "T1_12"    +UVM_TESTNAME=ahb_back2back_test +MASTER=1
run_test "T1_13"    +UVM_TESTNAME=ahb_force_test +MASTER=1 +OP=RETRY +DIR=W +BASE=80
run_test "T1_14_W"  +UVM_TESTNAME=ahb_retry_until_ok_test +MASTER=1 +DIR=W +BASE=40 +NRETRY=2
run_test "T1_14_R"  +UVM_TESTNAME=ahb_retry_until_ok_test +MASTER=1 +DIR=R +BASE=4 +NRETRY=3
run_test "T1_15a"   +UVM_TESTNAME=ahb_force_test +OP=RETRY +DIR=W +BASE=80
run_test "T1_15b"   +UVM_TESTNAME=ahb_force_test +OP=SPLIT +DIR=W +BASE=80
run_test "T1_16"    +UVM_TESTNAME=ahb_force_burst_test +BURST=INCR4 +DIR=W +OP=SPLIT +BASE=40 +BEAT=2 +RECOVER=0
run_test "T1_17"    +UVM_TESTNAME=ahb_force_burst_test +BURST=WRAP4 +DIR=R +OP=RETRY +BASE=4 +BEAT=1 +RECOVER=1
run_test "T1_18"    +UVM_TESTNAME=ahb_force_test +OP=BOTH +DIR=R +BASE=40

# ======================== LAYER 2 ==============================
run_test "T2_1"     +UVM_TESTNAME=ahb_l2_grant_test +MASTER=1
run_test "T2_2"     +UVM_TESTNAME=ahb_l2_wr_rd_test +MASTER=1 +BASE=10 +WDATA=5A5A0010
run_test "T2_3"     +UVM_TESTNAME=ahb_l2_decoder_test +MASTER=1
run_test "T2_4"     +UVM_TESTNAME=ahb_l2_default_err_test +MASTER=1
run_test "T2_5"     +UVM_TESTNAME=ahb_l2_boundary_test +MASTER=1
run_test "T2_6"     +UVM_TESTNAME=ahb_l2_hready_test +MASTER=1 +BASE=20 +WDATA=1234ABCD
run_test "T2_7"     +UVM_TESTNAME=ahb_l2_cross_raw_test +MASTER=1
run_test "T2_8"     +UVM_TESTNAME=ahb_l2_burst_intc_test +MASTER=1
run_test "T2_9"     +UVM_TESTNAME=ahb_l2_split_recover_test +MASTER=1 +BASE=0
run_test "T2_10"    +UVM_TESTNAME=ahb_l2_idle_intc_test +MASTER=1 +HOLD=3
run_test "T2_11"    +UVM_TESTNAME=ahb_l2_slave_sweep_test +MASTER=1
run_test "T2_12"    +UVM_TESTNAME=ahb_l2_retry_intc_test +BASE=50 +NRETRY=2 +WDATA=CAFE1250
run_test "T2_13"    +UVM_TESTNAME=ahb_l2_both_idle_test +M1HOLD=10 +M2HOLD=2

# ======================== LAYER 3 ==============================
run_test "T3_1"     +UVM_TESTNAME=ahb_l3_round_robin_test +ROUNDS=2
run_test "T3_2"     +UVM_TESTNAME=ahb_l3_m2_only_test +BASE=10 +WDATA=deadbeef
run_test "T3_3"     +UVM_TESTNAME=ahb_l3_handover_test
run_test "T3_4"     +UVM_TESTNAME=ahb_l3_handover_wait_test
run_test "T3_5"     +UVM_TESTNAME=ahb_l3_locked_burst_test
run_test "T3_6"     +UVM_TESTNAME=ahb_l3_burst_active_test
run_test "T3_7"     +UVM_TESTNAME=ahb_l3_idle_force_test +M1HOLD=12
run_test "T3_8"     +UVM_TESTNAME=ahb_l3_split_switch_test
run_test "T3_9"     +UVM_TESTNAME=ahb_l3_split_or_test
run_test "T3_10"    +UVM_TESTNAME=ahb_l3_both_masked_test
run_test "T3_11"    +UVM_TESTNAME=ahb_l3_mux_pipeline_test
run_test "T3_12"    +UVM_TESTNAME=ahb_l3_data_isolation_test
run_test "T3_13"    +UVM_TESTNAME=ahb_l3_err_recovery_test
run_test "T3_14"    +UVM_TESTNAME=ahb_l3_lock_over_split_test
run_test "T3_15"    +UVM_TESTNAME=ahb_l3_alt_stress_test
run_test "T3_16"    +UVM_TESTNAME=ahb_l3_locked_split_hold_test +MASTER=1
run_test "T3_17"    +UVM_TESTNAME=ahb_l3_retry_rr_test
run_test "T3_18"    +UVM_TESTNAME=ahb_l3_retry_vs_split_test +MASTER=1

# ======================== BONUS: PIPELINE ======================
run_test "T4"       +UVM_TESTNAME=ahb_chain_pipelined_test

# ======================== ADDON: SLAVE 2 (0x4000_0000+) ========
run_test "T1_9_S2"   +UVM_TESTNAME=ahb_force_test +OP=SPLIT +DIR=R +BASE=40000040
run_test "T1_10_S2"  +UVM_TESTNAME=ahb_force_test +OP=SPLIT +DIR=W +BASE=40000080 +LOCK=1
run_test "T1_13_S2"  +UVM_TESTNAME=ahb_force_test +OP=RETRY +DIR=W +BASE=40000080
run_test "T1_14W_S2" +UVM_TESTNAME=ahb_retry_until_ok_test +DIR=W +BASE=40000040 +NRETRY=2
run_test "T1_14R_S2" +UVM_TESTNAME=ahb_retry_until_ok_test +DIR=R +BASE=40000004 +NRETRY=3
run_test "T1_16_S2"  +UVM_TESTNAME=ahb_force_burst_test +BURST=INCR4 +DIR=W +OP=SPLIT +BASE=40000040 +BEAT=2 +RECOVER=0
run_test "T1_17_S2"  +UVM_TESTNAME=ahb_force_burst_test +BURST=WRAP4 +DIR=R +OP=RETRY +BASE=40000004 +BEAT=1 +RECOVER=1
run_test "T1_18_S2"  +UVM_TESTNAME=ahb_force_test +OP=BOTH +DIR=R +BASE=40000040
run_test "T1_4_5_S2" +UVM_TESTNAME=ahb_burst_test +BURST=INCR4 +DIR=WR +BASE=40000010 +PATTERN=DEAD

# ======================== ADDON: SLAVE 3 (0x8000_0000+) ========
run_test "T1_9_S3"   +UVM_TESTNAME=ahb_force_test +OP=SPLIT +DIR=R +BASE=80000040
run_test "T1_10_S3"  +UVM_TESTNAME=ahb_force_test +OP=SPLIT +DIR=W +BASE=80000080 +LOCK=1
run_test "T1_13_S3"  +UVM_TESTNAME=ahb_force_test +OP=RETRY +DIR=W +BASE=80000080
run_test "T1_14W_S3" +UVM_TESTNAME=ahb_retry_until_ok_test +DIR=W +BASE=80000040 +NRETRY=2
run_test "T1_14R_S3" +UVM_TESTNAME=ahb_retry_until_ok_test +DIR=R +BASE=80000004 +NRETRY=3
run_test "T1_16_S3"  +UVM_TESTNAME=ahb_force_burst_test +BURST=INCR4 +DIR=W +OP=SPLIT +BASE=80000040 +BEAT=2 +RECOVER=0
run_test "T1_17_S3"  +UVM_TESTNAME=ahb_force_burst_test +BURST=WRAP4 +DIR=R +OP=RETRY +BASE=80000004 +BEAT=1 +RECOVER=1
run_test "T1_18_S3"  +UVM_TESTNAME=ahb_force_test +OP=BOTH +DIR=R +BASE=80000040
run_test "T1_4_5_S3" +UVM_TESTNAME=ahb_burst_test +BURST=INCR4 +DIR=WR +BASE=80000010 +PATTERN=DEAD

# ================================================================
# MASTER 2 VARIANTS — nham phu coverage Arbiter phia M2
# (Chi ap dung cho cac test single-master da convert sang mst_seqr)
# ================================================================

# --- L1 voi +MASTER=2 ---
run_test "T1_3_M2"     +UVM_TESTNAME=ahb_single_test +MASTER=2 +DIR=WR +BASE=8
run_test "T1_8_M2"     +UVM_TESTNAME=ahb_burst_test +MASTER=2 +BURST=INCR8 +DIR=WR +BASE=20 +PATTERN=DEAD
run_test "T1_9_M2"     +UVM_TESTNAME=ahb_force_test +MASTER=2 +OP=SPLIT +DIR=R +BASE=40
run_test "T1_10_M2"    +UVM_TESTNAME=ahb_force_test +MASTER=2 +OP=SPLIT +DIR=W +BASE=80 +LOCK=1
run_test "T1_12_M2"    +UVM_TESTNAME=ahb_back2back_test +MASTER=2
run_test "T1_13_M2"    +UVM_TESTNAME=ahb_force_test +MASTER=2 +OP=RETRY +DIR=W +BASE=80
run_test "T1_14W_M2"   +UVM_TESTNAME=ahb_retry_until_ok_test +MASTER=2 +DIR=W +BASE=40 +NRETRY=2
run_test "T1_14R_M2"   +UVM_TESTNAME=ahb_retry_until_ok_test +MASTER=2 +DIR=R +BASE=4 +NRETRY=3

# --- Burst INCR16 (moi) de phu burst_remaining[3] ---
run_test "T1_INCR16_M2" +UVM_TESTNAME=ahb_burst_test +MASTER=2 +BURST=INCR16 +DIR=WR +BASE=0 +PATTERN=DEAD

# --- L2 voi +MASTER=2 ---
run_test "T2_1_M2"     +UVM_TESTNAME=ahb_l2_grant_test +MASTER=2
run_test "T2_2_M2"     +UVM_TESTNAME=ahb_l2_wr_rd_test +MASTER=2 +BASE=10 +WDATA=5A5A0010
run_test "T2_3_M2"     +UVM_TESTNAME=ahb_l2_decoder_test +MASTER=2
run_test "T2_4_M2"     +UVM_TESTNAME=ahb_l2_default_err_test +MASTER=2
run_test "T2_5_M2"     +UVM_TESTNAME=ahb_l2_boundary_test +MASTER=2
run_test "T2_6_M2"     +UVM_TESTNAME=ahb_l2_hready_test +MASTER=2 +BASE=20 +WDATA=1234ABCD
run_test "T2_7_M2"     +UVM_TESTNAME=ahb_l2_cross_raw_test +MASTER=2
run_test "T2_8_M2"     +UVM_TESTNAME=ahb_l2_burst_intc_test +MASTER=2
run_test "T2_9_M2"     +UVM_TESTNAME=ahb_l2_split_recover_test +MASTER=2 +BASE=0
run_test "T2_10_M2"    +UVM_TESTNAME=ahb_l2_idle_intc_test +MASTER=2 +HOLD=3
run_test "T2_11_M2"    +UVM_TESTNAME=ahb_l2_slave_sweep_test +MASTER=2

# --- L3 voi +MASTER=2 ---
run_test "T3_16_M2"    +UVM_TESTNAME=ahb_l3_locked_split_hold_test +MASTER=2
run_test "T3_18_M2"    +UVM_TESTNAME=ahb_l3_retry_vs_split_test +MASTER=2

# ================================================================
#                   MERGE & REPORT
# ================================================================
echo ""
echo ""
echo "========================================================"
echo " MERGE & REPORT"
echo "========================================================"

UCDB_COUNT=$(ls -1 ${UCDB_DIR}/*.ucdb 2>/dev/null | wc -l)
echo "UCDB files created: ${UCDB_COUNT} / ${TOTAL}"

if [ "${UCDB_COUNT}" -eq 0 ]; then
    echo "LOI: Khong co file UCDB nao duoc tao!"
    echo "Kiem tra log trong ${LOG_DIR}/"
    exit 1
fi

echo ""
echo "Merging ${UCDB_COUNT} UCDBs..."
vcover merge "${MERGED_UCDB}" ${UCDB_DIR}/*.ucdb
echo "  -> ${MERGED_UCDB}"

# ================================================================
#                       REPORT
# ================================================================
echo ""
echo "Generating reports..."

# Report day du (co ca TB)
vcover report "${MERGED_UCDB}" > "${REPORT_FULL}"
echo "  -> Full (co ca TB):  ${REPORT_FULL}"

# Report RTL-only (loai TB, dung -du= cho tung module RTL)
vcover report "${MERGED_UCDB}" \
    -du=AHB_Arbiter -du=ahb_decoder \
    -du=ahb_addr_ctrl_mux -du=ahb_write_data_mux \
    -du=ahb_read_data_mux -du=ahb_resp_mux -du=ahb_ready_mux \
    -du=AHB_Interconnect -du=AHB_Slave -du=AHB_Default_Slave \
    -du=AHB_System_Top \
    > "${REPORT_RTL}"
echo "  -> RTL-only (DU):    ${REPORT_RTL}"

# ================================================================
#                      TEXT -> PDF
# ================================================================
echo ""
echo "Converting RTL-only report to PDF..."

COMBINED="/tmp/ahb_coverage_final.txt"
{
    echo "================================================================"
    echo " AHB 2.0 Multi-Master Interconnect — Code Coverage Report"
    echo " Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Tests run: ${UCDB_COUNT} (52 goc + 18 S2/S3 + 22 M2)"
    echo " Simulator: Questa Altera FSE 2025.3"
    echo "================================================================"
    echo ""
    cat "${REPORT_RTL}"
} > "${COMBINED}"

if command -v enscript &> /dev/null && command -v ps2pdf &> /dev/null; then
    enscript --no-header -f Courier7 --landscape \
             -M A4 -p /tmp/ahb_cov_final.ps "${COMBINED}" 2>/dev/null
    ps2pdf /tmp/ahb_cov_final.ps "${REPORT_PDF}"
    rm -f /tmp/ahb_cov_final.ps "${COMBINED}"
    echo "  -> PDF: ${REPORT_PDF}"
else
    echo ""
    echo "WARN: Chua cai enscript/ghostscript."
    echo "  sudo apt-get install -y enscript ghostscript"
    echo ""
    echo "(File text van san sang tai: ${REPORT_FULL} va ${REPORT_RTL})"
fi

# ================================================================
#                       SUMMARY
# ================================================================
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo ""
echo "========================================================"
echo " REGRESSION SUMMARY"
echo "========================================================"
echo " Total tests:     ${TOTAL}"
echo " PASS:            ${PASSED}"
echo " FAIL:            ${FAILED}"
echo " UCDB created:    ${UCDB_COUNT}"
echo " Duration:        ${MINS}m ${SECS}s"
if [ "${FAILED}" -gt 0 ]; then
    echo ""
    echo " === FAILED TESTS ==="
    echo -e "${FAIL_LIST}"
fi
echo ""
echo " Output files:"
echo "   ${MERGED_UCDB}"
echo "   ${REPORT_FULL}"
echo "   ${REPORT_RTL}"
[ -f "${REPORT_PDF}" ] && echo "   ${REPORT_PDF}"
echo ""
echo " Logs:  ${LOG_DIR}/"
echo "========================================================"
echo " Done — $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"