# Kế hoạch xây dựng UVM Testbench — AHB 2.0 Multi-Master Interconnect

**DUT:** `AHB_System_Top` (2 Master × 3 Slave + 1 Default Slave)
**Phương pháp:** Directed test, UVM (defer SVA / Functional Coverage / Constrained-Random sang Phase 2)
**Mục tiêu:** Verify đủ **49 test case** (L1: T1.1–T1.18 = 18 · L2: T2.1–T2.13 = 13 · L3: T3.1–T3.18 = 18)
**Công cụ build:** EDA Playground (Xcelium + UVM 1.2) — **chưa cần VM Ubuntu/Xcelium trong toàn bộ giai đoạn build này** (xem §9)
**Triết lý:** Mỗi vài thành phần → **một compile/run gate** (cổng kiểm tra). Không bao giờ build hết rồi mới compile.

---

## 0. Ba lưu ý quan trọng trước khi bắt đầu

**(a) Các file interface/bind hiện KHÔNG có trong project.**
Kiến trúc (`UVM_TB_Architecture.md`) mô tả chi tiết `ahb_master_if`, `ahb_sys_if`, `ahb_slave_bd_if`, `ahb_default_slave_bd_if` và 2 file bind, nhưng tìm trong toàn bộ project knowledge thì **chưa thấy file source nào của chúng**. Kế hoạch này coi chúng là **cần viết mới** ở Milestone 1. Nếu thực tế bạn đã có sẵn ở đâu đó, chỉ cần dán vào và bỏ qua phần viết — nhưng **vẫn phải chạy compile gate 1** để xác nhận tên signal khớp.

**(b) Trả lời câu hỏi "Bước 1 có nên viết interface + bind + rìa ngoài + kiểm tra đồng nhất tên signal trước không?": CÓ — và đó chính xác là Milestone 1.**
Lý do: tên signal ở rìa (interface ↔ port DUT) là "hợp đồng" của toàn bộ TB. Sai một tên là không elaborate được. Khóa chặt lớp này trước loại bỏ cả một nhóm lỗi và tạo nền tảng ổn định. Nó cũng đúng với gợi ý của anh kỹ sư: **compile ra hierarchy trước, verify sau.**

**(c) Bạn KHÔNG cần VM trong suốt kế hoạch này.** Toàn bộ 49 directed test chạy tốt trên EDA Playground (Xcelium + UVM 1.2). Mình sẽ nhắc rõ ở §9 thời điểm nào mới cần chuyển sang Xcelium-on-Ubuntu.

---

## 1. Chiến lược build tổng thể (và lý do)

Build theo **3 pha lai (hybrid)**, không thuần "trong ra ngoài" cũng không thuần "ngoài vào trong" — vì mỗi lớp lỗi cần một hướng tấn công khác nhau:

| Pha | Hướng | Xây gì | Loại lỗi pha này dập tắt |
|---|---|---|---|
| **Pha A — Vỏ tĩnh** | **Ngoài → trong** | Interface, bind, `tb_top` nối DUT + clock/reset (CHƯA có UVM) | Sai/lệch **tên signal**, sai mapping port, RTL không elaborate |
| **Pha B — Khung UVM rỗng** | **Trên → xuống** | `pkg`, transaction stub, agent/env/test **rỗng** (chỉ `build`/`connect`, chưa có hành vi) | Sai plumbing **factory / phasing / config_db**, topology thiếu/sai component |
| **Pha C — Đổ hành vi** | **Trong → ngoài** | Driver → monitor → sequence → scoreboard → ref model, rồi mở rộng theo từng layer | Lỗi **timing / race / giao thức / so sánh dữ liệu** |

