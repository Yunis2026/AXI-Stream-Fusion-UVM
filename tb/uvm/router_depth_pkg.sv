/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : router_depth_pkg.sv
 *
 * Description:
 *   Parameterized FIFO depth verification.
 *
 * Supported regression configurations:
 *   - FIFO_DEPTH = 2
 *   - FIFO_DEPTH = 4
 *   - FIFO_DEPTH = 8
 *
 * Verification scenarios:
 *   P01 - Fill Output 0 FIFO to its configured depth
 *   P02 - Update APB during a full-FIFO stall
 *   P03 - Repeat the full-FIFO test on Output 1
 *   P04 - Verify both outputs recover and route correctly
 *
 * Reuses the existing AXI/APB UVM verification stack.
 */

package router_depth_pkg;

    import uvm_pkg::*;
    import axis_pkg::*;
    import apb_pkg::*;
    import router_dynamic_pkg::*;
    import router_stress_pkg::*;

    `include "uvm_macros.svh"

    class router_depth_test extends router_stress_test;

        `uvm_component_utils(router_depth_test)

        // Configured hardware FIFO depth.
        int fifo_depth;

        // Directed verification statistics.
        int unsigned full0_checks = 0;
        int unsigned full1_checks = 0;

        // Completion flags for both FIFO tests.
        bit output0_full_verified = 1'b0;
        bit output1_full_verified = 1'b0;

        // Tracks completion of a blocked final beat.
        bit final0_completed = 1'b0;
        bit final1_completed = 1'b0;

        // --------------------------------------------------
        // Constructor
        // --------------------------------------------------

        function new(
            string name = "router_depth_test",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // --------------------------------------------------
        // Build phase
        // --------------------------------------------------

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            if (!uvm_config_db#(int)::get(
                this,
                "",
                "fifo_depth",
                fifo_depth
            )) begin

                `uvm_fatal(
                    "DEPTH",
                    "FIFO depth configuration was not provided"
                )

            end

            // This regression exercises power-of-two
            // FIFO depths greater than or equal to two.
            if (
                fifo_depth < 2 ||
                ((fifo_depth & (fifo_depth - 1)) != 0)
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "FIFO depth must be a power of two >= 2"
                )

            end

            `uvm_info(
                "DEPTH",
                $sformatf(
                    "Parameterized verification: FIFO_DEPTH=%0d",
                    fifo_depth
                ),
                UVM_LOW
            )

        endfunction

        // ==================================================
        // P01: FILL OUTPUT 0 TO CONFIGURED DEPTH
        // ==================================================

        task automatic verify_output0_capacity();

            int unsigned accepted_before;

            `uvm_info(
                "DEPTH",
                "P01: Checking Output 0 FIFO capacity",
                UVM_LOW
            )

            // Keep Output 0 blocked.
            @(negedge src_vif.aclk);

            out0_vif.tready = 1'b0;
            out1_vif.tready = 1'b1;

            // Verify the reset-default route.
            apb_access(
                1'b0,
                8'h00,
                32'h0000_0000,
                1'b0,
                32'h0000_0000
            );

            // Fill exactly FIFO_DEPTH entries with
            // beats belonging to one unfinished packet.
            for (int i = 0; i < fifo_depth; i++) begin

                send_beat(
                    32'hD100_0000 + 32'(i + 1),
                    4'hF,
                    1'b0
                );

            end

            accepted_before = scoreboard.input_count;

            if (
                scoreboard.expected_q0.size() != fifo_depth ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.output0_count != 0 ||
                scoreboard.input_count != fifo_depth ||
                scoreboard.locked_route != 1'b0 ||
                !scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "Output 0 did not accept exactly FIFO_DEPTH beats"
                )

            end

            // Start one additional beat. It must be
            // blocked while Output 0 remains not ready.
            fork

                begin : source0

                    send_beat(
                        32'hD100_FFFF,
                        4'h3,
                        1'b1
                    );

                    final0_completed = 1'b1;

                end

                begin : control0

                    wait (
                        src_vif.tvalid === 1'b1 &&
                        src_vif.tready === 1'b0
                    );

                    // Verify the extra beat is stalled.
                    repeat (6) begin

                        @(posedge src_vif.aclk);

                        if (
                            src_vif.tvalid !== 1'b1 ||
                            src_vif.tready !== 1'b0 ||
                            src_vif.tdata  !== 32'hD100_FFFF ||
                            src_vif.tkeep  !== 4'h3 ||
                            src_vif.tlast  !== 1'b1 ||
                            final0_completed
                        ) begin

                            `uvm_fatal(
                                "DEPTH",
                                "Output 0 FIFO capacity/stall check failed"
                            )

                        end

                        full0_checks++;

                    end

                    // P02: Change the route while
                    // the final beat is still stalled.
                    apb_access(
                        1'b1,
                        8'h00,
                        32'h0000_0001,
                        1'b0,
                        32'h0000_0000
                    );

                    apb_access(
                        1'b0,
                        8'h00,
                        32'h0000_0000,
                        1'b0,
                        32'h0000_0001
                    );

                    // The configuration changed,
                    // but the active packet did not.
                    if (
                        scoreboard.route_sel != 1'b1 ||
                        scoreboard.locked_route != 1'b0 ||
                        !scoreboard.in_packet
                    ) begin

                        `uvm_fatal(
                            "DEPTH",
                            "Output 0 packet lock changed during APB update"
                        )

                    end

                    repeat (3) begin

                        @(posedge src_vif.aclk);

                        if (
                            src_vif.tvalid !== 1'b1 ||
                            src_vif.tready !== 1'b0 ||
                            src_vif.tdata !== 32'hD100_FFFF ||
                            scoreboard.input_count != accepted_before
                        ) begin

                            `uvm_fatal(
                                "DEPTH",
                                "Output 0 accepted the final beat while full"
                            )

                        end

                        full0_checks++;

                    end

                    // Release the blocked output.
                    @(negedge src_vif.aclk);

                    out0_vif.tready = 1'b1;

                end

            join

            // All FIFO_DEPTH+1 beats must be routed
            // through the original Output 0.
            wait (
                scoreboard.matched_count ==
                fifo_depth + 1
            );

            if (
                !final0_completed ||
                scoreboard.output0_count != fifo_depth + 1 ||
                scoreboard.output1_count != 0 ||
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "Output 0 FIFO drain or packet lock failed"
                )

            end

            output0_full_verified = 1'b1;

            `uvm_info(
                "DEPTH",
                "[PASS] P01/P02 Output 0 capacity and APB packet lock",
                UVM_LOW
            )

        endtask

        // ==================================================
        // VERIFY NEXT PACKET FOLLOWS OUTPUT 1
        // ==================================================

        task automatic verify_next_packet_output1();

            // The APB route was updated to 1 while
            // the previous packet was still pending.
            send_beat(
                32'hD200_0001,
                4'hF,
                1'b0
            );

            send_beat(
                32'hD200_0002,
                4'h3,
                1'b1
            );

            wait (
                scoreboard.matched_count ==
                fifo_depth + 3
            );

            if (
                scoreboard.output0_count != fifo_depth + 1 ||
                scoreboard.output1_count != 2 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "Next packet did not follow Output 1 route"
                )

            end

            `uvm_info(
                "DEPTH",
                "[PASS] Next packet followed Output 1",
                UVM_LOW
            )

        endtask

        // ==================================================
        // P03: VERIFY OUTPUT 1 FIFO CAPACITY
        // ==================================================

        task automatic verify_output1_capacity();

            int unsigned accepted_before;

            `uvm_info(
                "DEPTH",
                "P03: Checking Output 1 FIFO capacity",
                UVM_LOW
            )

            // Keep Output 0 ready and block Output 1.
            @(negedge src_vif.aclk);

            out0_vif.tready = 1'b1;
            out1_vif.tready = 1'b0;

            // The route remains configured to Output 1.
            for (int i = 0; i < fifo_depth; i++) begin

                send_beat(
                    32'hD300_0000 + 32'(i + 1),
                    4'hF,
                    1'b0
                );

            end

            accepted_before = scoreboard.input_count;

            if (
                scoreboard.expected_q1.size() != fifo_depth ||
                scoreboard.output1_count != 2 ||
                scoreboard.locked_route != 1'b1 ||
                !scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "Output 1 FIFO capacity mismatch"
                )

            end

            fork

                begin : source1

                    send_beat(
                        32'hD300_FFFF,
                        4'h7,
                        1'b1
                    );

                    final1_completed = 1'b1;

                end

                begin : control1

                    wait (
                        src_vif.tvalid === 1'b1 &&
                        src_vif.tready === 1'b0
                    );

                    repeat (6) begin

                        @(posedge src_vif.aclk);

                        if (
                            src_vif.tvalid !== 1'b1 ||
                            src_vif.tready !== 1'b0 ||
                            src_vif.tdata !== 32'hD300_FFFF ||
                            src_vif.tkeep !== 4'h7 ||
                            src_vif.tlast !== 1'b1 ||
                            final1_completed
                        ) begin

                            `uvm_fatal(
                                "DEPTH",
                                "Output 1 FIFO capacity/stall check failed"
                            )

                        end

                        full1_checks++;

                    end

                    // Switch the APB route back to
                    // Output 0 during the stalled packet.
                    apb_access(
                        1'b1,
                        8'h00,
                        32'h0000_0000,
                        1'b0,
                        32'h0000_0000
                    );

                    // Invalid writes must not modify
                    // the newly selected route.
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
                        32'h0000_0000
                    );

                    if (
                        scoreboard.route_sel != 1'b0 ||
                        scoreboard.locked_route != 1'b1 ||
                        !scoreboard.in_packet
                    ) begin

                        `uvm_fatal(
                            "DEPTH",
                            "Output 1 packet lock changed during APB update"
                        )

                    end

                    repeat (3) begin

                        @(posedge src_vif.aclk);

                        if (
                            src_vif.tvalid !== 1'b1 ||
                            src_vif.tready !== 1'b0 ||
                            src_vif.tdata !== 32'hD300_FFFF ||
                            scoreboard.input_count != accepted_before
                        ) begin

                            `uvm_fatal(
                                "DEPTH",
                                "Output 1 accepted the final beat while full"
                            )

                        end

                        full1_checks++;

                    end

                    @(negedge src_vif.aclk);

                    out1_vif.tready = 1'b1;

                end

            join

            // Expected total after this packet:
            //   Output 0 = fifo_depth + 1
            //   Output 1 = fifo_depth + 3
            wait (
                scoreboard.matched_count ==
                2 * fifo_depth + 4
            );

            if (
                !final1_completed ||
                scoreboard.output0_count != fifo_depth + 1 ||
                scoreboard.output1_count != fifo_depth + 3 ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "Output 1 FIFO drain or packet lock failed"
                )

            end

            output1_full_verified = 1'b1;

            `uvm_info(
                "DEPTH",
                "[PASS] P03 Output 1 capacity and APB packet lock",
                UVM_LOW
            )

        endtask

        // ==================================================
        // P04: VERIFY NEW ROUTE AFTER OUTPUT 1 DRAIN
        // ==================================================

        task automatic verify_next_packet_output0();

            send_beat(
                32'hD400_0001,
                4'hF,
                1'b0
            );

            send_beat(
                32'hD400_0002,
                4'h3,
                1'b1
            );

            wait (
                scoreboard.matched_count ==
                2 * fifo_depth + 6
            );

            if (
                scoreboard.output0_count != fifo_depth + 3 ||
                scoreboard.output1_count != fifo_depth + 3 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "Final packet did not follow Output 0 route"
                )

            end

            `uvm_info(
                "DEPTH",
                "[PASS] P04 next packet followed Output 0",
                UVM_LOW
            )

        endtask

        // ==================================================
        // MAIN TEST
        // ==================================================

        task run_phase(uvm_phase phase);

            int unsigned expected_beats;
            int unsigned expected_per_output;

            phase.raise_objection(this);

            // Initialize the sinks.
            out0_vif.tready = 1'b1;
            out1_vif.tready = 1'b1;

            // Reuse the existing AXI protocol checker.
            // The randomized READY controller is not
            // started in this directed depth test.
            fork
                check_stability();
            join_none

            wait (src_vif.aresetn === 1'b1);

            // Execute both FIFO capacity tests.
            verify_output0_capacity();
            verify_next_packet_output1();

            verify_output1_capacity();
            verify_next_packet_output0();

            // Continue observing after the final beat.
            repeat (5) @(posedge src_vif.aclk);

            expected_beats = 2 * fifo_depth + 6;
            expected_per_output = fifo_depth + 3;

            // ------------------------------------------
            // Verify coverage of both FIFO capacities
            // ------------------------------------------

            if (
                !output0_full_verified ||
                !output1_full_verified ||
                full0_checks != 9 ||
                full1_checks != 9
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "Both FIFO depth boundaries were not verified"
                )

            end

            // ------------------------------------------
            // Final AXI accounting
            // ------------------------------------------

            if (
                expected_axi_count != expected_beats ||
                axis_drv.driven_count != expected_beats ||
                input_mon.observed_count != expected_beats ||
                scoreboard.input_count != expected_beats ||
                scoreboard.matched_count != expected_beats ||
                output0_mon.observed_count != expected_per_output ||
                output1_mon.observed_count != expected_per_output ||
                scoreboard.output0_count != expected_per_output ||
                scoreboard.output1_count != expected_per_output ||
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.expected_q1.size() != 0 ||
                scoreboard.in_packet
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "Parameterized AXI transaction accounting failed"
                )

            end

            // ------------------------------------------
            // Final APB accounting
            // ------------------------------------------

            if (
                expected_apb_count != 6 ||
                expected_apb_errors != 1 ||
                cfg_agent.driver.completed_count != 6 ||
                cfg_agent.monitor.observed_count != 6 ||
                scoreboard.apb_count != 6 ||
                scoreboard.apb_error_count != 1
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "Parameterized APB accounting failed"
                )

            end

            // ------------------------------------------
            // Verify actual backpressure
            // ------------------------------------------

            if (
                source_stall_cycles == 0 ||
                output0_stall_cycles == 0 ||
                output1_stall_cycles == 0
            ) begin

                `uvm_fatal(
                    "DEPTH",
                    "Required backpressure did not occur"
                )

            end

            // ------------------------------------------
            // Final result
            // ------------------------------------------

            `uvm_info(
                "DEPTH",
                $sformatf(
                    "DEPTH_SUMMARY depth=%0d input=%0d matched=%0d out0=%0d out1=%0d apb=%0d errors=%0d",
                    fifo_depth,
                    scoreboard.input_count,
                    scoreboard.matched_count,
                    scoreboard.output0_count,
                    scoreboard.output1_count,
                    scoreboard.apb_count,
                    scoreboard.apb_error_count
                ),
                UVM_NONE
            )

            `uvm_info(
                "DEPTH",
                "ROUTER_DEPTH_UVM_PASS",
                UVM_NONE
            )

            phase.drop_objection(this);

        endtask

    endclass

endpackage