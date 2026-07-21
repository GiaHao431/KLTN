# Bước 1 → 3 — Thiết lập Code Coverage cho AHB 2.0 Multi-Master Interconnect trên Questa

**Mục tiêu tổng thể:** Sinh ra Code Coverage (Statement/Branch/Condition/Toggle/FSM — `bcstf`) cho RTL của DUT, qua chuỗi 6 bước:

```
[Bước 1] vlog -cover  →  [Bước 2] vopt +cover  →  [Bước 3] vsim -coverage  →
[Bước 4] vcover merge  →  [Bước 5] vcover report -html  →  [Bước 6] HTML → PDF
```

Tài liệu này tổng hợp Bước 1–3 (đã hoàn tất, kết quả PASS clean, coverage của 1 test đầu tiên = **17.41%**), dùng làm baseline để tiếp tục Bước 4 ở đoạn chat mới.

**Môi trường:** Questa Altera Starter FPGA Edition-64 2025.3, Ubuntu VM (Windows host). Thư mục làm việc chính: `~/questa_uvm` (chứa `work` library hợp lệ, **mọi lệnh vlog/vopt/vsim/vcover phải chạy từ đây**). RTL nằm ở `~/questa_rtl`.

---

## Bước 1 — `vlog -cover bcstf` (compile RTL + TB)

