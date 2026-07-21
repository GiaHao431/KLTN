# Bước 1 — Compile RTL với Code Coverage trên Questa (Starter Edition)

**Mục tiêu (goal):** Biên dịch (compile) toàn bộ RTL của DUT (AMBA AHB 2.0 Multi-master Interconnect) với cờ đo **Code Coverage**, sau đó compile testbench UVM để chuẩn bị cho các bước tiếp theo (`vopt` → `vsim` → `vcover report`).

**Môi trường:** Questa Altera Starter FPGA Edition-64, vlog 2025.3 Compiler, chạy trên Linux (Ubuntu VM).

---

## 1. Cấu trúc thư mục dự án (đã xác nhận)

```
~/
├── questa_rtl/
│   ├── ahb_decoder.sv
│   ├── ahb_addr_ctrl_mux.sv
│   ├── ahb_write_data_mux.sv
│   ├── ahb_read_data_mux.sv
│   ├── ahb_resp_mux.sv
│   ├── ahb_ready_mux.sv
│   ├── AHB_Arbiter.sv
│   ├── AHB_Slave.sv
│   ├── AHB_Default_Slave.sv
│   └── AHB_System_Top.sv
└── questa_uvm/
    ├── ahb_interfaces.sv      ← chứa 4 interface + 2 lệnh `bind`, tự-đầy-đủ
    ├── ahb_pkg_items.sv
    ├── ahb_pkg_agents.sv
    ├── ahb_pkg_scoreboard.sv
    ├── ahb_pkg_sequences.sv
    ├── ahb_pkg_tests.sv
    └── testbench.sv           ← top-level (module tb_top), gọi run_test()
```

**Điểm quan trọng về cấu trúc `testbench.sv`:** File này gói toàn bộ testbench theo kiểu "một file, nhiều `` `include ``" (phong cách EDA Playground):

```systemverilog
`include "ahb_interfaces.sv"     // dòng 1 — ngoài package, chứa interface + bind
package ahb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    ... (parameter, typedef dùng chung) ...
    `include "ahb_pkg_items.sv"
    `include "ahb_pkg_agents.sv"
    `include "ahb_pkg_scoreboard.sv"
    `include "ahb_pkg_sequences.sv"
    `include "ahb_pkg_tests.sv"
endpackage : ahb_pkg
module tb_top;
    ... instantiate DUT (AHB_System_Top), interface (m1_if, m2_if, sys_if) ...
    ... uvm_config_db#(...)::set(...) cho tất cả virtual interface ...
    initial run_test("ahb_smoke_test");
endmodule : tb_top
```

Nhờ đó, **chỉ cần một lệnh `vlog` duy nhất cho phía testbench** — không cần compile riêng từng file `ahb_pkg_*` hay file interface/bind, vì tất cả đã được kéo vào bên trong `testbench.sv` thông qua `` `include ``.

---

## 2. Lệnh compile đã chạy

```bash
RTL=~/questa_rtl
UVM=~/questa_uvm

# ---- 1a: Compile RTL với coverage (module thiết kế thật) ----
vlog -sv -cover bcstf \
    ${RTL}/ahb_decoder.sv \
    ${RTL}/ahb_addr_ctrl_mux.sv \
    ${RTL}/ahb_write_data_mux.sv \
    ${RTL}/ahb_read_data_mux.sv \
    ${RTL}/ahb_resp_mux.sv \
    ${RTL}/ahb_ready_mux.sv \
    ${RTL}/AHB_Arbiter.sv \
    ${RTL}/AHB_Slave.sv \
    ${RTL}/AHB_Default_Slave.sv \
    ${RTL}/AHB_System_Top.sv

# ---- 1b: Compile testbench (KHÔNG -cover — đây là TB, không phải RTL cần đo) ----
vlog -sv +incdir+${UVM} \
    ${UVM}/testbench.sv
```

### Giải thích cờ (flags)

| Cờ | Ý nghĩa |
|---|---|
| `-sv` | Ép compiler đọc file theo cú pháp SystemVerilog (áp dụng bất kể đuôi file là `.sv` hay khác) |
| `-cover bcstf` | Bật thu thập Code Coverage cho RTL, gồm 5 loại: **b**ranch, **c**ondition, **s**tatement, **t**oggle, **f**sm |
| `+incdir+${UVM}` | Chỉ định thư mục để `vlog` tìm các file được `` `include `` bên trong `testbench.sv` (ví dụ `ahb_interfaces.sv`, `ahb_pkg_items.sv`...) |

**Nguyên tắc cốt lõi:** cờ `-cover` **chỉ đặt cho các file RTL** (bước 1a) — mục đích là đo xem test suite kích hoạt được bao nhiêu phần trăm code thiết kế thật. Testbench (bước 1b) **không** cần `-cover` vì bản thân testbench không phải đối tượng cần đo coverage.

---

## 3. Kết quả

- **Compile RTL (1a):** 0 error, 0 warning.
- **Compile testbench (1b):** 0 error, 2 warning (không ảnh hưởng đến tính đúng đắn của thiết kế hay của coverage, cả hai đều mang tính thông báo — informational):

  1. **`vlog-13314`** — tại `ahb_interfaces.sv` dòng 99: port `memory_slave` (mảng bộ nhớ trong `ahb_slave_bd_if`, dùng để backdoor-probe bộ nhớ của slave) được mặc định là kiểu `var` thay vì `wire`, do compile option mặc định `-svinputport=relaxed`. Đây là hành vi chuẩn của SystemVerilog khi port là mảng đa chiều (không thể là `wire` theo LRM) — không phải lỗi.
  2. **`vlog-2650`** — 2 lệnh `bind` (trong `ahb_interfaces.sv`) được compile ở "compilation unit scope" (không nằm trong `-mfcu`). Cảnh báo gợi ý dùng `-mfcu -cuname` để đảm bảo elaboration nhận diện `bind`, nhưng với cách compile hiện tại (mỗi lệnh `vlog` riêng biệt theo từng nhóm file, không dùng multi-file compilation unit), `bind` vẫn được elaborate đúng bình thường ở bước `vopt`/`vsim` tiếp theo — đã được xác nhận qua các bước build trước đó của testbench (Gate 1: elaborate sạch, in đúng hierarchy `u_slave1.u_bd`...).

---

## 4. Trạng thái sẵn sàng cho Bước 2

Toàn bộ RTL (10 module) đã được compile với đầy đủ cờ coverage (`bcstf`), và testbench UVM đã compile thành công, sẵn sàng cho bước tiếp theo trong chuỗi:

```
[Bước 1 — DONE] vlog -cover  →  [Bước 2] vopt +cover  →  [Bước 3] vsim -coverage  →  [Bước 4] vcover merge  →  [Bước 5] vcover report -html  →  [Bước 6] HTML → PDF
```
