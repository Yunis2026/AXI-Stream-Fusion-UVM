/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : router_coverage_pkg.sv
 *
 * Description:
 *   Transaction-level functional coverage for the
 *   buffered APB-controlled AXI-Stream router.
 *
 * Coverage dimensions:
 *   - Packet destination
 *   - Destination x packet length
 *   - Destination x final TKEEP category
 *   - Invalid APB accesses
 *   - Mid-packet APB route updates
 *   - AXI source and output backpressure
 *   - Simultaneously pending output transactions
 *
 * Implementation:
 *   Explicit functional coverage counters are used
 *   for portable Verilator/UVM execution.
 *
 * This does not generate a native UCIS coverage database.
 */

package router_coverage_pkg;

    import uvm_pkg::*;
    import axis_pkg::*;
    import apb_pkg::*;
    import router_dynamic_pkg::*;
    import router_stress_pkg::*;

    `include "uvm_macros.svh"

    // Independent analysis implementation ports.
    `uvm_analysis_imp_decl(_cov_input)
    `uvm_analysis_imp_decl(_cov_apb)

    // ==================================================
    // 1. FUNCTIONAL COVERAGE COLLECTOR
    // ==================================================

    class router_functional_coverage extends uvm_component;

        `uvm_component_utils(router_functional_coverage)

        // ----------------------------------------------
        // Analysis implementation ports
        // ----------------------------------------------

        uvm_analysis_imp_cov_input #(
            axis_beat_item,
            router_functional_coverage
        ) input_imp;

        uvm_analysis_imp_cov_apb #(
            apb_item,
            router_functional_coverage
        ) apb_imp;

        // ----------------------------------------------
        // Physical interfaces for protocol sampling
        // ----------------------------------------------

        virtual axis_if src_vif;
        virtual axis_if out0_vif;
        virtual axis_if out1_vif;

        // ----------------------------------------------
        // Reference-model coverage state
        // ----------------------------------------------

        bit apb_route = 1'b0;

        bit in_packet = 1'b0;
        bit packet_route = 1'b0;

        int unsigned current_packet_length = 0;

        // ----------------------------------------------
        // Packet coverage counters
        // ----------------------------------------------

        // Index 0: Output 0
        // Index 1: Output 1
        int unsigned packet_count[2];

        int unsigned input_beat_count = 0;

        // Packet length categories:
        //   0: Short  (1 beat)
        //   1: Medium (2-4 beats)
        //   2: Long   (5+ beats)
        int unsigned length_cross[2][3];

        // Final TKEEP categories:
        //   0: Full    (4'hF)
        //   1: Partial (all other values)
        int unsigned keep_cross[2][2];

        // ----------------------------------------------
        // APB coverage counters
        // ----------------------------------------------

        int unsigned apb_count = 0;
        int unsigned valid_apb_writes = 0;
        int unsigned invalid_apb_accesses = 0;
        int unsigned midpacket_route_updates = 0;

        // ----------------------------------------------
        // Backpressure coverage counters
        // ----------------------------------------------

        int unsigned source_stall_cycles = 0;
        int unsigned output0_stall_cycles = 0;
        int unsigned output1_stall_cycles = 0;

        int unsigned dual_output_pending_cycles = 0;

        // ----------------------------------------------
        // Constructor
        // ----------------------------------------------

        function new(
            string name = "router_functional_coverage",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // ----------------------------------------------
        // Build phase
        // ----------------------------------------------

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            input_imp = new("input_imp", this);
            apb_imp   = new("apb_imp", this);

        endfunction

        // ==============================================
        // 2. APB TRANSACTION COVERAGE
        // ==============================================

        function void write_cov_apb(apb_item item);

            apb_count++;

            // Count slave error responses.
            if (item.slverr === 1'b1) begin

                invalid_apb_accesses++;

            end

            // Track valid writes to the route register.
            if (
                item.write  == 1'b1 &&
                item.addr   == 8'h00 &&
                item.slverr == 1'b0
            ) begin

                valid_apb_writes++;

                // Count an actual route change while
                // an AXI packet remains unfinished.
                if (
                    in_packet &&
                    item.wdata[0] != apb_route
                ) begin

                    midpacket_route_updates++;

                end

                // Update the configuration state.
                // The current packet remains locked
                // to packet_route until TLAST.
                apb_route = item.wdata[0];

            end

        endfunction

        // ==============================================
        // 3. AXI INPUT TRANSACTION COVERAGE
        // ==============================================

        function void write_cov_input(axis_beat_item item);

            bit selected_route;
            int length_category;
            int keep_category;

            // Determine the effective route at the
            // moment this input beat is accepted.
            selected_route = in_packet
                           ? packet_route
                           : apb_route;

            // A new packet starts when no packet
            // is currently active.
            if (!in_packet) begin

                packet_route = selected_route;
                current_packet_length = 0;

            end

            // Count the accepted input beat.
            input_beat_count++;
            current_packet_length++;

            // TLAST marks a completed packet.
            if (item.tlast) begin

                // --------------------------------------
                // Packet destination coverage
                // --------------------------------------

                packet_count[selected_route]++;

                // --------------------------------------
                // Packet length coverage
                // --------------------------------------

                if (current_packet_length == 1) begin

                    length_category = 0;

                end
                else if (current_packet_length <= 4) begin

                    length_category = 1;

                end
                else begin

                    length_category = 2;

                end

                length_cross[selected_route]
                            [length_category]++;

                // --------------------------------------
                // Final beat TKEEP coverage
                // --------------------------------------

                keep_category =
                    (item.tkeep == 4'hF) ? 0 : 1;

                keep_cross[selected_route]
                          [keep_category]++;

                // --------------------------------------
                // Release packet tracking state
                // --------------------------------------

                in_packet = 1'b0;
                current_packet_length = 0;

            end
            else begin

                // Maintain the locked route until
                // the final beat is accepted.
                in_packet = 1'b1;

            end

        endfunction

        // ==============================================
        // 4. BACKPRESSURE COVERAGE
        // ==============================================

        task run_phase(uvm_phase phase);

            forever begin

                @(posedge src_vif.aclk);

                if (src_vif.aresetn !== 1'b1) begin
                    continue;
                end

                // Source presented a beat but the
                // router was unable to accept it.
                if (
                    src_vif.tvalid === 1'b1 &&
                    src_vif.tready === 1'b0
                ) begin

                    source_stall_cycles++;

                end

                // Output 0 has valid data but its
                // downstream consumer is not ready.
                if (
                    out0_vif.tvalid === 1'b1 &&
                    out0_vif.tready === 1'b0
                ) begin

                    output0_stall_cycles++;

                end

                // Output 1 has valid data but its
                // downstream consumer is not ready.
                if (
                    out1_vif.tvalid === 1'b1 &&
                    out1_vif.tready === 1'b0
                ) begin

                    output1_stall_cycles++;

                end

                // Both output interfaces contain
                // valid pending transactions.
                if (
                    out0_vif.tvalid === 1'b1 &&
                    out1_vif.tvalid === 1'b1
                ) begin

                    dual_output_pending_cycles++;

                end

            end

        endtask

        // ==============================================
        // 5. COUNT COVERED FUNCTIONAL BINS
        // ==============================================

        function int unsigned get_hit_bins();

            int unsigned hits;

            hits = 0;

            // Two destination bins.
            for (int route = 0; route < 2; route++) begin

                if (packet_count[route] > 0) begin
                    hits++;
                end

                // Three length bins per destination.
                for (int len = 0; len < 3; len++) begin

                    if (length_cross[route][len] > 0) begin
                        hits++;
                    end

                end

                // Two final TKEEP bins per destination.
                for (int keep = 0; keep < 2; keep++) begin

                    if (keep_cross[route][keep] > 0) begin
                        hits++;
                    end

                end

            end

            // APB coverage bins.
            if (invalid_apb_accesses > 0) begin
                hits++;
            end

            if (midpacket_route_updates > 0) begin
                hits++;
            end

            // Backpressure coverage bins.
            if (source_stall_cycles > 0) begin
                hits++;
            end

            if (output0_stall_cycles > 0) begin
                hits++;
            end

            if (output1_stall_cycles > 0) begin
                hits++;
            end

            // Simultaneous valid outputs.
            if (dual_output_pending_cycles > 0) begin
                hits++;
            end

            return hits;

        endfunction

        // ----------------------------------------------
        // Total defined coverage bins
        // ----------------------------------------------

        function int unsigned get_total_bins();

            // Destination          : 2
            // Route x Length       : 6
            // Route x Final TKEEP  : 4
            // APB                  : 2
            // Backpressure         : 3
            // Dual pending outputs : 1
            return 18;

        endfunction

        // ==============================================
        // 6. CHECK ESSENTIAL COVERAGE CONDITIONS
        // ==============================================

        function bit essential_coverage_hit();

            // Both destinations must receive packets.
            if (
                packet_count[0] == 0 ||
                packet_count[1] == 0
            ) begin
                return 1'b0;
            end

            // Require real APB and packet-lock exercise.
            if (
                invalid_apb_accesses == 0 ||
                midpacket_route_updates == 0
            ) begin
                return 1'b0;
            end

            // All three backpressure conditions
            // must have occurred.
            if (
                source_stall_cycles == 0 ||
                output0_stall_cycles == 0 ||
                output1_stall_cycles == 0
            ) begin
                return 1'b0;
            end

            // At least one cycle must have pending
            // data on both output channels.
            if (dual_output_pending_cycles == 0) begin
                return 1'b0;
            end

            return 1'b1;

        endfunction

        // ==============================================
        // 7. PRINT COMPLETE COVERAGE RESULTS
        // ==============================================

        function void print_coverage();

            int unsigned hit_bins;
            int unsigned total_bins;
            real percentage;

            hit_bins   = get_hit_bins();
            total_bins = get_total_bins();

            percentage =
                100.0 * real'(hit_bins) / real'(total_bins);

            `uvm_info(
                "COVERAGE",
                $sformatf(
                    "Packets: route0=%0d route1=%0d total=%0d",
                    packet_count[0],
                    packet_count[1],
                    packet_count[0] + packet_count[1]
                ),
                UVM_NONE
            )

            // Print destination x length cross bins.
            for (int route = 0; route < 2; route++) begin

                `uvm_info(
                    "COVERAGE",
                    $sformatf(
                        "ROUTE_%0d_LENGTH short=%0d medium=%0d long=%0d",
                        route,
                        length_cross[route][0],
                        length_cross[route][1],
                        length_cross[route][2]
                    ),
                    UVM_NONE
                )

                `uvm_info(
                    "COVERAGE",
                    $sformatf(
                        "ROUTE_%0d_FINAL_KEEP full=%0d partial=%0d",
                        route,
                        keep_cross[route][0],
                        keep_cross[route][1]
                    ),
                    UVM_NONE
                )

            end

            `uvm_info(
                "COVERAGE",
                $sformatf(
                    "APB_COVERAGE total=%0d valid_writes=%0d invalid_accesses=%0d midpacket_updates=%0d",
                    apb_count,
                    valid_apb_writes,
                    invalid_apb_accesses,
                    midpacket_route_updates
                ),
                UVM_NONE
            )

            `uvm_info(
                "COVERAGE",
                $sformatf(
                    "STALL_COVERAGE source=%0d out0=%0d out1=%0d dual_pending=%0d",
                    source_stall_cycles,
                    output0_stall_cycles,
                    output1_stall_cycles,
                    dual_output_pending_cycles
                ),
                UVM_NONE
            )

            `uvm_info(
                "COVERAGE",
                $sformatf(
                    "COVERAGE_SUMMARY hit=%0d total=%0d percentage=%0.2f",
                    hit_bins,
                    total_bins,
                    percentage
                ),
                UVM_NONE
            )

            // Report uncovered cross bins explicitly.
            for (int route = 0; route < 2; route++) begin

                for (int len = 0; len < 3; len++) begin

                    if (length_cross[route][len] == 0) begin

                        `uvm_info(
                            "COVERAGE_HOLE",
                            $sformatf(
                                "Uncovered route=%0d length_category=%0d",
                                route,
                                len
                            ),
                            UVM_NONE
                        )

                    end

                end

                for (int keep = 0; keep < 2; keep++) begin

                    if (keep_cross[route][keep] == 0) begin

                        `uvm_info(
                            "COVERAGE_HOLE",
                            $sformatf(
                                "Uncovered route=%0d final_keep_category=%0d",
                                route,
                                keep
                            ),
                            UVM_NONE
                        )

                    end

                end

            end

        endfunction

    endclass

    // ==================================================
    // 8. COVERAGE-ENABLED STRESS TEST
    // ==================================================

    class router_coverage_test extends router_stress_test;

        `uvm_component_utils(router_coverage_test)

        router_functional_coverage coverage;

        // ----------------------------------------------
        // Constructor
        // ----------------------------------------------

        function new(
            string name = "router_coverage_test",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // ----------------------------------------------
        // Build phase
        // ----------------------------------------------

        function void build_phase(uvm_phase phase);

            // Build all components from the existing
            // router_stress_test first.
            super.build_phase(phase);

            coverage = router_functional_coverage::type_id::create(
                "coverage",
                this
            );

        endfunction

        // ----------------------------------------------
        // Connect phase
        // ----------------------------------------------

        function void connect_phase(uvm_phase phase);

            super.connect_phase(phase);

            // Subscribe to accepted AXI input beats.
            input_mon.ap.connect(
                coverage.input_imp
            );

            // Subscribe to completed APB transfers.
            cfg_agent.monitor.ap.connect(
                coverage.apb_imp
            );

            // Provide interfaces for cycle-level
            // backpressure observation.
            coverage.src_vif  = src_vif;
            coverage.out0_vif = out0_vif;
            coverage.out1_vif = out1_vif;

        endfunction

        // ----------------------------------------------
        // Run phase
        // ----------------------------------------------

        task run_phase(uvm_phase phase);

            // Hold an additional objection so the UVM
            // phase remains alive after the inherited
            // stress test completes.
            phase.raise_objection(this);

            `uvm_info(
                "COVERAGE",
                "Starting coverage-enabled router stress test",
                UVM_LOW
            )

            // Reuse every previously passing stress
            // scenario without duplicating its code.
            super.run_phase(phase);

            // Allow the final clock observations to
            // settle before producing coverage results.
            #1;

            // Confirm every input beat was observed.
            if (
                coverage.input_beat_count !=
                scoreboard.input_count
            ) begin

                `uvm_fatal(
                    "COVERAGE",
                    "Coverage input beat count mismatch"
                )

            end

            // One FIFO-full packet, two independent
            // output packets, and thirty random packets.
            if (
                coverage.packet_count[0] +
                coverage.packet_count[1] != 33
            ) begin

                `uvm_fatal(
                    "COVERAGE",
                    "Expected 33 completed AXI packets"
                )

            end

            // APB monitor and coverage collector
            // must observe the same transactions.
            if (
                coverage.apb_count !=
                cfg_agent.monitor.observed_count
            ) begin

                `uvm_fatal(
                    "COVERAGE",
                    "Coverage APB transaction count mismatch"
                )

            end

            // Print per-bin hit counts and percentage.
            coverage.print_coverage();

            // Require critical functional scenarios.
            if (!coverage.essential_coverage_hit()) begin

                `uvm_fatal(
                    "COVERAGE",
                    "Essential functional coverage not achieved"
                )

            end

            `uvm_info(
                "COVERAGE",
                "ROUTER_COVERAGE_UVM_PASS",
                UVM_NONE
            )

            phase.drop_objection(this);

        endtask

    endclass

endpackage