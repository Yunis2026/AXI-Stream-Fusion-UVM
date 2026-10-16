/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : router_fifo_apb_pkg.sv
 *
 * Description:
 *   Advanced FIFO-full and APB route-update verification.
 *
 * Verification objectives:
 *   - Fill Output 0 FIFO while its sink is stalled
 *   - Verify the fifth input beat is backpressured
 *   - Update APB route while the fifth beat is stalled
 *   - Verify the current packet retains its locked route
 *   - Verify invalid APB writes do not corrupt the route
 *   - Drain the full FIFO without data loss or reordering
 *   - Verify the next packet uses the new APB route
 *
 * The existing UVM agents, monitors, sequences,
 * protocol stability checker and scoreboard are reused.
 */

package router_fifo_apb_pkg;

    import uvm_pkg::*;
    import axis_pkg::*;
    import apb_pkg::*;
    import router_dynamic_pkg::*;
    import router_stress_pkg::*;

    `include "uvm_macros.svh"

    // ==================================================
    // FIFO-FULL / APB-UPDATE UVM TEST
    // ==================================================

    class router_fifo_apb_test extends router_stress_test;

        `uvm_component_utils(router_fifo_apb_test)

        // ----------------------------------------------
        // Scenario tracking
        // ----------------------------------------------

        bit fifth_beat_completed = 1'b0;

        bit fifo_full_observed = 1'b0;
        bit apb_updated_during_stall = 1'b0;
        bit packet_lock_verified = 1'b0;
        bit next_packet_verified = 1'b0;

        int unsigned fifth_beat_stall_cycles = 0;

        // ----------------------------------------------
        // Constructor
        // ----------------------------------------------

        function new(
            string name = "router_fifo_apb_test",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // ==================================================
        // CHECK THAT FIFTH BEAT REMAINS STALLED
        // ==================================================

        task automatic check_fifth_beat_stall();

            // Sample the presented fifth beat at
            // the same clock edge as the DUT.
            @(posedge src_vif.aclk);

            if (
                src_vif.tvalid !== 1'b1 ||
                src_vif.tready !== 1'b0 ||
                src_vif.tdata  !== 32'h0000_F005 ||
                src_vif.tkeep  !== 4'h3 ||
                src_vif.tlast  !== 1'b1
            ) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "Fifth input beat was not held stable during FIFO full"
                )

            end

            // Exactly four beats must already have
            // been accepted into the blocked route.
            if (
                scoreboard.input_count != 4 ||
                scoreboard.expected_q0.size() != 4 ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.output0_count != 0 ||
                scoreboard.output1_count != 0
            ) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "Unexpected FIFO occupancy or scoreboard state"
                )

            end

            if (fifth_beat_completed) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "Fifth beat completed before backpressure release"
                )

            end

            fifth_beat_stall_cycles++;

        endtask

        // ==================================================
        // S04: FIFO FULL PLUS MID-PACKET APB UPDATE
        // ==================================================

        task automatic test_fifo_full_apb_update();

            `uvm_info(
                "FIFO_APB",
                "S04: Starting FIFO-full APB-update scenario",
                UVM_LOW
            )

            // ------------------------------------------
            // Step 1: Block Output 0
            // ------------------------------------------

            out0_vif.tready = 1'b0;
            out1_vif.tready = 1'b1;

            // Verify the reset-default route is zero.
            apb_access(
                1'b0,
                8'h00,
                32'h0000_0000,
                1'b0,
                32'h0000_0000
            );

            // ------------------------------------------
            // Step 2: Fill the Output 0 FIFO
            // ------------------------------------------

            // All four beats belong to one unfinished
            // packet. TLAST remains low.
            send_beat(
                32'h0000_F001,
                4'hF,
                1'b0
            );

            send_beat(
                32'h0000_F002,
                4'hF,
                1'b0
            );

            send_beat(
                32'h0000_F003,
                4'hF,
                1'b0
            );

            send_beat(
                32'h0000_F004,
                4'hF,
                1'b0
            );

            // Verify exactly four accepted beats.
            if (
                scoreboard.input_count != 4 ||
                scoreboard.expected_q0.size() != 4 ||
                scoreboard.matched_count != 0 ||
                !scoreboard.in_packet ||
                scoreboard.locked_route != 1'b0
            ) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "Initial four-beat FIFO fill failed"
                )

            end

            // ------------------------------------------
            // Step 3: Drive the fifth beat concurrently
            // with APB configuration updates
            // ------------------------------------------

            fork

                // ======================================
                // Thread A: AXI Source
                // ======================================

                begin : fifth_beat_source

                    // This beat must remain stalled
                    // until Output 0 is released.
                    send_beat(
                        32'h0000_F005,
                        4'h3,
                        1'b1
                    );

                    // A completed Sequence indicates
                    // that the AXI handshake occurred.
                    fifth_beat_completed = 1'b1;

                end

                // ======================================
                // Thread B: APB and stall verification
                // ======================================

                begin : apb_while_stalled

                    // Wait for the source to present
                    // a valid but unaccepted fifth beat.
                    wait (
                        src_vif.tvalid === 1'b1 &&
                        src_vif.tready === 1'b0
                    );

                    fifo_full_observed = 1'b1;

                    // Verify prolonged backpressure
                    // before changing the route.
                    repeat (3) begin

                        check_fifth_beat_stall();

                    end

                    `uvm_info(
                        "FIFO_APB",
                        "[PASS] S04A four-entry FIFO full and fifth beat stalled",
                        UVM_LOW
                    )

                    // ----------------------------------
                    // Update route during stalled packet
                    // ----------------------------------

                    // Packet F was locked to Output 0
                    // by its first accepted beat.
                    //
                    // Change APB ROUTE_SEL to Output 1
                    // before accepting the final beat.
                    apb_access(
                        1'b1,
                        8'h00,
                        32'h0000_0001,
                        1'b0,
                        32'h0000_0000
                    );

                    // The configuration register must
                    // change while packet lock stays 0.
                    if (
                        scoreboard.route_sel != 1'b1 ||
                        scoreboard.locked_route != 1'b0 ||
                        !scoreboard.in_packet
                    ) begin

                        `uvm_fatal(
                            "FIFO_APB",
                            "APB update incorrectly modified packet lock"
                        )

                    end

                    apb_updated_during_stall = 1'b1;

                    // ----------------------------------
                    // Invalid APB access
                    // ----------------------------------

                    // Verify that an invalid write does
                    // not alter the new route setting.
                    apb_access(
                        1'b1,
                        8'h04,
                        32'h0000_0000,
                        1'b1,
                        32'h0000_0000
                    );

                    // Read back the new route.
                    apb_access(
                        1'b0,
                        8'h00,
                        32'h0000_0000,
                        1'b0,
                        32'h0000_0001
                    );

                    // ----------------------------------
                    // Verify the fifth beat is still
                    // blocked after all APB operations
                    // ----------------------------------

                    repeat (3) begin

                        check_fifth_beat_stall();

                    end

                    if (
                        scoreboard.route_sel != 1'b1 ||
                        scoreboard.locked_route != 1'b0 ||
                        scoreboard.input_count != 4 ||
                        scoreboard.matched_count != 0 ||
                        fifth_beat_completed
                    ) begin

                        `uvm_fatal(
                            "FIFO_APB",
                            "Packet routing or stall state changed unexpectedly"
                        )

                    end

                    `uvm_info(
                        "FIFO_APB",
                        "[PASS] S04B APB route changed while fifth beat remained stalled",
                        UVM_LOW
                    )

                    // ----------------------------------
                    // Release Output 0 backpressure
                    // ----------------------------------

                    // Drive TREADY on the falling edge
                    // to avoid sampling-edge races.
                    @(negedge src_vif.aclk);

                    out0_vif.tready = 1'b1;

                end

            join

            // ------------------------------------------
            // Step 4: Drain the entire original packet
            // ------------------------------------------

            // Five beats must reach Output 0 even
            // though the APB route is now Output 1.
            wait (scoreboard.matched_count == 5);

            if (
                !fifth_beat_completed ||
                scoreboard.input_count != 5 ||
                scoreboard.output0_count != 5 ||
                scoreboard.output1_count != 0 ||
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "Original packet did not drain through locked Output 0"
                )

            end

            packet_lock_verified = 1'b1;

            `uvm_info(
                "FIFO_APB",
                "[PASS] S04C all five beats retained Output 0 packet lock",
                UVM_LOW
            )

            // ------------------------------------------
            // Step 5: Send a new packet to Output 1
            // ------------------------------------------

            // The previous packet has ended, so the
            // next packet must use the updated route.
            send_beat(
                32'h0000_A201,
                4'hF,
                1'b0
            );

            send_beat(
                32'h0000_A202,
                4'h3,
                1'b1
            );

            wait (scoreboard.matched_count == 7);

            if (
                scoreboard.input_count != 7 ||
                scoreboard.output0_count != 5 ||
                scoreboard.output1_count != 2 ||
                scoreboard.matched_count != 7 ||
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "Next packet did not follow updated Output 1 route"
                )

            end

            next_packet_verified = 1'b1;

            `uvm_info(
                "FIFO_APB",
                "[PASS] S04D next packet followed updated Output 1 route",
                UVM_LOW
            )

        endtask

        // ==================================================
        // MAIN UVM RUN PHASE
        // ==================================================

        task run_phase(uvm_phase phase);

            phase.raise_objection(this);

            // ------------------------------------------
            // Initialize both output interfaces
            // ------------------------------------------

            out0_vif.tready = 1'b0;
            out1_vif.tready = 1'b1;

            // Reuse the existing AXI protocol stability
            // checker from router_stress_test.
            //
            // The ready_controller is intentionally not
            // started because this test drives TREADY
            // through directed stimulus.
            fork

                check_stability();

            join_none

            // Wait until the hardware reset is released.
            wait (src_vif.aresetn === 1'b1);

            test_fifo_full_apb_update();

            // Keep observing both outputs for possible
            // duplicated or unexpected transactions.
            repeat (5) @(posedge src_vif.aclk);

            // ------------------------------------------
            // Verify all expected scenario conditions
            // ------------------------------------------

            if (
                !fifo_full_observed ||
                !apb_updated_during_stall ||
                !packet_lock_verified ||
                !next_packet_verified
            ) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "One or more FIFO/APB test objectives were not reached"
                )

            end

            // Verify the fifth beat spent multiple
            // clock cycles under backpressure.
            if (fifth_beat_stall_cycles < 6) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "Insufficient fifth-beat stall duration"
                )

            end

            // ------------------------------------------
            // Verify driver and monitor transactions
            // ------------------------------------------

            if (
                axis_drv.driven_count != 7 ||
                input_mon.observed_count != 7 ||
                output0_mon.observed_count != 5 ||
                output1_mon.observed_count != 2
            ) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "AXI driver or monitor transaction count mismatch"
                )

            end

            // ------------------------------------------
            // Verify APB traffic and error responses
            // ------------------------------------------

            if (
                cfg_agent.driver.completed_count != 4 ||
                cfg_agent.monitor.observed_count != 4 ||
                scoreboard.apb_count != 4 ||
                scoreboard.apb_error_count != 1
            ) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "APB transaction or expected error count mismatch"
                )

            end

            // ------------------------------------------
            // Verify complete AXI scoreboard accounting
            // ------------------------------------------

            if (
                scoreboard.input_count != 7 ||
                scoreboard.output0_count != 5 ||
                scoreboard.output1_count != 2 ||
                scoreboard.matched_count != 7 ||
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "Final routing scoreboard verification failed"
                )

            end

            // Verify that real backpressure occurred.
            if (
                source_stall_cycles == 0 ||
                output0_stall_cycles == 0
            ) begin

                `uvm_fatal(
                    "FIFO_APB",
                    "Required AXI backpressure was not observed"
                )

            end

            // ------------------------------------------
            // Final result
            // ------------------------------------------

            `uvm_info(
                "FIFO_APB",
                $sformatf(
                    "FIFO_APB_SUMMARY input=%0d matched=%0d out0=%0d out1=%0d apb=%0d errors=%0d fifth_stalls=%0d",
                    scoreboard.input_count,
                    scoreboard.matched_count,
                    scoreboard.output0_count,
                    scoreboard.output1_count,
                    scoreboard.apb_count,
                    scoreboard.apb_error_count,
                    fifth_beat_stall_cycles
                ),
                UVM_NONE
            )

            `uvm_info(
                "FIFO_APB",
                "ROUTER_FIFO_APB_UVM_PASS",
                UVM_NONE
            )

            phase.drop_objection(this);

        endtask

    endclass

endpackage