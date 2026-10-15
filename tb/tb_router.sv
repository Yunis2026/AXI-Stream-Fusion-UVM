
/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : tb_router.sv
 *
 * Description:
 *   Self-checking integration testbench for the buffered router.
 *
 * Features:
 *   - Independent APB routing reference model
 *   - Two expected output queues
 *   - Multi-beat packet verification
 *   - Mid-packet APB configuration changes
 *   - Output backpressure verification
 *   - Output payload stability checks
 *
 * Notes:
 *   This is the first integration testbench.
 *   Full FIFO, reset stress, and randomized regression
 *   will be added in the next verification phase.
 */

`timescale 1ns/1ps

module tb_router;

    localparam int DATA_WIDTH = 32;
    localparam int FIFO_DEPTH = 4;

    typedef logic [36:0] beat_t;

    // --------------------------------------------------
    // 1. Clock and reset
    // --------------------------------------------------

    logic clk = 1'b0;
    logic rst_n = 1'b0;

    always #5 clk = ~clk;
    // --------------------------------------------------
    // Global simulation timeout protection
    // --------------------------------------------------

    // Prevent the testbench from hanging indefinitely
    // if an AXI-Stream handshake never completes.
    initial begin
    #10000;
    $fatal(1, "[FAIL] Router simulation timeout");
    end

    // --------------------------------------------------
    // 2. APB interface
    // --------------------------------------------------

    logic        psel = 0;
    logic        penable = 0;
    logic        pwrite = 0;
    logic [7:0]  paddr = '0;
    logic [31:0] pwdata = '0;

    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    // --------------------------------------------------
    // 3. AXI-Stream input
    // --------------------------------------------------

    logic [31:0] s_axis_tdata = '0;
    logic [3:0]  s_axis_tkeep = '0;
    logic        s_axis_tlast = 0;
    logic        s_axis_tvalid = 0;
    logic        s_axis_tready;

    // --------------------------------------------------
    // 4. AXI-Stream output 0
    // --------------------------------------------------

    logic [31:0] m0_axis_tdata;
    logic [3:0]  m0_axis_tkeep;
    logic        m0_axis_tlast;
    logic        m0_axis_tvalid;
    logic        m0_axis_tready = 1;

    // --------------------------------------------------
    // 5. AXI-Stream output 1
    // --------------------------------------------------

    logic [31:0] m1_axis_tdata;
    logic [3:0]  m1_axis_tkeep;
    logic        m1_axis_tlast;
    logic        m1_axis_tvalid;
    logic        m1_axis_tready = 1;

    // --------------------------------------------------
    // 6. DUT instantiation
    // --------------------------------------------------

    buffered_router #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),

        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),

        .m0_axis_tdata(m0_axis_tdata),
        .m0_axis_tkeep(m0_axis_tkeep),
        .m0_axis_tlast(m0_axis_tlast),
        .m0_axis_tvalid(m0_axis_tvalid),
        .m0_axis_tready(m0_axis_tready),

        .m1_axis_tdata(m1_axis_tdata),
        .m1_axis_tkeep(m1_axis_tkeep),
        .m1_axis_tlast(m1_axis_tlast),
        .m1_axis_tvalid(m1_axis_tvalid),
        .m1_axis_tready(m1_axis_tready)
    );

    // --------------------------------------------------
    // 7. Independent reference model
    // --------------------------------------------------

    beat_t expected_q0[$];
    beat_t expected_q1[$];

    // These values are predicted from bus transactions,
    // not from internal DUT routing registers.
    bit ref_route_sel = 0;
    bit ref_in_packet = 0;
    bit ref_packet_route = 0;

    // Total accepted input and output transfers.
    int input_count = 0;
    int output_count = 0;

    // Number of pending beats legitimately discarded by reset.
    int reset_dropped_count = 0;

    // Track output stalls across clock boundaries.
    bit prev_stall0 = 0;
    bit prev_stall1 = 0;

    beat_t prev_data0;
    beat_t prev_data1;

    // --------------------------------------------------
    // 8. Scoreboard and protocol checker
    // --------------------------------------------------

    always @(posedge clk) begin : scoreboard

        beat_t actual;
        beat_t expected;
        bit selected_route;

        if (rst_n) begin

            // Verify that a previously stalled output
            // remains valid and preserves its payload.
            if (prev_stall0) begin
                actual = {
                    m0_axis_tlast,
                    m0_axis_tkeep,
                    m0_axis_tdata
                };

                if (!m0_axis_tvalid || actual !== prev_data0)
                    $fatal(1, "[FAIL] Output 0 changed while stalled");
            end

            if (prev_stall1) begin
                actual = {
                    m1_axis_tlast,
                    m1_axis_tkeep,
                    m1_axis_tdata
                };

                if (!m1_axis_tvalid || actual !== prev_data1)
                    $fatal(1, "[FAIL] Output 1 changed while stalled");
            end

            // Remember current stalled output payloads.
            prev_stall0 = m0_axis_tvalid && !m0_axis_tready;
            prev_stall1 = m1_axis_tvalid && !m1_axis_tready;

            prev_data0 = {
                m0_axis_tlast,
                m0_axis_tkeep,
                m0_axis_tdata
            };

            prev_data1 = {
                m1_axis_tlast,
                m1_axis_tkeep,
                m1_axis_tdata
            };

            // Process output handshakes first.
            // These must consume previously queued beats.
            if (m0_axis_tvalid && m0_axis_tready) begin

                if (expected_q0.size() == 0)
                    $fatal(1, "[FAIL] Unexpected Output 0 beat");

                expected = expected_q0.pop_front();

                actual = {
                    m0_axis_tlast,
                    m0_axis_tkeep,
                    m0_axis_tdata
                };

                if (actual !== expected)
                    $fatal(1, "[FAIL] Output 0 data mismatch");

                output_count++;
            end

            if (m1_axis_tvalid && m1_axis_tready) begin

                if (expected_q1.size() == 0)
                    $fatal(1, "[FAIL] Unexpected Output 1 beat");

                expected = expected_q1.pop_front();

                actual = {
                    m1_axis_tlast,
                    m1_axis_tkeep,
                    m1_axis_tdata
                };

                if (actual !== expected)
                    $fatal(1, "[FAIL] Output 1 data mismatch");

                output_count++;
            end

            // Build expected transactions from accepted
            // input beats, using independent packet state.
            if (s_axis_tvalid && s_axis_tready) begin

                selected_route = ref_in_packet
                               ? ref_packet_route
                               : ref_route_sel;

                expected = {
                    s_axis_tlast,
                    s_axis_tkeep,
                    s_axis_tdata
                };

                if (selected_route == 0)
                    expected_q0.push_back(expected);
                else
                    expected_q1.push_back(expected);

                // Capture route on the first accepted beat.
                if (!ref_in_packet)
                    ref_packet_route = ref_route_sel;

                // Release lock only on an accepted TLAST.
                ref_in_packet = !s_axis_tlast;

                input_count++;
            end

            // Apply APB updates after input prediction.
            // This preserves pre-edge routing semantics
            // for simultaneous APB writes and first beats.
            if (psel && penable && pwrite &&
                pready && !pslverr) begin

                ref_route_sel = pwdata[0];
            end

        end
        else begin

    // Account for accepted beats that have not yet
    // been transmitted when reset is asserted.
    reset_dropped_count +=
        expected_q0.size() + expected_q1.size();

    // Reset flushes both expected output queues.
    expected_q0.delete();
    expected_q1.delete();

    // Reset the independent APB and packet models.
    ref_route_sel    = 1'b0;
    ref_in_packet    = 1'b0;
    ref_packet_route = 1'b0;

    // Clear output stall history across reset.
    prev_stall0 = 1'b0;
    prev_stall1 = 1'b0;

    end

    end

    // --------------------------------------------------
    // 9. APB write helper
    // --------------------------------------------------

    task automatic write_route(input bit route);

        // Setup phase: address and data become valid.
        @(negedge clk);

        psel    = 1;
        penable = 0;
        pwrite  = 1;
        paddr   = 8'h00;
        pwdata  = {31'b0, route};

        // Access phase: enable the APB transaction.
        @(negedge clk);
        penable = 1;

        // Register update occurs on the rising edge.
        @(posedge clk);

        if (!pready || pslverr)
            $fatal(1, "[FAIL] APB write response");

        // Return bus to idle without clock-edge races.
        @(negedge clk);
        psel    = 0;
        penable = 0;
        pwrite  = 0;

    endtask

    // --------------------------------------------------
    // 10. AXI-Stream input driver
    // --------------------------------------------------

    task automatic send_beat(
        input logic [31:0] data,
        input logic [3:0]  keep,
        input bit          last
    );

        // Drive input on the falling edge.
        @(negedge clk);

        s_axis_tdata  = data;
        s_axis_tkeep  = keep;
        s_axis_tlast  = last;
        s_axis_tvalid = 1;

        // Keep the beat stable until a successful
        // TVALID/TREADY handshake occurs.
        do begin
            @(posedge clk);
        end while (!s_axis_tready);

        // Deassert VALID after the accepted clock edge.
        @(negedge clk);
        s_axis_tvalid = 0;

    endtask

    // --------------------------------------------------
    // 11. Wait for all expected output beats
    // --------------------------------------------------

    task automatic wait_for_drain();

        int timeout = 0;

        // Check at falling edges after all DUT sequential
        // updates and scoreboard operations have settled.
        do begin
            @(negedge clk);

            timeout++;

            if (timeout > 30)
                $fatal(1, "[FAIL] Router drain timeout");

        end while (
            expected_q0.size() != 0 ||
            expected_q1.size() != 0
        );

    endtask

    // --------------------------------------------------
    // 12. Directed integration tests
    // --------------------------------------------------

    initial begin

        // Save the full router waveform for debugging.
        $dumpfile("waves/router_basic.vcd");
        $dumpvars(0, tb_router);

        $display("====================================");
        $display(" AXI-Stream Fusion: Router Tests");
        $display("====================================");

        // Initialize DUT using active-low reset.
        repeat (3) @(negedge clk);
        rst_n = 1;

        // R01: Default route is Output 0.
        send_beat(32'h0000_00A1, 4'hF, 1);
        wait_for_drain();
        $display("[PASS] R01: Default Route 0");

        // R02: Change route through APB.
        write_route(1);

        send_beat(32'h0000_00B1, 4'hF, 1);
        wait_for_drain();
        $display("[PASS] R02: APB Route 1");

        // R03: Multi-beat packet with TLAST.
        send_beat(32'h0000_00C1, 4'hF, 0);
        send_beat(32'h0000_00C2, 4'hF, 0);
        send_beat(32'h0000_00C3, 4'h3, 1);

        wait_for_drain();
        $display("[PASS] R03: Multi-Beat Packet");

        // R06: APB changes during an active packet.
        // All beats of Packet D must still use Output 0.
        write_route(0);

        send_beat(32'h0000_00D1, 4'hF, 0);

        // Reconfigure destination while packet is active.
        write_route(1);

        send_beat(32'h0000_00D2, 4'hF, 0);
        send_beat(32'h0000_00D3, 4'h1, 1);

        wait_for_drain();
        $display("[PASS] R06: Packet Route Lock");

        // The next packet must use the new configuration.
        send_beat(32'h0000_00E1, 4'hF, 1);

        wait_for_drain();
        $display("[PASS] R06: New Packet Uses Updated Route");

        // R05: Hold Output 1 not-ready while accepting
        // a two-beat packet into its FIFO.
        @(negedge clk);
        m1_axis_tready = 0;

        send_beat(32'h0000_00F1, 4'hF, 0);
        send_beat(32'h0000_00F2, 4'h3, 1);

        repeat (3) @(negedge clk);

        // Resume output consumption.
        m1_axis_tready = 1;

        wait_for_drain();
        $display("[PASS] R05: Output Backpressure");


        // --------------------------------------------------
        // R04: FIFO Full and Input Backpressure
        // --------------------------------------------------
        //
        // Verification objectives:
        //   1. Fill FIFO 1 while Output 1 is stalled.
        //   2. Confirm the fifth input beat is blocked.
        //   3. Hold the fifth beat stable during the stall.
        //   4. Resume output transfers.
        //   5. Verify that all five beats are delivered
        //      in the correct order without data loss.
        //
        // The first four beats form one packet.
        // The fifth beat is a separate single-beat packet.

        // Ensure the destination remains Output 1.
        write_route(1'b1);

        // Disable Output 1 consumption.
        @(negedge clk);
        m1_axis_tready = 1'b0;

        // Fill all four FIFO entries.
        send_beat(32'h0000_0101, 4'hF, 1'b0);
        send_beat(32'h0000_0102, 4'hF, 1'b0);
        send_beat(32'h0000_0103, 4'hF, 1'b0);
        send_beat(32'h0000_0104, 4'h3, 1'b1);

        // The reference queue must contain four
        // accepted beats while the output is stalled.
        if (expected_q1.size() != FIFO_DEPTH)
            $fatal(1, "[FAIL] R04: FIFO not filled");

        // The selected FIFO is now full.
        // The router must stop accepting input.
        if (s_axis_tready !== 1'b0)
            $fatal(1, "[FAIL] R04: Missing backpressure");

        // Run two activities concurrently:
        //   Thread 1 attempts to send a fifth beat.
        //   Thread 2 checks the stall and later releases
        //            the downstream backpressure.
        fork

            begin : blocked_input

                // This call must wait until the FIFO
                // has available space again.
                send_beat(
                    32'h0000_0105,
                    4'hF,
                    1'b1
                );

            end

            begin : release_backpressure

                // Keep Output 1 stalled for several
                // additional clock cycles.
                repeat (4) @(negedge clk);
                #1;

                // The fifth beat must still be waiting.
                if (s_axis_tvalid !== 1'b1)
                    $fatal(1,
                        "[FAIL] R04: Input VALID dropped");

                if (s_axis_tready !== 1'b0)
                    $fatal(1,
                        "[FAIL] R04: Input accepted while full");

                // Confirm FIFO 1 still presents valid
                // output data even while stalled.
                if (m1_axis_tvalid !== 1'b1)
                    $fatal(1,
                        "[FAIL] R04: Output VALID missing");

                // Allow Output 1 to consume data.
                m1_axis_tready = 1'b1;

            end

        join

        // Wait until all expected beats have exited.
        wait_for_drain();

        $display(
            "[PASS] R04: FIFO Full & Input Backpressure"
        );

        // --------------------------------------------------
        // R07: Simultaneous Push/Pop on FIFO 0
        // --------------------------------------------------
        //
        // Verification objectives:
        //   1. Start with two pending beats in FIFO 0.
        //   2. Enable input and output handshakes
        //      during the same clock cycle.
        //   3. Confirm that both operations are accepted.
        //   4. Confirm FIFO occupancy remains unchanged.
        //   5. Verify that all output data remains ordered.
        //
        // This test uses internal occupancy information
        // only for a white-box check. The scoreboard
        // continues to predict data independently.

        // Configure the router to select Output 0.
        write_route(1'b0);

        // Stall Output 0 so that beats accumulate.
        @(negedge clk);
        m0_axis_tready = 1'b0;

        // Fill FIFO 0 with the first two packet beats.
        send_beat(32'h0000_0201, 4'hF, 1'b0);
        send_beat(32'h0000_0202, 4'hF, 1'b0);

        // The two accepted beats must be pending.
        if (expected_q0.size() != 2)
            $fatal(1,
                "[FAIL] R07: Expected two pending beats");

        if (dut.u_fifo0.count !== 3'd2)
            $fatal(1,
                "[FAIL] R07: Initial FIFO count mismatch");

        // Drive the final packet beat and release
        // output backpressure on the same falling edge.
        @(negedge clk);

        s_axis_tdata  = 32'h0000_0203;
        s_axis_tkeep  = 4'h3;
        s_axis_tlast  = 1'b1;
        s_axis_tvalid = 1'b1;

        m0_axis_tready = 1'b1;

        // Allow combinational handshake logic to settle.
        #1;

        // Both input and output handshakes must occur
        // at the upcoming rising clock edge.
        if (!(s_axis_tvalid && s_axis_tready))
            $fatal(1,
                "[FAIL] R07: Input handshake missing");

        if (!(m0_axis_tvalid && m0_axis_tready))
            $fatal(1,
                "[FAIL] R07: Output handshake missing");

        // Check that FIFO 0 receives both operations.
        if (!(dut.fifo0_push && dut.fifo0_pop))
            $fatal(1,
                "[FAIL] R07: FIFO push/pop not simultaneous");

        // Process the simultaneous operations.
        @(posedge clk);
        #1;

        // One beat entered and one beat exited.
        // Occupancy must remain unchanged.
        if (dut.u_fifo0.count !== 3'd2)
            $fatal(1,
                "[FAIL] R07: FIFO occupancy changed");

        // The independent expected queue must also
        // retain exactly two pending beats.
        if (expected_q0.size() != 2)
            $fatal(1,
                "[FAIL] R07: Reference queue count mismatch");

        // Deassert input VALID at the falling edge
        // to prevent a duplicate transfer.
        @(negedge clk);
        s_axis_tvalid = 1'b0;

        // Allow the remaining FIFO entries to drain.
        wait_for_drain();

        $display(
            "[PASS] R07: Simultaneous FIFO Push/Pop"
        );

        // --------------------------------------------------
        // R08: Dual FIFO Concurrent Operation
        // --------------------------------------------------
        //
        // Verification objectives:
        //   1. Store independent packets in both FIFOs.
        //   2. Verify that both FIFOs can contain pending
        //      transactions at the same time.
        //   3. Allow Output 0 to progress while Output 1
        //      remains stalled.
        //   4. Verify simultaneous output handshakes.
        //   5. Check data ordering through the scoreboard.
        //
        // The independent scoreboard tracks both output
        // queues and checks TDATA, TKEEP, and TLAST.

        // --------------------------------------------------
        // R08-A: Stall both outputs
        // --------------------------------------------------

        @(negedge clk);

        // Prevent both downstream consumers from
        // accepting data while the packets are loaded.
        m0_axis_tready = 1'b0;
        m1_axis_tready = 1'b0;

        // Configure routing to Output 0.
        write_route(1'b0);

        // Send Packet A to FIFO 0.
        // The second beat terminates Packet A.
        send_beat(32'h0000_0301, 4'hF, 1'b0);
        send_beat(32'h0000_0302, 4'h3, 1'b1);

        // Configure routing to Output 1.
        write_route(1'b1);

        // Send Packet B to FIFO 1.
        // Both FIFOs now have pending transactions.
        send_beat(32'h0000_0401, 4'hF, 1'b0);
        send_beat(32'h0000_0402, 4'h1, 1'b1);

        // Verify that each reference queue contains
        // exactly two accepted input beats.
        if (expected_q0.size() != 2)
            $fatal(1,
                "[FAIL] R08: FIFO 0 expected queue size");

        if (expected_q1.size() != 2)
            $fatal(1,
                "[FAIL] R08: FIFO 1 expected queue size");

        // White-box occupancy checks complement the
        // independent transaction-level scoreboard.
        if (dut.u_fifo0.count !== 3'd2)
            $fatal(1,
                "[FAIL] R08: FIFO 0 occupancy mismatch");

        if (dut.u_fifo1.count !== 3'd2)
            $fatal(1,
                "[FAIL] R08: FIFO 1 occupancy mismatch");

        $display(
            "[PASS] R08-A: Both FIFOs Have Pending Packets"
        );

        // --------------------------------------------------
        // R08-B: Release only Output 0
        // --------------------------------------------------

        @(negedge clk);

        // Output 0 can consume data independently.
        // Output 1 remains stalled.
        m0_axis_tready = 1'b1;
        m1_axis_tready = 1'b0;

        #1;

        // FIFO 0 must present valid output data.
        if (!m0_axis_tvalid)
            $fatal(1,
                "[FAIL] R08: Output 0 VALID missing");

        // FIFO 1 must also preserve valid data
        // despite its downstream READY being low.
        if (!m1_axis_tvalid)
            $fatal(1,
                "[FAIL] R08: Output 1 VALID missing");

        // Accept one beat from Output 0.
        @(posedge clk);
        #1;

        // Output 0 has consumed one beat.
        // Output 1 must still have two pending beats.
        if (expected_q0.size() != 1)
            $fatal(1,
                "[FAIL] R08: Output 0 did not progress");

        if (expected_q1.size() != 2)
            $fatal(1,
                "[FAIL] R08: Output 1 progressed while stalled");

        $display(
            "[PASS] R08-B: Independent Output Progress"
        );

        // --------------------------------------------------
        // R08-C: Allow simultaneous output transfers
        // --------------------------------------------------

        @(negedge clk);

        // Both downstream consumers are now ready.
        m0_axis_tready = 1'b1;
        m1_axis_tready = 1'b1;

        #1;

        // Both output handshakes must be possible
        // in the same upcoming clock cycle.
        if (!(m0_axis_tvalid && m0_axis_tready))
            $fatal(1,
                "[FAIL] R08: Output 0 handshake missing");

        if (!(m1_axis_tvalid && m1_axis_tready))
            $fatal(1,
                "[FAIL] R08: Output 1 handshake missing");

        // Consume one beat from each output FIFO
        // on the same rising clock edge.
        @(posedge clk);
        #1;

        // FIFO 0 has now transmitted both packet beats.
        if (expected_q0.size() != 0)
            $fatal(1,
                "[FAIL] R08: FIFO 0 did not drain");

        // FIFO 1 has transmitted its first beat.
        if (expected_q1.size() != 1)
            $fatal(1,
                "[FAIL] R08: FIFO 1 queue mismatch");

        // Drain the remaining Output 1 beat.
        wait_for_drain();

        // Confirm no transactions remain pending.
        if (expected_q0.size() != 0 ||
            expected_q1.size() != 0)
            $fatal(1,
                "[FAIL] R08: Pending data after drain");

        $display(
            "[PASS] R08-C: Simultaneous Output Handshakes"
        );

        $display(
            "[PASS] R08: Dual FIFO Concurrent Operation"
        );

        // --------------------------------------------------
        // R09: Reset With Pending Transactions
        // --------------------------------------------------
        //
        // Verification objectives:
        //   1. Create pending transactions in both FIFOs.
        //   2. Keep a multi-beat packet active.
        //   3. Assert asynchronous reset.
        //   4. Confirm both FIFOs and packet state reset.
        //   5. Confirm the APB route returns to Output 0.
        //   6. Ensure no stale transactions appear.
        //   7. Send new packets after reset recovery.

        // --------------------------------------------------
        // R09-A: Prepare pending transactions
        // --------------------------------------------------

        // Stall both outputs to retain pending data.
        @(negedge clk);
        m0_axis_tready = 1'b0;
        m1_axis_tready = 1'b0;

        // Send a complete two-beat packet to FIFO 0.
        write_route(1'b0);

        send_beat(32'h0000_0501, 4'hF, 1'b0);
        send_beat(32'h0000_0502, 4'h3, 1'b1);

        // Start a second packet on FIFO 1.
        // Do not send TLAST, keeping packet lock active.
        write_route(1'b1);

        send_beat(32'h0000_0601, 4'hF, 1'b0);
        send_beat(32'h0000_0602, 4'hF, 1'b0);

        // Both FIFOs must contain pending transactions.
        if (expected_q0.size() != 2 ||
            expected_q1.size() != 2)
            $fatal(1,
                "[FAIL] R09: Pending queue setup failed");

        // The second packet is intentionally unfinished.
        if (dut.in_packet !== 1'b1)
            $fatal(1,
                "[FAIL] R09: Packet lock not active");

        if (dut.route_sel !== 1'b1)
            $fatal(1,
                "[FAIL] R09: APB route setup incorrect");

        $display(
            "[PASS] R09-A: Pending Data and Active Packet"
        );

        // --------------------------------------------------
        // R09-B: Assert asynchronous reset
        // --------------------------------------------------

        // Assert reset away from the rising clock edge.
        @(negedge clk);

        rst_n = 1'b0;

        // Keep the input interface inactive during reset.
        s_axis_tvalid = 1'b0;

        // Return APB control signals to idle.
        psel    = 1'b0;
        penable = 1'b0;
        pwrite  = 1'b0;

        #1;

        // Asynchronous reset must clear both FIFO counts.
        if (dut.u_fifo0.count !== 3'd0 ||
            dut.u_fifo1.count !== 3'd0)
            $fatal(1,
                "[FAIL] R09: FIFO occupancy not reset");

        // No AXI-Stream output is valid during reset.
        if (m0_axis_tvalid !== 1'b0 ||
            m1_axis_tvalid !== 1'b0)
            $fatal(1,
                "[FAIL] R09: Output VALID during reset");

        // Reset must release the packet lock.
        if (dut.in_packet !== 1'b0)
            $fatal(1,
                "[FAIL] R09: Packet lock not cleared");

        // APB route selection must return to Output 0.
        if (dut.route_sel !== 1'b0)
            $fatal(1,
                "[FAIL] R09: APB route not reset");

        // Hold reset through a rising clock edge so
        // the scoreboard can flush pending transactions.
        @(posedge clk);
        #1;

        if (expected_q0.size() != 0 ||
            expected_q1.size() != 0)
            $fatal(1,
                "[FAIL] R09: Reference queues not flushed");

        // Exactly four previously accepted beats were
        // discarded by reset in this test.
        if (reset_dropped_count != 4)
            $fatal(1,
                "[FAIL] R09: Reset drop count mismatch");

        $display(
            "[PASS] R09-B: Reset Clears Both FIFOs"
        );

        // --------------------------------------------------
        // R09-C: Release reset and check for stale data
        // --------------------------------------------------

        @(negedge clk);
        rst_n = 1'b1;

        // Allow both downstream consumers to run.
        m0_axis_tready = 1'b1;
        m1_axis_tready = 1'b1;

        // Wait for several cycles with no new input.
        // Neither output may produce stale transactions.
        repeat (3) begin

            @(negedge clk);
            #1;

            if (m0_axis_tvalid !== 1'b0 ||
                m1_axis_tvalid !== 1'b0)
                $fatal(1,
                    "[FAIL] R09: Stale data after reset");

        end

        $display(
            "[PASS] R09-C: No Stale Output After Reset"
        );

        // --------------------------------------------------
        // R09-D: Verify post-reset recovery
        // --------------------------------------------------

        // APB route defaults to Output 0.
        // No APB write is performed before this packet.
        send_beat(32'h0000_0701, 4'hF, 1'b1);

        wait_for_drain();

        // Verify APB can configure Output 1 again.
        write_route(1'b1);

        send_beat(32'h0000_0702, 4'h3, 1'b1);

        wait_for_drain();

        // All new transactions must be delivered.
        if (expected_q0.size() != 0 ||
            expected_q1.size() != 0)
            $fatal(1,
                "[FAIL] R09: Post-reset queues not empty");

        $display(
            "[PASS] R09-D: Post-Reset Router Recovery"
        );

        $display(
            "[PASS] R09: Reset With Pending Transactions"
        );




        // Both output reference queues must be empty.
        if (expected_q0.size() != 0 ||
            expected_q1.size() != 0)
            $fatal(1, "[FAIL] Pending expected beats");

        // Every input beat must be observed at an output.
        // Every accepted input beat must either be delivered
        // successfully or explicitly discarded by reset.  
        if (input_count != output_count + reset_dropped_count)
           $fatal(1,
        "[FAIL] Router beat accounting mismatch");

        // Display the final directed verification summary.
        $display("");
        $display("====================================");
        $display(" ALL ROUTER DIRECTED TESTS PASSED");
        $display(" Input beats        : %0d", input_count);
        $display(" Output beats       : %0d", output_count);
        $display(" Reset dropped beats: %0d", reset_dropped_count);
        $display("====================================");

        $finish;

    end

endmodule
