/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : tb_apb_uvm_top.sv
 *
 * Description:
 *   APB UVM agent and monitor integration test.
 *
 * Verification architecture:
 *
 *       APB Basic Sequence
 *               |
 *               v
 *           APB Agent
 *        +------+------+
 *        |             |
 *    Sequencer       Monitor
 *        |             |
 *      Driver     Analysis Port
 *        |             |
 *        v             v
 *     APB Bus     Analysis FIFO
 *        |
 *        v
 *  APB Register DUT
 *
 * Checks:
 *   - Ten directed APB transactions
 *   - Driver completion count
 *   - Monitor observation count
 *   - APB read/write/error statistics
 *   - Independent analysis FIFO contents
 */

`timescale 1ns/1ps

// ==================================================
// 1. UVM TEST PACKAGE
// ==================================================

package apb_uvm_smoke_pkg;

    import uvm_pkg::*;
    import apb_pkg::*;

    `include "uvm_macros.svh"

    // --------------------------------------------------
    // APB UVM smoke test
    // --------------------------------------------------

    class apb_uvm_smoke_test extends uvm_test;

        `uvm_component_utils(apb_uvm_smoke_test)

        // APB active agent.
        apb_agent agent;

        // Stores transactions published by the monitor.
        uvm_tlm_analysis_fifo #(apb_item) observed_fifo;

        // --------------------------------------------------
        // Constructor
        // --------------------------------------------------

        function new(
            string name = "apb_uvm_smoke_test",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // --------------------------------------------------
        // Build phase
        // --------------------------------------------------

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            // Create a reusable APB agent.
            agent = apb_agent::type_id::create(
                "agent",
                this
            );

            // Create a transaction FIFO connected to
            // the passive monitor analysis port.
            observed_fifo = new(
                "observed_fifo",
                this
            );

        endfunction

        // --------------------------------------------------
        // Connect phase
        // --------------------------------------------------

        function void connect_phase(uvm_phase phase);

            super.connect_phase(phase);

            // The APB agent connects its own driver
            // and sequencer internally.

            // Subscribe the analysis FIFO to all
            // observed APB transactions.
            agent.monitor.ap.connect(
                observed_fifo.analysis_export
            );

        endfunction

        // --------------------------------------------------
        // Verify monitor transaction stream
        // --------------------------------------------------

        function void verify_observed_transactions();

            apb_item observed;

            bit expected_write;
            bit [7:0] expected_addr;
            bit [31:0] expected_wdata;
            bit [31:0] expected_rdata;
            bit expected_error;

            // Ten transactions are expected.
            for (int i = 0; i < 10; i++) begin

                // Determine expected APB bus activity.
                case (i)

                    0: begin
                        expected_write = 1'b0;
                        expected_addr  = 8'h00;
                        expected_wdata = 32'h0000_0000;
                        expected_rdata = 32'h0000_0000;
                        expected_error = 1'b0;
                    end

                    1: begin
                        expected_write = 1'b1;
                        expected_addr  = 8'h00;
                        expected_wdata = 32'h0000_0001;
                        expected_rdata = 32'h0000_0000;
                        expected_error = 1'b0;
                    end

                    2: begin
                        expected_write = 1'b0;
                        expected_addr  = 8'h00;
                        expected_wdata = 32'h0000_0000;
                        expected_rdata = 32'h0000_0001;
                        expected_error = 1'b0;
                    end

                    3: begin
                        expected_write = 1'b1;
                        expected_addr  = 8'h04;
                        expected_wdata = 32'h0000_0000;
                        expected_rdata = 32'h0000_0000;
                        expected_error = 1'b1;
                    end

                    4: begin
                        expected_write = 1'b0;
                        expected_addr  = 8'h00;
                        expected_wdata = 32'h0000_0000;
                        expected_rdata = 32'h0000_0001;
                        expected_error = 1'b0;
                    end

                    5: begin
                        expected_write = 1'b1;
                        expected_addr  = 8'h00;
                        expected_wdata = 32'hFFFF_FFFE;
                        expected_rdata = 32'h0000_0000;
                        expected_error = 1'b0;
                    end

                    6: begin
                        expected_write = 1'b0;
                        expected_addr  = 8'h00;
                        expected_wdata = 32'h0000_0000;
                        expected_rdata = 32'h0000_0000;
                        expected_error = 1'b0;
                    end

                    7: begin
                        expected_write = 1'b1;
                        expected_addr  = 8'h00;
                        expected_wdata = 32'h0000_0000;
                        expected_rdata = 32'h0000_0000;
                        expected_error = 1'b0;
                    end

                    8: begin
                        expected_write = 1'b0;
                        expected_addr  = 8'h00;
                        expected_wdata = 32'h0000_0000;
                        expected_rdata = 32'h0000_0000;
                        expected_error = 1'b0;
                    end

                    9: begin
                        expected_write = 1'b0;
                        expected_addr  = 8'h04;
                        expected_wdata = 32'h0000_0000;
                        expected_rdata = 32'h0000_0000;
                        expected_error = 1'b1;
                    end

                    default: begin
                        `uvm_fatal(
                            "APB_TEST",
                            "Unexpected transaction index"
                        )
                    end

                endcase

                // Each bus transfer must have been
                // delivered through the analysis FIFO.
                if (!observed_fifo.try_get(observed)) begin

                    `uvm_fatal(
                        "APB_TEST",
                        $sformatf(
                            "Missing observed APB transaction %0d",
                            i + 1
                        )
                    )

                end

                // Compare request type, address and
                // slave error response.
                if (
                    observed.write  !== expected_write ||
                    observed.addr   !== expected_addr  ||
                    observed.slverr !== expected_error
                ) begin

                    `uvm_fatal(
                        "APB_TEST",
                        $sformatf(
                            "Observed APB control mismatch at transaction %0d: %s",
                            i + 1,
                            observed.convert2string()
                        )
                    )

                end

                // Compare write payload for writes.
                if (
                    expected_write &&
                    observed.wdata !== expected_wdata
                ) begin

                    `uvm_fatal(
                        "APB_TEST",
                        $sformatf(
                            "Observed APB write-data mismatch at transaction %0d",
                            i + 1
                        )
                    )

                end

                // Compare read response for reads.
                if (
                    !expected_write &&
                    observed.rdata !== expected_rdata
                ) begin

                    `uvm_fatal(
                        "APB_TEST",
                        $sformatf(
                            "Observed APB read-data mismatch at transaction %0d",
                            i + 1
                        )
                    )

                end

                `uvm_info(
                    "APB_TEST",
                    $sformatf(
                        "[MATCH] APB monitor transaction %0d",
                        i + 1
                    ),
                    UVM_LOW
                )

            end

            // No unexpected observed transactions
            // should remain in the analysis FIFO.
            if (observed_fifo.used() != 0) begin

                `uvm_fatal(
                    "APB_TEST",
                    "Unexpected extra observed APB transactions"
                )

            end

        endfunction

        // --------------------------------------------------
        // Run phase
        // --------------------------------------------------

        task run_phase(uvm_phase phase);

            apb_basic_sequence seq;

            phase.raise_objection(this);

            seq = apb_basic_sequence::type_id::create(
                "seq"
            );

            `uvm_info(
                "APB_TEST",
                "Starting APB UVM agent verification",
                UVM_LOW
            )

            // Start the sequence using the sequencer
            // owned by the reusable APB agent.
            seq.start(agent.sequencer);

            // ------------------------------------------
            // Sequence and driver count checks
            // ------------------------------------------

            if (seq.checked_count != 10) begin

                `uvm_fatal(
                    "APB_TEST",
                    "APB sequence transaction count mismatch"
                )

            end

            if (agent.driver.completed_count != 10) begin

                `uvm_fatal(
                    "APB_TEST",
                    "APB driver transaction count mismatch"
                )

            end

            // ------------------------------------------
            // Passive monitor statistics
            // ------------------------------------------

            if (
                agent.monitor.observed_count != 10 ||
                agent.monitor.write_count    != 4  ||
                agent.monitor.read_count     != 6  ||
                agent.monitor.error_count    != 2
            ) begin

                `uvm_fatal(
                    "APB_TEST",
                    $sformatf(
                        "APB monitor counts incorrect: total=%0d writes=%0d reads=%0d errors=%0d",
                        agent.monitor.observed_count,
                        agent.monitor.write_count,
                        agent.monitor.read_count,
                        agent.monitor.error_count
                    )
                )

            end

            // Verify the actual bus transactions
            // published through the analysis port.
            verify_observed_transactions();

            `uvm_info(
                "APB_TEST",
                "[PASS] APB monitor and agent integration",
                UVM_LOW
            )

            // Retain the existing regression markers.
            `uvm_info(
                "APB_TEST",
                "[PASS] APB transactions verified: 10",
                UVM_LOW
            )

            `uvm_info(
                "APB_TEST",
                "APB_UVM_SMOKE_PASS",
                UVM_NONE
            )

            phase.drop_objection(this);

        endtask

    endclass

endpackage

// ==================================================
// 2. HARDWARE SIMULATION TOP
// ==================================================

module tb_apb_uvm_top;

    import uvm_pkg::*;
    import apb_uvm_smoke_pkg::*;

    // --------------------------------------------------
    // Clock and reset
    // --------------------------------------------------

    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    // Generate a 100 MHz clock.
    always #5 clk = ~clk;

    // --------------------------------------------------
    // APB interface
    // --------------------------------------------------

    apb_if apb_bus (
        .pclk    (clk),
        .presetn (rst_n)
    );

    // APB configuration register output.
    logic route_sel;

    // --------------------------------------------------
    // APB register DUT
    // --------------------------------------------------

    apb_route_regs dut (

        .clk       (clk),
        .rst_n     (rst_n),

        .psel      (apb_bus.psel),
        .penable   (apb_bus.penable),
        .pwrite   (apb_bus.pwrite),
        .paddr    (apb_bus.paddr),
        .pwdata   (apb_bus.pwdata),

        .prdata   (apb_bus.prdata),
        .pready   (apb_bus.pready),
        .pslverr  (apb_bus.pslverr),

        .route_sel(route_sel)

    );

    // --------------------------------------------------
    // UVM configuration and startup
    // --------------------------------------------------

    initial begin

        // Enable waveform recording.
        $dumpfile("waves/apb_uvm_smoke.vcd");
        $dumpvars(0, tb_apb_uvm_top);

        // Provide an APB virtual interface to
        // the driver inside the active agent.
        uvm_config_db#(virtual apb_if)::set(
            null,
            "uvm_test_top.agent.driver",
            "vif",
            apb_bus
        );

        // Provide the same physical APB interface
        // to the independent passive monitor.
        uvm_config_db#(virtual apb_if)::set(
            null,
            "uvm_test_top.agent.monitor",
            "vif",
            apb_bus
        );

        // Start the UVM test.
        run_test("apb_uvm_smoke_test");

    end

    // --------------------------------------------------
    // Reset generation
    // --------------------------------------------------

    initial begin

        rst_n = 1'b0;

        repeat (3) @(negedge clk);

        rst_n = 1'b1;

    end

    // --------------------------------------------------
    // Global simulation watchdog
    // --------------------------------------------------

    initial begin

        #5000;

        $fatal(
            1,
            "[FAIL] APB agent integration timeout"
        );

    end

endmodule