**Vì sao thứ tự này:**
- **Pha A ngoài-vào-trong:** interface và bind định nghĩa hợp đồng tín hiệu. Phải đúng trước mọi thứ. Đây là milestone "compile + in hierarchy" của anh kỹ sư.
- **Pha B trên-xuống rỗng:** UVM dễ chết ở plumbing (factory/config_db/phasing) chứ không phải ở thuật toán. In được `print_topology()` đúng kiến trúc = plumbing chạy, trước khi đổ một dòng hành vi nào.
- **Pha C trong-ra-ngoài:** khi khung đã đứng, ưu tiên xác minh mảnh **rủi ro nhất (master driver pipeline)** end-to-end với DUT thật càng sớm càng tốt. Một lệnh write→read **pass thật** chứng minh cả chuỗi dọc (sequence → seqr → driver → vif → DUT → monitor → scoreboard) hoạt động. Hầu hết bug timing sẽ lộ ở đây — sửa xong mới scale.

**Cadence kiểm tra:** sau mỗi Milestone có **1 Gate**. Không qua Gate thì không sang Milestone sau.

---

## 2. Bố cục thư mục & THỨ TỰ COMPILE (rất quan trọng)

UVM/Xcelium nhạy với thứ tự biên dịch. Đề xuất layout + thứ tự trong file `run.f` (hoặc 2 pane Design/Testbench của EDA Playground):

```
rtl/         (đã có sẵn — chỉ gom lại)
  ahb_decoder.sv  ahb_addr_ctrl_mux.sv  ahb_write_data_mux.sv
  ahb_read_data_mux.sv  ahb_resp_mux.sv  ahb_ready_mux.sv
  AHB_Arbiter.sv  AHB_Slave.sv  AHB_Default_Slave.sv
  AHB_Interconnect.sv  AHB_System_Top.sv
intf/        (Milestone 1)
  ahb_master_if.sv  ahb_sys_if.sv
  ahb_slave_bd_if.sv  ahb_default_slave_bd_if.sv
  ahb_bind.sv               // chứa cả 2 lệnh bind
tb/          (Milestone 2+)
  ahb_pkg.sv                // import uvm_pkg; `include tất cả class UVM
  tb_top.sv                 // instantiate DUT + interface + run_test()
  seq/  agents/  env/  test/ (đặt file class, đều được include trong ahb_pkg.sv)
```

**Thứ tự compile bắt buộc:**
1. `uvm_macros.svh` + `uvm_pkg` (Xcelium: cờ `-uvm` / `-uvmhome`)
2. **RTL leaf trước** (decoder, 5 mux, arbiter, slave, default slave) → `AHB_Interconnect` → `AHB_System_Top`
3. **Interface** (4 file `*_if.sv`)
4. **`ahb_bind.sv`** (cần thấy cả module đích lẫn interface → phải sau cả 2)
5. **`ahb_pkg.sv`** (gói toàn bộ class UVM)
6. **`tb_top.sv`** (import `ahb_pkg`, nên compile **cuối cùng**)

> Quy tắc vàng UVM: **mọi class UVM nằm trong `ahb_pkg.sv`** (qua `\`include`), KHÔNG để class trôi nổi ngoài package. Interface/bind/tb_top thì nằm ngoài package (vì là module/interface).

---

## 3. Bảng kế hoạch theo Milestone (xương sống)

