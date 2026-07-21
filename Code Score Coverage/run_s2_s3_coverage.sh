#!/bin/bash
# ================================================================
# run_s2_s3_coverage.sh
# Addon: nham vao S2 (0x4000_0000+) va S3 (0x8000_0000+)
# de tang Condition/Branch/FSM coverage cua AHB_Slave instance 2 & 3
# ----------------------------------------------------------------
# Chay tu:  cd ~/questa_uvm && bash run_s2_s3_coverage.sh
# Dieu kien: ucdb_all/ da co san 52 file UCDB tu lan chay truoc
# Ket qua:  gop them 18 UCDB moi vao ucdb_all/, re-merge toan bo,
#           xuat report full + RTL-only + PDF
# ================================================================

UCDB_DIR="./ucdb_all"
MERGED_UCDB="./merged_coverage_v2.ucdb"
REPORT_FULL="./coverage_summary_v2.txt"
REPORT_RTL="./coverage_rtl_only_v2.txt"
REPORT_PDF="./coverage_report_v2.pdf"
LOG_DIR="./logs_coverage"

VSIM_FLAGS="-64 -c -coverage -onfinish stop -suppress 7061 -suppress 3009"

TOTAL=0
PASSED=0
FAILED=0
FAIL_LIST=""

mkdir -p "${UCDB_DIR}" "${LOG_DIR}"

run_test() {
    local id="$1"
    shift
    local ucdb="${UCDB_DIR}/${id}.ucdb"
    local log="${LOG_DIR}/${id}.log"
    TOTAL=$((TOTAL + 1))

    printf "\n[%02d] %-25s " "${TOTAL}" "${id}"

    vsim ${VSIM_FLAGS} tb_top_opt "$@" \
         -do "run -all; coverage save ${ucdb}; quit -f" \
         > "${log}" 2>&1

    if [ -f "${ucdb}" ]; then
        printf "OK"
        PASSED=$((PASSED + 1))
    else
        printf "FAIL (xem ${log})"
        FAILED=$((FAILED + 1))
        FAIL_LIST="${FAIL_LIST}  - ${id}\n"
    fi
}

echo "========================================================"
echo " Addon Coverage — nham vao Slave 2 & Slave 3"
echo " $(date '+%Y-%m-%d %H:%M')"
echo "========================================================"

# ==================== TARGET SLAVE 2 (0x4000_0000+) ============
run_test "T1_9_S2"   +UVM_TESTNAME=ahb_force_test +OP=SPLIT +DIR=R +BASE=40000040
run_test "T1_10_S2"  +UVM_TESTNAME=ahb_force_test +OP=SPLIT +DIR=W +BASE=40000080 +LOCK=1
run_test "T1_13_S2"  +UVM_TESTNAME=ahb_force_test +OP=RETRY +DIR=W +BASE=40000080
run_test "T1_14W_S2" +UVM_TESTNAME=ahb_retry_until_ok_test +DIR=W +BASE=40000040 +NRETRY=2
run_test "T1_14R_S2" +UVM_TESTNAME=ahb_retry_until_ok_test +DIR=R +BASE=40000004 +NRETRY=3
run_test "T1_16_S2"  +UVM_TESTNAME=ahb_force_burst_test +BURST=INCR4 +DIR=W +OP=SPLIT +BASE=40000040 +BEAT=2 +RECOVER=0
run_test "T1_17_S2"  +UVM_TESTNAME=ahb_force_burst_test +BURST=WRAP4 +DIR=R +OP=RETRY +BASE=40000004 +BEAT=1 +RECOVER=1
run_test "T1_18_S2"  +UVM_TESTNAME=ahb_force_test +OP=BOTH +DIR=R +BASE=40000040
run_test "T1_4_5_S2" +UVM_TESTNAME=ahb_burst_test +BURST=INCR4 +DIR=WR +BASE=40000010 +PATTERN=DEAD

# ==================== TARGET SLAVE 3 (0x8000_0000+) ============
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
#   RE-MERGE: gop toan bo ucdb_all/ (52 file cu + 18 file moi)
# ================================================================
echo ""
echo ""
echo "========================================================"
echo " RE-MERGE (52 test cu + 18 test moi = 70 UCDB)"
echo "========================================================"

UCDB_COUNT=$(ls -1 ${UCDB_DIR}/*.ucdb 2>/dev/null | wc -l)
echo "Tong so UCDB trong ${UCDB_DIR}: ${UCDB_COUNT}"

if [ "${UCDB_COUNT}" -eq 0 ]; then
    echo "LOI: khong tim thay UCDB nao."
    exit 1
fi

vcover merge "${MERGED_UCDB}" ${UCDB_DIR}/*.ucdb
echo "  -> ${MERGED_UCDB}"

# ================================================================
#   REPORT: ban day du (co ahb_pkg/TB) + ban RTL-only (dung -du=)
# ================================================================
echo ""
echo "Generating reports..."

vcover report "${MERGED_UCDB}" > "${REPORT_FULL}"
echo "  -> Full (co ca TB):  ${REPORT_FULL}"

vcover report "${MERGED_UCDB}" \
    -du=AHB_Arbiter -du=ahb_decoder \
    -du=ahb_addr_ctrl_mux -du=ahb_write_data_mux \
    -du=ahb_read_data_mux -du=ahb_resp_mux -du=ahb_ready_mux \
    -du=AHB_Interconnect -du=AHB_Slave -du=AHB_Default_Slave \
    -du=AHB_System_Top \
    > "${REPORT_RTL}"
echo "  -> RTL-only:          ${REPORT_RTL}"

# ================================================================
#   PDF (chi ban RTL-only — day la con so dua vao luan van)
# ================================================================
echo ""
echo "Converting RTL-only report to PDF..."

COMBINED="/tmp/ahb_coverage_v2.txt"
{
    echo "================================================================"
    echo " AHB 2.0 Multi-Master Interconnect — Code Coverage (RTL only)"
    echo " Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Tests: 52 goc + 18 bo sung (nham S2/S3) = 70"
    echo " Simulator: Questa Altera FSE 2025.3"
    echo "================================================================"
    echo ""
    cat "${REPORT_RTL}"
} > "${COMBINED}"

if command -v enscript &> /dev/null && command -v ps2pdf &> /dev/null; then
    enscript --no-header -f Courier7 --landscape \
             -M A4 -p /tmp/ahb_cov_v2.ps "${COMBINED}" 2>/dev/null
    ps2pdf /tmp/ahb_cov_v2.ps "${REPORT_PDF}"
    rm -f /tmp/ahb_cov_v2.ps "${COMBINED}"
    echo "  -> PDF: ${REPORT_PDF}"
else
    echo "WARN: chua cai enscript/ghostscript (xem huong dan lan truoc)."
fi

# ================================================================
echo ""
echo "========================================================"
echo " ADDON SUMMARY"
echo "========================================================"
echo " Test moi chay:     ${TOTAL}"
echo " UCDB tao thanh cong: ${PASSED}"
echo " UCDB thieu:         ${FAILED}"
if [ "${FAILED}" -gt 0 ]; then
    echo ""
    echo " Test khong tao duoc UCDB:"
    echo -e "${FAIL_LIST}"
fi
echo ""
echo " So sanh voi lan truoc:"
echo "   coverage_rtl_only.txt   (70 test cu, TRUOC addon)"
echo "   ${REPORT_RTL}   (TRUOC + 18 test moi)"
echo "========================================================"
