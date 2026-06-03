# AHB Layer 2 — Hướng Dẫn Debug Waveform (Chu Kỳ Từng Clock)

## Mục lục
1. [Nguyên tắc Pipeline AHB](#pipeline)
2. [Bảng Encoding v2 (0=M1, 1=M2)](#encoding)
3. [Nhóm Tín Hiệu Cần Thêm Vào Waveform](#signals)
4. [T2.1 — M1 Write to Slave 1](#t21)
5. [T2.2 — M1 Read from Slave 1 (Read-After-Write)](#t22)
6. [T2.3 — Default Slave ERROR (2-Cycle)](#t23)
7. [T2.4 — M1 Write to Slave 2 (Decoder Routing)](#t24)
8. [T2.5 — M1 Write to Slave 3](#t25)
9. [T2.6 — HREADY_GLOBAL Feedback Loop](#t26)
10. [T2.7 — Cross-Slave Read-After-Write](#t27)
11. [T2.8 — INCR4 Burst via Interconnect](#t28)
12. [Bảng Chẩn Đoán Lỗi Thường Gặp](#failures)

---

## 1. Nguyên Tắc Pipeline AHB <a name="pipeline"></a>

AHB có **2 pha chồng lấp** trên bus:

```
Clock:     |  N  |  N+1  |  N+2  |
           |     |       |       |
Pha:       |← AP →|← DP  →|       |
           |     |       |       |
HADDR_S:   |ADDR |  ---  |       |   ← Master đưa địa chỉ trong AP
HTRANS_S:  |NS   |  IDL  |       |
HSEL_Sx:   |  1  |   0   |       |   ← Decoder comb từ HADDR_S
MUX_SEL:   |  x  |   x   |       |   ← Decoder comb, được chốt vào pipeline reg
           |     |       |       |
HWDATA_S:  |     |  DATA |       |   ← Master drive data 1 cycle SAU AP
HRDATA_M:  |     | DATA_R|       |   ← Slave trả data trong DP
HRESP_M:   | OK  |  OK   |       |   ← Được chốt bởi resp_mux sau 1 cycle delay
HREADY:    |  1  |   1   |       |   ← S1 HREADYOUT=1, không có wait state
```

**Quy tắc quan trọng:**
- Tín hiệu `HADDR_S`, `HTRANS_S`, `HSEL_Sx` thay đổi ngay (combinational)
- Tín hiệu `HRDATA_M`, `HRESP_M`, `HREADY_GLOBAL` luôn **trễ 1 cycle** so với AP  
  (do pipeline registers trong read_data_mux / resp_mux / ready_mux)
- `HWDATA_S` trễ 1 cycle so với AP (do write_data_mux pipeline register)
- `HMASTER` cập nhật ngay khi Arbiter FSM chuyển trạng thái (comb từ state_q)

---

## 2. Bảng Encoding v2 <a name="encoding"></a>

| Signal / State | Giá trị | Ý nghĩa |
|---|---|---|
| `HMASTER` | `4'd0` | **M1 owns bus** — cả IDLE lẫn GNT_M1 đều = 0 |
| `HMASTER` | `4'd1` | **M2 owns bus** |
| `HMASTER` | `4'd2+` | Reserved / illegal → MUX mặc định sang M1 |
| `HGRANT_M1` | `1` | Arbiter đang grant cho M1 (phân biệt IDLE vs GNT) |
| `HGRANT_M2` | `1` | Arbiter đang grant cho M2 |

> **Lưu ý:** `HMASTER=4'd0` KHÔNG có nghĩa là "idle" nữa trong v2.  
> Dùng `HGRANT_M1/M2` để phân biệt "idle" (cả hai = 0) và "M1 granted" (HGRANT_M1=1).

---

## 3. Nhóm Tín Hiệu Cần Thêm Vào EDA Playground <a name="signals"></a>

Trong EDA Playground Waveform viewer, thêm theo thứ tự này:

### Group A — Clock & Reset
```
HCLK, HRESETn
```

### Group B — Arbiter (Bus Ownership)
```
u_arbiter/state_q          ← FSM state: ST_IDLE / ST_GNT_M1 / ST_GNT_M2
HBUSREQ_M1, HBUSREQ_M2    ← Master đang xin bus
HGRANT_M1,  HGRANT_M2      ← Arbiter chấp thuận
HMASTER[3:0]                ← v2: 0=M1, 1=M2
HMASTLOCK
```

### Group C — Shared Address Bus (Address Phase)
```
HADDR_S[31:0]
HTRANS_S[1:0]              ← 2'b00=IDLE, 2'b10=NONSEQ, 2'b11=SEQ
HWRITE_S
HSIZE_S[2:0], HBURST_S[2:0]
```

### Group D — Decoder Outputs
```
HSEL_S1, HSEL_S2, HSEL_S3, HSEL_DEFAULT
MUX_SEL[1:0]               ← 2'b00=S1, 2'b01=S2, 2'b10=S3, 2'b11=DEFAULT
```

### Group E — Data Bus
```
HWDATA_S[31:0]             ← Write data (1 cycle delayed)
HRDATA_M[31:0]             ← Read data từ Slave
u_write_data_mux/master_sel_data_phase[3:0]   ← pipeline select register
```

### Group F — Handshake (Pipeline Response)
```
HREADY_GLOBAL              ← HREADY seen by Masters (= HREADY)
HRESP_M[1:0]               ← 2'b00=OKAY, 2'b01=ERROR
u_ready_mux/mux_sel_data_phase[1:0]   ← pipeline select register
```

### Group G — Slave Individual
```
HREADYOUT_S1, HRESP_S1[1:0]
HREADYOUT_S2, HRESP_S2[1:0]
HREADYOUT_S3, HRESP_S3[1:0]
HREADYOUT_DEFAULT, HRESP_DEFAULT[1:0]
```

### Group H — BFM Monitor (nếu có)
```
m1_bfm/HBUSREQ, m1_bfm/HGRANT
```

---

## 4. T2.1 — TC_L2_M1_WRITE_S1 <a name="t21"></a>

**Mục đích:** M1 write 0xDEADBEEF vào địa chỉ 0x0000_0010 (Slave 1)

```
Ký hiệu: IDL=IDLE, NS=NONSEQ, OK=OKAY, X=don't-care
─────────────────────────────────────────────────────────────────────────────
Cycle:         |  RST | C1  | C2  | C3  | C4  | C5  |
Signal         |      |     |     |     |     |     |
─────────────────────────────────────────────────────────────────────────────
HRESETn:       |  0   |  1  |  1  |  1  |  1  |  1  |
HBUSREQ_M1:    |  0   |  1  |  1  |  1  |  0  |  0  |

─── Arbiter FSM ────────────────────────────────────────────────────────────
state_q:       | IDLE | GNT1| GNT1| GNT1|IDLE |IDLE | ← cập nhật tại posedge
HGRANT_M1:     |  0   |  1  |  1  |  1  |  0  |  0  | ← comb từ state_q
HMASTER[3:0]:  | 4'd0 |4'd0 |4'd0 |4'd0 |4'd0 |4'd0 | ← v2: M1=0, IDLE=0

─── Address Phase (comb, BFM drive sau khi thấy HGRANT=1) ──────────────────
HADDR_S:       |  0   |  0  |0x10 |  0  |  0  |  0  |  ← BFM drive tại C2
HTRANS_S:      | IDL  | IDL | NS  | IDL | IDL | IDL |
HWRITE_S:      |  0   |  0  |  1  |  0  |  0  |  0  |
HSEL_S1:       |  0   |  0  |  1  |  0  |  0  |  0  | ← decoder: HADDR[31:30]=00
MUX_SEL:       | 00   | 00  | 00  | 00  | 00  | 00  |

─── Pipeline Registers (chốt tại posedge khi HREADY=1) ─────────────────────
write_data_mux│
 master_sel_dp:|4'd0  |4'd0 |4'd0 |4'd0 |4'd0 |4'd0 | ← 0=M1, không đổi
ready_mux│
 mux_sel_dp:  | 00   | 00  | 00  | 00  | 00  | 00  | ← route → S1

─── Data Phase ─────────────────────────────────────────────────────────────
HWDATA_S:      |  0   |  0  |  0  |0xDE | ... |  0  | ← pipeline delay 1 cy
HREADYOUT_S1:  |  1   |  1  |  1  |  1  |  1  |  1  | ← S1 no wait states
HREADY_GLOBAL: |  1   |  1  |  1  |  1  |  1  |  1  |
HRESP_M:       | OK   | OK  | OK  | OK  | OK  | OK  |
─────────────────────────────────────────────────────────────────────────────
```

**Chú thích quan trọng C1:**
> Tại `posedge C1`: Arbiter thấy `HBUSREQ_M1=1, eff_req_m2=0` → `state_q ← ST_GNT_M1`
> → Ngay sau đó (comb): `HGRANT_M1=1, HMASTER=4'd0`

**Chú thích quan trọng C2:**
> BFM phát hiện `HGRANT_M1=1`, drive `HADDR_S=0x10, HTRANS=NONSEQ, HWRITE=1`
> Decoder comb: `HSEL_S1=1, MUX_SEL=2'b00`  
> Tại `posedge C2` (HREADY=1): `master_sel_dp ← 4'd0`, `mux_sel_dp ← 2'b00`

**Chú thích quan trọng C3:**
> `master_sel_dp=4'd0` → `HWDATA_S = HWDATA_M1 = 0xDEADBEEF`  
> S1 nhận write và lưu vào SRAM tại offset 0x10/4=4

**✅ Assertions cần pass:**
- `HGRANT_M1 == 1` khi BFM bắt đầu drive
- `HMASTER == 4'd0` (v2: M1=0)
- `HRESP_M == OKAY` tại C3
- `HREADY_GLOBAL == 1` xuyên suốt (S1 no wait)

**🔴 Failure Patterns:**
| Triệu chứng | Nguyên nhân |
|---|---|
| `HGRANT_M1` không lên 1 | Arbiter state_q không chuyển; kiểm tra HBUSREQ_M1 và reset |
| `HMASTER == 4'd1` thay vì 4'd0 | Arbiter còn encoding cũ (v1); kiểm tra file đã cập nhật |
| `HWDATA_S` sai (= HWDATA_M2) | write_data_mux dùng encoding cũ; `master_sel_dp==4'd1` → M2 |
| `HSEL_S1 == 0` | Decoder không nhận HADDR_M1; kiểm tra addr_ctrl_mux wiring |

---

## 5. T2.2 — TC_L2_M1_READ_S1 <a name="t22"></a>

**Mục đích:** Read lại data đã write ở T2.1, verify pipeline 1-cycle delay

```
─────────────────────────────────────────────────────────────────────────────
Cycle:         | C1  | C2  | C3  | C4  |
               |     |     |     |     |
─── Address Phase ──────────────────────────────────────────────────────────
HADDR_S:       |0x10 |  0  |  0  |  0  |  ← Read addr
HTRANS_S:      | NS  | IDL | IDL | IDL |
HWRITE_S:      |  0  |  0  |  0  |  0  |  ← Read = 0
HSEL_S1:       |  1  |  0  |  0  |  0  |

─── Pipeline Registers ─────────────────────────────────────────────────────
mux_sel_dp:    | 00  | 00  | 00  | 00  |  ← S1 routing

─── Data Phase (1 cycle AFTER AP) ──────────────────────────────────────────
HRDATA_M:      |  0  |0xDE…|  0  |  0  |  ← DATA valid tại C2 (1 cy delay)
HRESP_M:       | OK  | OK  | OK  | OK  |
HREADY:        |  1  |  1  |  1  |  1  |
─────────────────────────────────────────────────────────────────────────────
```

**Key insight — Pipeline delay:**
```
   posedge C1:  mux_sel_dp ← 2'b00 (S1)
                                     ↓
   C2 (comb):  HRDATA_M = HRDATA_S1 = 0xDEADBEEF  ✓
```

**🔴 Failure Patterns:**
| Triệu chứng | Nguyên nhân |
|---|---|
| `HRDATA_M == 0` tại C2 | S1 SRAM chưa được write; T2.1 thực sự fail |
| `HRDATA_M` có data ngay tại C1 (không delay) | read_data_mux pipeline register bị bypass |
| `HRDATA_M` đúng nhưng test FAIL | Testbench sample sai chu kỳ (nên đọc ở posedge C2) |

---

## 6. T2.3 — DEFAULT SLAVE ERROR (2-Cycle) <a name="t23"></a>

**Mục đích:** Write vào 0xC000_0000 → Default Slave → 2-cycle ERROR response

```
─────────────────────────────────────────────────────────────────────────────
Cycle:         | C1  | C2  | C3  | C4  | C5  |
               |     |     |     |     |     |
─── Address Phase ──────────────────────────────────────────────────────────
HADDR_S:       |0xC0…|  0  |  0  |  0  |  0  |  ← 0xC000_0000
HTRANS_S:      | NS  | IDL | IDL | IDL | IDL |
HSEL_DEFAULT:  |  1  |  0  |  0  |  0  |  0  |  ← HADDR[31:30]=11

─── Default Slave FSM ───────────────────────────────────────────────────────
ds_ps:         | IDL |CYC1 |CYC2 | IDL | IDL |  ← cập nhật tại posedge
HREADYOUT_DEF: |  1  |  0  |  1  |  1  |  1  |  ← CYC1=0! CYC2=1
HRESP_DEFAULT: | OK  | ERR | ERR | OK  | OK  |

─── Pipeline Registers ─────────────────────────────────────────────────────
mux_sel_dp:    | 11  | 11  | 11  | 11  | --  |  ← route → DEFAULT SLAVE
               (captured at posedge C1 when HREADY=1)

─── Interconnect Output ─────────────────────────────────────────────────────
HREADY_GLOBAL: |  1  |  0  |  1  |  1  |  1  |  ← follows HREADYOUT_DEFAULT
HRESP_M:       | OK  | ERR | ERR | OK  | OK  |  ← 1 cy delay from resp_mux

Chú thích HREADY: Tại C2: HREADY=0 (CYC1) → Pipeline registers KHÔNG update
                  Tại C3: HREADY=1 (CYC2) → Kết thúc transfer lỗi
─────────────────────────────────────────────────────────────────────────────
```

**2-cycle ERROR Protocol (AHB §3.9.3):**
```
           |← AP →|← DP-ERR-CYC1 →|← DP-ERR-CYC2 →|
HREADY:    |  1   |       0        |       1         |  
HRESP:     |  OK  |     ERROR      |     ERROR       |  ← Master nhận lỗi tại CYC2
HTRANS     |  NS  |      IDL       |      IDL        |  ← Master hủy pipeline
```

**Timing chi tiết:**

| Cycle | Event |
|---|---|
| C1 | AP: HADDR=0xC000_0000, HTRANS=NONSEQ. Default Slave: `active_transfer=1` → `ns=ST_ERROR_CYC1` |
| C1 posedge | `ds_ps ← ST_ERROR_CYC1`, `mux_sel_dp ← 2'b11` |
| C2 | DS comb output (ps=CYC1): `HREADYOUT=0, HRESP=ERROR`. `HREADY_GLOBAL=0` |
| C2 posedge | HREADY=0 → pipeline regs KHÔNG update. `ds_ps ← ST_ERROR_CYC2` |
| C3 | DS comb output (ps=CYC2): `HREADYOUT=1, HRESP=ERROR`. `HREADY_GLOBAL=1` |
| C3 posedge | HREADY=1 → `mux_sel_dp` có thể update. `ds_ps ← ST_IDLE` |

**✅ Assertions cần pass:**
- `HSEL_DEFAULT == 1` tại C1
- `HREADY_GLOBAL == 0` tại C2 (CYC1 dips)
- `HREADY_GLOBAL == 1` tại C3 (CYC2 recovery)
- `HRESP_M == 2'b01 (ERROR)` tại C2 VÀ C3

**🔴 Failure Patterns:**
| Triệu chứng | Nguyên nhân |
|---|---|
| `HSEL_DEFAULT == 0` | Decoder không nhận HADDR[31:30]=11; kiểm tra addr_ctrl_mux |
| `HREADY_GLOBAL` không về 0 | ready_mux chưa chốt MUX_SEL=2'b11 kịp; xem mux_sel_dp |
| `HRESP_M` không báo ERROR | resp_mux routing sai; kiểm tra pipeline register |
| Chỉ thấy 1 chu kỳ ERROR | Default Slave FSM lỗi; kiểm tra `ds_ps` waveform |

---

## 7. T2.4 — M1 WRITE TO SLAVE 2 <a name="t24"></a>

**Mục đích:** Kiểm tra Decoder routing HADDR[31:30]=01 → S2, MUX_SEL=2'b01

```
─────────────────────────────────────────────────────────────────────────────
Cycle:         | C1  | C2  | C3  |
─── Address Phase ──────────────────────────────────────────────────────────
HADDR_S:       |0x40…|  0  |  0  |  ← 0x4000_0010
HTRANS_S:      | NS  | IDL | IDL |
HSEL_S2:       |  1  |  0  |  0  |  ← HADDR[31:30]=01 → S2
HSEL_S1:       |  0  |  0  |  0  |  ← S1 KHÔNG được chọn ← ★ kiểm tra điều này
MUX_SEL:       | 01  | 01  | 01  |  ← route → S2

─── Pipeline Registers ─────────────────────────────────────────────────────
mux_sel_dp:    | 01  | 01  | 01  |  ← sau posedge C1
HWDATA_S:      |  0  |0xBE…|  0  |  ← write data (HWDATA_M1 pipeline delayed)

─── Data Phase ─────────────────────────────────────────────────────────────
HRESP_M:       | OK  | OK  | OK  |
HREADY:        |  1  |  1  |  1  |
─────────────────────────────────────────────────────────────────────────────
```

**✅ Key Check: MUX_SEL must switch**
```
  T2.1: MUX_SEL = 2'b00 (S1)
  T2.4: MUX_SEL = 2'b01 (S2)  ← Decoder routing change
```

**🔴 Failure:** `HSEL_S1=1` vẫn bật khi write S2 → addr_ctrl_mux không routing đúng HADDR_M1

---

## 8. T2.5 — M1 WRITE TO SLAVE 3 <a name="t25"></a>

**Mục đích:** Kiểm tra Decoder routing HADDR[31:30]=10 → S3, MUX_SEL=2'b10

```
HADDR_S:   | 0x8000_0010 |   ← HADDR[31:30] = 10
HSEL_S3:   |      1      |   ← S3 selected
MUX_SEL:   |    2'b10    |
```

**Note:** Tương tự T2.4, chỉ khác Slave và địa chỉ.

---

## 9. T2.6 — HREADY_GLOBAL FEEDBACK LOOP <a name="t26"></a>

**Mục đích:** Quan sát HREADY_GLOBAL tự hồi tiếp lại ready_mux và Arbiter

**Sơ đồ hồi tiếp:**
```
HREADYOUT_S1 ──┐
HREADYOUT_S2 ──┤  ready_mux ──→ HREADY_GLOBAL ──┬──→ Slaves (HREADY_IN)
HREADYOUT_S3 ──┤      ↑                          ├──→ Arbiter (HREADY)
HREADYOUT_DEF─┘      │                          └──→ Pipeline Regs (enable)
                       └──────────────────────────── (self-feedback)
```

```
─────────────────────────────────────────────────────────────────────────────
Cycle:               | C1  | C2  | C3  | C4  | C5  |
─────────────────────────────────────────────────────────────────────────────
Kịch bản: write to S1 (no wait state)
─────────────────────────────────────────────────────────────────────────────
HADDR_S:             |0x10 |  0  |  0  |  0  |  0  |
HSEL_S1:             |  1  |  0  |  0  |  0  |  0  |
mux_sel_dp (ready):  | 00  | 00  | 00  | 00  | 00  | ← captured at posedge C1
HREADYOUT_S1:        |  1  |  1  |  1  |  1  |  1  | ← S1 no wait
HREADY_GLOBAL:       |  1  |  1  |  1  |  1  |  1  | ← always 1 for S1
─────────────────────────────────────────────────────────────────────────────
Kịch bản với wait state (hypothetical, S1 có thể insert 0):
─────────────────────────────────────────────────────────────────────────────
HREADYOUT_S1:        |  1  |  1  |  0  |  0  |  1  | ← S1 insert 2 wait states
HREADY_GLOBAL:       |  1  |  1  |  0  |  0  |  1  | ← follow S1
Pipeline regs EN:    |  1  |  1  |  0  |  0  |  1  | ← freeze on HREADY=0
master_sel_dp:       |  x  |  x  | HOLD|HOLD |update| ← frozen during wait
─────────────────────────────────────────────────────────────────────────────
```

**✅ Kiểm tra:**
- `HREADY_GLOBAL === HREADY` — hai signal này phải giống hệt nhau
- Khi `HREADY=0`: tất cả pipeline registers freeze (không update)
- Khi `HREADY=1`: pipeline registers mới update

---

## 10. T2.7 — CROSS-SLAVE READ-AFTER-WRITE <a name="t27"></a>

**Mục đích:** Write S1, sau đó read S2 (khác nhau), sau đó re-read S1 → kiểm tra không contamination

**Waveform tổng thể:**
```
Phase:    | W_S1 | R_S2 | R_S1 |

HADDR_S:  |0x0010|0x4020|0x0010|
MUX_SEL:  |  00  |  01  |  00  |  ← Decoder phải switch đúng
HSEL_S1:  |  1   |  0   |  1   |  ← S1: on, off, on
HSEL_S2:  |  0   |  1   |  0   |  ← S2: off, on, off

HRDATA_M: |  0   | S2dat| S1dat|  ← read_data_mux phải chọn đúng slave
```

**Critical check — MUX_SEL Switch:**
```
W_S1 phase: mux_sel_dp = 2'b00 → HRDATA_M routes from S1
R_S2 phase: mux_sel_dp = 2'b01 → HRDATA_M routes from S2  ← watch this!
R_S1 phase: mux_sel_dp = 2'b00 → HRDATA_M routes from S1
```

**🔴 Failure: Cross-contamination**
- `HRDATA_M` lấy từ S1 khi đang read S2 → read_data_mux `mux_sel_dp` không update kịp

---

## 11. T2.8 — INCR4 BURST VIA INTERCONNECT <a name="t28"></a>

**Mục đích:** 4-beat INCR4 burst write rồi read 4 words, verify data integrity

**INCR4 Burst Write Timing (4 beats):**
```
─────────────────────────────────────────────────────────────────────────────
Cycle:         | C1  | C2  | C3  | C4  | C5  | C6  | C7  |
─────────────────────────────────────────────────────────────────────────────
HADDR_S:       |0x00 |0x04 |0x08 |0x0C |  0  |  0  |  0  |  ← auto-increment
HTRANS_S:      | NS  | SEQ | SEQ | SEQ | IDL |     |     |  ← NS, SEQ,SEQ,SEQ
HBURST_S:      |INCR4|INCR4|INCR4|INCR4| 0   |     |     |  ← 3'b011
HWRITE_S:      |  1  |  1  |  1  |  1  |  0  |     |     |
HSEL_S1:       |  1  |  1  |  1  |  1  |  0  |     |     |
─────────────────────────────────────────────────────────────────────────────
HWDATA_S:      |  0  |D[0] |D[1] |D[2] |D[3] |     |     |  ← pipeline delay
HREADY:        |  1  |  1  |  1  |  1  |  1  |  1  |  1  |
─────────────────────────────────────────────────────────────────────────────
```

**AHB HTRANS Sequence for INCR4:**
```
Beat 1: HTRANS = NONSEQ (2'b10), HADDR = base
Beat 2: HTRANS = SEQ    (2'b11), HADDR = base + 4
Beat 3: HTRANS = SEQ    (2'b11), HADDR = base + 8
Beat 4: HTRANS = SEQ    (2'b11), HADDR = base + 12
Beat 5: HTRANS = IDLE   (2'b00), burst complete
```

**Burst Read (sau write) — verify all 4 words:**
```
Read Cycle:    | C8  | C9  | C10 | C11 | C12 |
HADDR_S:       |0x00 |0x04 |0x08 |0x0C |  0  |
HTRANS_S:      | NS  | SEQ | SEQ | SEQ | IDL |
HRDATA_M:      |  0  |D[0] |D[1] |D[2] |D[3] |  ← 1 cycle delay per beat
```

**✅ Key checks:**
- HTRANS sequence: NS → SEQ → SEQ → SEQ → IDL
- HBURST_S stays INCR4 for all 4 beats
- HADDR increments by 4 each beat
- HWDATA pipeline: first data appears 1 cycle AFTER first NONSEQ
- All 4 read-back values match write values

---

## 12. Bảng Chẩn Đoán Lỗi Thường Gặp <a name="failures"></a>

### 12.1 — Encoding Issues

| Triệu chứng Waveform | Root Cause | Cách Kiểm Tra |
|---|---|---|
| `HMASTER=4'd1` khi M1 granted | Arbiter còn v1 encoding | Xem `state_q==ST_GNT_M1` nhưng `HMASTER=4'd1` |
| `HWDATA_S = HWDATA_M2` khi M1 granted | write_data_mux dùng 4'd1→M1 (cũ) | Xem `master_sel_data_phase` value |
| `HADDR_S = HADDR_M2` khi M1 granted | addr_ctrl_mux dùng 4'd1→M1 (cũ) | Comb: `HMASTER_SEL=4'd0` nhưng đọc M2 |

### 12.2 — Pipeline Timing Issues

| Triệu chứng | Root Cause |
|---|---|
| `HRDATA_M` valid cùng cycle với AP | read_data_mux bị bypass, không có pipeline reg |
| `HRDATA_M` delay 2 cycles (không phải 1) | read_data_mux bị double-register |
| `HWDATA_S` không match data M1 drive | write_data_mux `master_sel_dp` capture sai |
| Slave SRAM không lưu data | `HWRITE_S` sai vì `addr_ctrl_mux` routing M2 data |

### 12.3 — Arbiter / Grant Issues

| Triệu chứng | Root Cause |
|---|---|
| `HGRANT_M1` không bao giờ = 1 | `HBUSREQ_M1` không được assert hoặc Arbiter reset stuck |
| `HGRANT_M1=1` nhưng bus idle mãi | BFM không nhận grant (edge detection issue) |
| `HGRANT_M1` toggle liên tục | `last_master_q` không cập nhật; `HREADY` không về 1 |

### 12.4 — Decoder Issues

| Triệu chứng | Root Cause |
|---|---|
| Sai slave được chọn | Địa chỉ test sai; kiểm tra `HADDR[31:30]` trong waveform |
| `HSEL_DEFAULT` khi write S1 | `HADDR_S` nhận từ M2 (= 0x0) thay vì M1 — addr_ctrl_mux bug |
| 2 HSEL đồng thời = 1 | Decoder bug (không xảy ra với design này vì dùng case) |

### 12.5 — HREADY Feedback Loop

| Triệu chứng | Root Cause |
|---|---|
| Simulation treo (timeout) | HREADY stuck = 0; xem slave nào giữ `HREADYOUT=0` |
| Pipeline registers không cập nhật | `HREADY_GLOBAL` không reach pipeline reg enable port |
| `HREADY ≠ HREADY_GLOBAL` | Wiring bug trong top-level (`assign HREADY = HREADY_GLOBAL`) |

---

## Checklist Debug Nhanh

```
□ 1. HRESETn: Xác nhận reset đủ thời gian (≥2 cycles) trước khi test
□ 2. HBUSREQ_M1: Phải = 1 trước posedge để Arbiter grant trong cycle tiếp theo
□ 3. HGRANT_M1: Phải = 1 SAU ĐÚNG 1 cycle từ khi HBUSREQ=1
□ 4. HMASTER: Phải = 4'd0 khi M1 granted (v2 encoding)
□ 5. HADDR_S: Phải = địa chỉ từ M1 (không phải M2) — xem addr_ctrl_mux
□ 6. HSEL_Sx: Đúng slave được chọn theo HADDR[31:30]
□ 7. MUX_SEL: Match với HSEL (00=S1, 01=S2, 10=S3, 11=DEFAULT)
□ 8. mux_sel_dp: Capture tại posedge khi HREADY=1 (1 cycle sau MUX_SEL)
□ 9. HWDATA_S: Xuất hiện 1 cycle SAU AP (pipeline)
□ 10. HRDATA_M: Xuất hiện 1 cycle SAU AP (pipeline)
□ 11. HREADY: Không stuck ở 0 (nếu stuck, xem slave nào đang hold)
□ 12. T2.3: Đúng 2 cycles ERROR: HREADY=0 rồi HREADY=1 cùng HRESP=ERROR
```

---

*Phiên bản: v2 (HMASTER encoding: 0=M1, 1=M2)*  
*Dự án: AHB 2.0 Multi-Master Interconnect — Layer 2 Integration Test*