| MS | Tên | Hướng | Component xây | **GATE — điều kiện qua** |
|---|---|---|---|---|
| **M0** | Khung file + compile RTL | — | `run.f`, gom RTL, top rỗng | RTL elaborate sạch standalone (0 error/0 warning lạ) |
| **M1** | Interface + bind + `tb_top` tĩnh | Ngoài→trong | 4 interface, 2 bind, `tb_top` (clock/reset, nối DUT) | **Elaborate full cấu trúc, in được design hierarchy, reset nhả OK — CHƯA có UVM. Tên signal khớp 100%.** |
| **M2** | Khung UVM rỗng | Trên→xuống | `pkg`, transaction stub, 8 agent + env + vseqr + scoreboard (rỗng), base test | **`print_topology()` in đúng kiến trúc (8 agent + sb + vseqr). config_db trace không MISSING.** |
| **M3** | Vertical slice (smoke) | Trong→ngoài | seq_item đầy đủ, **master driver**, master monitor, atomic write/read seq, smoke test | **1 master ghi→đọc S1 qua arbiter PASS** (grant OK, data đúng, HRESP=OKAY). Không ghost transfer. |
| **M4** | Scoreboard + ref model | Trong→ngoài | scoreboard self-check, ref model, 3 slave backdoor monitor | Smoke test thành **self-checking PASS/FAIL**. T1.1–T1.3 pass. |
| **M5** | Hoàn tất Layer 1 | Trong→ngoài | `slv_rsp` agent (force hooks), burst seq, virtual seq phối SPLIT/RETRY giữa burst | **18/18 test L1 (T1.1–T1.18) pass.** |
| **M6** | Layer 2 (1 Master qua Interconnect) | Trong→ngoài | L2 seq (routing/mux/default-error/HREADY), check qua sys_if/bus_mon | **13/13 test L2 (T2.1–T2.13) pass.** |
| **M7** | Layer 3 (2 Master) | Trong→ngoài | virtual seq phối M1+M2 (RR, handover, lock, split, isolation…) | **18/18 test L3 (T3.1–T3.18) pass.** |
| **M8** | Regression + dọn dẹp | — | test list, summary pass/fail | **49/49 pass trong 1 lần regression.** Cân nhắc chuyển VM (§9). |

---

## 4. Chi tiết từng Milestone (các bước nhỏ + check)

### M0 — Khung file & compile RTL nền
- **0.1** Tạo `run.f` theo thứ tự §2; gom 11 file RTL (đã có) vào `rtl/`.
- **0.2** Viết 1 `top_rtl_only` cực nhỏ: instantiate `AHB_System_Top`, gen clock, tie hết input về 0/IDLE, chạy ~200 ns. → *verify:* compile + elaborate **0 error**; reset chạy; không X-propagation lạ trên `HREADY`.
- **Lý do:** tách lỗi RTL ra khỏi lỗi TB. RTL đã chạy trong bundle nên bước này thường nhanh — nhưng xác nhận nó **compile độc lập** (ngoài bundle) là cần thiết.

### M1 — Interface + bind + `tb_top` tĩnh ⟵ *trả lời câu hỏi của bạn: đây là bước 1*
- **1.1** `ahb_master_if.sv`: tên signal **generic** (`HADDR`, `HTRANS`, `HWRITE`, `HSIZE`, `HBURST`, `HWDATA`, `HBUSREQ`, `HLOCK`, `HGRANT`, `HRDATA_M`, `HRESP_M`, `HREADY`). 2 clocking block: `drv_cb` (`output #1, input #1step`), `mon_cb` (`input #1step`). `HRESETn` là **input** (tb_top sở hữu). Modport `drv_mp`, `mon_mp`.
- **1.2** `ahb_sys_if.sv`: drive `force_split_sN`/`force_retry_sN`; observe `HMASTER_o`, `HSEL_*_o`, `HSPLIT_*_o`, `HREADY_GLOBAL_o`, `HADDR_S_o`…; `ctrl_cb` + `mon_cb`.
- **1.3** `ahb_slave_bd_if.sv` (toàn bộ port **input**, `mon_cb`) — probe đúng tên nội bộ của `AHB_Slave`: `ps_slave`, `ns_slave`, `local_addr`, `local_addr_base`, `local_burst`, `local_size`, `beat_cnt`, `split_master_reg`, `resp_abort`, `memory_slave`, `HREADYOUT`, `HRESP`, `HSPLITx`, `HRDATA`. + `ahb_default_slave_bd_if.sv`: `ps`, `ns`, `active_transfer`, `HREADYOUT_DEFAULT`, `HRESP_DEFAULT`.
- **1.4** `ahb_bind.sv`:
  `bind AHB_Slave ahb_slave_bd_if u_bd (.*)` (hoặc liệt kê tường minh) và `bind AHB_Default_Slave ahb_default_slave_bd_if u_bd (.*)`. → bind tự chèn vào `u_slave1/2/3` và `u_default_slave` lúc elaboration, **không sửa RTL**.
