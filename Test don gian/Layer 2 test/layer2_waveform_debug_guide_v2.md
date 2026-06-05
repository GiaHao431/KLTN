# AHB Layer 2 — Hướng Dẫn Debug Waveform v2 (Timing Chính Xác)

## Mục lục
1. [AHB Pipeline + Simulation Event Ordering](#pipeline)
2. [Encoding v2 (0=M1, 1=M2)](#encoding)
3. [Nhóm Tín Hiệu Cần Thêm Vào Waveform](#signals)
4. [T2.1 — M1 Write to Slave 1](#t21)
5. [T2.2 — M1 Read from Slave 1](#t22)
6. [T2.3 — Default Slave ERROR (2-Cycle)](#t23)
7. [T2.4 — M1 Write to Slave 2](#t24)
8. [T2.5 — M1 Write to Slave 3](#t25)
9. [T2.6 — HREADY_GLOBAL Feedback](#t26)
10. [T2.7 — Cross-Slave Read-After-Write](#t27)
11. [T2.8 — INCR4 Burst via Interconnect](#t28)
12. [Bảng Chẩn Đoán Lỗi Thường Gặp](#failures)

---

## 1. AHB Pipeline + Simulation Event Ordering <a name="pipeline"></a>

### 1.1 AHB Pipeline 2-pha

```
       | Cycle N (Address Phase) | Cycle N+1 (Data Phase)  |
       |                          |                          |
Master:| HADDR, HTRANS, HWRITE   | HWDATA (write)           |
Slave: | HSEL (comb from Decoder)| HRDATA (read), HRESP     |
Ready: | HREADY sampled          | HREADY sampled           |
```

**Quy tắc:** Data Phase luôn trễ 1 cycle so với Address Phase.

### 1.2 Simulation Delta Ordering (tại 1 posedge)

Khi posedge HCLK xảy ra, simulator chạy 3 bước theo thứ tự:

```
┌─────────────────────────────────────────────────────────────────┐
│  ① ACTIVE region                                                │
│     • @(posedge HCLK) triggers (BFM tasks, testbench)           │
│     • BFM đọc HREADY/HRESP ở ĐÂY → thấy giá trị CŨ (pre-NBA) │
│     • blocking assignments (=) trong TB                          │
├─────────────────────────────────────────────────────────────────┤
│  ② NBA region                                                   │
│     • Non-blocking (<=) execute:                                │
│       – Slave: ps_slave ← ns_slave                              │
│       – Pipeline regs: mux_sel_dp ← MUX_SEL                    │
│       – SRAM write: memory[addr] ← HWDATA                      │
├─────────────────────────────────────────────────────────────────┤
│  ③ Re-evaluate (combinational)                                  │
│     • always_comb blocks re-fire vì inputs (ps_slave...) đổi    │
│     • Slave: HREADYOUT, HRESP cập nhật                          │
│     • Ready_mux: HREADY_GLOBAL cập nhật                         │
│     • Giá trị MỚI này stable cho tới posedge tiếp theo          │
└─────────────────────────────────────────────────────────────────┘
```

**Hệ quả quan trọng:** BFM đọc HREADY tại ① nhưng HREADY thay đổi tại ③.
→ BFM luôn thấy giá trị HREADY **của chu kỳ trước**, không phải chu kỳ hiện tại.

### 1.3 Slave ST_ACTIVE Wait-State

AHB_Slave có 1 wait-state bắt buộc cho **mọi** NONSEQ transfer:

```
ST_IDLE ──(NONSEQ)──→ ST_ACTIVE ──→ ST_WBURST/ST_RBURST ──→ ST_IDLE
            │              │                │
         HREADY=1      HREADY=0         HREADY=1
         (accept AP)   (wait-state)     (transfer done)
```

Burst: chỉ beat đầu (NONSEQ) đi qua ST_ACTIVE. Beats SEQ tiếp theo ở
ST_WBURST/ST_RBURST → HREADY=1 liên tục, không bị wait.

---

## 2. Encoding v2 <a name="encoding"></a>

| HMASTER | Ý nghĩa | Ghi chú |
|---|---|---|
| `4'd0` | **M1 / IDLE** | Cả idle lẫn GNT_M1 đều = 0 |
| `4'd1` | **M2** | |
| `4'd2+` | Reserved | MUX mặc định → M1 |

Dùng `HGRANT_M1/M2` để phân biệt idle vs granted.
Layer 2: `HGRANT_M1=1` suốt simulation vì chỉ test M1, M2 idle.

---

## 3. Nhóm Tín Hiệu <a name="signals"></a>

### Group A — Clock & Reset
```
HCLK, HRESETn
```

### Group B — Arbiter
```
u_arbiter/state_q[1:0]     ← 00=IDLE, 01=GNT_M1, 10=GNT_M2
HBUSREQ_M1, HBUSREQ_M2
HGRANT_M1,  HGRANT_M2
HMASTER[3:0]                ← v2: 0=M1, 1=M2
```

### Group C — Address Bus
```
HADDR_S[31:0], HTRANS_S[1:0], HWRITE_S
HSIZE_S[2:0], HBURST_S[2:0]
```

### Group D — Decoder
```
HSEL_S1, HSEL_S2, HSEL_S3, HSEL_DEFAULT
MUX_SEL[1:0]
```

### Group E — Data Bus + Pipeline
```
HWDATA_S[31:0], HRDATA_M[31:0]
master_sel_data_phase[3:0]        ← write_data_mux pipeline reg
```

### Group F — Handshake
```
HREADY_GLOBAL, HRESP_M[1:0]
u_ready_mux/mux_sel_data_phase[1:0]
```

### Group G — Slave Individual
```
HREADYOUT_S1, HRESP_S1, u_slave1/ps_slave
HREADYOUT_S2, HRESP_S2
HREADYOUT_S3, HRESP_S3
HREADYOUT_DEFAULT, HRESP_DEFAULT
```

---

## 4. T2.1 — M1 Write 0xDEADBEEF → Slave 1 (0x0000_0010) <a name="t21"></a>

### Timeline chính xác (đã sửa repeat(3) → 1 cycle)

```
Ký hiệu: NS=NONSEQ, IDL=IDLE, OK=OKAY, ACT=ST_ACTIVE, WB=ST_WBURST
────────────────────────────────────────────────────────────────────────────────
 Cycle │ Signal chính         │ Giá trị          │ Event
────────────────────────────────────────────────────────────────────────────────
  R1-5 │ HRESETn              │ 0                │ Reset (5 cycles)
       │ Tất cả               │ initial values   │
────────────────────────────────────────────────────────────────────────────────
  C0   │ HRESETn              │ 0→1 (#1 sau P5)  │ ahb_reset release reset
       │ (ahb_reset sync)     │ @(posedge)       │ ahb_reset trả về ở P6
────────────────────────────────────────────────────────────────────────────────
  C1   │ HBUSREQ_M1           │ 0→1              │ TB set HBUSREQ=1
       │ @(posedge) sync      │                  │ 1 cycle chờ Arbiter
       │                      │                  │
       │ Posedge P7:          │                  │
       │   Arbiter NBA:       │ state_q←GNT_M1   │ Thấy HBUSREQ_M1=1
       │   Comb:              │ HGRANT_M1=1      │ Grant lập tức
       │                      │ HMASTER=4'd0     │ v2: M1=0
────────────────────────────────────────────────────────────────────────────────
  C2   │ ahb_write_single     │                  │ ensure_grant(): HGRANT=1
       │ bắt đầu              │                  │ → return ngay (không chờ)
       │                      │                  │
       │ @(posedge HCLK); #1  │                  │ BFM chờ 1 posedge rồi drive
       │ HADDR_M1             │ 0x0000_0010      │ ← Address Phase bắt đầu
       │ HTRANS               │ NONSEQ (2'b10)   │
       │ HWRITE               │ 1                │
       │ HBURST               │ SINGLE (3'b000)  │
       │                      │                  │
       │ addr_ctrl_mux comb:  │ HADDR_S=0x10     │ HMASTER_SEL=0 → route M1
       │ Decoder comb:        │ HSEL_S1=1        │ HADDR[31:30]=00
       │                      │ MUX_SEL=2'b00    │
       │                      │                  │
       │ Slave1 comb (ST_IDLE)│ ns=ST_ACTIVE     │ Thấy NONSEQ
       │                      │ HREADYOUT=1      │ Vẫn ở ST_IDLE → READY=1
────────────────────────────────────────────────────────────────────────────────
  C3   │ Posedge:             │                  │
       │                      │                  │
       │ ① Active region:     │                  │
       │   BFM: @(posedge)    │ HREADY=1 (cũ!)   │ BFM thấy HREADY=1 (pre-NBA)
       │   while(!HREADY)     │ → FALSE → skip   │ → BFM tiến tới data phase
       │                      │                  │
       │ ② NBA region:        │                  │
       │   Slave1:            │ ps←ST_ACTIVE     │ Chuyển trạng thái
       │   Pipeline regs:     │ mux_sel_dp←00    │ Chốt MUX_SEL (HREADY=1)
       │                      │ master_sel_dp←0  │ Chốt HMASTER (HREADY=1)
       │   Slave1 addr latch: │ local_addr←0x04  │ 0x10[9:2]=0x04
       │                      │ local_write←1    │
       │                      │ local_burst←SNGL │
       │                      │                  │
       │ ③ Comb re-eval:      │                  │
       │   Slave1 (ST_ACTIVE):│ HREADYOUT=0  ★   │ Wait-state!
       │                      │ ns=ST_WBURST     │
       │   Ready_mux:         │ HREADY_GLOBAL=0  │ Drop!
       │                      │                  │
       │ #1:                  │                  │
       │   BFM:               │ HWDATA=0xDEAD…   │ ★ HWDATA xuất hiện
       │                      │ HTRANS=IDLE      │ ★ cùng lúc HREADY drop
       │                      │                  │
       │ Waveform quan sát:   │                  │
       │   HREADY_GLOBAL      │ 1→0              │ Slave wait-state
       │   HWDATA_S           │ 0→0xDEADBEEF     │ Pipeline delay từ M1
       │   HTRANS_S           │ NS→IDL           │ BFM chuyển IDLE
────────────────────────────────────────────────────────────────────────────────
  C4   │ Posedge:             │                  │
       │                      │                  │
       │ ① Active region:     │                  │
       │   BFM: @(posedge)    │ HREADY=0 (cũ!)   │ BFM thấy HREADY=0
       │   while(!HREADY)     │ → TRUE → loop!   │ ★ BFM STALL 1 cycle ★
       │   @(posedge HCLK)    │                  │ → chờ C5
       │                      │                  │
       │ ② NBA region:        │                  │
       │   Slave1:            │ ps←ST_WBURST     │
       │   Beat counter:      │ beat_cnt←1       │ B_SINGLE → cnt=1
       │   Ready_mux:         │ HREADY=0→no upd  │ mux_sel_dp giữ nguyên
       │                      │                  │
       │ ③ Comb re-eval:      │                  │
       │   Slave1 (ST_WBURST):│ HREADYOUT=1  ★   │ HREADY phục hồi!
       │     B_SINGLE:        │ ns=ST_IDLE       │ Chuyển về idle
       │   Ready_mux:         │ HREADY_GLOBAL=1  │ Recovery!
       │                      │                  │
       │ Waveform quan sát:   │                  │
       │   HREADY_GLOBAL      │ 0→1              │ Recovery sau wait-state
────────────────────────────────────────────────────────────────────────────────
  C5   │ Posedge:             │                  │ ★ WRITE HOÀN TẤT ★
       │                      │                  │
       │ ① Active region:     │                  │
       │   BFM: @(posedge)    │ HREADY=1 ✓       │ Exit while loop
       │   ok=(HRESP==OKAY)   │ ok=1 ✓           │ Write success!
       │                      │                  │
       │ ② NBA region:        │                  │
       │   Slave1:            │ ps←ST_IDLE       │ Transaction done
       │   SRAM Write:        │ ps_pre=ST_WBURST │ Điều kiện TRUE
       │                      │ mem[0x04]←0xDEAD │ ★ DATA WRITTEN ★
       │   Beat counter:      │ beat_cnt←0       │
       │                      │                  │
       │ #1:                  │                  │
       │   BFM:               │ HWRITE=0         │ Clean up
       │                      │ HWDATA=0         │
       │                      │                  │
       │ Waveform quan sát:   │                  │
       │   HWDATA_S           │ 0xDEADBEEF→0     │
       │   HWRITE_S           │ 1→0              │
────────────────────────────────────────────────────────────────────────────────
```

### Tóm tắt timeline T2.1 (5 cycles hữu ích)

```
C1: HBUSREQ=1 → Arbiter grants M1
C2: BFM drive Address Phase (HADDR=0x10, NONSEQ, WRITE)
C3: AP kết thúc. Wait-state: HREADY drops 0. HWDATA=0xDEADBEEF xuất hiện.
C4: BFM stall (HREADY=0). Slave→ST_WBURST. HREADY recovery→1.
C5: BFM thấy HREADY=1 → ok=1. SRAM write thực thi. Transfer done.
```

---

## 5. T2.2 — M1 Read 0x0000_0010 → Verify 0xDEADBEEF <a name="t22"></a>

Read pipeline tương tự write nhưng data flow ngược lại.

```
────────────────────────────────────────────────────────────────────────────────
 Cycle │ Event                                     │ Key Signals
────────────────────────────────────────────────────────────────────────────────
  C1   │ BFM: ensure_grant (HGRANT=1, skip)         │
       │ @(posedge); #1: HADDR=0x10, HTRANS=NS,     │ HADDR_S=0x10
       │                 HWRITE=0                    │ HWRITE_S=0
       │ Slave1 comb: ns=ST_ACTIVE                   │ HSEL_S1=1
────────────────────────────────────────────────────────────────────────────────
  C2   │ ① BFM: HREADY=1(cũ) → skip while           │
       │ ② Slave1: ps←ST_ACTIVE                      │
       │ ③ Comb: HREADYOUT=0 (wait-state)            │ HREADY_GLOBAL: 1→0
       │ #1: HTRANS=IDLE                              │
────────────────────────────────────────────────────────────────────────────────
  C3   │ ① BFM: HREADY=0 → loop → chờ C4            │ BFM STALL
       │ ② Slave1: ps←ST_RBURST                      │
       │    beat_cnt←1                                │
       │ ③ Comb (ST_RBURST, B_SINGLE, addr≠0x00):    │
       │    HREADYOUT=1, HRDATA=memory[0x04]          │ HRDATA_S1=0xDEADBEEF
       │    ns=ST_IDLE                                │ HREADY_GLOBAL: 0→1
────────────────────────────────────────────────────────────────────────────────
  C4   │ ① BFM: HREADY=1 → exit while                │
       │    data = HRDATA = 0xDEADBEEF ✓              │ ★ READ COMPLETE ★
       │    ok = (HRESP==OKAY) = 1 ✓                  │
       │ ② Slave1: ps←ST_IDLE                         │
────────────────────────────────────────────────────────────────────────────────
```

**Chú ý:** HRDATA_M valid tại C3 (sau comb re-eval ③), nhưng BFM đọc nó tại C4
(active region ①). Do pipeline, data luôn available 1 cycle trước khi BFM sample.

**🔴 Nếu HRDATA_M ≠ 0xDEADBEEF:**
- Kiểm tra `mux_sel_data_phase` trong read_data_mux → phải = 2'b00 (S1)
- Kiểm tra Slave1 memory[0x04] → nếu = 0 thì T2.1 write đã fail
- Kiểm tra HMASTER → nếu ≠ 0 thì encoding bug

---

## 6. T2.3 — Default Slave ERROR (2-Cycle) <a name="t23"></a>

Default Slave **KHÔNG có ST_ACTIVE wait-state** — chỉ có 2-cycle error FSM.

```
────────────────────────────────────────────────────────────────────────────────
 Cycle │ Event                                     │ Key Signals
────────────────────────────────────────────────────────────────────────────────
  C1   │ BFM: HADDR=0xC000_0000, HTRANS=NONSEQ      │ HADDR_S=0xC000_0000
       │ Decoder: HSEL_DEFAULT=1, MUX_SEL=2'b11      │ HSEL_DEFAULT=1
       │ DefSlave comb (ST_IDLE): ns=ST_ERROR_CYC1    │ HREADYOUT_DEFAULT=1
────────────────────────────────────────────────────────────────────────────────
  C2   │ ① BFM: HREADY=1(cũ) → skip while            │ AP kết thúc
       │ ② DefSlave: ps←ST_ERROR_CYC1                 │
       │    Pipeline: mux_sel_dp←2'b11                 │
       │ ③ Comb (CYC1): HREADYOUT=0, HRESP=ERROR      │ HREADY: 1→0
       │ #1: HWDATA=0xBAD0CAFE, HTRANS=IDLE            │ HRESP_M=ERROR
────────────────────────────────────────────────────────────────────────────────
  C3   │ ① BFM: HREADY=0 → loop                       │ ERROR cycle 1
       │ ② DefSlave: ps←ST_ERROR_CYC2                  │
       │ ③ Comb (CYC2): HREADYOUT=1, HRESP=ERROR      │ HREADY: 0→1
       │                                               │ HRESP_M=ERROR (still)
────────────────────────────────────────────────────────────────────────────────
  C4   │ ① BFM: HREADY=1 → exit while                 │ ERROR cycle 2
       │    ok = (HRESP==OKAY) → FALSE → ok=0 ✓        │ ★ ERROR DETECTED ★
       │ ② DefSlave: ps←ST_IDLE                         │
────────────────────────────────────────────────────────────────────────────────
```

**2-cycle ERROR protocol (AHB §3.9.3):**
```
       │ CYC1        │ CYC2        │
HREADY │    0         │    1         │
HRESP  │  ERROR       │  ERROR       │
       │ ← kéo dài → │ ← kết thúc →│
```

Master nhận lỗi khi thấy HRESP=ERROR + HREADY=1 (cuối CYC2).

---

## 7. T2.4 — M1 Write to Slave 2 (0x4000_0010) <a name="t24"></a>

Timing giống T2.1 nhưng Decoder route sang S2.

```
C1: BFM: HADDR=0x4000_0010. Decoder: HSEL_S2=1, MUX_SEL=2'b01  ← KEY CHECK
C2: Slave2 → ST_ACTIVE. HREADY drops 0. HWDATA=0xCAFE1234.
C3: Slave2 → ST_WBURST. HREADY recovery 1. BFM stall.
C4: BFM: HREADY=1, ok=1. SRAM write tại Slave2. Transfer done.
```

**Key check:** `MUX_SEL == 2'b01` (không phải 2'b00).
**Verify:** Read back → HRDATA phải = 0xCAFE1234.

---

## 8. T2.5 — M1 Write to Slave 3 (0x8000_0010) <a name="t25"></a>

```
C1: BFM: HADDR=0x8000_0010. Decoder: HSEL_S3=1, MUX_SEL=2'b10
C2: Wait-state. C3: Recovery. C4: Done. Data=0xBEEF5678.
```

---

## 9. T2.6 — HREADY_GLOBAL Feedback <a name="t26"></a>

Mục đích: xác nhận HREADY_GLOBAL dips → recovers → pipeline hoạt động.

```
Feedback loop:

HREADYOUT_Sx ──→ ready_mux ──→ HREADY_GLOBAL ──┬→ Slaves (HREADY_IN)
                      ↑                          ├→ Arbiter (HREADY)
                      │                          ├→ Pipeline regs (enable)
                      └──────────────────────────┘  (self-feedback)
```

Mỗi Slave transfer đều trigger loop: HREADY_GLOBAL drop (ST_ACTIVE) → 
pipeline regs freeze (EN=0) → HREADY_GLOBAL recovery (ST_WBURST) → 
pipeline regs resume. Đã tự nhiên xảy ra ở T2.1.

**✅ Check:**
- `HREADY_GLOBAL === HREADY` luôn TRUE (wire assign trong Interconnect)
- Khi `HREADY_GLOBAL=0`: `mux_sel_data_phase` KHÔNG đổi (frozen)
- Khi `HREADY_GLOBAL=1`: `mux_sel_data_phase` update bình thường

---

## 10. T2.7 — Cross-Slave RAW <a name="t27"></a>

3 bước: Write S1 → Read S2 → Re-read S1.

```
────────────────────────────────────────────────────────────────────────────────
 Step │ Addr             │ MUX_SEL  │ mux_sel_dp │ Expected Data
────────────────────────────────────────────────────────────────────────────────
  1   │ Write 0x0000_0030│ 2'b00    │ 00         │ W: 0xAAAABBBB → S1
  2   │ Read  0x4000_0008│ 2'b01    │ 01 ← SWITCH│ R: 30 (S2 seed mem[2])
  3   │ Read  0x0000_0030│ 2'b00    │ 00 ← SWITCH│ R: 0xAAAABBBB (S1, intact)
────────────────────────────────────────────────────────────────────────────────
```

**Critical check:** `mux_sel_data_phase` trong ready_mux/read_data_mux phải
switch từ 00→01→00. Nếu bị kẹt, HRDATA_M sẽ đọc từ sai slave.

**🔴 Cross-contamination:** Nếu Step 3 đọc ra giá trị ≠ 0xAAAABBBB:
- Kiểm tra `mux_sel_dp` có switch lại 00 không
- Kiểm tra Slave1 memory[0x0C] (0x30/4=0x0C) có bị ghi đè không

---

## 11. T2.8 — INCR4 Burst <a name="t28"></a>

4-beat write rồi 4-beat read tại S1 (base=0x0000_0040).

### Write Burst Timing:

```
────────────────────────────────────────────────────────────────────────────────
 Cycle │ HTRANS │ HADDR_S    │ HWDATA_S     │ Slave1 state │ HREADY
────────────────────────────────────────────────────────────────────────────────
  C1   │ NONSEQ │ 0x0040     │ ---          │ IDLE→ACTIVE  │ 1
  C2   │ SEQ    │ 0x0044     │ ---          │ ACTIVE       │ 1→0 (wait)
  C3   │ SEQ    │ 0x0044     │ wdata[0]     │ WBURST       │ 0→1
       │ (stall)│ (held)     │              │ beat_cnt=4   │
  C4   │ SEQ    │ 0x0048     │ wdata[1]     │ WBURST       │ 1
       │        │            │              │ beat_cnt=3   │
  C5   │ IDLE   │ 0x004C     │ wdata[2]     │ WBURST       │ 1
       │        │            │              │ beat_cnt=2   │
  C6   │ IDLE   │ ---        │ wdata[3]     │ WBURST→IDLE  │ 1
       │        │            │              │ beat_cnt=1→0 │
  C7   │        │            │              │ IDLE         │ 1
       │        │            │              │              │ ★ BURST DONE ★
────────────────────────────────────────────────────────────────────────────────
```

**Lưu ý burst:**
- Beat đầu (NONSEQ) bị 1 wait-state từ ST_ACTIVE → HREADY=0 tại C2
- Beats SEQ tiếp theo: ST_WBURST liên tục → HREADY=1 → không bị wait
- HWDATA luôn trễ 1 cycle so với HADDR (pipeline delay)
- HADDR auto-increment +4 mỗi beat (BFM tính)

### Read Burst Timing:

```
 Cycle │ HTRANS │ HADDR_S │ HRDATA_M     │ Slave1     │ HREADY
────────────────────────────────────────────────────────────────────────────
  C1   │ NONSEQ │ 0x0040  │ ---          │ IDLE→ACT   │ 1
  C2   │ SEQ    │ 0x0044  │ ---          │ ACTIVE     │ 1→0 (wait)
  C3   │ SEQ    │ 0x0044  │ rdata[0]     │ RBURST     │ 0→1
  C4   │ SEQ    │ 0x0048  │ rdata[1]     │ RBURST     │ 1
  C5   │ IDLE   │ 0x004C  │ rdata[2]     │ RBURST     │ 1
  C6   │        │         │ rdata[3]     │ RBURST→IDL │ 1
  C7   │        │         │              │ IDLE       │ 1 ★ DONE ★
────────────────────────────────────────────────────────────────────────────
```

**✅ Verify:** rdata[0..3] phải = wdata[0..3] = {0x11110001, 0x22220002, 0x33330003, 0x44440004}

---

## 12. Bảng Chẩn Đoán Lỗi <a name="failures"></a>

### 12.1 Encoding

| Triệu chứng | Root Cause | Kiểm tra |
|---|---|---|
| HMASTER=4'd1 khi M1 granted | Arbiter v1 encoding | state_q=GNT_M1 nhưng HMASTER≠0 |
| HWDATA_S = HWDATA_M2 | write_data_mux encoding sai | master_sel_dp phải = 4'd0 |
| HADDR_S = HADDR_M2 | addr_ctrl_mux encoding sai | HMASTER_SEL phải = 4'd0 |

### 12.2 Pipeline Timing

| Triệu chứng | Root Cause |
|---|---|
| HRDATA_M valid cùng cycle AP | read_data_mux bypass pipeline |
| HRDATA_M delay 2 cycles | Double-registered hoặc BFM sample sai |
| HWDATA_S không match M1 | master_sel_dp ≠ 4'd0 → route M2 |

### 12.3 Wait-State

| Triệu chứng | Root Cause |
|---|---|
| Simulation treo (timeout) | HREADY stuck 0 — Slave FSM kẹt |
| Không thấy HREADY dip | Slave không vào ST_ACTIVE — check HSEL, HTRANS |
| BFM stall 2+ cycles | Slave có >1 wait state (chỉ nên có 1 từ ST_ACTIVE) |

### 12.4 Decoder

| Triệu chứng | Root Cause |
|---|---|
| Sai slave selected | HADDR_S sai → check addr_ctrl_mux |
| HSEL_DEFAULT khi write S1 | HADDR_S nhận từ M2 thay M1 |
| 2 HSEL bật cùng lúc | Decoder bug (case không mutex) |

---

## Checklist Debug Nhanh

```
□  1. HRESETn: ≥5 cycles reset, release ổn định
□  2. HBUSREQ_M1=1 trước posedge → Arbiter grant sau 1 cycle
□  3. HGRANT_M1=1 → HMASTER=4'd0 (v2 encoding)
□  4. BFM drive address: HADDR_S=target, HTRANS=NONSEQ
□  5. Decoder: đúng HSEL_Sx và MUX_SEL
□  6. Posedge AP end: Slave→ST_ACTIVE, HREADYOUT drops 0
□  7. HWDATA_S xuất hiện cùng lúc HREADY drop (đúng, BFM thấy HREADY=1 pre-NBA)
□  8. Cycle tiếp: Slave→ST_WBURST, HREADYOUT recovery 1
□  9. BFM stall 1 cycle (thấy HREADY=0 ở active region)
□ 10. Cycle tiếp: BFM thấy HREADY=1, sample ok. SRAM write execute.
□ 11. HGRANT_M1 luôn=1 suốt Layer 2 (M2 idle, expected)
□ 12. T2.3: Default Slave 2-cycle ERROR, không có ST_ACTIVE wait-state
□ 13. T2.8 Burst: chỉ beat đầu (NONSEQ) bị wait, SEQ beats không bị
```

---

*Phiên bản: v2.1 (timing đã sửa — loại bỏ repeat(3), bổ sung Slave wait-state)*
*Dự án: AHB 2.0 Multi-Master Interconnect — Layer 2 Integration Test*
