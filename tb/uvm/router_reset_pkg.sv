/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : router_reset_pkg.sv
 *
 * Description:
 *   Reset-during-traffic UVM verification.
 *
 * Verification objectives:
 *   - Reset while a packet is unfinished
 *   - Reset with buffered, unconsumed AXI beats
 *   - Discard outstanding expected transactions
 *   - Clear packet route-lock state
 *   - Restore APB routing register default
 *   - Prevent stale data after reset
 *   - Verify post-reset AXI/APB functionality
 */

package router_reset_pkg;

    import uvm_pkg::*;
    import axis_pkg::*;
    import apb_pkg::*;
    import router_dynamic_pkg::*;

    `include "uvm_macros.svh"

    // ==================================================
    // 1. RESET-AWARE ROUTER SCOREBOARD
    // ==================================================

    class router_reset_scoreboard
        extends router_dynamic_scoreboard;

        `uvm_component_utils(router_reset_scoreboard)

        // Number of accepted input beats intentionally
        // discarded because of a DUT reset.
        int unsigned reset_discarded_count = 0;

        // Number of explicitly verified runtime resets.
        int unsigned runtime_reset_count = 0;

        function new(
            string name = "router_reset_scoreboard",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // ----------------------------------------------
        // Apply the expected reset behavior
        // ----------------------------------------------

        function void apply_runtime_reset();

            int unsigned pending0;
            int unsigned pending1;

            pending0 = expected_q0.size();
            pending1 = expected_q1.size();

            // Count beats accepted by the router but
            // not yet transferred to either output.
            reset_discarded_count += pending0 + pending1;

            // The hardware FIFOs are reset, so their
            // corresponding expected queues must also
            // be discarded by the reference model.
            expected_q0.delete();
            expected_q1.delete();

            // Reset the APB reference configuration.
            route_sel = 1'b0;

            // Reset packet-boundary and route-lock state.
            in_packet    = 1'b0;
            locked_route = 1'b0;

            runtime_reset_count++;

            `uvm_info(
                "RESET_SB",
                $sformatf(
                    "Reset applied: pending0=%0d pending1=%0d total_discarded=%0d",
                    pending0,
                    pending1,
                    reset_discarded_count
                ),
                UVM_LOW
            )

        endfunction

        // ----------------------------------------------
        // Reset-aware end-of-test accounting
        // ----------------------------------------------

        function void check_phase(uvm_phase phase);

            // The normal dynamic scoreboard requires:
            //
            //     input_count == matched_count
            //
            // That condition is not appropriate when
            // reset intentionally discards buffered
            // transactions. This test checks the
            // reset-aware accounting equation instead.

            if (
                expected_q0.size() != 0 ||
                expected_q1.size() != 0
            ) begin

                `uvm_error(
                    "RESET_SB",
                    "Expected queues not empty at test end"
                )

            end

            if (
                input_count !=
                matched_count + reset_discarded_count
            ) begin

                `uvm_error(
                    "RESET_SB",
                    $sformatf(
                        "Accounting mismatch: input=%0d matched=%0d reset_discarded=%0d",
                        input_count,
                        matched_count,
                        reset_discarded_count
                    )
                )

            end

            if (in_packet) begin

                `uvm_error(
                    "RESET_SB",
                    "Packet state remains active at test end"
                )

            end

            `uvm_info(
                "RESET_SB",
                $sformatf(
                    "RESET_SUMMARY input=%0d matched=%0d discarded=%0d output0=%0d output1=%0d apb=%0d resets=%0d",
                    input_count,
                    matched_count,
                    reset_discarded_count,
                    output0_count,
                    output1_count,
                    apb_count,
                    runtime_reset_count
                ),
                UVM_NONE
            )

        endfunction

    endclass

    // ==================================================
    // 2. RESET-DURING-TRAFFIC UVM TEST
    // ==================================================

    class router_reset_test extends router_dynamic_test;

        `uvm_component_utils(router_reset_test)

        // ----------------------------------------------
        // Interfaces
        // ----------------------------------------------

        virtual router_reset_if reset_vif;

        virtual axis_if src_vif;
        virtual axis_if out0_vif;
        virtual axis_if out1_vif;

        // Reset-aware scoreboard handle.
        router_reset_scoreboard reset_sb;

        function new(
            string name = "router_reset_test",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // ----------------------------------------------
        // Build phase
        // ----------------------------------------------

        function void build_phase(uvm_phase phase);

            // Replace the standard dynamic scoreboard
            // with a reset-aware derived implementation
            // through the UVM factory.
            router_dynamic_scoreboard::type_id::set_type_override(
                router_reset_scoreboard::get_type()
            );

            // Build existing AXI/APB UVM components.
            super.build_phase(phase);

            // Obtain the reset request interface.
            if (!uvm_config_db#(virtual router_reset_if)::get(
                this,
                "",
                "reset_vif",
                reset_vif
            )) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "Reset control interface not found"
                )

            end

            // Obtain the AXI source interface.
            if (!uvm_config_db#(virtual axis_if)::get(
                this,
                "",
                "src_vif",
                src_vif
            )) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "AXI source interface not found"
                )

            end

            // Obtain Output 0 interface.
            if (!uvm_config_db#(virtual axis_if)::get(
                this,
                "",
                "out0_vif",
                out0_vif
            )) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "AXI Output 0 interface not found"
                )

            end

            // Obtain Output 1 interface.
            if (!uvm_config_db#(virtual axis_if)::get(
                this,
                "",
                "out1_vif",
                out1_vif
            )) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "AXI Output 1 interface not found"
                )

            end

            // Confirm the factory created the
            // intended reset-aware scoreboard.
            if (!$cast(reset_sb, scoreboard)) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "Scoreboard factory override failed"
                )

            end

        endfunction

        // ==================================================
        // 3. RESET CONTROL TASK
        // ==================================================

        task automatic perform_runtime_reset();

            // Assert reset at a falling clock edge
            // to avoid racing rising-edge monitors.
            @(negedge src_vif.aclk);

            reset_vif.request = 1'b1;

            // The DUT reset clears outstanding data.
            // Apply the same transition to the model.
            reset_sb.apply_runtime_reset();

            // Keep reset asserted for three cycles.
            repeat (3) begin

                @(posedge src_vif.aclk);

                // The two FIFOs should no longer
                // present valid output transactions.
                if (
                    out0_vif.tvalid !== 1'b0 ||
                    out1_vif.tvalid !== 1'b0
                ) begin

                    `uvm_fatal(
                        "RESET_TEST",
                        "Output TVALID remained asserted during reset"
                    )

                end

            end

            // Deassert reset away from rising edge.
            @(negedge src_vif.aclk);

            reset_vif.request = 1'b0;

            // Allow reset release to propagate.
            @(posedge src_vif.aclk);
            #1;

        endtask

        // ==================================================
        // 4. MAIN VERIFICATION SCENARIOS
        // ==================================================

        task run_phase(uvm_phase phase);

            phase.raise_objection(this);

            // ------------------------------------------
            // Initialize the controlled output sinks
            // ------------------------------------------

            out0_vif.tready = 1'b1;
            out1_vif.tready = 1'b0;

            reset_vif.request = 1'b0;

            // Wait until startup reset is released.
            wait (src_vif.aresetn === 1'b1);

            `uvm_info(
                "RESET_TEST",
                "Starting reset-during-active-traffic verification",
                UVM_LOW
            )

            // ==========================================
            // RST01: Route data to blocked Output 1
            // ==========================================

            // Configure Route 1.
            apb_access(
                1'b1,
                8'h00,
                32'h0000_0001,
                1'b0,
                32'h0000_0000
            );

            // Verify the configuration was written.
            apb_access(
                1'b0,
                8'h00,
                32'h0000_0000,
                1'b0,
                32'h0000_0001
            );

            // Three accepted beats of an incomplete
            // packet are buffered by the router.
            //
            // Output 1 cannot drain its FIFO because
            // the downstream TREADY remains low.
            send_beat(
                32'hDEAD_0101,
                4'hF,
                1'b0
            );

            send_beat(
                32'hDEAD_0102,
                4'hF,
                1'b0
            );

            send_beat(
                32'hDEAD_0103,
                4'hF,
                1'b0
            );

            // Confirm that all beats were accepted
            // but none reached the blocked output.
            if (
                reset_sb.input_count != 3 ||
                reset_sb.matched_count != 0 ||
                reset_sb.expected_q1.size() != 3 ||
                reset_sb.expected_q0.size() != 0 ||
                !reset_sb.in_packet
            ) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "Pre-reset buffered-packet state mismatch"
                )

            end

            if (out1_vif.tvalid !== 1'b1) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "Expected buffered data on blocked Output 1"
                )

            end

            `uvm_info(
                "RESET_TEST",
                "[PASS] RST01 three unfinished packet beats buffered",
                UVM_LOW
            )

            // ==========================================
            // RST02: Reset while packet is outstanding
            // ==========================================

            perform_runtime_reset();

            // Check the reference model accounted
            // for all three discarded transactions.
            if (
                reset_sb.reset_discarded_count != 3 ||
                reset_sb.runtime_reset_count != 1 ||
                reset_sb.in_packet ||
                reset_sb.route_sel != 1'b0 ||
                reset_sb.expected_q0.size() != 0 ||
                reset_sb.expected_q1.size() != 0
            ) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "Reset did not clear reference-model state"
                )

            end

            // Re-enable Output 1 after reset.
            // No pre-reset data may reappear.
            @(negedge src_vif.aclk);

            out1_vif.tready = 1'b1;

            repeat (4) begin

                @(posedge src_vif.aclk);

                if (
                    out0_vif.tvalid !== 1'b0 ||
                    out1_vif.tvalid !== 1'b0
                ) begin

                    `uvm_fatal(
                        "RESET_TEST",
                        "Stale AXI data appeared after reset"
                    )

                end

            end

            `uvm_info(
                "RESET_TEST",
                "[PASS] RST02 outstanding FIFO data discarded on reset",
                UVM_LOW
            )

            // ==========================================
            // RST03: APB route defaults to Output 0
            // ==========================================

            // Before reset the route was 1.
            // After reset a read must return 0.
            apb_access(
                1'b0,
                8'h00,
                32'h0000_0000,
                1'b0,
                32'h0000_0000
            );

            // A new packet must use Output 0.
            send_beat(
                32'hCAFE_0001,
                4'hF,
                1'b0
            );

            send_beat(
                32'hCAFE_0002,
                4'h3,
                1'b1
            );

            // Wait until both new beats are checked.
            wait (reset_sb.matched_count == 2);

            if (
                reset_sb.output0_count != 2 ||
                reset_sb.output1_count != 0
            ) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "Post-reset default routing mismatch"
                )

            end

            `uvm_info(
                "RESET_TEST",
                "[PASS] RST03 default route and packet state restored",
                UVM_LOW
            )

            // ==========================================
            // RST04: Reprogram route after reset
            // ==========================================

            // Verify that APB configuration remains
            // functional following runtime reset.
            apb_access(
                1'b1,
                8'h00,
                32'h0000_0001,
                1'b0,
                32'h0000_0000
            );

            // A complete new packet must reach
            // Output 1 without old buffered data.
            send_beat(
                32'hCAFE_1001,
                4'h7,
                1'b1
            );

            wait (reset_sb.matched_count == 3);

            // Continue monitoring for unexpected data.
            repeat (4) @(posedge src_vif.aclk);

            // ==========================================
            // RST05: End-to-end accounting
            // ==========================================

            if (
                reset_sb.input_count != 6 ||
                reset_sb.matched_count != 3 ||
                reset_sb.reset_discarded_count != 3 ||
                reset_sb.output0_count != 2 ||
                reset_sb.output1_count != 1 ||
                reset_sb.apb_count != 4 ||
                reset_sb.runtime_reset_count != 1
            ) begin

                `uvm_fatal(
                    "RESET_TEST",
                    $sformatf(
                        "Final count mismatch: input=%0d matched=%0d discarded=%0d out0=%0d out1=%0d apb=%0d",
                        reset_sb.input_count,
                        reset_sb.matched_count,
                        reset_sb.reset_discarded_count,
                        reset_sb.output0_count,
                        reset_sb.output1_count,
                        reset_sb.apb_count
                    )
                )

            end

            if (
                axis_drv.driven_count != 6 ||
                input_mon.observed_count != 6 ||
                output0_mon.observed_count != 2 ||
                output1_mon.observed_count != 1
            ) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "Driver/monitor accounting mismatch"
                )

            end

            if (
                reset_sb.expected_q0.size() != 0 ||
                reset_sb.expected_q1.size() != 0 ||
                reset_sb.in_packet
            ) begin

                `uvm_fatal(
                    "RESET_TEST",
                    "Unexpected pending transactions at test end"
                )

            end

            `uvm_info(
                "RESET_TEST",
                "[PASS] RST04 post-reset APB reconfiguration and routing",
                UVM_LOW
            )

            `uvm_info(
                "RESET_TEST",
                "[PASS] RST05 reset-aware transaction accounting",
                UVM_LOW
            )

            `uvm_info(
                "RESET_TEST",
                "ROUTER_RESET_UVM_PASS",
                UVM_NONE
            )

            phase.drop_objection(this);

        endtask

    endclass

endpackage