- **1.5** `tb_top.sv` (CHƯA `run_test`, hoặc để stub): gen `HCLK` (#5), `HRESETn` (nhả sau 5 cycle); instantiate `AHB_System_Top` + `m1_if`/`m2_if`/`sys_if`; **map generic → port DUT**: `m1_if.HADDR → HADDR_M1`, `m2_if.* → *_M2`, và **fan** `HRDATA_M`/`HRESP_M`/`HREADY` (shared output) ra cả `m1_if` lẫn `m2_if`.
- **GATE 1 ✅** Compile RTL+intf+bind+tb_top: **0 elaboration error** (đây là nơi lệch tên signal lộ ra); in **design hierarchy** (kiểm `u_slave1.u_bd` v.v. xuất hiện = bind thành công); chạy 200 ns thấy reset nhả, clock chạy. **Chưa có UVM.**

### M2 — Khung UVM rỗng (in topology)
- **2.1** `ahb_pkg.sv`: `import uvm_pkg::*; \`include "uvm_macros.svh";` + `\`include` mọi file class. `ahb_seq_item` tạm (vài field cũng được).
- **2.2** Class **rỗng** (chỉ `uvm_*_utils` + `build_phase` tạo con; chưa hành vi): `ahb_master_agent` (seqr+drv+mon), `ahb_slv_rsp_agent` (seqr+drv), `ahb_slave_bd_monitor` ×3 trong agent passive, `ahb_default_slave_bd_monitor`, `ahb_bus_monitor`, `ahb_scoreboard`, `ahb_virtual_sequencer`, `ahb_env`, `ahb_base_test`.
  → **Tái sử dụng class:** `m1_agent` & `m2_agent` dùng **chung 1 class**, phân biệt bằng vif qua config_db. 3 slave-monitor dùng **chung 1 class**. (đúng tinh thần OOP/reuse của UVM, và "simplicity first").
- **2.3** `tb_top` thêm `run_test();` + `uvm_config_db#(virtual ...)::set(...)` cho m1_if/m2_if/sys_if/4 bd_if.
- **GATE 2 ✅** Chạy `ahb_base_test` rỗng có gọi `uvm_top.print_topology()`. **In ra đúng** sơ đồ: `env → scoreboard, v_seqr, m1_agent(seqr/drv/mon), m2_agent(...), slv_rsp_agent(seqr/drv), s1/s2/s3_mon, default_mon, bus_mon`. Bật `+UVM_CONFIG_DB_TRACE` để chắc các vif **không bị MISSING**. *(Đây là milestone "compile + hierarchy" anh kỹ sư yêu cầu.)*

> 💡 **Tradeoff cần bạn quyết (CLAUDE.md §1):** `default_mon` và `bus_mon` theo kiến trúc là *passive, dự phòng coverage*, **không nối scoreboard**. Để topology in đúng kiến trúc đã chốt, mình **giữ chúng ở dạng instantiate-only stub** (sample + debug print, không check). Nếu bạn muốn tối giản tối đa cho kịp deadline, có thể **defer hẳn 2 cái này** và thêm lại ở Phase 2 — kiến trúc vẫn đúng về mặt directed test. Mặc định: **giữ stub**.

### M3 — Vertical slice / smoke (mảnh dọc rủi ro nhất)
- **3.1** `ahb_seq_item` đầy đủ: `addr, wdata, dir(R/W), trans, burst, size, lock, busreq, beats[], + trường kỳ vọng (exp_rdata, exp_resp)`. `do_copy`/`convert2string`.
- **3.2** **`ahb_master_driver`** — pipeline AHB qua **clocking block** (KHÔNG dùng `#1` thủ công):
  - `ensure_grant`: kéo `HBUSREQ=1`, sample `HGRANT` qua `mon_cb`; **drive NONSEQ NGAY trong cycle thấy grant** (tránh "grant nhưng idle" 1 cycle → arbiter switch → **ghost transfer**, chính là bug *FIX L3-9* trong BFM cũ).
  - Address phase (T): HADDR/HTRANS=NONSEQ/HWRITE/HSIZE/HBURST. Data phase (T+1): HWDATA; chờ `HREADY`; xử lý wait-state. Trả lại IDLE sau SINGLE.
- **3.3** `ahb_master_monitor`: sample qua `mon_cb`, đóng gói transaction quan sát, `ap.write()`.
- **3.4** Atomic seq: `ahb_write_single_seq`, `ahb_read_single_seq`. Smoke virtual seq: M1 ghi 0xDEADBEEF→0x04 rồi đọc lại.
- **3.5** `tc_l1_single_wr_rd` (T1.2). Scoreboard giai đoạn này chỉ cần in/đối chiếu thô.
- **GATE 3 ✅** Smoke test: grant lấy được, write commit (xác nhận qua waveform hoặc backdoor), read trả đúng 0xDEADBEEF, HRESP=OKAY, **không ghost transfer**. → Chuỗi dọc chạy. *Đa số bug timing/race xuất hiện và được dập ở đây.*

### M4 — Scoreboard + Reference model (self-check lõi L1)
- **4.1** `ahb_scoreboard`: 5 `uvm_analysis_imp` (trước tiên dùng 2 cổng master). **Ref model**: 3 mảng `ref_mem[0:255]` seed (`[0]=SEED, [1]=2×SEED, [2]=3×SEED`; SEED_S1=10/S2=20/S3=30); decoder `HADDR[31:30]`; word-index `HADDR[9:2]`; predictor write/read; predictor response (default→ERROR; force_split→SPLIT; force_retry→RETRY; còn lại→OKAY); burst-address model (INCR tăng theo HSIZE; WRAP4/8/16 quấn quanh base).
- **4.2** 3 `ahb_slave_bd_monitor` → nối analysis port vào scoreboard. Sample: `memory_slave[local_addr]`, `HRDATA`, `HRESP`, `HREADYOUT`, `HSPLITx`, `ps_slave`, `beat_cnt`, `local_addr`.
- **4.3** Logic so sánh: read front-door vs ref; nội dung memory backdoor sau write vs ref; response vs predicted. **Chỉ commit khi beat OKAY + HREADY=1**; freeze khi `resp_abort`.
- **GATE 4 ✅** Smoke test thành **self-checking** (sb báo PASS/FAIL). T1.1, T1.2, T1.3 pass.

### M5 — Hoàn tất Layer 1
- **5.1** `ahb_slv_rsp_driver` + `slv_rsp_seqr`: drive `force_split_sN`/`force_retry_sN` qua `sys_if.ctrl_cb`, **đúng beat** trong data phase. Force seq tương ứng. *(Lưu ý: `force_split` ưu tiên hơn `force_retry`; cả hai bị suppress khi `HMASTLOCK=1`.)*
- **5.2** Composite burst seq: INCR4 / INCR8 / INCR16 / WRAP4 / INCR-undef (kết thúc bằng IDLE).
- **5.3** Virtual seq phối hợp: chạy burst trên M1 **đồng thời** `slv_rsp` chèn SPLIT/RETRY tại beat chỉ định (T1.9/13/16/17). Cần virtual sequencer điều phối `m1_seqr` + `slv_rsp_seqr`.
- **GATE 5 ✅** **18/18** test L1 pass (gồm cả 2-cycle SPLIT/RETRY, HSPLITx 1-cycle, mid-burst abort không commit, SPLIT-under-lock bị suppress, priority SPLIT>RETRY).

### M6 — Layer 2 (1 Master qua Interconnect)
> Hạ tầng single-master đã đủ sau M5. L2 chủ yếu là **seq mới + check routing/mux**. (Lưu ý: trong tb_top hợp nhất, "Layer 1" cũng đã chạy xuyên fabric vì DUT là `AHB_System_Top`; L2 nhấn vào *routing/mux/decoder/default-error/HREADY-loop*.)
- **6.x** Seq + check: decoder sweep S2/S3 (HSEL one-hot, MUX_SEL), default-slave ERROR 2-cycle (T2.4), decode boundary (T2.5), cross-slave RAW (T2.7), burst-via-interconnect INCR4/INCR8 (T2.8), HREADY feedback loop (T2.6 — kiểm mux **không update** khi HREADY_GLOBAL=0; `mux_sel_data_phase` = MUX_SEL trễ đúng 1 cycle gated-HREADY), slave sweep (T2.11), RETRY-via-interconnect không mask (T2.12), grant-from-IDLE/IDLE-via-intc/both-idle (T2.1/10/13). Routing check lấy từ `sys_if` observation outputs (hoặc bật `bus_mon`).
- **GATE 6 ✅** **13/13** test L2 pass.

### M7 — Layer 3 (2 Master)
- **7.1** Virtual seq phối **M1 + M2** (qua virtual sequencer giữ `m1_seqr_h`, `m2_seqr_h`, `slv_rsp_seqr_h`): round-robin (T3.1), grant-M2-from-IDLE (T3.2), handover during transfer / blocked by wait-state (T3.3/3.4), locked burst HLOCK (T3.5), unlocked burst protection (T3.6), idle force switch (T3.7), SPLIT+switch & aggregation & both-masked (T3.8/9/10), mux pipeline on switch (T3.11), data isolation 2 master (T3.12), default ERROR + recovery (T3.13), HLOCK>SPLIT 2-master & 1-master (T3.14/3.16), alternating stress ×8 (T3.15), RETRY+RR yield (T3.17), RETRY vs SPLIT contrast (T3.18).
- **7.2** Scoreboard xử lý 2 master đồng thời: ref model dùng **bộ nhớ chia sẻ** nên cross-master write/read tự nhiên đúng (T3.12 Phase B).
- **GATE 7 ✅** **18/18** test L3 pass.

### M8 — Regression & dọn dẹp
- **8.1** Test list + script chạy lần lượt + in **summary 49/49**.
- **8.2** Rà lại UVM_ERROR/UVM_WARNING = 0; xem có cần VM không (§9).
- **GATE 8 ✅** **49/49 pass trong một lần regression.**

---

## 5. Ước lượng số lượng class/seq (khớp chiến lược "kinh tế test class")

| Loại | Số lượng | Ghi chú |
|---|---|---|
| Interface | 4 + 1 bind | M1 |
| Transaction | 1 (`ahb_seq_item`) | + có thể 1 cho force nếu muốn tách |
| Driver | 2 (`master`, `slv_rsp`) | master dùng chung cho M1/M2 |
| Monitor | 3 (`master`, `slave_bd`, `default_bd`/`bus`) | reuse tối đa |
| Agent | 8 instance / **4 class** | reuse master ×2, slave-mon ×3 |
| Atomic seq | ~8 | write/read single, idle, reset, force_split, force_retry, … |
| Composite seq | ~10–12 | INCR4/8/16, WRAP4, INCR-undef, back2back, burst+split… |
| Virtual seq | ~8–10 | mỗi nhóm kịch bản L2/L3 một virtual seq |
| Test class | **~6–7** | 1 base + ~2 L1 + ~2 L2 + ~2 L3; **49 test KHÔNG cần 49 class** — chọn seq qua config/`+UVM_TESTNAME` hoặc tham số |

---

## 6. Bản đồ 49 test case → Milestone

| Milestone | Test cases | Số |
|---|---|---|
| M3 (smoke) | T1.2 | 1 |
| M4 | T1.1, T1.2, T1.3 | (lõi) |
| **M5 (toàn L1)** | T1.1 → T1.18 | **18** |
| **M6 (toàn L2)** | T2.1 → T2.13 | **13** |
| **M7 (toàn L3)** | T3.1 → T3.18 | **18** |
| **M8** | Regression toàn bộ | **49** |

---

## 7. Nhắc về tính đúng đắn (carry-over từ RTL + review)

1. **Chống race condition:** mọi clocking block dùng `default input #1step output #1`. Driver/monitor **không** dùng `#1` thủ công như BFM cũ — đây là cải tiến đúng đắn phải giữ.
2. **Đồng nhất tên signal:** tên trong interface trùng **tuyệt đối** tên port DUT theo IHI0011A; chỗ duy nhất đổi tên là `ahb_master_if` (generic) → map sang `*_M1`/`*_M2` tại `tb_top`.
3. **Zero-gap grant (FIX L3-9):** driver phải drive NONSEQ **ngay** cycle thấy `HGRANT` (sample post-NBA), tránh ghost transfer. Arbiter có `idle_grant_cnt` ngưỡng 4 được canh theo timing này.
4. **SPLIT/RETRY:** `force_split` > `force_retry`; **cả hai bị suppress khi `HMASTLOCK=1`** (locked transfer phải hoàn tất, HLOCK>SPLIT, §3.11.5/§3.12.3). Beat bị abort **không** commit memory, `beat_cnt`/`local_addr` **freeze** (`resp_abort`).
5. **Bắt tay 2 chu kỳ:** SPLIT (RBURST/WBURST→ST_LITTLE), RETRY (→ST_RETRY2), ERROR default (ERROR_CYC1→CYC2). HSPLITx assert đúng **1 cycle** ở ST_LITTLE; RETRY **không** assert HSPLITx, **không** latch `split_master_reg`.
6. **Pipeline mux data-phase:** `read_data_mux`/`resp_mux`/`ready_mux` register `mux_sel_data_phase = MUX_SEL` **trễ 1 cycle gated-HREADY**; `write_data_mux` register `master_sel_data_phase`. Ref model phải canh đúng pha này (đặc biệt T2.2/2.6/3.11).
7. **Address map:** `HADDR[31:30]` → `00`=S1, `01`=S2, `10`=S3, `11`=Default(ERROR). Word index = `HADDR[9:2]` (SRAM 256×32).
8. **DUT là full system:** không có slave standalone — "Layer 1" = single-master đánh 1 slave, quan sát nội bộ slave qua backdoor.

---

## 8. Rủi ro thường gặp & cách phòng (checklist nhanh)

- **Quên include class trong `ahb_pkg.sv`** → "class not found". Mỗi class mới → thêm `\`include` ngay.
- **vif MISSING trong config_db** → set sai scope/tên. Dùng `+UVM_CONFIG_DB_TRACE` ở Gate 2.
- **Bind sai tên nội bộ slave** → elaboration error ở Gate 1. So tên với `AHB_Slave_claude_ver4` trước.
- **Ghost transfer** (driver drive khi chưa grant) → áp dụng zero-gap grant (§7.3).
- **Sai pha read data** (đọc HRDATA sớm/muộn 1 cycle) → bám `mon_cb` + nhớ mux trễ 1 cycle (§7.6).
- **Reset chưa nhả mà sequence đã chạy** → đồng bộ với `HRESETn` trong run_phase/objection.

---

## 9. EDA Playground hay Xcelium-on-Ubuntu? (nhắc bạn)

**Trong toàn bộ M0→M7 (đủ 49 directed test): dùng EDA Playground (Xcelium + UVM 1.2) là đủ. CHƯA cần VM.**

Chỉ chuyển sang **Xcelium trên Ubuntu** khi gặp một trong các *trigger* sau (đa số rơi vào sau M7 / Phase 2):
- Vượt **giới hạn số file / dung lượng** của EDA Playground.
- Cần **regression script bền vững** + lưu **waveform database** lớn để debug sâu.
- Bắt đầu **Phase 2** (SVA / functional coverage / constrained-random) cần nhiều compute & coverage DB.
- Cần chạy nhiều seed / nhiều test song song.

Khi đến lúc đó, mình sẽ giúp bạn chuyển `run.f` + lệnh `xrun` sang môi trường local. Còn trong lúc build, mình sẽ chủ động nhắc nếu thấy chạm trigger.

---

## 10. Việc cần làm tiếp theo (ngay)

1. Xác nhận **tradeoff §M2** (giữ stub hay defer `default_mon`/`bus_mon`).
2. Bắt đầu **M0 → M1**: mình có thể viết ngay 4 interface + 2 bind + `tb_top` tĩnh để bạn chạy **Gate 1** trên EDA Playground.

> *Nguyên tắc xuyên suốt: build vài thành phần → qua một Gate → mới build tiếp. Không bao giờ "build hết rồi mới compile".*
