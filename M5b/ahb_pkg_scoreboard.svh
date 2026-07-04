// ahb_pkg_scoreboard.svh -- M5b -- scoreboard + env (include SAU agents)
    class ahb_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(ahb_scoreboard)
        uvm_analysis_imp_m1#(ahb_seq_item,      ahb_scoreboard) imp_m1;
        uvm_analysis_imp_m2#(ahb_seq_item,      ahb_scoreboard) imp_m2;
        uvm_analysis_imp_s1#(ahb_slave_bd_item, ahb_scoreboard) imp_s1;
        uvm_analysis_imp_s2#(ahb_slave_bd_item, ahb_scoreboard) imp_s2;
        uvm_analysis_imp_s3#(ahb_slave_bd_item, ahb_scoreboard) imp_s3;
        uvm_analysis_imp_default_slv#(ahb_default_slave_bd_item, ahb_scoreboard) imp_default_slv;
        uvm_analysis_imp_bus#(ahb_bus_item,     ahb_scoreboard) imp_bus;
        logic [31:0] ref_mem_s1 [256];
        logic [31:0] ref_mem_s2 [256];
        logic [31:0] ref_mem_s3 [256];
        int unsigned n_writes_seen     = 0;
        int unsigned n_reads_seen      = 0;
        int unsigned n_reads_compared  = 0;
        int unsigned n_mismatch        = 0;
        int unsigned n_unexpected_resp = 0;
        int unsigned n_split_seen      = 0;
        int unsigned n_retry_seen      = 0;
        int unsigned n_bd_state_chg  [4];
        int unsigned n_bd_mem_write  [4];
        int unsigned n_bd_resp_chg   [4];
        int unsigned n_ds_state_chg    = 0;
        int unsigned n_ds_hit           = 0;
        int unsigned n_bus_master_chg   = 0;
        int unsigned n_bus_sel_chg      = 0;
        int unsigned n_bus_force_hook   = 0;
        int unsigned n_bus_snapshot     = 0;
        ahb_seq_item      pending_fd_q[4][$];
        ahb_slave_bd_item pending_bd_q[4][$];
        typedef enum {NO_MATCH, MATCH_OK, MATCH_DATA_BAD} match_result_e;
        int unsigned n_writes_matched       = 0;
        int unsigned n_orphan_fd_writes     = 0;
        int unsigned n_orphan_bd_writes     = 0;
        int unsigned n_writes_data_mismatch = 0;
        function new(string name, uvm_component parent);
            super.new(name, parent);
            imp_m1          = new("imp_m1",          this);
            imp_m2          = new("imp_m2",          this);
            imp_s1          = new("imp_s1",          this);
            imp_s2          = new("imp_s2",          this);
            imp_s3          = new("imp_s3",          this);
            imp_default_slv = new("imp_default_slv", this);
            imp_bus         = new("imp_bus",         this);
            init_ref_memory();
            init_counters();
        endfunction
        function void init_counters();
            foreach (n_bd_state_chg[i]) n_bd_state_chg[i] = 0;
            foreach (n_bd_mem_write[i]) n_bd_mem_write[i] = 0;
            foreach (n_bd_resp_chg[i])  n_bd_resp_chg[i]  = 0;
        endfunction
        function void init_ref_memory();
            foreach (ref_mem_s1[i]) ref_mem_s1[i] = 32'd0;
            foreach (ref_mem_s2[i]) ref_mem_s2[i] = 32'd0;
            foreach (ref_mem_s3[i]) ref_mem_s3[i] = 32'd0;
            ref_mem_s1[0] = 32'(SEED_S1);
            ref_mem_s1[1] = 32'(SEED_S1 * 2);
            ref_mem_s1[2] = 32'(SEED_S1 * 3);
            ref_mem_s2[0] = 32'(SEED_S2);
            ref_mem_s2[1] = 32'(SEED_S2 * 2);
            ref_mem_s2[2] = 32'(SEED_S2 * 3);
            ref_mem_s3[0] = 32'(SEED_S3);
            ref_mem_s3[1] = 32'(SEED_S3 * 2);
            ref_mem_s3[2] = 32'(SEED_S3 * 3);
        endfunction
        function int decode_slave(logic [31:0] addr);
            case (addr[31:30])
                2'b00: return 1;
                2'b01: return 2;
                2'b10: return 3;
                2'b11: return 0;
                default: return 0;
            endcase
        endfunction
        function logic [7:0] word_idx(logic [31:0] addr);
            return addr[9:2];
        endfunction
        function logic [7:0] sb_next_word_idx(logic [7:0] base,
                                               logic [7:0] cur,
                                               logic [2:0] burst_type);
            logic [7:0] lin = cur + 8'h01;
            case (burst_type)
                B_WRAP4 : return {base[7:2], lin[1:0]};
                B_WRAP8 : return {base[7:3], lin[2:0]};
                B_WRAP16: return {base[7:4], lin[3:0]};
                default : return lin;
            endcase
        endfunction
        function void write_m1(ahb_seq_item it);
            process_master_txn(it, "M1");
        endfunction
        function void write_m2(ahb_seq_item it);
            process_master_txn(it, "M2");
        endfunction
        function void process_master_txn(ahb_seq_item it, string mname);
            int     slv = decode_slave(it.addr);
            logic [7:0] idx = word_idx(it.addr);
            if (slv == 0) begin
                if (it.resp == R_OKAY) begin
                    n_unexpected_resp++;
                    `uvm_error("SB_DSLAVE",
                        $sformatf("%s @ 0x%08h hit Default Slave but got OKAY (expected ERROR)",
                                  mname, it.addr))
                end
                return;
            end
            if (it.dir == AHB_WRITE) begin
                n_writes_seen++;
                if (it.num_beats > 1 && it.beats_wr.size() > 0) begin
                    logic [7:0] base_widx = idx;
                    logic [7:0] cur_widx  = idx;
                    for (int b = 0; b < it.beats_wr.size(); b++) begin
                        logic [1:0] b_resp;
                        b_resp = (b < it.beats_resp.size()) ? it.beats_resp[b] : R_OKAY;
                        if (b_resp == R_OKAY) begin
                            case (slv)
                                1: ref_mem_s1[cur_widx] = it.beats_wr[b];
                                2: ref_mem_s2[cur_widx] = it.beats_wr[b];
                                3: ref_mem_s3[cur_widx] = it.beats_wr[b];
                            endcase
                            track_frontdoor_write(slv, cur_widx, it.beats_wr[b]);
                        end
                        `uvm_info("SB_WRITE",
                            $sformatf("%s WR_BURST S%0d[0x%02h] beat=%0d = 0x%08h resp=%s",
                                      mname, slv, cur_widx, b, it.beats_wr[b],
                                      ahb_seq_item::resp_name(b_resp)), UVM_MEDIUM)
                        if (b < it.beats_wr.size() - 1)
                            cur_widx = sb_next_word_idx(base_widx, cur_widx, it.burst);
                    end
                end
                else begin
                    if (it.resp == R_OKAY) begin
                        case (slv)
                            1: ref_mem_s1[idx] = it.wdata;
                            2: ref_mem_s2[idx] = it.wdata;
                            3: ref_mem_s3[idx] = it.wdata;
                            default: ;
                        endcase
                    end
                    `uvm_info("SB_WRITE",
                        $sformatf("%s WR S%0d[0x%02h] = 0x%08h  resp=%s",
                                  mname, slv, idx, it.wdata,
                                  ahb_seq_item::resp_name(it.resp)), UVM_MEDIUM)
                    if (it.resp == R_OKAY)
                        track_frontdoor_write(slv, idx, it.wdata);
                    else if (it.resp == R_SPLIT) n_split_seen++;
                    else if (it.resp == R_RETRY) n_retry_seen++;
                end
            end
            else begin
                logic [31:0] exp;
                n_reads_seen++;
                if (it.num_beats > 1 && it.beats_rd.size() > 0) begin
                    logic [7:0] base_widx = idx;
                    logic [7:0] cur_widx  = idx;
                    for (int b = 0; b < it.beats_rd.size(); b++) begin
                        logic [1:0] b_resp;
                        b_resp = (b < it.beats_resp.size()) ? it.beats_resp[b] : R_OKAY;
                        case (slv)
                            1: exp = ref_mem_s1[cur_widx];
                            2: exp = ref_mem_s2[cur_widx];
                            3: exp = ref_mem_s3[cur_widx];
                            default: exp = 32'h0;
                        endcase
                        if (b_resp == R_OKAY) begin
                            n_reads_compared++;
                            if (it.beats_rd[b] !== exp) begin
                                n_mismatch++;
                                `uvm_error("SB_MISMATCH",
                                    $sformatf("%s RD_BURST S%0d[0x%02h] beat=%0d act=0x%08h exp=0x%08h",
                                              mname, slv, cur_widx, b, it.beats_rd[b], exp))
                            end else begin
                                `uvm_info("SB_READ",
                                    $sformatf("%s RD_BURST S%0d[0x%02h] beat=%0d = 0x%08h  match",
                                              mname, slv, cur_widx, b, it.beats_rd[b]), UVM_MEDIUM)
                            end
                        end
                        if (b < it.beats_rd.size() - 1)
                            cur_widx = sb_next_word_idx(base_widx, cur_widx, it.burst);
                    end
                end
                else begin
                    case (slv)
                        1: exp = ref_mem_s1[idx];
                        2: exp = ref_mem_s2[idx];
                        3: exp = ref_mem_s3[idx];
                        default: exp = 32'h0;
                    endcase
                    if (it.resp == R_SPLIT) begin
                        n_split_seen++;
                        `uvm_info("SB_RD_RESP",
                            $sformatf("%s RD S%0d[0x%02h] resp=SPLIT (aborted, no compare)",
                                      mname, slv, idx), UVM_MEDIUM)
                    end
                    else if (it.resp == R_RETRY) begin
                        n_retry_seen++;
                        `uvm_info("SB_RD_RESP",
                            $sformatf("%s RD S%0d[0x%02h] resp=RETRY (aborted, no compare)",
                                      mname, slv, idx), UVM_MEDIUM)
                    end
                    else if (it.resp != R_OKAY) begin
                        n_unexpected_resp++;
                        `uvm_warning("SB_RD_RESP",
                            $sformatf("%s RD S%0d[0x%02h] resp=%s (expected OKAY)",
                                      mname, slv, idx,
                                      ahb_seq_item::resp_name(it.resp)))
                    end
                    else begin
                        n_reads_compared++;
                        if (it.rdata !== exp) begin
                            n_mismatch++;
                            `uvm_error("SB_MISMATCH",
                                $sformatf("%s RD S%0d[0x%02h] act=0x%08h exp=0x%08h",
                                          mname, slv, idx, it.rdata, exp))
                        end else begin
                            `uvm_info("SB_READ",
                                $sformatf("%s RD S%0d[0x%02h] = 0x%08h  match",
                                          mname, slv, idx, it.rdata), UVM_MEDIUM)
                        end
                    end
                end
            end
        endfunction
        function void write_s1(ahb_slave_bd_item bd); process_slv_bd(bd); endfunction
        function void write_s2(ahb_slave_bd_item bd); process_slv_bd(bd); endfunction
        function void write_s3(ahb_slave_bd_item bd); process_slv_bd(bd); endfunction
        function void process_slv_bd(ahb_slave_bd_item bd);
            int id = bd.slave_id;
            if (id < 1 || id > 3) begin
                `uvm_warning("SB_BD",
                    $sformatf("backdoor item with bad slave_id=%0d", id))
                return;
            end
            case (bd.event_type)
                EV_STATE_CHG: n_bd_state_chg[id]++;
                EV_MEM_WRITE: begin
                    n_bd_mem_write[id]++;
                    track_backdoor_write(bd);
                end
                EV_RESP_CHG : n_bd_resp_chg[id]++;
                default     : ;
            endcase
            `uvm_info("SB_BD",
                $sformatf("S%0d backdoor evt=%s @%0t",
                          id, ahb_slave_bd_item::event_name(bd.event_type),
                          bd.t_event),
                UVM_HIGH)
        endfunction
        function match_result_e try_consume_backdoor(int sid,
                                                     logic [7:0]  widx,
                                                     logic [31:0] data);
            int k;
            for (k = 0; k < pending_bd_q[sid].size(); k++) begin
                if (pending_bd_q[sid][k].mem_idx == widx) begin
                    if (pending_bd_q[sid][k].mem_data_new === data) begin
                        pending_bd_q[sid].delete(k);
                        return MATCH_OK;
                    end else begin
                        `uvm_error("SB_XCHK",
                            $sformatf("DATA MISMATCH S%0d[0x%02h]: fd_data=0x%08h bd_data=0x%08h",
                                      sid, widx, data,
                                      pending_bd_q[sid][k].mem_data_new))
                        pending_bd_q[sid].delete(k);
                        return MATCH_DATA_BAD;
                    end
                end
            end
            return NO_MATCH;
        endfunction
        function match_result_e try_consume_frontdoor(int sid,
                                                      logic [7:0]  widx,
                                                      logic [31:0] data);
            int k;
            for (k = 0; k < pending_fd_q[sid].size(); k++) begin
                if (word_idx(pending_fd_q[sid][k].addr) == widx) begin
                    if (pending_fd_q[sid][k].wdata === data) begin
                        pending_fd_q[sid].delete(k);
                        return MATCH_OK;
                    end else begin
                        `uvm_error("SB_XCHK",
                            $sformatf("DATA MISMATCH S%0d[0x%02h]: fd_data=0x%08h bd_data=0x%08h",
                                      sid, widx,
                                      pending_fd_q[sid][k].wdata, data))
                        pending_fd_q[sid].delete(k);
                        return MATCH_DATA_BAD;
                    end
                end
            end
            return NO_MATCH;
        endfunction
        function void track_frontdoor_write(int sid, logic [7:0] widx, logic [31:0] data);
            match_result_e r;
            ahb_seq_item   parked;
            r = try_consume_backdoor(sid, widx, data);
            case (r)
                MATCH_OK: begin
                    n_writes_matched++;
                    `uvm_info("SB_XCHK",
                        $sformatf("MATCH (BD→FD): S%0d[0x%02h] = 0x%08h",
                                  sid, widx, data),
                        UVM_MEDIUM)
                end
                MATCH_DATA_BAD: begin
                    n_writes_data_mismatch++;
                end
                NO_MATCH: begin
                    parked = ahb_seq_item::type_id::create("fd_park");
                    parked.dir   = AHB_WRITE;
                    parked.addr  = {22'h0, widx, 2'b00};
                    parked.wdata = data;
                    pending_fd_q[sid].push_back(parked);
                    `uvm_info("SB_XCHK",
                        $sformatf("FD WRITE parked: S%0d[0x%02h] = 0x%08h (awaiting BD)",
                                  sid, widx, data),
                        UVM_HIGH)
                end
            endcase
        endfunction
        function void track_backdoor_write(ahb_slave_bd_item bd);
            match_result_e r;
            int sid;
            sid = bd.slave_id;
            r = try_consume_frontdoor(sid, bd.mem_idx, bd.mem_data_new);
            case (r)
                MATCH_OK: begin
                    n_writes_matched++;
                    `uvm_info("SB_XCHK",
                        $sformatf("MATCH (FD→BD): S%0d[0x%02h] = 0x%08h",
                                  sid, bd.mem_idx, bd.mem_data_new),
                        UVM_MEDIUM)
                end
                MATCH_DATA_BAD: begin
                    n_writes_data_mismatch++;
                end
                NO_MATCH: begin
                    pending_bd_q[sid].push_back(bd);
                    `uvm_info("SB_XCHK",
                        $sformatf("BD WRITE parked: S%0d[0x%02h] = 0x%08h (awaiting FD)",
                                  sid, bd.mem_idx, bd.mem_data_new),
                        UVM_HIGH)
                end
            endcase
        endfunction
        function void check_phase(uvm_phase phase);
            int sid, k;
            super.check_phase(phase);
            for (sid = 1; sid <= 3; sid++) begin
                n_orphan_fd_writes += pending_fd_q[sid].size();
                for (k = 0; k < pending_fd_q[sid].size(); k++) begin
                    `uvm_error("SB_XCHK",
                        $sformatf("ORPHAN FD: S%0d[0x%02h] = 0x%08h never confirmed by backdoor",
                                  sid,
                                  word_idx(pending_fd_q[sid][k].addr),
                                  pending_fd_q[sid][k].wdata))
                end
                n_orphan_bd_writes += pending_bd_q[sid].size();
                for (k = 0; k < pending_bd_q[sid].size(); k++) begin
                    `uvm_error("SB_XCHK",
                        $sformatf("ORPHAN BD: S%0d[0x%02h] = 0x%08h has no matching frontdoor",
                                  sid,
                                  pending_bd_q[sid][k].mem_idx,
                                  pending_bd_q[sid][k].mem_data_new))
                end
            end
        endfunction
        function void write_default_slv(ahb_default_slave_bd_item bd);
            case (bd.event_type)
                EV_DS_STATE: n_ds_state_chg++;
                EV_DS_HIT  : n_ds_hit++;
                default    : ;
            endcase
            `uvm_info("SB_DS",
                $sformatf("DS backdoor evt=%0d @%0t (HRESP=%s)",
                          bd.event_type, bd.t_event,
                          ahb_seq_item::resp_name(bd.HRESP_DEFAULT)),
                UVM_HIGH)
        endfunction
        function void write_bus(ahb_bus_item bi);
            case (bi.event_type)
                EV_MASTER_CHG  : n_bus_master_chg++;
                EV_SEL_CHG     : n_bus_sel_chg++;
                EV_FORCE_HOOK  : n_bus_force_hook++;
                EV_BUS_SNAPSHOT: n_bus_snapshot++;
                default        : ;
            endcase
            `uvm_info("SB_BUS",
                $sformatf("BUS backdoor evt=%s @%0t (HMASTER=%0d)",
                          ahb_bus_item::event_name(bi.event_type),
                          bi.t_event, bi.HMASTER),
                UVM_HIGH)
        endfunction
        function void report_phase(uvm_phase phase);
            int total_bd_state = n_bd_state_chg[1] + n_bd_state_chg[2] + n_bd_state_chg[3];
            int total_bd_mem   = n_bd_mem_write[1] + n_bd_mem_write[2] + n_bd_mem_write[3];
            int total_bd_resp  = n_bd_resp_chg[1]  + n_bd_resp_chg[2]  + n_bd_resp_chg[3];
            bit did_write = (n_writes_seen > 0);
            bit did_read  = (n_reads_seen  > 0);
            bit saw_force = ((n_split_seen + n_retry_seen) > 0);
            bit bus_alive = ((n_bus_master_chg + n_bus_sel_chg +
                              n_bus_snapshot   + n_bus_force_hook) > 0);
            bit hard_err  = ((n_mismatch > 0) || (n_unexpected_resp > 0) ||
                             (n_writes_data_mismatch > 0) ||
                             (n_orphan_fd_writes > 0) || (n_orphan_bd_writes > 0));
            super.report_phase(phase);
            `uvm_info("SB_REPORT", "========== SCOREBOARD SUMMARY ==========", UVM_LOW)
            `uvm_info("SB_REPORT", "  [Frontdoor — master monitors]", UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Writes observed   : %0d", n_writes_seen),  UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Reads  observed   : %0d", n_reads_seen),   UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Reads  compared   : %0d", n_reads_compared), UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Mismatches        : %0d", n_mismatch),     UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Unexpected resp   : %0d", n_unexpected_resp), UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    SPLIT  observed   : %0d", n_split_seen), UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    RETRY  observed   : %0d", n_retry_seen), UVM_LOW)
            `uvm_info("SB_REPORT", "  [Backdoor — slave monitors (S1/S2/S3)]", UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    State transitions : S1=%0d  S2=%0d  S3=%0d  (total=%0d)",
                          n_bd_state_chg[1], n_bd_state_chg[2], n_bd_state_chg[3], total_bd_state),
                UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Memory writes     : S1=%0d  S2=%0d  S3=%0d  (total=%0d)",
                          n_bd_mem_write[1], n_bd_mem_write[2], n_bd_mem_write[3], total_bd_mem),
                UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    HRESP changes     : S1=%0d  S2=%0d  S3=%0d  (total=%0d)",
                          n_bd_resp_chg[1],  n_bd_resp_chg[2],  n_bd_resp_chg[3], total_bd_resp),
                UVM_LOW)
            `uvm_info("SB_REPORT", "  [Backdoor — default slave]", UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    State transitions : %0d", n_ds_state_chg), UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Default-slave hits: %0d", n_ds_hit), UVM_LOW)
            `uvm_info("SB_REPORT", "  [Bus monitor (sys_if)]", UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Initial snapshots : %0d", n_bus_snapshot), UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Master changes    : %0d", n_bus_master_chg), UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    HSEL  changes     : %0d", n_bus_sel_chg),    UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Force-hook pulses : %0d", n_bus_force_hook), UVM_LOW)
            if (n_bus_master_chg == 0 && n_bus_sel_chg == 0)
                `uvm_info("SB_REPORT",
                    "    (0 Master/HSEL changes is EXPECTED for single-master smoke:",
                    UVM_LOW)
            if (n_bus_master_chg == 0 && n_bus_sel_chg == 0)
                `uvm_info("SB_REPORT",
                    "       arbiter v2 encodes M1=4'd0 same as IDLE; HADDR[31:30]=00 keeps HSEL_S1=1)",
                    UVM_LOW)
            `uvm_info("SB_REPORT", "  [M5b — Dual-Path Cross-Check]", UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Writes matched (FD↔BD) : %0d", n_writes_matched), UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Data mismatches        : %0d", n_writes_data_mismatch), UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Orphan FD writes       : %0d", n_orphan_fd_writes), UVM_LOW)
            `uvm_info("SB_REPORT",
                $sformatf("    Orphan BD writes       : %0d", n_orphan_bd_writes), UVM_LOW)
            if (hard_err)
                `uvm_error("SB_REPORT",
                    "  ====> M5b FAILED: data-integrity error (see SB_* errors above) <====")
            else if (!bus_alive)
                `uvm_error("SB_REPORT",
                    "  ====> M5b FAILED: bus monitor produced no events (snapshot missing) <====")
            else if (total_bd_state == 0)
                `uvm_error("SB_REPORT",
                    "  ====> M5b FAILED: slave bd monitor saw no STATE transitions <====")
            else if (did_write && !saw_force && n_writes_matched == 0 && total_bd_mem == 0)
                `uvm_error("SB_REPORT",
                    "  ====> M5b FAILED: OKAY writes issued but none confirmed FD↔BD <====")
            else if (did_read && !saw_force && n_reads_compared == 0)
                `uvm_error("SB_REPORT",
                    "  ====> M5b FAILED: reads issued but none compared <====")
            else
                `uvm_info("SB_REPORT",
                    "  ====> M5b SCOREBOARD CHECK PASSED <====", UVM_LOW)
            `uvm_info("SB_REPORT", "========================================", UVM_LOW)
        endfunction
    endclass : ahb_scoreboard
    class ahb_env extends uvm_env;
        `uvm_component_utils(ahb_env)
        ahb_master_agent             m1_agent;
        ahb_master_agent             m2_agent;
        ahb_slv_rsp_agent            slv_rsp_agent;
        ahb_slave_bd_mon_agent       s1_mon_agent;
        ahb_slave_bd_mon_agent       s2_mon_agent;
        ahb_slave_bd_mon_agent       s3_mon_agent;
        ahb_default_slave_bd_mon_agent default_mon_agent;
        ahb_bus_mon_agent            bus_mon_agent;
        ahb_virtual_sequencer        v_seqr;
        ahb_scoreboard               sb;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "s1_mon_agent",      "is_active", UVM_PASSIVE);
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "s2_mon_agent",      "is_active", UVM_PASSIVE);
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "s3_mon_agent",      "is_active", UVM_PASSIVE);
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "default_mon_agent", "is_active", UVM_PASSIVE);
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "bus_mon_agent",     "is_active", UVM_PASSIVE);
            uvm_config_db#(int unsigned)::set(this, "s1_mon_agent.mon", "slave_id", 1);
            uvm_config_db#(int unsigned)::set(this, "s2_mon_agent.mon", "slave_id", 2);
            uvm_config_db#(int unsigned)::set(this, "s3_mon_agent.mon", "slave_id", 3);
            m1_agent          = ahb_master_agent           ::type_id::create("m1_agent",          this);
            m2_agent          = ahb_master_agent           ::type_id::create("m2_agent",          this);
            slv_rsp_agent     = ahb_slv_rsp_agent          ::type_id::create("slv_rsp_agent",     this);
            s1_mon_agent      = ahb_slave_bd_mon_agent     ::type_id::create("s1_mon_agent",      this);
            s2_mon_agent      = ahb_slave_bd_mon_agent     ::type_id::create("s2_mon_agent",      this);
            s3_mon_agent      = ahb_slave_bd_mon_agent     ::type_id::create("s3_mon_agent",      this);
            default_mon_agent = ahb_default_slave_bd_mon_agent::type_id::create("default_mon_agent", this);
            bus_mon_agent     = ahb_bus_mon_agent          ::type_id::create("bus_mon_agent",     this);
            v_seqr = ahb_virtual_sequencer::type_id::create("v_seqr", this);
            sb     = ahb_scoreboard       ::type_id::create("sb",     this);
        endfunction
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            m1_agent.mon.ap.connect(sb.imp_m1);
            m2_agent.mon.ap.connect(sb.imp_m2);
            s1_mon_agent.mon.ap.connect(sb.imp_s1);
            s2_mon_agent.mon.ap.connect(sb.imp_s2);
            s3_mon_agent.mon.ap.connect(sb.imp_s3);
            default_mon_agent.mon.ap.connect(sb.imp_default_slv);
            bus_mon_agent.mon.ap.connect(sb.imp_bus);
            v_seqr.m1_seqr_h      = m1_agent.seqr;
            v_seqr.m2_seqr_h      = m2_agent.seqr;
            v_seqr.slv_rsp_seqr_h = slv_rsp_agent.seqr;
        endfunction
    endclass : ahb_env
