
/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : tb_fifo.sv
 *
 * Description:
 *   Self-checking SystemVerilog testbench for the synchronous FIFO.
 *
 * Verification scenarios:
 *   1. Reset and initial empty state
 *   2. Normal FIFO push operations
 *   3. Full and overflow protection
 *   4. Simultaneous push/pop
 *   5. FIFO ordering and empty protection
 *   6. Pointer wraparound
 *   7. Reset with pending data
 *
 * Methodology:
 *   An independent SystemVerilog queue acts as the reference model.
 *   All expected values are derived from accepted FIFO operations.
 */

`timescale 1ns/1ps

module tb_fifo;

    // --------------------------------------------------
    // Configuration
    // --------------------------------------------------

    localparam int DATA_WIDTH = 37;
    localparam int DEPTH      = 4;

    typedef logic [DATA_WIDTH-1:0] beat_t;

    // --------------------------------------------------
    // DUT interface signals
    // --------------------------------------------------

    logic clk = 0;
    logic rst_n = 0;

    logic push = 0;
    logic pop  = 0;

    beat_t din  = '0;
    beat_t dout;

    logic full;
    logic empty;

    // --------------------------------------------------
    // Reference model and test statistics
    // --------------------------------------------------

    beat_t expected_q[$];

    int test_count = 0;

    // --------------------------------------------------
    // Clock generation: 10 ns period
    // --------------------------------------------------

    always #5 clk = ~clk;

    // --------------------------------------------------
    // DUT instantiation
    // --------------------------------------------------

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .push  (push),
        .din   (din),
        .pop   (pop),
        .dout  (dout),
        .full  (full),
        .empty (empty)
    );

    // --------------------------------------------------
    // Check FIFO status against the reference queue
    // --------------------------------------------------

    task automatic check_status(input string test_name);

        bit expected_full;
        bit expected_empty;

        expected_full  = (expected_q.size() == DEPTH);
        expected_empty = (expected_q.size() == 0);

        if (full !== expected_full) begin
            $fatal(1,
                "[FAIL] %s: FULL mismatch",
                test_name
            );
        end

        if (empty !== expected_empty) begin
            $fatal(1,
                "[FAIL] %s: EMPTY mismatch",
                test_name
            );
        end

        // The DUT specifies zero output when FIFO is empty.
        if (expected_empty && dout !== '0) begin
            $fatal(1,
                "[FAIL] %s: DOUT must be zero when empty",
                test_name
            );
        end

        // Verify the visible head when FIFO is non-empty.
        if (!expected_empty && dout !== expected_q[0]) begin
            $fatal(1,
                "[FAIL] %s: FIFO head mismatch",
                test_name
            );
        end

    endtask

    // --------------------------------------------------
    // Execute and automatically verify one clock cycle
    // --------------------------------------------------

    task automatic run_cycle(
        input bit    do_push,
        input bit    do_pop,
        input beat_t data,
        input string test_name
    );

        bit accepted_push;
        bit accepted_pop;
        beat_t discarded;

        // Drive inputs on the falling edge to avoid races
        // with the DUT's rising-edge sequential logic.
        @(negedge clk);

        push = do_push;
        pop  = do_pop;
        din  = data;

        #1;

        // Predict accepted operations independently.
        // This matches the specified conservative full policy.
        accepted_push = do_push &&
                        (expected_q.size() < DEPTH);

        accepted_pop = do_pop &&
                       (expected_q.size() > 0);

        // Check the state before the active clock edge.
        check_status(test_name);

        // Wait for the DUT to process the operations.
        @(posedge clk);

        // Update the reference model using the
        // pre-edge accepted operations.
        if (accepted_pop) begin
            discarded = expected_q.pop_front();
        end

        if (accepted_push) begin
            expected_q.push_back(data);
        end

        // Allow nonblocking assignments to settle.
        #1;

        // Compare the resulting FIFO state.
        check_status(test_name);

        test_count++;

        $display(
            "[PASS] %-32s | Occupancy = %0d",
            test_name,
            expected_q.size()
        );

    endtask

    // --------------------------------------------------
    // Main directed test sequence
    // --------------------------------------------------

    initial begin

        // --------------------------------------------------
// Waveform dump for debugging and verification
// --------------------------------------------------

// Save the waveform to the project's waves directory.
$dumpfile("waves/fifo_directed.vcd");

// Record the testbench and DUT signals.
$dumpvars(0, tb_fifo);
        $display("====================================");
        $display(" AXI-Stream Fusion: FIFO Testbench");
        $display("====================================");

        // --------------------------------------------------
        // T01: Initial reset
        // --------------------------------------------------

        repeat (2) @(posedge clk);
        #1;

        expected_q.delete();
        check_status("T01: Initial Reset");

        rst_n = 1;

        $display("[PASS] T01: Initial Reset");

        // --------------------------------------------------
        // T02: Normal FIFO push
        // --------------------------------------------------

        run_cycle(1, 0, 37'd11, "T02: Push A");
        run_cycle(1, 0, 37'd22, "T02: Push B");
        run_cycle(1, 0, 37'd33, "T02: Push C");
        run_cycle(1, 0, 37'd44, "T02: Push D");

        // --------------------------------------------------
        // T03: Full and overflow protection
        // --------------------------------------------------

        // FIFO is full; this push must be rejected.
        run_cycle(1, 0, 37'd55, "T03: Push When Full");

        // --------------------------------------------------
        // T04: Simultaneous push/pop
        // --------------------------------------------------

        // FIFO starts full. Pop succeeds, but push is
        // rejected under the conservative full policy.
        run_cycle(1, 1, 37'd66, "T04: Push/Pop When Full");

        // FIFO now has three entries.
        // Both operations should be accepted.
        run_cycle(1, 1, 37'd66, "T04: Simultaneous Push/Pop");

        // --------------------------------------------------
        // T05: FIFO ordering and empty protection
        // --------------------------------------------------

        run_cycle(0, 1, '0, "T05: Pop C");
        run_cycle(0, 1, '0, "T05: Pop D");
        run_cycle(0, 1, '0, "T05: Pop New Data");

        // Reading an empty FIFO must not change its state.
        run_cycle(0, 1, '0, "T05: Pop When Empty");

        // --------------------------------------------------
        // T06: Pointer wraparound
        // --------------------------------------------------

        run_cycle(1, 0, 37'd77, "T06: Push 77");
        run_cycle(1, 0, 37'd88, "T06: Push 88");

        run_cycle(0, 1, '0, "T06: Pop 77");

        run_cycle(1, 0, 37'd99, "T06: Push 99");

        run_cycle(0, 1, '0, "T06: Pop 88");
        run_cycle(0, 1, '0, "T06: Pop 99");

        // --------------------------------------------------
        // T07: Reset with pending data
        // --------------------------------------------------

        run_cycle(1, 0, 37'd101, "T07: Push Before Reset");
        run_cycle(1, 0, 37'd102, "T07: Second Pending Beat");

        // Assert reset away from the rising clock edge.
        @(negedge clk);

        push  = 0;
        pop   = 0;
        rst_n = 0;

        expected_q.delete();

        #1;
        check_status("T07: Async Reset");

        // Keep reset asserted through one clock edge.
        @(posedge clk);
        #1;

        rst_n = 1;

        check_status("T07: Reset Released");

        $display("[PASS] T07: Reset With Pending Data");

        // Verify that the FIFO operates after reset.
        run_cycle(1, 0, 37'd103, "T07: Push After Reset");
        run_cycle(0, 1, '0, "T07: Pop After Reset");

        // --------------------------------------------------
        // Final test result
        // --------------------------------------------------

        if (expected_q.size() != 0) begin
            $fatal(1, "[FAIL] Reference queue not empty");
        end

        $display("");
        $display("====================================");
        $display(" ALL FIFO DIRECTED TESTS PASSED");
        $display(" Checked cycles: %0d", test_count);
        $display("====================================");

        $finish;

    end

endmodule
