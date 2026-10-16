/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : tb_axis_driver_top.sv
 *
 * Description:
 *   UVM source-driver and scoreboard integration test.
 *
 * Verification architecture:
 *
 *   Sequence -> Sequencer -> Driver -> AXI Input
 *                                      |
 *                                      v
 *                                Buffered Router
 *                                      |
 *                         +------------+------------+
 *                         |                         |
 *                     Output 0                  Output 1
 *                         |                         |
 *                     Monitor 0                 Monitor 1
 *                         |                         |
 *                         +------------+------------+
 *                                      |
 *                                  Scoreboard
 *
 * An additional input monitor predicts the expected
 * destination and payload for each accepted input beat.
 *
 * APB remains idle in this test.
 * The default destination is Output 0.
 */

`timescale 1ns/1ps

// ==================================================
// 1. UVM TEST PACKAGE
// ==================================================

package axis_driver_smoke_pkg;

    import uvm_pkg::*;
    import axis_pkg::*;

    `include "uvm_macros.svh"

    // --------------------------------------------------
    // UVM integration test
    // --------------------------------------------------

    class axis_driver_smoke_test extends uvm_test;

        `uvm_component_utils(axis_driver_smoke_test)

        // ----------------------------------------------
        // UVM components
        // ----------------------------------------------

        axis_sequencer sequencer;

        axis_source_driver driver;

        // Passive monitors for all AXI-Stream interfaces.
        axis_output_monitor input_monitor;
        axis_output_monitor monitor0;
        axis_output_monitor monitor1;

        // Independent transaction-level scoreboard.
        axis_router_scoreboard scoreboard;

        // ----------------------------------------------
        // Constructor
        // ----------------------------------------------

        function new(
            string name = "axis_driver_smoke_test",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // ----------------------------------------------
        // Build phase
        // ----------------------------------------------

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            // Create the AXI sequencer.
            sequencer = axis_sequencer::type_id::create(
                "sequencer", this
            );

            // Create the AXI source driver.
            driver = axis_source_driver::type_id::create(
                "driver", this
            );

            // Observe accepted input transactions.
            input_monitor = axis_output_monitor::type_id::create(
                "input_monitor", this
            );

            // Observe both independent output channels.
            monitor0 = axis_output_monitor::type_id::create(
                "monitor0", this
            );

            monitor1 = axis_output_monitor::type_id::create(
                "monitor1", this
            );

            // Create the transaction-level scoreboard.
            scoreboard = axis_router_scoreboard::type_id::create(
                "scoreboard", this
            );

        endfunction

        // ----------------------------------------------
        // Connect phase
        // ----------------------------------------------

        function void connect_phase(uvm_phase phase);

            super.connect_phase(phase);

            // Connect the UVM transaction source.
            driver.seq_item_port.connect(
                sequencer.seq_item_export
            );

            // Send observed input transactions to
            // the scoreboard reference model.
            input_monitor.ap.connect(
                scoreboard.input_imp
            );

            // Send real output transactions to
            // their corresponding scoreboard ports.
            monitor0.ap.connect(
                scoreboard.output0_imp
            );

            monitor1.ap.connect(
                scoreboard.output1_imp
            );

        endfunction

        // ----------------------------------------------
        // Run phase
        // ----------------------------------------------

        task run_phase(uvm_phase phase);

            axis_basic_sequence seq;

            // Keep the UVM run phase alive.
            phase.raise_objection(this);

            seq = axis_basic_sequence::type_id::create(
                "seq"
            );

            `uvm_info(
                "AXIS_TEST",
                "Starting three-beat AXI packet sequence",
                UVM_LOW
            )

            // Start the sequence on the sequencer.
            seq.start(sequencer);

            // The driver must complete three accepted
            // AXI-Stream input transfers.
            if (driver.driven_count != 3) begin

                `uvm_fatal(
                    "AXIS_TEST",
                    "Driver did not complete three input handshakes"
                )

            end

            // Wait for the independent scoreboard to
            // match all three expected transactions.
            wait (scoreboard.matched_count == 3);

            // Keep monitors active briefly to detect
            // unexpected or duplicate output transfers.
            #30;

            // ------------------------------------------
            // Monitor count verification
            // ------------------------------------------

            if (
                input_monitor.observed_count != 3 ||
                monitor0.observed_count != 3 ||
                monitor1.observed_count != 0
            ) begin

                `uvm_fatal(
                    "AXIS_TEST",
                    "AXI monitor transaction-count mismatch"
                )

            end

            // ------------------------------------------
            // Scoreboard result verification
            // ------------------------------------------

            if (
                scoreboard.input_count != 3 ||
                scoreboard.output0_count != 3 ||
                scoreboard.output1_count != 0 ||
                scoreboard.matched_count != 3 ||
                scoreboard.expected_q0.size() != 0 ||
                scoreboard.expected_q1.size() != 0
            ) begin

                `uvm_fatal(
                    "AXIS_TEST",
                    "Router scoreboard completion mismatch"
                )

            end

            `uvm_info(
                "AXIS_TEST",
                "[PASS] Three AXI monitors and UVM scoreboard",
                UVM_LOW
            )

            // Explicit success marker for regression.
            `uvm_info(
                "AXIS_TEST",
                "AXIS_DRIVER_SMOKE_PASS",
                UVM_NONE
            )

            phase.drop_objection(this);

        endtask

    endclass

endpackage

// ==================================================
// 2. HARDWARE SIMULATION TOP
// ==================================================

module tb_axis_driver_top;

    import uvm_pkg::*;
    import axis_driver_smoke_pkg::*;

    // --------------------------------------------------
    // 1. Clock and reset
    // --------------------------------------------------

    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    // 100 MHz clock with a 10 ns period.
    always #5 clk = ~clk;

    // --------------------------------------------------
    // 2. AXI-Stream interfaces
    // --------------------------------------------------

    // Input interface driven by the UVM source driver.
    axis_if #(
        .DATA_WIDTH(32)
    ) s_if (
        .aclk(clk),
        .aresetn(rst_n)
    );

    // Output 0 interface observed by monitor0.
    axis_if #(
        .DATA_WIDTH(32)
    ) m0_if (
        .aclk(clk),
        .aresetn(rst_n)
    );

    // Output 1 interface observed by monitor1.
    axis_if #(
        .DATA_WIDTH(32)
    ) m1_if (
        .aclk(clk),
        .aresetn(rst_n)
    );

    // --------------------------------------------------
    // 3. AXI-Stream Output 0 signals
    // --------------------------------------------------

    logic [31:0] m0_tdata;
    logic [3:0]  m0_tkeep;
    logic        m0_tlast;
    logic        m0_tvalid;

    // --------------------------------------------------
    // 4. AXI-Stream Output 1 signals
    // --------------------------------------------------

    logic [31:0] m1_tdata;
    logic [3:0]  m1_tkeep;
    logic        m1_tlast;
    logic        m1_tvalid;

    // --------------------------------------------------
    // 5. Output interface connections
    // --------------------------------------------------

    // Output 0 monitor observes DUT output signals.
    assign m0_if.tdata  = m0_tdata;
    assign m0_if.tkeep  = m0_tkeep;
    assign m0_if.tlast  = m0_tlast;
    assign m0_if.tvalid = m0_tvalid;

    // Output 0 accepts every valid transaction.
    assign m0_if.tready = 1'b1;

    // Output 1 monitor observes DUT output signals.
    assign m1_if.tdata  = m1_tdata;
    assign m1_if.tkeep  = m1_tkeep;
    assign m1_if.tlast  = m1_tlast;
    assign m1_if.tvalid = m1_tvalid;

    // Output 1 accepts every valid transaction.
    assign m1_if.tready = 1'b1;

    // --------------------------------------------------
    // 6. Buffered Router DUT
    // --------------------------------------------------

    buffered_router #(
        .DATA_WIDTH(32),
        .FIFO_DEPTH(4)
    ) dut (

        .clk   (clk),
        .rst_n (rst_n),

        // APB is idle during this smoke test.
        // Reset configuration selects Output 0.
        .psel    (1'b0),
        .penable (1'b0),
        .pwrite  (1'b0),
        .paddr   (8'h00),
        .pwdata  (32'h0000_0000),

        .prdata  (),
        .pready  (),
        .pslverr (),

        // ------------------------------------------
        // AXI-Stream input
        // ------------------------------------------

        .s_axis_tdata  (s_if.tdata),
        .s_axis_tkeep  (s_if.tkeep),
        .s_axis_tlast  (s_if.tlast),
        .s_axis_tvalid (s_if.tvalid),
        .s_axis_tready (s_if.tready),

        // ------------------------------------------
        // AXI-Stream Output 0
        // ------------------------------------------

        .m0_axis_tdata  (m0_tdata),
        .m0_axis_tkeep  (m0_tkeep),
        .m0_axis_tlast  (m0_tlast),
        .m0_axis_tvalid (m0_tvalid),
        .m0_axis_tready (m0_if.tready),

        // ------------------------------------------
        // AXI-Stream Output 1
        // ------------------------------------------

        .m1_axis_tdata  (m1_tdata),
        .m1_axis_tkeep  (m1_tkeep),
        .m1_axis_tlast  (m1_tlast),
        .m1_axis_tvalid (m1_tvalid),
        .m1_axis_tready (m1_if.tready)

    );

    // --------------------------------------------------
    // 7. UVM configuration and simulation startup
    // --------------------------------------------------

    initial begin

        // Generate VCD waveform output.
        $dumpfile("waves/axis_driver_smoke.vcd");
        $dumpvars(0, tb_axis_driver_top);

        // ------------------------------------------
        // Source driver virtual interface
        // ------------------------------------------

        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.driver",
            "vif",
            s_if
        );

        // ------------------------------------------
        // Input monitor virtual interface
        // ------------------------------------------

        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.input_monitor",
            "vif",
            s_if
        );

        // ------------------------------------------
        // Output 0 monitor virtual interface
        // ------------------------------------------

        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.monitor0",
            "vif",
            m0_if
        );

        // ------------------------------------------
        // Output 1 monitor virtual interface
        // ------------------------------------------

        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.monitor1",
            "vif",
            m1_if
        );

        // Start the UVM test through the factory.
        run_test("axis_driver_smoke_test");

    end

    // --------------------------------------------------
    // 8. Reset generation
    // --------------------------------------------------

    initial begin

        rst_n = 1'b0;

        // Keep reset active for three clock cycles.
        repeat (3) @(negedge clk);

        rst_n = 1'b1;

    end

    // --------------------------------------------------
    // 9. Global simulation watchdog
    // --------------------------------------------------

    initial begin

        #2000;

        $fatal(
            1,
            "[FAIL] UVM scoreboard integration timeout"
        );

    end

endmodule