/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : router_reset_if.sv
 *
 * Description:
 *   Reset request interface controlled by a UVM test.
 *
 * The hardware top combines this request with the
 * startup reset to generate the DUT active-low reset.
 */

interface router_reset_if (
    input logic clk
);

    // Request assertion of the DUT active-low reset.
    logic request = 1'b0;

endinterface