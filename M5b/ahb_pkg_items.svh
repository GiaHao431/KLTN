// ahb_pkg_items.svh -- M5b -- sequence items (include DAU TIEN trong package)
    class ahb_seq_item extends uvm_sequence_item;
        rand ahb_dir_e        dir;
        rand logic [31:0]     addr;
        rand logic [31:0]     wdata;
        rand logic [1:0]      trans;
        rand logic [2:0]      burst;
        rand logic [2:0]      size;
        rand bit              lock;
        rand bit              busreq;
        rand int unsigned     num_beats;
             logic [31:0]     beats_wr[$];
             logic [31:0]     rdata;
             logic [31:0]     beats_rd[$];
             logic [1:0]      resp;
             logic [1:0]      beats_resp[$];
             logic [31:0]     exp_rdata;
             logic [1:0]      exp_resp;
        constraint c_default {
            soft trans     == T_NONSEQ;
            soft burst     == B_SINGLE;
            soft size      == SZ_WORD;
            soft lock      == 1'b0;
            soft busreq    == 1'b1;
            soft num_beats == 1;
            addr[1:0]  == 2'b00;
        }
        `uvm_object_utils_begin(ahb_seq_item)
            `uvm_field_enum(ahb_dir_e, dir,   UVM_ALL_ON)
            `uvm_field_int (addr,             UVM_ALL_ON)
            `uvm_field_int (wdata,            UVM_ALL_ON)
            `uvm_field_int (trans,            UVM_ALL_ON)
            `uvm_field_int (burst,            UVM_ALL_ON)
            `uvm_field_int (size,             UVM_ALL_ON)
            `uvm_field_int (lock,             UVM_ALL_ON)
            `uvm_field_int (busreq,           UVM_ALL_ON)
            `uvm_field_int (num_beats,        UVM_ALL_ON)
            `uvm_field_int (rdata,            UVM_ALL_ON | UVM_NOCOMPARE)
            `uvm_field_int (resp,             UVM_ALL_ON | UVM_NOCOMPARE)
            `uvm_field_int (exp_rdata,        UVM_ALL_ON)
            `uvm_field_int (exp_resp,         UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name = "ahb_seq_item");
            super.new(name);
        endfunction
        function string convert2string();
            string s;
            s = $sformatf(
                "%s @0x%08h | dir=%s wdata=0x%08h rdata=0x%08h resp=%s burst=%0d N=%0d size=%0d lock=%0b",
                trans_name(trans), addr, dir.name(), wdata, rdata,
                resp_name(resp), burst, num_beats, size, lock);
            if (dir == AHB_WRITE && beats_wr.size() > 0) begin
                s = {s, " wr:["};
                foreach (beats_wr[i]) s = {s, $sformatf("%0d:0x%08h ", i, beats_wr[i])};
                s = {s, "]"};
            end
            if (dir == AHB_READ && beats_rd.size() > 0) begin
                s = {s, " rd:["};
                foreach (beats_rd[i]) s = {s, $sformatf("%0d:0x%08h ", i, beats_rd[i])};
                s = {s, "]"};
            end
            return s;
        endfunction
        static function string trans_name(logic [1:0] t);
            case (t)
                T_IDLE:   return "IDLE";
                T_BUSY:   return "BUSY";
                T_NONSEQ: return "NONSEQ";
                T_SEQ:    return "SEQ";
                default:  return "????";
            endcase
        endfunction
        static function string resp_name(logic [1:0] r);
            case (r)
                R_OKAY:  return "OKAY";
                R_ERROR: return "ERROR";
                R_RETRY: return "RETRY";
                R_SPLIT: return "SPLIT";
                default: return "????";
            endcase
        endfunction
    endclass : ahb_seq_item
    class ahb_force_item extends uvm_sequence_item;
        rand int unsigned slave_id;
        rand bit          op_split;
        rand bit          op_retry;
        rand int unsigned beat_index;
        rand int unsigned hold_cycles;
        constraint c_force_valid { slave_id inside {1, 2, 3}; }
        `uvm_object_utils_begin(ahb_force_item)
            `uvm_field_int(slave_id,    UVM_ALL_ON)
            `uvm_field_int(op_split,    UVM_ALL_ON)
            `uvm_field_int(op_retry,    UVM_ALL_ON)
            `uvm_field_int(beat_index,  UVM_ALL_ON)
            `uvm_field_int(hold_cycles, UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name = "ahb_force_item");
            super.new(name);
        endfunction
        function string convert2string();
            return $sformatf("FORCE slv=%0d split=%0b retry=%0b beat=%0d hold=%0d",
                             slave_id, op_split, op_retry, beat_index, hold_cycles);
        endfunction
    endclass : ahb_force_item
    typedef enum logic [1:0] {
        EV_STATE_CHG = 2'd0,
        EV_MEM_WRITE = 2'd1,
        EV_RESP_CHG  = 2'd2
    } slv_bd_event_e;
    class ahb_slave_bd_item extends uvm_sequence_item;
        slv_bd_event_e   event_type;
        int unsigned     slave_id;
        time             t_event;
        logic [2:0]      ps_slave;
        logic [2:0]      ns_slave;
        logic [2:0]      prev_ps;
        logic [7:0]      local_addr;
        logic [7:0]      local_addr_base;
        logic [5:0]      beat_cnt;
        logic [2:0]      local_burst;
        logic [2:0]      local_size;
        logic [7:0]      mem_idx;
        logic [31:0]     mem_data_new;
        logic [31:0]     mem_data_old;
        logic [1:0]      HRESP;
        logic [1:0]      prev_HRESP;
        logic            HREADYOUT;
        logic            resp_abort;
        logic [15:0]     HSPLITx;
        logic [31:0]     HRDATA;
        `uvm_object_utils_begin(ahb_slave_bd_item)
            `uvm_field_enum(slv_bd_event_e, event_type, UVM_ALL_ON)
            `uvm_field_int (slave_id,        UVM_ALL_ON)
            `uvm_field_int (ps_slave,        UVM_ALL_ON)
            `uvm_field_int (ns_slave,        UVM_ALL_ON)
            `uvm_field_int (prev_ps,         UVM_ALL_ON)
            `uvm_field_int (local_addr,      UVM_ALL_ON)
            `uvm_field_int (beat_cnt,        UVM_ALL_ON)
            `uvm_field_int (mem_idx,         UVM_ALL_ON)
            `uvm_field_int (mem_data_new,    UVM_ALL_ON)
            `uvm_field_int (mem_data_old,    UVM_ALL_ON)
            `uvm_field_int (HRESP,           UVM_ALL_ON)
            `uvm_field_int (HREADYOUT,       UVM_ALL_ON)
            `uvm_field_int (HSPLITx,         UVM_ALL_ON)
            `uvm_field_int (HRDATA,          UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name = "ahb_slave_bd_item");
            super.new(name);
        endfunction
        static function string state_name(logic [2:0] s);
            case (s)
                3'b000: return "ST_IDLE";
                3'b001: return "ST_ACTIVE";
                3'b010: return "ST_RETRY2";
                3'b011: return "ST_LITTLE";
                3'b100: return "ST_WBURST";
                3'b101: return "ST_RBURST";
                default: return $sformatf("ST_?(%0d)", s);
            endcase
        endfunction
        static function string event_name(slv_bd_event_e e);
            case (e)
                EV_STATE_CHG: return "STATE_CHG";
                EV_MEM_WRITE: return "MEM_WRITE";
                EV_RESP_CHG : return "RESP_CHG";
                default     : return "?";
            endcase
        endfunction
    endclass : ahb_slave_bd_item
    typedef enum logic {
        EV_DS_HIT   = 1'b0,
        EV_DS_STATE = 1'b1
    } ds_event_e;
    class ahb_default_slave_bd_item extends uvm_sequence_item;
        ds_event_e   event_type;
        time         t_event;
        logic [1:0]  ps, ns, prev_ps;
        logic        active_transfer;
        logic        HREADYOUT_DEFAULT;
        logic [1:0]  HRESP_DEFAULT;
        `uvm_object_utils_begin(ahb_default_slave_bd_item)
            `uvm_field_enum(ds_event_e, event_type, UVM_ALL_ON)
            `uvm_field_int (ps,                UVM_ALL_ON)
            `uvm_field_int (ns,                UVM_ALL_ON)
            `uvm_field_int (prev_ps,           UVM_ALL_ON)
            `uvm_field_int (active_transfer,   UVM_ALL_ON)
            `uvm_field_int (HREADYOUT_DEFAULT, UVM_ALL_ON)
            `uvm_field_int (HRESP_DEFAULT,     UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name = "ahb_default_slave_bd_item");
            super.new(name);
        endfunction
    endclass : ahb_default_slave_bd_item
    typedef enum logic [1:0] {
        EV_MASTER_CHG   = 2'd0,
        EV_SEL_CHG      = 2'd1,
        EV_FORCE_HOOK   = 2'd2,
        EV_BUS_SNAPSHOT = 2'd3
    } bus_event_e;
    class ahb_bus_item extends uvm_sequence_item;
        bus_event_e  event_type;
        time         t_event;
        logic [3:0]  HMASTER, prev_HMASTER;
        logic        HMASTLOCK;
        logic        HSEL_S1, HSEL_S2, HSEL_S3, HSEL_DEFAULT;
        logic [3:0]  prev_HSEL_bits;
        logic [3:0]  curr_HSEL_bits;
        logic [31:0] HADDR_S;
        logic [1:0]  HTRANS_S;
        logic        HWRITE_S;
        logic        force_split_pulse;
        logic        force_retry_pulse;
        logic [2:0]  force_split_which;
        logic [2:0]  force_retry_which;
        `uvm_object_utils_begin(ahb_bus_item)
            `uvm_field_enum(bus_event_e, event_type, UVM_ALL_ON)
            `uvm_field_int (HMASTER,            UVM_ALL_ON)
            `uvm_field_int (prev_HMASTER,       UVM_ALL_ON)
            `uvm_field_int (HMASTLOCK,          UVM_ALL_ON)
            `uvm_field_int (HSEL_S1,            UVM_ALL_ON)
            `uvm_field_int (HSEL_S2,            UVM_ALL_ON)
            `uvm_field_int (HSEL_S3,            UVM_ALL_ON)
            `uvm_field_int (HSEL_DEFAULT,       UVM_ALL_ON)
            `uvm_field_int (HADDR_S,            UVM_ALL_ON)
            `uvm_field_int (HTRANS_S,           UVM_ALL_ON)
            `uvm_field_int (HWRITE_S,           UVM_ALL_ON)
            `uvm_field_int (force_split_pulse,  UVM_ALL_ON)
            `uvm_field_int (force_retry_pulse,  UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name = "ahb_bus_item");
            super.new(name);
        endfunction
        static function string event_name(bus_event_e e);
            case (e)
                EV_MASTER_CHG  : return "MASTER_CHG";
                EV_SEL_CHG     : return "SEL_CHG";
                EV_FORCE_HOOK  : return "FORCE_HOOK";
                EV_BUS_SNAPSHOT: return "SNAPSHOT";
                default        : return "?";
            endcase
        endfunction
    endclass : ahb_bus_item
