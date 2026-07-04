// ahb_pkg_sequences.svh -- M5b -- sequences + virtual sequences (include SAU scoreboard/env)
    class ahb_base_seq extends uvm_sequence#(ahb_seq_item);
        `uvm_object_utils(ahb_base_seq)
        function new(string name = "ahb_base_seq");
            super.new(name);
        endfunction
    endclass : ahb_base_seq
    class ahb_write_single_seq extends ahb_base_seq;
        rand logic [31:0] addr;
        rand logic [31:0] wdata;
        rand bit          lock;
        constraint c_defaults {
            soft lock      == 1'b0;
            addr[1:0]      == 2'b00;
        }
        `uvm_object_utils(ahb_write_single_seq)
        function new(string name = "ahb_write_single_seq");
            super.new(name);
        endfunction
        task body();
            ahb_seq_item it;
            it = ahb_seq_item::type_id::create("w_it");
            start_item(it);
            it.dir       = AHB_WRITE;
            it.addr      = addr;
            it.wdata     = wdata;
            it.trans     = T_NONSEQ;
            it.burst     = B_SINGLE;
            it.size      = SZ_WORD;
            it.lock      = lock;
            it.busreq    = 1'b1;
            it.num_beats = 1;
            it.exp_resp  = R_OKAY;
            finish_item(it);
        endtask
    endclass : ahb_write_single_seq
    class ahb_read_single_seq extends ahb_base_seq;
        rand logic [31:0] addr;
        rand bit          lock;
              logic [31:0] rdata;
              logic [1:0]  resp;
        constraint c_defaults {
            soft lock     == 1'b0;
            addr[1:0]     == 2'b00;
        }
        `uvm_object_utils(ahb_read_single_seq)
        function new(string name = "ahb_read_single_seq");
            super.new(name);
        endfunction
        task body();
            ahb_seq_item it;
            it = ahb_seq_item::type_id::create("r_it");
            start_item(it);
            it.dir       = AHB_READ;
            it.addr      = addr;
            it.trans     = T_NONSEQ;
            it.burst     = B_SINGLE;
            it.size      = SZ_WORD;
            it.lock      = lock;
            it.busreq    = 1'b1;
            it.num_beats = 1;
            it.exp_resp  = R_OKAY;
            finish_item(it);
            rdata = it.rdata;
            resp  = it.resp;
        endtask
    endclass : ahb_read_single_seq
    typedef enum {
        PAT_DEAD,
        PAT_INDEX,
        PAT_RAND
    } burst_pat_e;
    class ahb_write_burst_seq extends ahb_base_seq;
        rand logic [31:0]   base_addr;
        rand logic [2:0]    burst_type;
        burst_pat_e         pattern = PAT_DEAD;
        logic [31:0]        user_data[$];
        constraint c_align { base_addr[1:0] == 2'b00; }
        constraint c_dflt  { soft burst_type == B_INCR4; }
        `uvm_object_utils(ahb_write_burst_seq)
        function new(string name = "ahb_write_burst_seq"); super.new(name); endfunction
        function int unsigned beats_of(logic [2:0] b);
            case (b)
                B_INCR4, B_WRAP4  : return 4;
                B_INCR8, B_WRAP8  : return 8;
                B_INCR16,B_WRAP16 : return 16;
                default           : return 1;
            endcase
        endfunction
        task body();
            ahb_seq_item it;
            int unsigned N;
            it = ahb_seq_item::type_id::create("wr_burst");
            N  = beats_of(burst_type);
            start_item(it);
            it.dir       = AHB_WRITE;
            it.addr      = base_addr;
            it.trans     = T_NONSEQ;
            it.burst     = burst_type;
            it.size      = SZ_WORD;
            it.lock      = 1'b0;
            it.busreq    = 1'b1;
            it.num_beats = N;
            it.beats_wr  = {};
            if (user_data.size() == N) begin
                it.beats_wr = user_data;
            end else begin
                for (int i = 0; i < N; i++) begin
                    case (pattern)
                        PAT_DEAD  : it.beats_wr.push_back(32'hDEAD_BE00 | i);
                        PAT_INDEX : it.beats_wr.push_back(32'hAAAA_0000 | i);
                        default   : it.beats_wr.push_back($urandom());
                    endcase
                end
            end
            it.wdata    = it.beats_wr[0];
            it.exp_resp = R_OKAY;
            finish_item(it);
            `uvm_info("SEQ_WR", $sformatf("burst done base=0x%08h burst=%0d N=%0d",
                                           base_addr, burst_type, N), UVM_LOW)
        endtask
    endclass : ahb_write_burst_seq
    class ahb_read_burst_seq extends ahb_base_seq;
        rand logic [31:0]   base_addr;
        rand logic [2:0]    burst_type;
        logic [31:0]        rdata_out[$];
        constraint c_align { base_addr[1:0] == 2'b00; }
        constraint c_dflt  { soft burst_type == B_INCR4; }
        `uvm_object_utils(ahb_read_burst_seq)
        function new(string name = "ahb_read_burst_seq"); super.new(name); endfunction
        function int unsigned beats_of(logic [2:0] b);
            case (b)
                B_INCR4, B_WRAP4  : return 4;
                B_INCR8, B_WRAP8  : return 8;
                B_INCR16,B_WRAP16 : return 16;
                default           : return 1;
            endcase
        endfunction
        task body();
            ahb_seq_item it;
            int unsigned N;
            it = ahb_seq_item::type_id::create("rd_burst");
            N  = beats_of(burst_type);
            start_item(it);
            it.dir       = AHB_READ;
            it.addr      = base_addr;
            it.trans     = T_NONSEQ;
            it.burst     = burst_type;
            it.size      = SZ_WORD;
            it.lock      = 1'b0;
            it.busreq    = 1'b1;
            it.num_beats = N;
            it.exp_resp  = R_OKAY;
            finish_item(it);
            rdata_out = it.beats_rd;
            `uvm_info("SEQ_RD", $sformatf("burst done base=0x%08h burst=%0d N=%0d",
                                           base_addr, burst_type, N), UVM_LOW)
        endtask
    endclass : ahb_read_burst_seq
    class ahb_force_seq extends uvm_sequence#(ahb_force_item);
        rand int unsigned slave_id;
        rand bit          op_split;
        rand bit          op_retry;
        rand int unsigned beat_index;
        constraint c_dflt {
            soft slave_id   == 1;
            soft op_split   == 1'b1;
            soft op_retry   == 1'b0;
            soft beat_index == 0;
        }
        `uvm_object_utils(ahb_force_seq)
        function new(string name = "ahb_force_seq"); super.new(name); endfunction
        task body();
            ahb_force_item it;
            it = ahb_force_item::type_id::create("force_it");
            start_item(it);
            it.slave_id   = slave_id;
            it.op_split   = op_split;
            it.op_retry   = op_retry;
            it.beat_index = beat_index;
            finish_item(it);
            `uvm_info("FORCE_SEQ", $sformatf("issued %s", it.convert2string()), UVM_LOW)
        endtask
    endclass : ahb_force_seq
    class ahb_m3_smoke_vseq extends uvm_sequence;
        `uvm_object_utils(ahb_m3_smoke_vseq)
        `uvm_declare_p_sequencer(ahb_virtual_sequencer)
        function new(string name = "ahb_m3_smoke_vseq");
            super.new(name);
        endfunction
        task body();
            ahb_write_single_seq w_seq;
            ahb_read_single_seq  r_seq;
            logic [31:0] initial_val;
            `uvm_info("M3_SMOKE", "===== M3 Smoke Test Starting =====", UVM_LOW)
            `uvm_info("M3_SMOKE", "Step 1: Read initial S1[1] (expect 0x14 = 20)", UVM_LOW)
            r_seq = ahb_read_single_seq::type_id::create("r_seq_pre");
            r_seq.addr = 32'h0000_0004;
            r_seq.lock = 1'b0;
            r_seq.start(p_sequencer.m1_seqr_h);
            initial_val = r_seq.rdata;
            `uvm_info("M3_SMOKE",
                $sformatf("  → got 0x%08h, resp=%s",
                          initial_val, ahb_seq_item::resp_name(r_seq.resp)),
                UVM_LOW)
            if (initial_val !== 32'h0000_0014)
                `uvm_warning("M3_SMOKE",
                    $sformatf("Initial S1[1] = 0x%08h, expected 0x14",
                              initial_val))
            `uvm_info("M3_SMOKE", "Step 2: Write 0xDEADBEEF to S1[1]", UVM_LOW)
            w_seq = ahb_write_single_seq::type_id::create("w_seq");
            w_seq.addr  = 32'h0000_0004;
            w_seq.wdata = 32'hDEAD_BEEF;
            w_seq.lock  = 1'b0;
            w_seq.start(p_sequencer.m1_seqr_h);
            `uvm_info("M3_SMOKE", "Step 3: Read back S1[1] (expect 0xDEADBEEF)", UVM_LOW)
            r_seq = ahb_read_single_seq::type_id::create("r_seq_post");
            r_seq.addr = 32'h0000_0004;
            r_seq.lock = 1'b0;
            r_seq.start(p_sequencer.m1_seqr_h);
            if (r_seq.rdata !== 32'hDEAD_BEEF)
                `uvm_error("M3_SMOKE",
                    $sformatf("READBACK MISMATCH: exp=0xDEADBEEF act=0x%08h",
                              r_seq.rdata))
            else
                `uvm_info("M3_SMOKE",
                    $sformatf("READBACK OK: 0x%08h ✓", r_seq.rdata), UVM_LOW)
            if (r_seq.resp !== R_OKAY)
                `uvm_error("M3_SMOKE",
                    $sformatf("Readback resp not OKAY: %s",
                              ahb_seq_item::resp_name(r_seq.resp)))
            `uvm_info("M3_SMOKE", "===== M3 Smoke Test Completed =====", UVM_LOW)
        endtask
    endclass : ahb_m3_smoke_vseq
    class ahb_burst_writeread_vseq extends uvm_sequence;
        `uvm_object_utils(ahb_burst_writeread_vseq)
        `uvm_declare_p_sequencer(ahb_virtual_sequencer)
        logic [31:0]  base_addr   = 32'h0000_0010;
        logic [2:0]   burst_type  = B_INCR4;
        burst_pat_e   pattern     = PAT_DEAD;
        bit           do_write    = 1'b1;
        bit           do_read     = 1'b1;
        function new(string name = "ahb_burst_writeread_vseq"); super.new(name); endfunction
        task body();
            ahb_write_burst_seq w;
            ahb_read_burst_seq  r;
            int unsigned N;
            logic [31:0] expected[$];
            case (burst_type)
                B_INCR4, B_WRAP4  : N = 4;
                B_INCR8, B_WRAP8  : N = 8;
                B_INCR16,B_WRAP16 : N = 16;
                default           : N = 1;
            endcase
            if (do_write) begin
                w = ahb_write_burst_seq::type_id::create("w");
                w.base_addr  = base_addr;
                w.burst_type = burst_type;
                w.pattern    = pattern;
                w.start(p_sequencer.m1_seqr_h);
                expected = {};
                for (int i = 0; i < N; i++) begin
                    case (pattern)
                        PAT_DEAD  : expected.push_back(32'hDEAD_BE00 | i);
                        PAT_INDEX : expected.push_back(32'hAAAA_0000 | i);
                        default   : expected.push_back(32'h0);
                    endcase
                end
            end
            if (do_read) begin
                r = ahb_read_burst_seq::type_id::create("r");
                r.base_addr  = base_addr;
                r.burst_type = burst_type;
                r.start(p_sequencer.m1_seqr_h);
                if (do_write && pattern != PAT_RAND) begin
                    for (int i = 0; i < r.rdata_out.size() && i < expected.size(); i++) begin
                        if (r.rdata_out[i] !== expected[i])
                            `uvm_error("VSEQ_CHK",
                                $sformatf("read-back mismatch beat=%0d exp=0x%08h got=0x%08h",
                                          i, expected[i], r.rdata_out[i]))
                    end
                end
            end
            `uvm_info("VSEQ", $sformatf("burst WR done base=0x%08h burst=%0d",
                                         base_addr, burst_type), UVM_LOW)
        endtask
    endclass : ahb_burst_writeread_vseq
    class ahb_force_single_vseq extends uvm_sequence;
        `uvm_object_utils(ahb_force_single_vseq)
        `uvm_declare_p_sequencer(ahb_virtual_sequencer)
        int unsigned slave_id  = 1;
        bit          op_split  = 1'b1;
        bit          op_retry  = 1'b0;
        bit          is_write  = 1'b0;
        logic [31:0] base_addr = 32'h0000_0040;
        logic [31:0] wr_data   = 32'hDEAD_BEEF;
        bit          lock      = 1'b0;
        function new(string name = "ahb_force_single_vseq"); super.new(name); endfunction
        task body();
            ahb_force_seq        fseq;
            ahb_write_single_seq wseq;
            ahb_read_single_seq  rseq;
            fseq = ahb_force_seq::type_id::create("fseq");
            fseq.slave_id   = slave_id;
            fseq.op_split   = op_split;
            fseq.op_retry   = op_retry;
            fseq.beat_index = 0;
            fork
                fseq.start(p_sequencer.slv_rsp_seqr_h);
                begin
                    if (is_write) begin
                        wseq = ahb_write_single_seq::type_id::create("wseq");
                        wseq.addr  = base_addr;
                        wseq.wdata = wr_data;
                        wseq.lock  = lock;
                        wseq.start(p_sequencer.m1_seqr_h);
                    end else begin
                        rseq = ahb_read_single_seq::type_id::create("rseq");
                        rseq.addr = base_addr;
                        rseq.lock = lock;
                        rseq.start(p_sequencer.m1_seqr_h);
                    end
                end
            join
            `uvm_info("FORCE_VSEQ",
                $sformatf("done slv=%0d split=%0b retry=%0b dir=%s base=0x%08h lock=%0b",
                          slave_id, op_split, op_retry, is_write ? "W" : "R",
                          base_addr, lock), UVM_LOW)
        endtask
    endclass : ahb_force_single_vseq