- Compile RTL (11 file — xem danh sách đầy đủ ở mục "Bài học" bên dưới) với `-cover bcstf`.
- Compile `testbench.sv` (kéo theo toàn bộ UVM package qua `` `include ``) **không** gắn `-cover` — đúng nguyên tắc chỉ đo coverage RTL, không đo TB/UVM (đã thảo luận và xác nhận là chuẩn công nghiệp: Code Coverage đo đối tượng cần verify, không đo công cụ verify).
- Kết quả: 0 error. 2 warning benign (port `memory_slave` default `var` do mảng đa chiều; `bind` compile ngoài `-mfcu` — cả hai không ảnh hưởng elaboration).

---

## Bước 2 — `vopt +cover` (tối ưu hóa + giữ instrumentation)

### Lỗi #1 — `vopt-13130`: "Failed to find design unit 'tb_top'"
- **Nguyên nhân:** Chạy `vopt` từ thư mục `~` (home), trong khi `work` library thật (chứa `tb_top` đã compile) nằm ở `~/questa_uvm`. `work` là thư mục vật lý theo `cwd`, không phải biến toàn cục.
- **Fix:** `cd ~/questa_uvm` trước khi chạy `vopt`. Xác nhận bằng `vdir`.

### Lỗi #2 — "Module 'AHB_Interconnect' is not defined"
- **Nguyên nhân:** Danh sách file RTL compile ở Bước 1a **thiếu file `AHB_Interconnect.sv`** (module fabric wrapper gồm Arbiter + Decoder + 5 Mux, được `AHB_System_Top` instantiate qua `u_intc`). Lỗi không lộ ra lúc `vlog` (mỗi file compile độc lập cú pháp) mà chỉ lộ ở `vopt` vì đây là bước elaborate/link hierarchy đầu tiên.
- **Fix:** Compile bổ sung `vlog -sv -cover bcstf ~/questa_rtl/AHB_Interconnect.sv` (giữ `-cover` vì đây là RTL thật). **Danh sách RTL đầy đủ và đúng thứ tự tham chiếu (theo `UVM_Build_Plan.md`)** phải là:
  ```
  ahb_decoder.sv → ahb_addr_ctrl_mux.sv → ahb_write_data_mux.sv →
  ahb_read_data_mux.sv → ahb_resp_mux.sv → ahb_ready_mux.sv →
  AHB_Arbiter.sv → AHB_Slave.sv → AHB_Default_Slave.sv →
  AHB_Interconnect.sv → AHB_System_Top.sv
  ```

### Lỗi #3 — `vopt-7061`: "Variable 'memory_slave' driven in an always_ff block, may not be driven by any other process"
- **Nguyên nhân:** False-positive đã biết của Questa. `memory_slave` (mảng bộ nhớ thật trong `AHB_Slave.sv`, ghi bởi 1 `always_ff` duy nhất) đồng thời được nối ra ngoài qua backdoor-probe port của `ahb_slave_bd_if` (qua `bind`) để scoreboard/monitor **đọc** giá trị. Vì cổng đa chiều buộc phải là kiểu `var` (không thể là `wire`), static driver-checker của Questa hiểu nhầm thành 2 tiến trình cùng ghi — thực chất chỉ 1 tiến trình ghi, phía interface chỉ đọc thụ động.
- **Fix:** `-suppress 7061`.

### Lệnh `vopt` cuối cùng (đã PASS: 0 error, 4 warning, 3 suppressed error)
```bash
cd ~/questa_uvm
vopt -64 +acc -cover bcstf -suppress 7061 tb_top -o tb_top_opt
```

---

## Bước 3 — `vsim -coverage` (chạy mô phỏng, ghi UCDB)

### Lỗi #1 — `vsim-3009` [TSCALE]: thiếu `timeunit/timeprecision` nhất quán
- **Nguyên nhân:** Các file RTL có khai báo `` `timescale 1ns / 1ps ``, còn `uvm_pkg`, `ahb_pkg`, `tb_top`, `ahb_master_if` thì không. Đây là kiểm tra "best practice" nghiêm ngặt của Questa, không phải race condition thật (mọi delay trong thiết kế đều là bội số `ns` nguyên, không mất độ chính xác).
- **Fix:** `-suppress 3009`.

### Lỗi #2 — `vcover-7`: "Failed to open UCDB file... in read mode" khi chạy `vcover report`
- **Nguyên nhân thật (sau khi loại trừ khả năng sai thư mục bằng `find`):** UVM tự gọi `$finish` khi kết thúc test (`uvm_root.svh`). Theo mặc định, Questa **thoát ngay khi gặp `$finish`** trong `-do` script, khiến các lệnh phía sau dấu `;` (`coverage save ...`) **không bao giờ được thực thi**, dù console log trông như mô phỏng đã chạy xong hoàn chỉnh (scoreboard PASS, 0 UVM_ERROR).
- **Fix:** Thêm `-onfinish stop` vào lệnh `vsim` — báo Questa trả quyền điều khiển lại cho `-do` script khi gặp `$finish` thay vì thoát ngay.

### Lệnh `vsim` cuối cùng (đã PASS: 0 error, 1 warning benign, UCDB tạo thành công)
```bash
vsim -64 -c -coverage -onfinish stop \
     -suppress 7061 -suppress 3009 \
     tb_top_opt \
     -do "run -all; coverage save tb_top_smoke.ucdb; quit -f"
```

### Kết quả xác nhận
- Scoreboard `ahb_smoke_test` PASS clean, khớp với kết quả trên EDA Playground/Xcelium (0 UVM_ERROR, 0 UVM_FATAL, mismatches = 0).
- `vcover report tb_top_smoke.ucdb` chạy được → **Code Coverage = 17.41%** cho 1/49 test (`ahb_smoke_test`) — con số thấp là bình thường và đúng dự đoán, vì mới chỉ chạy 1 test đơn lẻ, chưa phản ánh coverage tổng thể.

---

## Bài học tổng hợp — tránh lặp lại ở Bước 4 trở đi

1. **Luôn chạy toàn bộ chuỗi lệnh từ cùng một `cwd` nhất quán** (`~/questa_uvm`) — `work` library là thư mục vật lý theo vị trí gọi lệnh, không phải biến môi trường toàn cục. Trước khi debug sâu, luôn `pwd` + `vdir`/`find` để xác nhận vị trí trước.
2. **Danh sách file RTL compile phải đối chiếu đầy đủ với `UVM_Build_Plan.md`** — dễ bỏ sót module trung gian như `AHB_Interconnect.sv`; lỗi này chỉ lộ ra ở bước elaborate (`vopt`), không lộ lúc `vlog`.
3. **Cờ `-cover bcstf` phải lặp lại giống hệt ở cả `vlog` VÀ `vopt`** — thiếu ở `vopt` sẽ khiến instrumentation coverage bị tối ưu hóa mất dù `vlog` đã cài đúng.
4. **3 cờ `-suppress` cần mang theo xuyên suốt mọi lệnh `vopt`/`vsim` tiếp theo** (kể cả khi chạy full regression 49 test ở Bước 4):
   - `-suppress 7061` (bắt buộc từ `vopt` trở đi) — false-positive driver-conflict của backdoor-probe `memory_slave`.
   - `-suppress 3009` (bắt buộc từ `vsim` trở đi) — false-positive TSCALE mismatch giữa RTL và TB/UVM.
5. **Mọi lệnh `vsim` có `-do` script chứa `coverage save` phải có `-onfinish stop`** — nếu không, `$finish` do UVM tự gọi sẽ khiến Questa thoát sớm, bỏ qua toàn bộ lệnh phía sau trong script (dù log trông như PASS hoàn chỉnh, file `.ucdb` sẽ không hề được tạo ra).
6. **Code Coverage (Questa) và Functional Coverage (Phase 2, EDA Playground) là 2 luồng song song, không thay thế nhau** — Code Coverage đo % dòng/nhánh RTL đã được thực thi; Functional Coverage đo % kịch bản/tình huống theo testplan đã được bao phủ. Không gộp report của 2 luồng.

---

## Trạng thái sẵn sàng cho Bước 4

- Snapshot tối ưu đã sẵn sàng: `tb_top_opt` (trong `work` library tại `~/questa_uvm`).
- Lệnh `vsim` baseline (đã verify PASS) sẵn sàng để nhân rộng cho cả 49 test, mỗi test cần:
  - Đổi tên file UCDB output cho từng test (ví dụ `<ten_test>.ucdb`).
  - Thêm `+UVM_TESTNAME=<ten_test>` để override test mặc định (`ahb_smoke_test`) đang hard-code trong `testbench.sv`.
  - Giữ nguyên toàn bộ cờ đã xác lập: `-64 -c -coverage -onfinish stop -suppress 7061 -suppress 3009`.
- Bước 4 (`vcover merge`) sẽ gộp toàn bộ 49 file `.ucdb` riêng lẻ thành 1 database tổng, làm cơ sở cho `vcover report -html` (Bước 5) — con số coverage tổng thể (mục tiêu so sánh) chỉ có ý nghĩa sau bước merge này.
- Có thể tái sử dụng/mở rộng `regression_questa.sh` đã có sẵn từ trước (dùng cho regression functional) để tự động hóa vòng lặp 49 test kèm coverage, tránh gõ tay từng lệnh.
