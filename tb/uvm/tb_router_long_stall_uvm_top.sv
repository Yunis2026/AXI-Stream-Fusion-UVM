/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : tb_router_long_stall_uvm_top.sv
 *
 * Description:
 *   Simulation top for sustained AXI-Stream
 *   backpressure and independent FIFO recovery.
 *
 * Configuration:
 *   - Data width: 32 bits
 *   - FIFO depth: 4 entries per output
 *   - Two independent AXI-Stream output channels
 *   - One APB configuration interface
 *
 * Output TREADY is controlled by the UVM test.
 */

`timescale 1ns/1ps

module tb_router_long_stall_uvm_top;

    import uvm_pkg::*;
    import router_long_stall_pkg::*;

    // ==================================================
    // 1. CLOCK AND RESET
    // ==================================================

    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    // 100 MHz clock.
    always #5 clk = ~clk;

    // ==================================================
    // 2. INTERFACE INSTANCES
    // ==================================================

    // AXI-Stream source interface.
    axis_if #(
        .DATA_WIDTH(32)
    ) s_if (
        .aclk(clk),
        .aresetn(rst_n)
    );

    // AXI-Stream Output 0 interface.
    axis_if #(
        .DATA_WIDTH(32)
    ) m0_if (
        .aclk(clk),
        .aresetn(rst_n)
    );

    // AXI-Stream Output 1 interface.
    axis_if #(
        .DATA_WIDTH(32)
    ) m1_if (
        .aclk(clk),
        .aresetn(rst_n)
    );

    // APB configuration interface.
    apb_if cfg_if (
        .pclk(clk),
        .presetn(rst_n)
    );

    // ==================================================
    // 3. DUT OUTPUT SIGNALS
    // ==================================================

    logic [31:0] m0_tdata;
    logic [3:0]  m0_tkeep;
    logic        m0_tlast;
    logic        m0_tvalid;

    logic [31:0] m1_tdata;
    logic [3:0]  m1_tkeep;
    logic        m1_tlast;
    logic        m1_tvalid;

    // ==================================================
    // 4. OUTPUT INTERFACE CONNECTIONS
    // ==================================================

    assign m0_if.tdata  = m0_tdata;
    assign m0_if.tkeep  = m0_tkeep;
    assign m0_if.tlast  = m0_tlast;
    assign m0_if.tvalid = m0_tvalid;

    assign m1_if.tdata  = m1_tdata;
    assign m1_if.tkeep  = m1_tkeep;
    assign m1_if.tlast  = m1_tlast;
    assign m1_if.tvalid = m1_tvalid;

    // TREADY is intentionally not assigned here.
    // The UVM test drives both output sink interfaces.

    // ==================================================
    // 5. BUFFERED ROUTER DUT
    // ==================================================

    buffered_router #(
        .DATA_WIDTH(32),
        .FIFO_DEPTH(4)
    ) dut (

        // ----------------------------------------------
        // Clock and reset
        // ----------------------------------------------

        .clk   (clk),
        .rst_n (rst_n),

        // ----------------------------------------------
        // APB configuration interface
        // ----------------------------------------------

        .psel    (cfg_if.psel),
        .penable (cfg_if.penable),
        .pwrite  (cfg_if.pwrite),
        .paddr   (cfg_if.paddr),
        .pwdata  (cfg_if.pwdata),

        .prdata  (cfg_if.prdata),
        .pready  (cfg_if.pready),
        .pslverr (cfg_if.pslverr),

        // ----------------------------------------------
        // AXI-Stream input
        // ----------------------------------------------

        .s_axis_tdata  (s_if.tdata),
        .s_axis_tkeep  (s_if.tkeep),
        .s_axis_tlast  (s_if.tlast),
        .s_axis_tvalid (s_if.tvalid),
        .s_axis_tready (s_if.tready),

        // ----------------------------------------------
        // AXI-Stream Output 0
        // ----------------------------------------------

        .m0_axis_tdata  (m0_tdata),
        .m0_axis_tkeep  (m0_tkeep),
        .m0_axis_tlast  (m0_tlast),
        .m0_axis_tvalid (m0_tvalid),
        .m0_axis_tready (m0_if.tready),

        // ----------------------------------------------
        // AXI-Stream Output 1
        // ----------------------------------------------

        .m1_axis_tdata  (m1_tdata),
        .m1_axis_tkeep  (m1_tkeep),
        .m1_axis_tlast  (m1_tlast),
        .m1_axis_tvalid (m1_tvalid),
        .m1_axis_tready (m1_if.tready)

    );

    // ==================================================
    // 6. UVM CONFIGURATION AND STARTUP
    // ==================================================

    initial begin

        // Enable waveforms.
        $dumpfile("waves/router_long_stall_uvm.vcd");
        $dumpvars(0, tb_router_long_stall_uvm_top);

        // AXI source driver.
        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.axis_drv",
            "vif",
            s_if
        );

        // AXI input monitor.
        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.input_mon",
            "vif",
            s_if
        );

        // AXI Output 0 monitor.
        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.output0_mon",
            "vif",
            m0_if
        );

        // AXI Output 1 monitor.
        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.output1_mon",
            "vif",
            m1_if
        );

        // APB agent driver.
        uvm_config_db#(virtual apb_if)::set(
            null,
            "uvm_test_top.cfg_agent.driver",
            "vif",
            cfg_if
        );

        // APB agent monitor.
        uvm_config_db#(virtual apb_if)::set(
            null,
            "uvm_test_top.cfg_agent.monitor",
            "vif",
            cfg_if
        );

        // Source interface used by the UVM test.
        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top",
            "src_vif",
            s_if
        );

        // Output 0 interface used by the UVM test.
        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top",
            "out0_vif",
            m0_if
        );

        // Output 1 interface used by the UVM test.
        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top",
            "out1_vif",
            m1_if
        );

        // Run the dedicated long-duration test.
        run_test("router_long_stall_test");

    end

    // ==================================================
    // 7. RESET GENERATION
    // ==================================================

    initial begin

        rst_n = 1'b0;

        repeat (3) @(negedge clk);

        rst_n = 1'b1;

    end

    // ==================================================
    // 8. SIMULATION WATCHDOG
    // ==================================================

    initial begin

        // Allow up to 50 microseconds for the
        // directed long-duration stall scenarios.
        #50000;

        $fatal(
            1,
            "[FAIL] Long-duration backpressure timeout"
        );

    end

endmodule