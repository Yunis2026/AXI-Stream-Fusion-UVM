/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : router_long_stall_pkg.sv
 *
 * Description:
 *   Long-duration AXI-Stream backpressure verification.
 *
 * Scenarios:
 *   L01 - Full FIFO with 300-cycle upstream stall
 *   L02 - Independent 400-cycle Output 1 stall
 *   L03 - Dual-output pending data for 250 cycles
 *
 * Reused infrastructure:
 *   - AXI-Stream source driver and sequencer
 *   - AXI-Stream input and output monitors
 *   - APB UVM agent
 *   - Dynamic routing scoreboard
 *   - AXI protocol stability checker
 */

package router_long_stall_pkg;

    import uvm_pkg::*;
    import axis_pkg::*;
    import apb_pkg::*;
    import router_dynamic_pkg::*;
    import router_stress_pkg::*;

    `include "uvm_macros.svh"

    class router_long_stall_test extends router_stress_test;

        `uvm_component_utils(router_long_stall_test)

        // ----------------------------------------------
        // Directed stall durations
        // ----------------------------------------------

        localparam int L01_STALL_CYCLES = 300;
        localparam int L02_STALL_CYCLES = 400;
        localparam int L03_STALL_CYCLES = 250;

        // ----------------------------------------------
        // Scenario completion flags
        // ----------------------------------------------

        bit l01_completed = 1'b0;
        bit l02_completed = 1'b0;
        bit l03_completed = 1'b0;

        bit fifth_beat_completed = 1'b0;

        // ----------------------------------------------
        // Observed scenario statistics
        // ----------------------------------------------

        int unsigned fifth_beat_stall_checks = 0;
        int unsigned output1_long_stall_checks = 0;
        int unsigned dual_pending_checks = 0;

        // ----------------------------------------------
        // Constructor
        // ----------------------------------------------

        function new(
            string name = "router_long_stall_test",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // ==================================================
        // L01: LONG UPSTREAM STALL WITH A FULL FIFO
        // ==================================================

        task automatic test_long_fifo_stall();

            `uvm_info(
                "LONG_STALL",
                "L01: Starting 300-cycle FIFO-full stall",
                UVM_LOW
            )

            // Use the reset-default route.
            apb_access(
                1'b0,
                8'h00,
                32'h0000_0000,
                1'b0,
                32'h0000_0000
            );

            // Block Output 0 at the falling edge.
            @(negedge src_vif.aclk);

            out0_vif.tready = 1'b0;
            out1_vif.tready = 1'b1;

            // Fill the four-entry Output 0 FIFO.
            // The packet remains unfinished.
            send_beat(
                32'h1000_0001,
                4'hF,
                1'b0
            );

            send_beat(
                32'h1000_0002,
                4'hF,
                1'b0
            );

            send_beat(
                32'h1000_0003,
                4'hF,
                1'b0
            );

            send_beat(
                32'h1000_0004,
                4'hF,
                1'b0
            );

            // Confirm four accepted and zero
            // matched transactions.
            if (
                scoreboard.input_count != 4 ||
                scoreboard.matched_count != 0 ||
                scoreboard.expected_q0.size() != 4 ||
                scoreboard.expected_q1.size() != 0 ||
                !scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "L01 FIFO fill state mismatch"
                )

            end

            // Attempt the fifth beat while the
            // FIFO is full. It must remain blocked.
            fork

                // --------------------------------------
                // Source thread
                // --------------------------------------

                begin : source_thread

                    send_beat(
                        32'h1000_0005,
                        4'h3,
                        1'b1
                    );

                    fifth_beat_completed = 1'b1;

                end

                // --------------------------------------
                // Backpressure verification thread
                // --------------------------------------

                begin : stall_thread

                    wait (
                        src_vif.tvalid === 1'b1 &&
                        src_vif.tready === 1'b0
                    );

                    // Verify 300 consecutive stalled
                    // clock sampling points.
                    for (
                        int cycle = 0;
                        cycle < L01_STALL_CYCLES;
                        cycle++
                    ) begin

                        @(posedge src_vif.aclk);

                        // The fifth beat must retain
                        // its payload and VALID.
                        if (
                            src_vif.tvalid !== 1'b1 ||
                            src_vif.tready !== 1'b0 ||
                            src_vif.tdata !== 32'h1000_0005 ||
                            src_vif.tkeep !== 4'h3 ||
                            src_vif.tlast !== 1'b1
                        ) begin

                            `uvm_fatal(
                                "LONG_STALL",
                                $sformatf(
                                    "L01 fifth-beat stability failure at cycle %0d",
                                    cycle
                                )
                            )

                        end

                        // Output 0 must not consume data.
                        if (
                            out0_vif.tready !== 1'b0 ||
                            out0_vif.tvalid !== 1'b1 ||
                            out0_vif.tdata !== 32'h1000_0001
                        ) begin

                            `uvm_fatal(
                                "LONG_STALL",
                                "L01 blocked Output 0 changed unexpectedly"
                            )

                        end

                        if (
                            scoreboard.input_count != 4 ||
                            scoreboard.output0_count != 0 ||
                            scoreboard.output1_count != 0 ||
                            fifth_beat_completed
                        ) begin

                            `uvm_fatal(
                                "LONG_STALL",
                                "L01 transfer occurred during full FIFO stall"
                            )

                        end

                        fifth_beat_stall_checks++;

                    end

                    // Release Output 0 backpressure.
                    @(negedge src_vif.aclk);

                    out0_vif.tready = 1'b1;

                end

            join

            // The fifth handshake must have occurred.
            if (!fifth_beat_completed) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "L01 fifth beat did not complete"
                )

            end

            // Drain and verify the complete packet.
            wait (scoreboard.matched_count == 5);

            if (
                scoreboard.input_count != 5 ||
                scoreboard.output0_count != 5 ||
                scoreboard.output1_count != 0 ||
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "L01 FIFO drain verification failed"
                )

            end

            l01_completed = 1'b1;

            `uvm_info(
                "LONG_STALL",
                "[PASS] L01 300-cycle FIFO-full stall and recovery",
                UVM_LOW
            )

        endtask

        // ==================================================
        // L02: INDEPENDENT OUTPUT BACKPRESSURE
        // ==================================================

        task automatic test_independent_long_stall();

            `uvm_info(
                "LONG_STALL",
                "L02: Starting 400-cycle independent stall",
                UVM_LOW
            )

            // Route the first packet to Output 1.
            apb_access(
                1'b1,
                8'h00,
                32'h0000_0001,
                1'b0,
                32'h0000_0000
            );

            // Block Output 1 only.
            @(negedge src_vif.aclk);

            out0_vif.tready = 1'b1;
            out1_vif.tready = 1'b0;

            // Queue a complete three-beat packet
            // into the blocked Output 1 FIFO.
            send_beat(
                32'h2000_0001,
                4'hF,
                1'b0
            );

            send_beat(
                32'h2000_0002,
                4'hF,
                1'b0
            );

            send_beat(
                32'h2000_0003,
                4'h3,
                1'b1
            );

            if (
                scoreboard.expected_q1.size() != 3 ||
                scoreboard.output1_count != 0
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "L02 Output 1 did not buffer three beats"
                )

            end

            // Reconfigure the next packet to Output 0.
            apb_access(
                1'b1,
                8'h00,
                32'h0000_0000,
                1'b0,
                32'h0000_0000
            );

            // Output 0 must continue transferring,
            // even while Output 1 is blocked.
            send_beat(
                32'h2100_0001,
                4'hF,
                1'b0
            );

            send_beat(
                32'h2100_0002,
                4'h3,
                1'b1
            );

            wait (scoreboard.output0_count == 7);

            if (
                scoreboard.output1_count != 0 ||
                scoreboard.expected_q1.size() != 3
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "L02 independent output operation failed"
                )

            end

            // Maintain Output 1 backpressure for
            // 400 consecutive sampling cycles.
            for (
                int cycle = 0;
                cycle < L02_STALL_CYCLES;
                cycle++
            ) begin

                @(posedge src_vif.aclk);

                if (
                    out1_vif.tready !== 1'b0 ||
                    out1_vif.tvalid !== 1'b1 ||
                    out1_vif.tdata !== 32'h2000_0001 ||
                    out1_vif.tkeep !== 4'hF ||
                    out1_vif.tlast !== 1'b0
                ) begin

                    `uvm_fatal(
                        "LONG_STALL",
                        $sformatf(
                            "L02 Output 1 stability failure at cycle %0d",
                            cycle
                        )
                    )

                end

                if (
                    scoreboard.output0_count != 7 ||
                    scoreboard.output1_count != 0
                ) begin

                    `uvm_fatal(
                        "LONG_STALL",
                        "L02 unexpected output transaction"
                    )

                end

                output1_long_stall_checks++;

            end

            // Allow Output 1 to drain.
            @(negedge src_vif.aclk);

            out1_vif.tready = 1'b1;

            wait (scoreboard.matched_count == 10);

            if (
                scoreboard.output0_count != 7 ||
                scoreboard.output1_count != 3 ||
                scoreboard.expected_q1.size() != 0
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "L02 Output 1 drain failed"
                )

            end

            l02_completed = 1'b1;

            `uvm_info(
                "LONG_STALL",
                "[PASS] L02 400-cycle independent output stall",
                UVM_LOW
            )

        endtask

        // ==================================================
        // L03: BOTH OUTPUTS PENDING AND SELECTIVE DRAIN
        // ==================================================

        task automatic test_dual_output_long_stall();

            `uvm_info(
                "LONG_STALL",
                "L03: Starting 250-cycle dual-output stall",
                UVM_LOW
            )

            // Block both output sinks.
            @(negedge src_vif.aclk);

            out0_vif.tready = 1'b0;
            out1_vif.tready = 1'b0;

            // Select Output 0 for the next packet.
            apb_access(
                1'b1,
                8'h00,
                32'h0000_0000,
                1'b0,
                32'h0000_0000
            );

            // Queue two beats on Output 0.
            send_beat(
                32'h3000_0001,
                4'hF,
                1'b0
            );

            send_beat(
                32'h3000_0002,
                4'h3,
                1'b1
            );

            // Select Output 1 for the next packet.
            apb_access(
                1'b1,
                8'h00,
                32'h0000_0001,
                1'b0,
                32'h0000_0000
            );

            // Queue two beats on Output 1.
            send_beat(
                32'h3100_0001,
                4'hF,
                1'b0
            );

            send_beat(
                32'h3100_0002,
                4'h3,
                1'b1
            );

            // APB must remain functional even
            // when both AXI outputs are stalled.
            apb_access(
                1'b0,
                8'h00,
                32'h0000_0000,
                1'b0,
                32'h0000_0001
            );

            if (
                scoreboard.expected_q0.size() != 2 ||
                scoreboard.expected_q1.size() != 2 ||
                scoreboard.output0_count != 7 ||
                scoreboard.output1_count != 3
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "L03 dual-output pending state mismatch"
                )

            end

            // Both outputs must retain their first
            // pending beats for 250 cycles.
            for (
                int cycle = 0;
                cycle < L03_STALL_CYCLES;
                cycle++
            ) begin

                @(posedge src_vif.aclk);

                if (
                    out0_vif.tready !== 1'b0 ||
                    out1_vif.tready !== 1'b0 ||
                    out0_vif.tvalid !== 1'b1 ||
                    out1_vif.tvalid !== 1'b1
                ) begin

                    `uvm_fatal(
                        "LONG_STALL",
                        "L03 dual-output pending state lost"
                    )

                end

                if (
                    out0_vif.tdata !== 32'h3000_0001 ||
                    out0_vif.tkeep !== 4'hF ||
                    out0_vif.tlast !== 1'b0 ||
                    out1_vif.tdata !== 32'h3100_0001 ||
                    out1_vif.tkeep !== 4'hF ||
                    out1_vif.tlast !== 1'b0
                ) begin

                    `uvm_fatal(
                        "LONG_STALL",
                        $sformatf(
                            "L03 payload stability failure at cycle %0d",
                            cycle
                        )
                    )

                end

                if (
                    scoreboard.output0_count != 7 ||
                    scoreboard.output1_count != 3
                ) begin

                    `uvm_fatal(
                        "LONG_STALL",
                        "L03 output transferred while stalled"
                    )

                end

                dual_pending_checks++;

            end

            // Release Output 0 but keep Output 1
            // blocked to verify independent draining.
            @(negedge src_vif.aclk);

            out0_vif.tready = 1'b1;

            wait (scoreboard.output0_count == 9);

            if (
                scoreboard.output1_count != 3 ||
                scoreboard.expected_q1.size() != 2
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "L03 selective drain failed"
                )

            end

            // Confirm Output 1 remains stalled.
            repeat (10) begin

                @(posedge src_vif.aclk);

                if (
                    out1_vif.tvalid !== 1'b1 ||
                    out1_vif.tready !== 1'b0
                ) begin

                    `uvm_fatal(
                        "LONG_STALL",
                        "L03 Output 1 did not remain stalled"
                    )

                end

            end

            // Release Output 1.
            @(negedge src_vif.aclk);

            out1_vif.tready = 1'b1;

            wait (scoreboard.matched_count == 14);

            if (
                scoreboard.output0_count != 9 ||
                scoreboard.output1_count != 5 ||
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "L03 final dual-output drain failed"
                )

            end

            l03_completed = 1'b1;

            `uvm_info(
                "LONG_STALL",
                "[PASS] L03 250-cycle dual-output stall and selective recovery",
                UVM_LOW
            )

        endtask

        // ==================================================
        // MAIN RUN PHASE
        // ==================================================

        task run_phase(uvm_phase phase);

            phase.raise_objection(this);

            // Set deterministic initial sink behavior.
            out0_vif.tready = 1'b1;
            out1_vif.tready = 1'b1;

            // Reuse the existing source/output
            // protocol stability checker.
            //
            // This test controls TREADY directly,
            // so the random ready controller is
            // intentionally not started.
            fork
                check_stability();
            join_none

            // Wait for reset release.
            wait (src_vif.aresetn === 1'b1);

            // Execute all directed stress scenarios.
            test_long_fifo_stall();
            test_independent_long_stall();
            test_dual_output_long_stall();

            // Observe a short quiet period for
            // unexpected duplicated output beats.
            repeat (5) @(posedge src_vif.aclk);

            // ------------------------------------------
            // Scenario completion checks
            // ------------------------------------------

            if (
                !l01_completed ||
                !l02_completed ||
                !l03_completed
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "One or more long-stall scenarios failed"
                )

            end

            if (
                fifth_beat_stall_checks != L01_STALL_CYCLES ||
                output1_long_stall_checks != L02_STALL_CYCLES ||
                dual_pending_checks != L03_STALL_CYCLES
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "Long-duration stall checks did not complete"
                )

            end

            // ------------------------------------------
            // AXI transfer accounting
            // ------------------------------------------

            if (
                axis_drv.driven_count != 14 ||
                input_mon.observed_count != 14 ||
                output0_mon.observed_count != 9 ||
                output1_mon.observed_count != 5
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "AXI driver/monitor transaction count mismatch"
                )

            end

            if (
                scoreboard.input_count != 14 ||
                scoreboard.matched_count != 14 ||
                scoreboard.output0_count != 9 ||
                scoreboard.output1_count != 5 ||
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "Final AXI scoreboard accounting mismatch"
                )

            end

            // ------------------------------------------
            // APB transaction accounting
            // ------------------------------------------

            if (
                cfg_agent.driver.completed_count != 6 ||
                cfg_agent.monitor.observed_count != 6 ||
                scoreboard.apb_count != 6 ||
                scoreboard.apb_error_count != 0
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "APB transaction count mismatch"
                )

            end

            // ------------------------------------------
            // Backpressure statistics
            // ------------------------------------------

            if (
                source_stall_cycles < L01_STALL_CYCLES ||
                output0_stall_cycles < L01_STALL_CYCLES ||
                output1_stall_cycles < L02_STALL_CYCLES
            ) begin

                `uvm_fatal(
                    "LONG_STALL",
                    "Insufficient AXI backpressure was observed"
                )

            end

            // ------------------------------------------
            // Final test summary
            // ------------------------------------------

            `uvm_info(
                "LONG_STALL",
                $sformatf(
                    "LONG_STALL_SUMMARY input=%0d matched=%0d out0=%0d out1=%0d apb=%0d l01=%0d l02=%0d l03=%0d",
                    scoreboard.input_count,
                    scoreboard.matched_count,
                    scoreboard.output0_count,
                    scoreboard.output1_count,
                    scoreboard.apb_count,
                    fifth_beat_stall_checks,
                    output1_long_stall_checks,
                    dual_pending_checks
                ),
                UVM_NONE
            )

            `uvm_info(
                "LONG_STALL",
                "ROUTER_LONG_STALL_UVM_PASS",
                UVM_NONE
            )

            phase.drop_objection(this);

        endtask

    endclass

endpackage