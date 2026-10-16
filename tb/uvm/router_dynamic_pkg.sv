/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : router_dynamic_pkg.sv
 *
 * Description:
 *   Combined APB and AXI-Stream UVM verification.
 *
 * Features:
 *   - APB-controlled route selection
 *   - Packet-level route locking
 *   - Independent expected output queues
 *   - APB error-response checking
 *   - Input/output beat comparison
 *
 * This test uses always-ready output sinks.
 */

package router_dynamic_pkg;

    import uvm_pkg::*;
    import axis_pkg::*;
    import apb_pkg::*;

    `include "uvm_macros.svh"

    // Independent analysis callbacks for four monitors.
    `uvm_analysis_imp_decl(_dyn_input)
    `uvm_analysis_imp_decl(_dyn_output0)
    `uvm_analysis_imp_decl(_dyn_output1)
    `uvm_analysis_imp_decl(_dyn_apb)

    // ==================================================
    // 1. Dynamic routing scoreboard
    // ==================================================

    class router_dynamic_scoreboard extends uvm_scoreboard;

        `uvm_component_utils(router_dynamic_scoreboard)

        uvm_analysis_imp_dyn_input #(
            axis_beat_item, router_dynamic_scoreboard
        ) input_imp;

        uvm_analysis_imp_dyn_output0 #(
            axis_beat_item, router_dynamic_scoreboard
        ) output0_imp;

        uvm_analysis_imp_dyn_output1 #(
            axis_beat_item, router_dynamic_scoreboard
        ) output1_imp;

        uvm_analysis_imp_dyn_apb #(
            apb_item, router_dynamic_scoreboard
        ) apb_imp;

        axis_beat_item expected_q0[$];
        axis_beat_item expected_q1[$];

        // Independent reference-model state.
        bit route_sel = 1'b0;
        bit in_packet = 1'b0;
        bit locked_route = 1'b0;

        int unsigned input_count = 0;
        int unsigned output0_count = 0;
        int unsigned output1_count = 0;
        int unsigned matched_count = 0;
        int unsigned apb_count = 0;
        int unsigned apb_error_count = 0;

        function new(
            string name = "router_dynamic_scoreboard",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            input_imp   = new("input_imp", this);
            output0_imp = new("output0_imp", this);
            output1_imp = new("output1_imp", this);
            apb_imp     = new("apb_imp", this);

        endfunction

        // ----------------------------------------------
        // Track completed APB transactions
        // ----------------------------------------------

        function void write_dyn_apb(apb_item item);

            apb_count++;

            if (item.slverr) begin
                apb_error_count++;
            end

            // Only a successful write to address 0x00
            // updates the reference-model route.
            if (
                item.write &&
                item.addr == 8'h00 &&
                item.slverr == 1'b0
            ) begin

                route_sel = item.wdata[0];

                `uvm_info(
                    "ROUTER_DYN_SB",
                    $sformatf(
                        "APB updated route selection to %0d",
                        route_sel
                    ),
                    UVM_LOW
                )
            end

        endfunction

        // ----------------------------------------------
        // Predict the destination of each input beat
        // ----------------------------------------------

        function void write_dyn_input(axis_beat_item item);

            axis_beat_item expected;
            bit selected_route;

            selected_route = in_packet
                           ? locked_route
                           : route_sel;

            expected = axis_beat_item::type_id::create(
                "expected"
            );

            expected.copy(item);

            if (selected_route == 1'b0) begin
                expected_q0.push_back(expected);
            end
            else begin
                expected_q1.push_back(expected);
            end

            // Capture the route on the first beat.
            if (!in_packet) begin
                locked_route = selected_route;
            end

            // TLAST ends the packet.
            in_packet = !item.tlast;

            input_count++;

            `uvm_info(
                "ROUTER_DYN_SB",
                $sformatf(
                    "Input %0d -> expected Output %0d: %s",
                    input_count,
                    selected_route,
                    item.convert2string()
                ),
                UVM_LOW
            )

        endfunction

        // ----------------------------------------------
        // Compare actual Output 0 transactions
        // ----------------------------------------------

        function void write_dyn_output0(axis_beat_item actual);

            axis_beat_item expected;

            if (expected_q0.size() == 0) begin
                `uvm_fatal(
                    "ROUTER_DYN_SB",
                    "Unexpected beat on Output 0"
                )
            end

            expected = expected_q0.pop_front();

            if (
                actual.tdata !== expected.tdata ||
                actual.tkeep !== expected.tkeep ||
                actual.tlast !== expected.tlast
            ) begin

                `uvm_fatal(
                    "ROUTER_DYN_SB",
                    $sformatf(
                        "Output 0 mismatch: expected %s, actual %s",
                        expected.convert2string(),
                        actual.convert2string()
                    )
                )
            end

            output0_count++;
            matched_count++;

            `uvm_info(
                "ROUTER_DYN_SB",
                $sformatf(
                    "[MATCH] Output 0 beat %0d",
                    output0_count
                ),
                UVM_LOW
            )

        endfunction

        // ----------------------------------------------
        // Compare actual Output 1 transactions
        // ----------------------------------------------

        function void write_dyn_output1(axis_beat_item actual);

            axis_beat_item expected;

            if (expected_q1.size() == 0) begin
                `uvm_fatal(
                    "ROUTER_DYN_SB",
                    "Unexpected beat on Output 1"
                )
            end

            expected = expected_q1.pop_front();

            if (
                actual.tdata !== expected.tdata ||
                actual.tkeep !== expected.tkeep ||
                actual.tlast !== expected.tlast
            ) begin

                `uvm_fatal(
                    "ROUTER_DYN_SB",
                    $sformatf(
                        "Output 1 mismatch: expected %s, actual %s",
                        expected.convert2string(),
                        actual.convert2string()
                    )
                )
            end

            output1_count++;
            matched_count++;

            `uvm_info(
                "ROUTER_DYN_SB",
                $sformatf(
                    "[MATCH] Output 1 beat %0d",
                    output1_count
                ),
                UVM_LOW
            )

        endfunction

        // ----------------------------------------------
        // Verify all expected beats were consumed
        // ----------------------------------------------

        function void check_phase(uvm_phase phase);

            super.check_phase(phase);

            if (
                expected_q0.size() != 0 ||
                expected_q1.size() != 0
            ) begin

                `uvm_error(
                    "ROUTER_DYN_SB",
                    "Expected queues not empty at test end"
                )
            end

            if (input_count != matched_count) begin

                `uvm_error(
                    "ROUTER_DYN_SB",
                    "Accepted and matched beat counts differ"
                )
            end

            `uvm_info(
                "ROUTER_DYN_SB",
                $sformatf(
                    "Summary: input=%0d output0=%0d output1=%0d matched=%0d apb=%0d errors=%0d",
                    input_count,
                    output0_count,
                    output1_count,
                    matched_count,
                    apb_count,
                    apb_error_count
                ),
                UVM_LOW
            )

        endfunction

    endclass

    // ==================================================
    // 2. Single-beat AXI-Stream sequence
    // ==================================================

    class router_axis_beat_sequence
        extends uvm_sequence #(axis_beat_item);

        `uvm_object_utils(router_axis_beat_sequence)

        bit [31:0] payload;
        bit [3:0]  keep_mask;
        bit        last;

        function new(
            string name = "router_axis_beat_sequence"
        );
            super.new(name);
        endfunction

        virtual task body();

            axis_beat_item req;

            req = axis_beat_item::type_id::create("req");

            start_item(req);

            req.tdata = payload;
            req.tkeep = keep_mask;
            req.tlast = last;

            finish_item(req);

        endtask

    endclass

    // ==================================================
    // 3. Single-transaction APB sequence
    // ==================================================

    class router_apb_access_sequence
        extends uvm_sequence #(apb_item);

        `uvm_object_utils(router_apb_access_sequence)

        bit        do_write;
        bit [7:0]  address;
        bit [31:0] write_data;
        bit        expected_error;
        bit [31:0] expected_read;

        function new(
            string name = "router_apb_access_sequence"
        );
            super.new(name);
        endfunction

        virtual task body();

            apb_item req;

            req = apb_item::type_id::create("req");

            start_item(req);

            req.write = do_write;
            req.addr  = address;
            req.wdata = write_data;

            finish_item(req);

            if (req.slverr !== expected_error) begin
                `uvm_fatal(
                    "ROUTER_APB_SEQ",
                    "APB slave error response mismatch"
                )
            end

            if (
                !do_write &&
                req.rdata !== expected_read
            ) begin

                `uvm_fatal(
                    "ROUTER_APB_SEQ",
                    $sformatf(
                        "Readback mismatch: expected=0x%08h actual=0x%08h",
                        expected_read,
                        req.rdata
                    )
                )
            end

        endtask

    endclass

    // ==================================================
    // 4. Combined APB + AXI UVM test
    // ==================================================

    class router_dynamic_test extends uvm_test;

        `uvm_component_utils(router_dynamic_test)

        axis_sequencer     axis_sqr;
        axis_source_driver axis_drv;

        axis_output_monitor input_mon;
        axis_output_monitor output0_mon;
        axis_output_monitor output1_mon;

        apb_agent cfg_agent;

        router_dynamic_scoreboard scoreboard;

        function new(
            string name = "router_dynamic_test",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // ----------------------------------------------
        // Create the verification components
        // ----------------------------------------------

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            axis_sqr = axis_sequencer::type_id::create(
                "axis_sqr", this
            );

            axis_drv = axis_source_driver::type_id::create(
                "axis_drv", this
            );

            input_mon = axis_output_monitor::type_id::create(
                "input_mon", this
            );

            output0_mon = axis_output_monitor::type_id::create(
                "output0_mon", this
            );

            output1_mon = axis_output_monitor::type_id::create(
                "output1_mon", this
            );

            cfg_agent = apb_agent::type_id::create(
                "cfg_agent", this
            );

            scoreboard = router_dynamic_scoreboard::type_id::create(
                "scoreboard", this
            );

        endfunction

        // ----------------------------------------------
        // Connect the verification components
        // ----------------------------------------------

        function void connect_phase(uvm_phase phase);

            super.connect_phase(phase);

            axis_drv.seq_item_port.connect(
                axis_sqr.seq_item_export
            );

            input_mon.ap.connect(
                scoreboard.input_imp
            );

            output0_mon.ap.connect(
                scoreboard.output0_imp
            );

            output1_mon.ap.connect(
                scoreboard.output1_imp
            );

            cfg_agent.monitor.ap.connect(
                scoreboard.apb_imp
            );

        endfunction

        // ----------------------------------------------
        // Send one AXI-Stream beat
        // ----------------------------------------------

        task automatic send_beat(
            input bit [31:0] data,
            input bit [3:0]  keep,
            input bit        last
        );

            router_axis_beat_sequence seq;

            seq = router_axis_beat_sequence::type_id::create(
                "axis_beat_seq"
            );

            seq.payload   = data;
            seq.keep_mask = keep;
            seq.last      = last;

            seq.start(axis_sqr);

        endtask

        // ----------------------------------------------
        // Execute one APB transfer
        // ----------------------------------------------

        task automatic apb_access(
            input bit        do_write,
            input bit [7:0]  addr,
            input bit [31:0] wdata,
            input bit        error_expected,
            input bit [31:0] read_expected
        );

            router_apb_access_sequence seq;

            seq = router_apb_access_sequence::type_id::create(
                "apb_access_seq"
            );

            seq.do_write       = do_write;
            seq.address        = addr;
            seq.write_data     = wdata;
            seq.expected_error = error_expected;
            seq.expected_read  = read_expected;

            seq.start(cfg_agent.sequencer);

        endtask

        // ----------------------------------------------
        // Execute directed dynamic-routing scenarios
        // ----------------------------------------------

        task run_phase(uvm_phase phase);

            phase.raise_objection(this);

            `uvm_info(
                "ROUTER_TEST",
                "Starting combined APB and AXI verification",
                UVM_LOW
            )

            // ==========================================
            // D01: Route packet B to Output 1
            // ==========================================

            apb_access(
                1'b1, 8'h00, 32'h0000_0001,
                1'b0, 32'h0000_0000
            );

            // Confirm APB readback.
            apb_access(
                1'b0, 8'h00, 32'h0000_0000,
                1'b0, 32'h0000_0001
            );

            send_beat(32'h0000_00B1, 4'hF, 1'b0);
            send_beat(32'h0000_00B2, 4'hF, 1'b0);
            send_beat(32'h0000_00B3, 4'h3, 1'b1);

            `uvm_info(
                "ROUTER_TEST",
                "[PASS] D01 packet B sent with Route 1",
                UVM_LOW
            )

            // ==========================================
            // D02: Route packet C to Output 0
            // ==========================================

            apb_access(
                1'b1, 8'h00, 32'h0000_0000,
                1'b0, 32'h0000_0000
            );

            send_beat(32'h0000_00C1, 4'hF, 1'b0);
            send_beat(32'h0000_00C2, 4'hF, 1'b0);
            send_beat(32'h0000_00C3, 4'h1, 1'b1);

            `uvm_info(
                "ROUTER_TEST",
                "[PASS] D02 packet C sent with Route 0",
                UVM_LOW
            )

            // ==========================================
            // D03: Update APB in the middle of packet D
            // ==========================================

            // First accepted beat locks packet D
            // to Output 0.
            send_beat(32'h0000_00D1, 4'hF, 1'b0);

            // Change ROUTE_SEL to Output 1 while
            // packet D is still unfinished.
            apb_access(
                1'b1, 8'h00, 32'h0000_0001,
                1'b0, 32'h0000_0000
            );

            // Invalid address must not change route.
            apb_access(
                1'b1, 8'h04, 32'h0000_0000,
                1'b1, 32'h0000_0000
            );

            // Confirm that ROUTE_SEL remains 1.
            apb_access(
                1'b0, 8'h00, 32'h0000_0000,
                1'b0, 32'h0000_0001
            );

            // Both remaining beats must follow
            // the locked route to Output 0.
            send_beat(32'h0000_00D2, 4'hF, 1'b0);
            send_beat(32'h0000_00D3, 4'h7, 1'b1);

            `uvm_info(
                "ROUTER_TEST",
                "[PASS] D03 mid-packet APB update exercised",
                UVM_LOW
            )

            // ==========================================
            // D04: Next packet E uses new Route 1
            // ==========================================

            send_beat(32'h0000_00E1, 4'hF, 1'b0);
            send_beat(32'h0000_00E2, 4'h3, 1'b1);

            // Wait until all accepted beats reach
            // their correct destination.
            wait (scoreboard.matched_count == 11);

            // Continue observing for unexpected beats.
            #40;

            // ==========================================
            // Final independent checks
            // ==========================================

            if (
                axis_drv.driven_count       != 11 ||
                input_mon.observed_count    != 11 ||
                output0_mon.observed_count  != 6  ||
                output1_mon.observed_count  != 5
            ) begin

                `uvm_fatal(
                    "ROUTER_TEST",
                    "AXI driver/monitor count mismatch"
                )
            end

            if (
                scoreboard.input_count      != 11 ||
                scoreboard.output0_count    != 6  ||
                scoreboard.output1_count    != 5  ||
                scoreboard.matched_count    != 11 ||
                scoreboard.apb_count        != 6  ||
                scoreboard.apb_error_count  != 1  ||
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "ROUTER_TEST",
                    "Dynamic routing scoreboard mismatch"
                )
            end

            if (
                cfg_agent.driver.completed_count != 6 ||
                cfg_agent.monitor.observed_count  != 6
            ) begin

                `uvm_fatal(
                    "ROUTER_TEST",
                    "APB agent transfer count mismatch"
                )
            end

            `uvm_info(
                "ROUTER_TEST",
                "[PASS] D04 next packet follows updated route",
                UVM_LOW
            )

            `uvm_info(
                "ROUTER_TEST",
                "ROUTER_DYNAMIC_UVM_PASS",
                UVM_NONE
            )

            phase.drop_objection(this);

        endtask

    endclass

endpackage