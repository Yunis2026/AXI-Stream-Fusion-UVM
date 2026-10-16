/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : tb_router_dynamic_uvm_top.sv
 *
 * Description:
 *   Hardware simulation top for combined APB and
 *   AXI-Stream dynamic routing verification.
 *
 * Interfaces:
 *   - One APB configuration interface
 *   - One AXI-Stream input interface
 *   - Two AXI-Stream output interfaces
 *
 * The two outputs are permanently ready in this test.
 */

`timescale 1ns/1ps

module tb_router_dynamic_uvm_top;

    import uvm_pkg::*;
    import router_dynamic_pkg::*;

    // ==================================================
    // 1. Clock and reset
    // ==================================================

    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    // 100 MHz simulation clock.
    always #5 clk = ~clk;

    // ==================================================
    // 2. Interface instances
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
    // 3. AXI output signal declarations
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
    // 4. Output monitoring connections
    // ==================================================

    assign m0_if.tdata  = m0_tdata;
    assign m0_if.tkeep  = m0_tkeep;
    assign m0_if.tlast  = m0_tlast;
    assign m0_if.tvalid = m0_tvalid;
    assign m0_if.tready = 1'b1;

    assign m1_if.tdata  = m1_tdata;
    assign m1_if.tkeep  = m1_tkeep;
    assign m1_if.tlast  = m1_tlast;
    assign m1_if.tvalid = m1_tvalid;
    assign m1_if.tready = 1'b1;

    // ==================================================
    // 5. Buffered AXI-Stream Router DUT
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

        // AXI-Stream source input.
        .s_axis_tdata  (s_if.tdata),
        .s_axis_tkeep  (s_if.tkeep),
        .s_axis_tlast  (s_if.tlast),
        .s_axis_tvalid (s_if.tvalid),
        .s_axis_tready (s_if.tready),

        // AXI-Stream Output 0.
        .m0_axis_tdata  (m0_tdata),
        .m0_axis_tkeep  (m0_tkeep),
        .m0_axis_tlast  (m0_tlast),
        .m0_axis_tvalid (m0_tvalid),
        .m0_axis_tready (m0_if.tready),

        // AXI-Stream Output 1.
        .m1_axis_tdata  (m1_tdata),
        .m1_axis_tkeep  (m1_tkeep),
        .m1_axis_tlast  (m1_tlast),
        .m1_axis_tvalid (m1_tvalid),
        .m1_axis_tready (m1_if.tready)

    );

    // ==================================================
    // 6. Virtual interface configuration
    // ==================================================

    initial begin

        $dumpfile("waves/router_dynamic_uvm.vcd");
        $dumpvars(0, tb_router_dynamic_uvm_top);

        // ----------------------------------------------
        // AXI source driver
        // ----------------------------------------------

        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.axis_drv",
            "vif",
            s_if
        );

        // ----------------------------------------------
        // AXI input monitor
        // ----------------------------------------------

        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.input_mon",
            "vif",
            s_if
        );

        // ----------------------------------------------
        // AXI Output 0 monitor
        // ----------------------------------------------

        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.output0_mon",
            "vif",
            m0_if
        );

        // ----------------------------------------------
        // AXI Output 1 monitor
        // ----------------------------------------------

        uvm_config_db#(virtual axis_if)::set(
            null,
            "uvm_test_top.output1_mon",
            "vif",
            m1_if
        );

        // ----------------------------------------------
        // APB Agent Driver
        // ----------------------------------------------

        uvm_config_db#(virtual apb_if)::set(
            null,
            "uvm_test_top.cfg_agent.driver",
            "vif",
            cfg_if
        );

        // ----------------------------------------------
        // APB Agent Monitor
        // ----------------------------------------------

        uvm_config_db#(virtual apb_if)::set(
            null,
            "uvm_test_top.cfg_agent.monitor",
            "vif",
            cfg_if
        );

        // Start the complete UVM verification test.
        run_test("router_dynamic_test");

    end

    // ==================================================
    // 7. Reset
    // ==================================================

    initial begin

        rst_n = 1'b0;

        repeat (3) @(negedge clk);

        rst_n = 1'b1;

    end

    // ==================================================
    // 8. Watchdog
    // ==================================================

    initial begin

        #5000;

        $fatal(
            1,
            "[FAIL] Combined APB/AXI UVM verification timeout"
        );

    end

endmodule