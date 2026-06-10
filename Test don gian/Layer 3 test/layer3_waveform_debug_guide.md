# AHB Layer 3 — Hướng Dẫn Debug Waveform (2 Masters Active)

## Mục lục
1. [Tín Hiệu Mới Cần Theo Dõi](#signals)
2. [T3.1 — Round-Robin Grant](#t31)
3. [T3.2 — Bus Handover](#t32)
4. [T3.3 — Locked Burst (HLOCK)](#t33)
5. [T3.4 — SPLIT + Master Switch](#t34)
6. [T3.5 — SPLIT OR Logic](#t35)
7. [T3.6 — addr_ctrl_mux Switch](#t36)
8. [T3.7 — write_data_mux Pipeline](#t37)
9. [T3.8 — Concurrent Access](#t38)
10. [Bug mới phát hiện: SPLIT_BIT](#splitbug)
11. [Bảng Chẩn Đoán](#failures)

---

## 1. Tín Hiệu Mới Cần Theo Dõi <a name="signals"></a>

Layer 3 thêm các signal so với Layer 2:

### Group B+ — Arbitration (MỚI — quan trọng nhất L3)
```
u_intc/u_arbiter/state_q[1:0]     ← 00=IDLE, 01=GNT_M1, 10=GNT_M2
HBUSREQ_M1, HBUSREQ_M2            ← Cả hai master đều active!
HGRANT_M1,  HGRANT_M2              ← Xen kẽ trong round-robin
HMASTER[3:0]                        ← 0=M1, 1=M2
HMASTLOCK                           ← 1 khi locked transfer
u_intc/u_arbiter/last_master_q      ← Round-robin fairness state
u_intc/u_arbiter/split_mask_m1_q    ← 1=M1 bị mask do SPLIT
u_intc/u_arbiter/split_mask_m2_q    ← 1=M2 bị mask do SPLIT
```

### Group H+ — SPLIT Path (MỚI)
```
HSPLIT_S1[15:0], HSPLIT_S2[15:0], HSPLIT_S3[15:0]
u_intc/HSPLIT_COMBINED[15:0]        ← = S1 | S2 | S3
u_slave1/split_master_reg[3:0]      ← Master ID bị SPLIT
u_slave1/ps_slave                   ← Theo dõi ST_LITTLE/ST_TIME_PASS
```

### Group I — M2 BFM (MỚI)
```
u_bfm_m2/HADDR, u_bfm_m2/HTRANS
u_bfm_m2/HWRITE, u_bfm_m2/HWDATA
u_bfm_m2/HBUSREQ, u_bfm_m2/HGRANT
```

---

## 2. T3.1 — Round-Robin Grant <a name="t31"></a>

**Mục đích:** M1+M2 cùng request → Arbiter phân xử xen kẽ

```
──────────────────────────────────────────────────────────────────
 Cycle │ HBUSREQ_M1 │ HBUSREQ_M2 │ state_q  │ HGRANT │ HMASTER
──────────────────────────────────────────────────────────────────
  C1   │     1      │     1      │ IDLE     │ --     │  0
  C2   │     1      │     1      │ GNT_M1  │ M1=1   │  0(M1)
       │            │            │          │ M2=0   │
  ...  │ M1 thực hiện write tới S1 (3-5 cycles incl. wait-state)
  Cx   │     1      │     1      │ GNT_M1  │ M1=1   │  0
  Cx+1 │     1      │     1      │ GNT_M2  │ M1=0   │  1(M2)
       │            │            │          │ M2=1   │
  ...  │ M2 thực hiện write tới S2 (3-5 cycles)
──────────────────────────────────────────────────────────────────
```

**Key:** `last_master_q` quyết định ai được ưu tiên khi cả hai cùng request:
- `last_master_q = 2'd1` (M1 vừa xong) → grant M2 tiếp
- `last_master_q = 2'd2` (M2 vừa xong) → grant M1 tiếp

**✅ Check:**
- Cả `HGRANT_M1` và `HGRANT_M2` đều phải lên 1 ít nhất 1 lần
- `HMASTER` phải chuyển 0→1→... (không stuck)

---

## 3. T3.2 — Bus Handover <a name="t32"></a>

**Mục đích:** M1 đang write, M2 request → Arbiter chờ M1 xong

```
──────────────────────────────────────────────────────────────────
 Cycle │ Event                        │ HGRANT_M1 │ HGRANT_M2
──────────────────────────────────────────────────────────────────
  C1   │ M1 bắt đầu write (AP)       │    1      │    0
  C2   │ M2 asserts HBUSREQ=1        │    1      │    0
  C3   │ M1 data phase (wait-state)  │    1      │    0
  C4   │ M1 data phase (HREADY=1)    │    1      │    0
  C5   │ M1 transfer done!           │    0      │    1  ← HANDOVER
       │ Arbiter: state→GNT_M2       │           │
  C6   │ M2 bắt đầu write (AP)      │    0      │    1
──────────────────────────────────────────────────────────────────
```

**Key insight:** Arbiter chỉ thay đổi grant khi `HREADY=1` (data phase complete).
Khi `HREADY=0` (Slave wait-state), grant giữ nguyên.

---

## 4. T3.3 — Locked Burst (HLOCK) <a name="t33"></a>

**Mục đích:** M1 HLOCK=1 + INCR4, M2 không thể preempt

```
──────────────────────────────────────────────────────────────────
 Cycle │ HLOCK_M1 │ HMASTLOCK │ HGRANT_M1 │ HGRANT_M2 │ HTRANS
──────────────────────────────────────────────────────────────────
  C1   │    1     │    1      │    1      │    0      │ NONSEQ
  C2   │    1     │    1      │    1      │    0      │ (wait)
  C3   │    1     │    1      │    1      │    0      │ SEQ
  C4   │    1     │    1      │    1      │    0      │ SEQ
  C5   │    1     │    1      │    1      │    0      │ SEQ
  C6   │    1     │    1      │    1      │    0      │ IDLE
  C7   │    0     │    0      │    0      │    1      │ (M2 AP)
──────────────────────────────────────────────────────────────────
```

**Arbiter logic (ST_GNT_M1):**
```systemverilog
if (HLOCK_M1) state_d = ST_GNT_M1;  // ← Lock giữ grant bất chấp M2
```

**🔴 Failure:** `HGRANT_M2=1` khi `HMASTLOCK=1` → Arbiter lock logic bị bypass

---

## 5. T3.4 — SPLIT + Master Switch <a name="t34"></a>

**Đây là test phức tạp nhất.** Trace SPLIT path end-to-end:

```
──────────────────────────────────────────────────────────────────
 Cycle │ Event                              │ Key Signals
──────────────────────────────────────────────────────────────────
  C1   │ M1 read addr=0x0000_0000           │ HTRANS=NONSEQ
       │ Decoder: HSEL_S1=1                 │ HWRITE=0
──────────────────────────────────────────────────────────────────
  C2   │ Slave1: ST_IDLE→ST_ACTIVE          │ HREADY=0 (wait)
──────────────────────────────────────────────────────────────────
  C3   │ Slave1: ST_ACTIVE→ST_RBURST        │
       │ local_addr=0x00, B_SINGLE          │
       │ → SPLIT condition detected!         │
       │ HREADYOUT=0, HRESP=SPLIT           │ HRESP_M=SPLIT
       │ ns=ST_LITTLE                       │ HREADY=0
──────────────────────────────────────────────────────────────────
  C4   │ Slave1: ST_RBURST→ST_LITTLE        │ SPLIT cycle 1/2
       │ SEQ BLOCK 5: split_master_reg ←    │
       │   HMASTER=4'd0 (M1, v2 encoding)  │
       │ HREADYOUT=0, HRESP=SPLIT           │
──────────────────────────────────────────────────────────────────
  C5   │ Slave1: ST_LITTLE (output)          │ SPLIT cycle 2/2
       │ HREADYOUT=1, HRESP=SPLIT           │ HREADY=1
       │ HSPLITx=16'h0001 << 0 = 16'h0001  │ ★ bit[0] for M1
       │ ns=ST_IDLE                         │
       │                                     │
       │ Arbiter (posedge):                  │
       │   HRESP=SPLIT, HREADY=1            │
       │   → split_confirmed=1              │
       │   → split_mask_m1_q ← 1            │ ★ M1 MASKED
       │   → state_d = GNT_M2 (eff_req_m2) │
       │                                     │
       │ HSPLIT_COMBINED[0]=1               │ ★ bit[0] = 1
       │   → split_mask_m1_q ← 0 (clear!)  │ ★ M1 UNMASKED
──────────────────────────────────────────────────────────────────
  C6   │ Arbiter: state=GNT_M2              │ HGRANT_M2=1
       │ M2 can now use bus                  │ HMASTER=4'd1
──────────────────────────────────────────────────────────────────
```

**Timing subtlety cho SPLIT mask:**
Trong Arbiter SEQ_PROC (posedge C5):
```systemverilog
// Priority: clear (HSPLITx) before set (HRESP=SPLIT)
if (HSPLIT_COMBINED[SPLIT_BIT_M1])         // HSPLITx[0]=1 → clear mask
    split_mask_m1_q <= 1'b0;
else if (state_q == ST_GNT_M1 && HRESP_S == RESP_SPLIT)  // set mask
    split_mask_m1_q <= 1'b1;
```

Vì `if` có priority cao hơn `else if`, nếu HSPLIT và HRESP_SPLIT xảy ra
cùng cycle, mask sẽ được **clear** (không set). Hành vi này có thể khiến
M1 bị mask rồi unmasked rất nhanh, hoặc không bị mask gì cả — tuỳ vào
timing cụ thể của Slave.

---

## 6. T3.5 — SPLIT OR Logic <a name="t35"></a>

```
HSPLIT_COMBINED = HSPLIT_S1 | HSPLIT_S2 | HSPLIT_S3

Slave 1 SPLIT (M1):  HSPLIT_S1 = 16'h0001 (bit 0)
Slave 2 SPLIT (M2):  HSPLIT_S2 = 16'h0002 (bit 1)
─────────────────────────────────────────────────────
HSPLIT_COMBINED:      16'h0003 (bits 0,1)
```

**✅ Check:** `HSPLIT_COMBINED` phải = bitwise OR 3 slaves.

---

## 7. T3.6 — addr_ctrl_mux Switch <a name="t36"></a>

```
M1 owns bus: HMASTER_SEL=4'd0 → HADDR_S = HADDR_M1
     ↓ Arbiter handover
M2 owns bus: HMASTER_SEL=4'd1 → HADDR_S = HADDR_M2
```

**Waveform check:**
- Khi `HMASTER` chuyển 0→1, `HADDR_S` phải chuyển từ M1 addr sang M2 addr
- Không có glitch (spurious value) giữa 2 giá trị

---

## 8. T3.7 — write_data_mux Pipeline <a name="t37"></a>

```
 Cycle │ HMASTER_SEL │ master_sel_dp │ HWDATA_S
───────┼─────────────┼───────────────┼──────────────────
  Cn   │  0 (M1)     │  0 (captured) │ HWDATA_M1
  Cn+1 │  1 (M2)     │  0 (pipeline!)│ HWDATA_M1 ← ★ vẫn M1
  Cn+2 │  1 (M2)     │  1 (now M2)   │ HWDATA_M2 ← ★ switched
```

Pipeline register trễ 1 cycle, gated by HREADY. Nếu `HREADY=0`,
`master_sel_dp` KHÔNG update → giữ nguyên master trước đó.

**✅ Check:** S1 phải có data từ M1, S2 phải có data từ M2.
Nếu ngược lại → pipeline delay bị miss.

---

## 9. T3.8 — Concurrent Access <a name="t38"></a>

M1→S1 (0x0000_0080), M2→S2 (0x4000_0080). Tuần tự qua Arbiter.

```
Phase 1: M1 write 0xAAAA_8888 → S1 (HMASTER=0, MUX_SEL=00)
Phase 2: M2 write 0xBBBB_9999 → S2 (HMASTER=1, MUX_SEL=01)

Cross-check:
  S1 memory[0x20] = 0xAAAA_8888? ✓ (không bị 0xBBBB_9999)
  S2 memory[0x20] = 0xBBBB_9999? ✓ (không bị 0xAAAA_8888)
```

---

## 10. Bug SPLIT_BIT đã sửa <a name="splitbug"></a>

| Item | L2 Bundle (BUG) | L3 Bundle (FIX) |
|---|---|---|
| `SPLIT_BIT_M1` | 1 | **0** ← match HMASTER=0 for M1 |
| `SPLIT_BIT_M2` | 2 | **1** ← match HMASTER=1 for M2 |

Slave tạo `HSPLITx = 16'h0001 << HMASTER`. Với v2 encoding:
- M1: HMASTER=0 → bit[0]. Arbiter phải check `HSPLIT_COMBINED[0]`.
- M2: HMASTER=1 → bit[1]. Arbiter phải check `HSPLIT_COMBINED[1]`.

Nếu không sửa: M1 bị SPLIT → mask KHÔNG BAO GIỜ được clear → bus hang!

---

## 11. Bảng Chẩn Đoán <a name="failures"></a>

### Arbitration Issues

| Triệu chứng | Root Cause |
|---|---|
| M2 không bao giờ được grant | HBUSREQ_M2 chưa assert, hoặc Arbiter stuck GNT_M1 |
| Grant toggle liên tục | HREADY=1 liên tục + cả 2 request → round-robin mỗi cycle |
| M1 bị starvation | split_mask_m1_q stuck ở 1 → SPLIT_BIT encoding bug |

### SPLIT Issues

| Triệu chứng | Root Cause |
|---|---|
| M1 bị mask mãi mãi | SPLIT_BIT_M1 sai → Arbiter không clear mask |
| HSPLIT_COMBINED = 0 | Slave không vào ST_LITTLE, hoặc Interconnect wiring bug |
| SPLIT nhưng M2 không được grant | M2 chưa assert HBUSREQ, hoặc eff_req_m2=0 |

### Master Switch Issues

| Triệu chứng | Root Cause |
|---|---|
| HADDR_S = M2 addr khi M1 granted | addr_ctrl_mux encoding sai (v1 vs v2) |
| HWDATA_S = M1 data trong M2 phase | write_data_mux master_sel_dp chưa switch |
| S1 có data từ M2 | Cross-contamination: pipeline delay không đúng |

---

*Phiên bản: v1.0 — Layer 3 System Test*
*Encoding: v2 (HMASTER 0=M1, 1=M2, SPLIT_BIT_M1=0, SPLIT_BIT_M2=1)*
