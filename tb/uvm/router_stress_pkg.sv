/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : router_stress_pkg.sv
 *
 * Description:
 *   Directed and constrained-random UVM stress tests.
 *
 * Tests:
 *   S01 - FIFO full and upstream backpressure
 *   S02 - Independent output backpressure
 *   S03 - Random packets, routes, TKEEP and TREADY
 *
 * The existing dynamic routing scoreboard is reused.
 */

package router_stress_pkg;

    import uvm_pkg::*;
    import axis_pkg::*;
    import apb_pkg::*;
    import router_dynamic_pkg::*;

    `include "uvm_macros.svh"

    class router_stress_test extends uvm_test;

        `uvm_component_utils(router_stress_test)

        // ----------------------------------------------
        // Verification components
        // ----------------------------------------------

        axis_sequencer     axis_sqr;
        axis_source_driver axis_drv;

        axis_output_monitor input_mon;
        axis_output_monitor output0_mon;
        axis_output_monitor output1_mon;

        apb_agent cfg_agent;

        router_dynamic_scoreboard scoreboard;

        // ----------------------------------------------
        // Physical interfaces
        // ----------------------------------------------

        virtual axis_if src_vif;
        virtual axis_if out0_vif;
        virtual axis_if out1_vif;

        // ----------------------------------------------
        // Ready controller modes
        // ----------------------------------------------

        localparam int READY_ALL    = 0;
        localparam int STALL_OUT0   = 1;
        localparam int STALL_OUT1   = 2;
        localparam int READY_RANDOM = 3;

        int ready_mode = READY_ALL;

        // ----------------------------------------------
        // Expected transaction counters
        // ----------------------------------------------

        int unsigned expected_axi_count = 0;
        int unsigned expected_apb_count = 0;
        int unsigned expected_apb_errors = 0;

        // ----------------------------------------------
        // Backpressure statistics
        // ----------------------------------------------

        int unsigned source_stall_cycles = 0;
        int unsigned output0_stall_cycles = 0;
        int unsigned output1_stall_cycles = 0;

        int unsigned random_output0_stalls = 0;
        int unsigned random_output1_stalls = 0;

        bit fifo_full_verified = 1'b0;

        // ----------------------------------------------
        // Previous-cycle stall tracking
        // ----------------------------------------------

        bit src_prev_stall = 1'b0;
        bit out0_prev_stall = 1'b0;
        bit out1_prev_stall = 1'b0;

        logic [31:0] src_prev_data;
        logic [3:0]  src_prev_keep;
        logic        src_prev_last;

        logic [31:0] out0_prev_data;
        logic [3:0]  out0_prev_keep;
        logic        out0_prev_last;

        logic [31:0] out1_prev_data;
        logic [3:0]  out1_prev_keep;
        logic        out1_prev_last;

        // ----------------------------------------------
        // Constructor
        // ----------------------------------------------

        function new(
            string name = "router_stress_test",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // ----------------------------------------------
        // Build phase
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

            if (!uvm_config_db#(virtual axis_if)::get(
                this, "", "src_vif", src_vif
            )) begin
                `uvm_fatal("STRESS", "Source interface missing")
            end

            if (!uvm_config_db#(virtual axis_if)::get(
                this, "", "out0_vif", out0_vif
            )) begin
                `uvm_fatal("STRESS", "Output 0 interface missing")
            end

            if (!uvm_config_db#(virtual axis_if)::get(
                this, "", "out1_vif", out1_vif
            )) begin
                `uvm_fatal("STRESS", "Output 1 interface missing")
            end

        endfunction

        // ----------------------------------------------
        // Connect phase
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

        // ==============================================
        // READY CONTROLLER
        // ==============================================

        task automatic ready_controller();

            forever begin

                // Change TREADY away from the sampling edge.
                @(negedge src_vif.aclk);

                case (ready_mode)

                    READY_ALL: begin
                        out0_vif.tready = 1'b1;
                        out1_vif.tready = 1'b1;
                    end

                    STALL_OUT0: begin
                        out0_vif.tready = 1'b0;
                        out1_vif.tready = 1'b1;
                    end

                    STALL_OUT1: begin
                        out0_vif.tready = 1'b1;
                        out1_vif.tready = 1'b0;
                    end

                    READY_RANDOM: begin

                        // Independent random acceptance.
                        // Approximately 55% READY probability.
                        out0_vif.tready =
                            ($urandom_range(0, 99) < 55);

                        out1_vif.tready =
                            ($urandom_range(0, 99) < 55);

                    end

                    default: begin
                        out0_vif.tready = 1'b1;
                        out1_vif.tready = 1'b1;
                    end

                endcase

            end

        endtask

        // ==============================================
        // PROTOCOL STABILITY CHECKER
        // ==============================================

        task automatic check_stability();

            forever begin

                @(posedge src_vif.aclk);

                if (src_vif.aresetn !== 1'b1) begin

                    src_prev_stall = 1'b0;
                    out0_prev_stall = 1'b0;
                    out1_prev_stall = 1'b0;

                    continue;

                end

                // --------------------------------------
                // Source interface stability
                // --------------------------------------

                // When the previous rising edge was
                // stalled, VALID and payload must remain
                // unchanged through this rising edge.
                if (src_prev_stall) begin

                    if (
                        src_vif.tvalid !== 1'b1 ||
                        src_vif.tdata !== src_prev_data ||
                        src_vif.tkeep !== src_prev_keep ||
                        src_vif.tlast !== src_prev_last
                    ) begin

                        `uvm_fatal(
                            "AXIS_PROTOCOL",
                            "Source changed VALID/payload during stall"
                        )

                    end

                end

                src_prev_stall =
                    (src_vif.tvalid === 1'b1 &&
                     src_vif.tready === 1'b0);

                src_prev_data = src_vif.tdata;
                src_prev_keep = src_vif.tkeep;
                src_prev_last = src_vif.tlast;

                if (src_prev_stall) begin
                    source_stall_cycles++;
                end

                // --------------------------------------
                // Output 0 stability
                // --------------------------------------

                if (out0_prev_stall) begin

                    if (
                        out0_vif.tvalid !== 1'b1 ||
                        out0_vif.tdata !== out0_prev_data ||
                        out0_vif.tkeep !== out0_prev_keep ||
                        out0_vif.tlast !== out0_prev_last
                    ) begin

                        `uvm_fatal(
                            "AXIS_PROTOCOL",
                            "Output 0 changed VALID/payload during stall"
                        )

                    end

                end

                out0_prev_stall =
                    (out0_vif.tvalid === 1'b1 &&
                     out0_vif.tready === 1'b0);

                out0_prev_data = out0_vif.tdata;
                out0_prev_keep = out0_vif.tkeep;
                out0_prev_last = out0_vif.tlast;

                if (out0_prev_stall) begin

                    output0_stall_cycles++;

                    if (ready_mode == READY_RANDOM) begin
                        random_output0_stalls++;
                    end

                end

                // --------------------------------------
                // Output 1 stability
                // --------------------------------------

                if (out1_prev_stall) begin

                    if (
                        out1_vif.tvalid !== 1'b1 ||
                        out1_vif.tdata !== out1_prev_data ||
                        out1_vif.tkeep !== out1_prev_keep ||
                        out1_vif.tlast !== out1_prev_last
                    ) begin

                        `uvm_fatal(
                            "AXIS_PROTOCOL",
                            "Output 1 changed VALID/payload during stall"
                        )

                    end

                end

                out1_prev_stall =
                    (out1_vif.tvalid === 1'b1 &&
                     out1_vif.tready === 1'b0);

                out1_prev_data = out1_vif.tdata;
                out1_prev_keep = out1_vif.tkeep;
                out1_prev_last = out1_vif.tlast;

                if (out1_prev_stall) begin

                    output1_stall_cycles++;

                    if (ready_mode == READY_RANDOM) begin
                        random_output1_stalls++;
                    end

                end

            end

        endtask

        // ==============================================
        // AXI BEAT SEQUENCE HELPER
        // ==============================================

        task automatic send_beat(
            input bit [31:0] data,
            input bit [3:0]  keep,
            input bit        last
        );

            router_axis_beat_sequence seq;

            seq = router_axis_beat_sequence::type_id::create(
                "stress_axis_beat"
            );

            seq.payload = data;
            seq.keep_mask = keep;
            seq.last = last;

            // Completion requires a real AXI handshake.
            seq.start(axis_sqr);

            expected_axi_count++;

        endtask

        // ==============================================
        // APB ACCESS SEQUENCE HELPER
        // ==============================================

        task automatic apb_access(
            input bit        write,
            input bit [7:0]  addr,
            input bit [31:0] data,
            input bit        error_expected,
            input bit [31:0] read_expected
        );

            router_apb_access_sequence seq;

            seq = router_apb_access_sequence::type_id::create(
                "stress_apb_access"
            );

            seq.do_write       = write;
            seq.address        = addr;
            seq.write_data     = data;
            seq.expected_error = error_expected;
            seq.expected_read  = read_expected;

            seq.start(cfg_agent.sequencer);

            expected_apb_count++;

            if (error_expected) begin
                expected_apb_errors++;
            end

        endtask

        // ==============================================
        // S01: FIFO FULL AND BACKPRESSURE
        // ==============================================

        task automatic test_fifo_full();

            `uvm_info(
                "STRESS",
                "S01: Starting FIFO full test",
                UVM_LOW
            )

            // Block Output 0 completely.
            ready_mode = STALL_OUT0;

            repeat (2) @(posedge src_vif.aclk);

            // Fill all four FIFO entries.
            send_beat(32'h0000_F001, 4'hF, 1'b0);
            send_beat(32'h0000_F002, 4'hF, 1'b0);
            send_beat(32'h0000_F003, 4'hF, 1'b0);
            send_beat(32'h0000_F004, 4'hF, 1'b0);

            // Attempt the fifth beat while FIFO is full.
            // One thread drives the beat; the other
            // verifies that it remains blocked.
            fork

                begin

                    send_beat(
                        32'h0000_F005,
                        4'h3,
                        1'b1
                    );

                end

                begin

                    // Wait until the fifth beat is
                    // presented and upstream is blocked.
                    wait (
                        src_vif.tvalid === 1'b1 &&
                        src_vif.tready === 1'b0
                    );

                    repeat (4) begin

                        @(posedge src_vif.aclk);

                        if (
                            src_vif.tvalid !== 1'b1 ||
                            src_vif.tready !== 1'b0 ||
                            src_vif.tdata  !== 32'h0000_F005 ||
                            src_vif.tkeep  !== 4'h3 ||
                            src_vif.tlast  !== 1'b1
                        ) begin

                            `uvm_fatal(
                                "STRESS",
                                "FIFO full did not block fifth beat correctly"
                            )

                        end

                    end

                    if (scoreboard.output0_count != 0) begin

                        `uvm_fatal(
                            "STRESS",
                            "Output 0 transferred while TREADY was low"
                        )

                    end

                    fifo_full_verified = 1'b1;

                    // Release backpressure.
                    ready_mode = READY_ALL;

                end

            join

            // Drain all five expected beats.
            wait (scoreboard.matched_count == 5);

            `uvm_info(
                "STRESS",
                "[PASS] S01 FIFO full and fifth-beat stall",
                UVM_LOW
            )

        endtask

        // ==============================================
        // S02: INDEPENDENT OUTPUT BACKPRESSURE
        // ==============================================

        task automatic test_independent_outputs();

            `uvm_info(
                "STRESS",
                "S02: Starting independent backpressure test",
                UVM_LOW
            )

            // Route the next packet to Output 1.
            apb_access(
                1'b1, 8'h00, 32'h0000_0001,
                1'b0, 32'h0000_0000
            );

            // Block Output 1 while Output 0 stays ready.
            ready_mode = STALL_OUT1;

            repeat (2) @(posedge src_vif.aclk);

            // Queue three beats in Output 1.
            send_beat(32'h0000_A101, 4'hF, 1'b0);
            send_beat(32'h0000_A102, 4'hF, 1'b0);
            send_beat(32'h0000_A103, 4'h3, 1'b1);

            // Reconfigure routing to Output 0.
            apb_access(
                1'b1, 8'h00, 32'h0000_0000,
                1'b0, 32'h0000_0000
            );

            // Output 0 must continue functioning
            // even though Output 1 is stalled.
            send_beat(32'h0000_B101, 4'hF, 1'b0);
            send_beat(32'h0000_B102, 4'h3, 1'b1);

            wait (scoreboard.output0_count == 7);

            if (scoreboard.output1_count != 0) begin

                `uvm_fatal(
                    "STRESS",
                    "Output 1 transferred despite backpressure"
                )

            end

            // Release Output 1 and drain its FIFO.
            ready_mode = READY_ALL;

            wait (scoreboard.matched_count == 10);

            `uvm_info(
                "STRESS",
                "[PASS] S02 independent FIFO backpressure",
                UVM_LOW
            )

        endtask

        // ==============================================
        // S03: RANDOM TRAFFIC AND BACKPRESSURE
        // ==============================================

        task automatic test_random_traffic();

            bit route;
            bit [3:0] keep;
            bit [31:0] data;

            int packet_length;

            `uvm_info(
                "STRESS",
                "S03: Starting randomized packet stress",
                UVM_LOW
            )

            ready_mode = READY_RANDOM;

            // Generate 30 packets with independent
            // route choices and random packet lengths.
            for (int p = 0; p < 30; p++) begin

                route = 1'($urandom_range(0, 1));

                packet_length = int'($urandom_range(1, 8));

                // Every fourth packet must contain
                // multiple beats for a mid-packet update.
                if ((p % 4) == 0 && packet_length < 2) begin
                    packet_length = 2;
                end

                // Select the destination using APB.
                apb_access(
                    1'b1,
                    8'h00,
                    {31'b0, route},
                    1'b0,
                    32'h0000_0000
                );

                // Exercise invalid APB writes and
                // confirm that they do not change route.
                if ((p % 6) == 0) begin

                    apb_access(
                        1'b1,
                        8'h04,
                        32'hFFFF_FFFF,
                        1'b1,
                        32'h0000_0000
                    );

                    apb_access(
                        1'b0,
                        8'h00,
                        32'h0000_0000,
                        1'b0,
                        {31'b0, route}
                    );

                end

                // Generate one complete AXI packet.
                for (int b = 0; b < packet_length; b++) begin

                    // Non-final beats use all bytes.
                    // Final beats use a random nonzero mask.
                    keep = (b == packet_length - 1)
                         ? 4'($urandom_range(1, 15))
                         : 4'hF;

                    data = 32'h5500_0000 |
                           (32'(p) << 8) |
                           32'(b);

                    send_beat(
                        data,
                        keep,
                        (b == packet_length - 1)
                    );

                    // Change the APB route after the
                    // first beat of every fourth packet.
                    // Remaining beats must keep the
                    // original packet destination.
                    if (b == 0 && (p % 4) == 0) begin

                        apb_access(
                            1'b1,
                            8'h00,
                            {31'b0, !route},
                            1'b0,
                            32'h0000_0000
                        );

                    end

                end

            end

            // Stop random stalls and drain both FIFOs.
            ready_mode = READY_ALL;

            wait (
                scoreboard.matched_count == expected_axi_count
            );

            `uvm_info(
                "STRESS",
                "[PASS] S03 randomized packet stress",
                UVM_LOW
            )

        endtask

        // ==============================================
        // MAIN TEST
        // ==============================================

        task run_phase(uvm_phase phase);

            phase.raise_objection(this);

            // Initialize both sinks to ready.
            out0_vif.tready = 1'b1;
            out1_vif.tready = 1'b1;

            ready_mode = READY_ALL;

            // Run independent sink control and
            // AXI protocol checking in parallel.
            fork
                ready_controller();
                check_stability();
            join_none

            // Wait until reset has been released.
            wait (src_vif.aresetn === 1'b1);

            // Confirm reset route using APB readback.
            apb_access(
                1'b0,
                8'h00,
                32'h0000_0000,
                1'b0,
                32'h0000_0000
            );

            test_fifo_full();

            test_independent_outputs();

            test_random_traffic();

            // Let the output monitors detect any
            // unexpected duplicate transactions.
            repeat (5) @(posedge src_vif.aclk);

            // ------------------------------------------
            // Final transaction checks
            // ------------------------------------------

            if (!fifo_full_verified) begin
                `uvm_fatal(
                    "STRESS",
                    "FIFO full condition was not verified"
                )
            end

            if (
                axis_drv.driven_count != expected_axi_count ||
                input_mon.observed_count != expected_axi_count ||
                scoreboard.input_count != expected_axi_count ||
                scoreboard.matched_count != expected_axi_count
            ) begin

                `uvm_fatal(
                    "STRESS",
                    "AXI transaction count mismatch"
                )

            end

            if (
                output0_mon.observed_count != scoreboard.output0_count ||
                output1_mon.observed_count != scoreboard.output1_count
            ) begin

                `uvm_fatal(
                    "STRESS",
                    "Output monitor count mismatch"
                )

            end

            if (
                scoreboard.output0_count +
                scoreboard.output1_count != expected_axi_count
            ) begin

                `uvm_fatal(
                    "STRESS",
                    "Output counts do not match accepted inputs"
                )

            end

            if (
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "STRESS",
                    "Expected queues or packet state not empty"
                )

            end

            // ------------------------------------------
            // Final APB checks
            // ------------------------------------------

            if (
                cfg_agent.driver.completed_count != expected_apb_count ||
                cfg_agent.monitor.observed_count != expected_apb_count ||
                scoreboard.apb_count != expected_apb_count ||
                scoreboard.apb_error_count != expected_apb_errors
            ) begin

                `uvm_fatal(
                    "STRESS",
                    "APB transaction count mismatch"
                )

            end

            // ------------------------------------------
            // Final backpressure checks
            // ------------------------------------------

            if (
                source_stall_cycles == 0 ||
                output0_stall_cycles == 0 ||
                output1_stall_cycles == 0 ||
                random_output0_stalls == 0 ||
                random_output1_stalls == 0
            ) begin

                `uvm_fatal(
                    "STRESS",
                    "Insufficient backpressure was exercised"
                )

            end

            `uvm_info(
                "STRESS",
                $sformatf(
                    "STRESS_SUMMARY axi=%0d out0=%0d out1=%0d apb=%0d apb_errors=%0d source_stalls=%0d out0_stalls=%0d out1_stalls=%0d",
                    expected_axi_count,
                    scoreboard.output0_count,
                    scoreboard.output1_count,
                    expected_apb_count,
                    expected_apb_errors,
                    source_stall_cycles,
                    output0_stall_cycles,
                    output1_stall_cycles
                ),
                UVM_NONE
            )

            `uvm_info(
                "STRESS",
                "ROUTER_STRESS_UVM_PASS",
                UVM_NONE
            )

            phase.drop_objection(this);

        endtask

    endclass

endpackage