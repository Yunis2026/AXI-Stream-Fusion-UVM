
/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : tb_apb_regs.sv
 *
 * Description:
 *   Self-checking directed testbench for APB route registers.
 *
 * Verification:
 *   - Reset values
 *   - APB read/write transactions
 *   - Setup and access phase behavior
 *   - Reserved register bits
 *   - Invalid address error response
 *   - Register stability and reset recovery
 */

`timescale 1ns/1ps

module tb_apb_regs;

    // --------------------------------------------------
    // Clock and reset
    // --------------------------------------------------

    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    // Generate a 10 ns clock.
    always #5 clk = ~clk;

    // --------------------------------------------------
    // APB interface signals
    // --------------------------------------------------

    logic        psel    = 1'b0;
    logic        penable = 1'b0;
    logic        pwrite  = 1'b0;

    logic [7:0]  paddr   = '0;
    logic [31:0] pwdata  = '0;

    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    // Routing configuration output
    logic route_sel;

    // Number of completed test cases.
    int test_count = 0;

    // --------------------------------------------------
    // DUT instantiation
    // --------------------------------------------------

    apb_route_regs dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .psel      (psel),
        .penable   (penable),
        .pwrite    (pwrite),
        .paddr     (paddr),
        .pwdata    (pwdata),
        .prdata    (prdata),
        .pready    (pready),
        .pslverr   (pslverr),
        .route_sel (route_sel)
    );

    // --------------------------------------------------
    // APB write task
    // --------------------------------------------------

    task automatic apb_write(
        input logic [7:0]  addr,
        input logic [31:0] data,
        input bit          expect_error,
        input bit          expected_route,
        input string       test_name
    );

        bit old_route;

        old_route = route_sel;

        // SETUP PHASE:
        // Drive the request on a falling clock edge.
        @(negedge clk);

        psel    = 1'b1;
        penable = 1'b0;
        pwrite  = 1'b1;
        paddr   = addr;
        pwdata  = data;

        #1;

        // A register write must not occur in setup phase.
        if (route_sel !== old_route)
            $fatal(1, "[FAIL] Register changed in setup");

        // Error response is only asserted during access.
        if (pslverr !== 1'b0)
            $fatal(1, "[FAIL] PSLVERR during setup");

        // ACCESS PHASE:
        // Assert PENABLE during the next cycle.
        @(negedge clk);
        penable = 1'b1;

        #1;

        // This DUT implements zero-wait-state APB.
        if (pready !== 1'b1)
            $fatal(1, "[FAIL] PREADY mismatch");

        if (pslverr !== expect_error)
            $fatal(1, "[FAIL] PSLVERR mismatch");

        // A write must not commit before the access edge.
        if (route_sel !== old_route)
            $fatal(1, "[FAIL] Early register update");

        // Commit the APB transfer at the rising edge.
        @(posedge clk);
        #1;

        if (route_sel !== expected_route)
            $fatal(1, "[FAIL] %s: ROUTE_SEL mismatch",
                   test_name);

        // Return the APB bus to idle.
        @(negedge clk);

        psel    = 1'b0;
        penable = 1'b0;
        pwrite  = 1'b0;

        #1;

        test_count++;

        $display("[PASS] %s", test_name);

    endtask

    // --------------------------------------------------
    // APB read task
    // --------------------------------------------------

    task automatic apb_read(
        input logic [7:0]  addr,
        input logic [31:0] expected_data,
        input bit          expect_error,
        input string       test_name
    );

        bit old_route;

        old_route = route_sel;

        // SETUP PHASE
        @(negedge clk);

        psel    = 1'b1;
        penable = 1'b0;
        pwrite  = 1'b0;
        paddr   = addr;

        // ACCESS PHASE
        @(negedge clk);
        penable = 1'b1;

        #1;

        // Check read data and APB response signals.
        if (pready !== 1'b1)
            $fatal(1, "[FAIL] PREADY during read");

        if (pslverr !== expect_error)
            $fatal(1, "[FAIL] Read PSLVERR mismatch");

        if (prdata !== expected_data)
            $fatal(1,
                   "[FAIL] %s: PRDATA mismatch",
                   test_name);

        // Reading must not modify routing configuration.
        @(posedge clk);
        #1;

        if (route_sel !== old_route)
            $fatal(1, "[FAIL] Read modified register");

        // Return to idle.
        @(negedge clk);

        psel    = 1'b0;
        penable = 1'b0;

        #1;

        test_count++;

        $display("[PASS] %s", test_name);

    endtask

    // --------------------------------------------------
    // Main test sequence
    // --------------------------------------------------

    initial begin

        // Enable waveform recording.
        $dumpfile("waves/apb_regs_directed.vcd");
        $dumpvars(0, tb_apb_regs);

        $display("====================================");
        $display(" AXI-Stream Fusion: APB Verification");
        $display("====================================");

        // T01: Initial reset.
        repeat (2) @(negedge clk);
        #1;

        if (route_sel !== 1'b0)
            $fatal(1, "[FAIL] T01: Reset value");

        rst_n = 1'b1;

        test_count++;
        $display("[PASS] T01: Initial Reset");

        // T02: Select Output 1.
        apb_write(
            8'h00, 32'h0000_0001,
            1'b0, 1'b1,
            "T02: Write ROUTE_SEL = 1"
        );

        // T03: Read routing configuration.
        apb_read(
            8'h00, 32'h0000_0001,
            1'b0,
            "T03: Read ROUTE_SEL = 1"
        );

        // T04: Select Output 0.
        apb_write(
            8'h00, 32'h0000_0000,
            1'b0, 1'b0,
            "T04: Write ROUTE_SEL = 0"
        );

        // T05: Reserved upper bits must be ignored.
        apb_write(
            8'h00, 32'hFFFF_FFFE,
            1'b0, 1'b0,
            "T05: Reserved Bits Ignored"
        );

        apb_read(
            8'h00, 32'h0000_0000,
            1'b0,
            "T05: Reserved Bits Read Zero"
        );

        // T06: Invalid write must not change ROUTE_SEL.
        apb_write(
            8'h04, 32'h0000_0001,
            1'b1, 1'b0,
            "T06: Invalid Address Write"
        );

        // T07: Invalid read must report error.
        apb_read(
            8'h04, 32'h0000_0000,
            1'b1,
            "T07: Invalid Address Read"
        );

        // T08: Setup phase protection is checked
        // automatically by every apb_write() transaction.
        test_count++;
        $display("[PASS] T08: Setup Phase Protection");

        // T09: Reset after configuration.
        apb_write(
            8'h00, 32'h0000_0001,
            1'b0, 1'b1,
            "T09: Configure Before Reset"
        );

        // Assert reset between active clock edges.
        @(negedge clk);

        rst_n  = 1'b0;
        psel   = 1'b0;
        penable = 1'b0;

        #1;

        if (route_sel !== 1'b0)
            $fatal(1, "[FAIL] T09: Reset failed");

        // Hold reset through a rising clock edge.
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        test_count++;
        $display("[PASS] T09: Reset Recovery");

        // Final summary.
        $display("");
        $display("====================================");
        $display(" ALL APB DIRECTED TESTS PASSED");
        $display(" Passed checks: %0d", test_count);
        $display("====================================");

        $finish;

    end

endmodule
