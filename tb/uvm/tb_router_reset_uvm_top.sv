/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : tb_router_reset_uvm_top.sv
 *
 * Description:
 *   Hardware top for UVM reset-during-traffic tests.
 *
 * Reset architecture:
 *   - Startup reset initializes the DUT
 *   - UVM reset request triggers runtime reset
 *
 * The UVM test controls output backpressure and
 * runtime reset without hierarchical signal forcing.
 */

`timescale 1ns/1ps

module tb_router_reset_uvm_top;

    import uvm_pkg::*;
    import router_reset_pkg::*;

    // ==================================================
    // 1. CLOCK AND RESET
    // ==================================================

    logic clk = 1'b0;

    logic startup_reset_done = 1'b0;

    wire rst_n;

    // 100 MHz simulation clock.
    always #5 clk = ~clk;

    // Dedicated runtime reset request.
    router_reset_if reset_bus (
        .clk(clk)
    );

    // Assert reset during startup or when requested
    // by the UVM reset verification sequence.
    assign rst_n =
        startup_reset_done && !reset_bus.request;

    // ==================================================
    // 2. AXI AND APB INTERFACES
    // ==================================================

    axis_if #(
        .DATA_WIDTH(32)
    ) s_if (
        .aclk(clk),
        .aresetn(rst_n)
    );

    axis_if #(
        .DATA_WIDTH(32)
    ) m0_if (
        .aclk(clk),
        .aresetn(rst_n)
    );

    axis_if #(
        .DATA_WIDTH(32)
    ) m1_if (
        .aclk(clk),
        .aresetn(rst_n)
    );

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

    // The UVM test drives both output TREADY signals.

    // ==================================================
    // 5. BUFFERED ROUTER DUT
    // ==================================================

    buffered_router #(
        .DATA_WIDTH(32),
        .FIFO_DEPTH(4)
    ) dut (

        .clk   (clk),
        .rst_n (rst_n),

        // APB configuration interface.
        .psel    (cfg_if.psel),
        .penable (cfg_if.penable),
        .pwrite  (cfg_if.pwrite),
        .paddr   (cfg_if.paddr),
        .pwdata  (cfg_if.pwdata),

        .prdata  (cfg_if.prdata),
        .pready  (cfg_if.pready),
        .pslverr (cfg_if.pslverr),

        // AXI input interface.
        .s_axis_tdata  (s_if.tdata),
        .s_axis_tkeep  (s_if.tkeep),
        .s_axis_tlast  (s_if.tlast),
        .s_axis_tvalid (s_if.tvalid),
        .s_axis_tready (s_if.tready),

        // Output 0.
        .m0_axis_tdata  (m0_tdata),
        .m0_axis_tkeep  (m0_tkeep),
        .m0_axis_tlast  (m0_tlast),
        .m0_axis_tvalid (m0_tvalid),
        .m0_axis_tready (m0_if.tready),

        // Output 1.
        .m1_axis_tdata  (m1_tdata),
        .m1_axis_tkeep  (m1_tkeep),
        .m1_axis_tlast  (m1_tlast),
        .m1_axis_tvalid (m1_tvalid),
        .m1_axis_tready (m1_if.tready)

    );

    // ==================================================
    // 6. UVM VIRTUAL INTERFACE CONFIGURATION
    // ==================================================

    initial begin

        $dumpfile("waves/router_reset_uvm.vcd");
        $dumpvars(0, tb_router_reset_uvm_top);

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

        // APB configuration driver.
        uvm_config_db#(virtual apb_if)::set(
            null,
            "uvm_test_top.cfg_agent.driver",
            "vif",
            cfg_if
        );

        // APB configuration monitor.
        uvm_config_db#(virtual apb_if)::set(
            null,
            "uvm_test_top.cfg_agent.monitor",
            "vif",
            cfg_if
        );

        // AXI source interface for reset test.
        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top",
            "src_vif",
            s_if
        );

        // AXI Output 0 interface for reset test.
        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top",
            "out0_vif",
            m0_if
        );

        // AXI Output 1 interface for reset test.
        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top",
            "out1_vif",
            m1_if
        );

        // Runtime reset control interface.
        uvm_config_db#(virtual router_reset_if)::set(
            null,
            "uvm_test_top",
            "reset_vif",
            reset_bus
        );

        // Start the new UVM reset test.
        run_test("router_reset_test");

    end

    // ==================================================
    // 7. STARTUP RESET GENERATION
    // ==================================================

    initial begin

        startup_reset_done = 1'b0;

        repeat (3) @(negedge clk);

        startup_reset_done = 1'b1;

    end

    // ==================================================
    // 8. GLOBAL SIMULATION WATCHDOG
    // ==================================================

    initial begin

        #10000;

        $fatal(
            1,
            "[FAIL] Router reset UVM test timeout"
        );

    end

endmodule