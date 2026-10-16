
/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : axis_if.sv
 *
 * Description:
 *   Reusable AXI-Stream interface for UVM verification.
 *
 * Features:
 *   - Parameterized data width
 *   - TVALID/TREADY handshake
 *   - TDATA/TKEEP/TLAST signals
 *   - Source, sink, and monitor modports
 */

interface axis_if #(
    parameter int DATA_WIDTH = 32
)(
    input logic aclk,
    input logic aresetn
);

    localparam int KEEP_WIDTH = DATA_WIDTH / 8;

    // --------------------------------------------------
    // AXI-Stream channel signals
    // --------------------------------------------------

    logic [DATA_WIDTH-1:0] tdata;
    logic [KEEP_WIDTH-1:0] tkeep;

    logic tlast;
    logic tvalid;
    logic tready;

    // --------------------------------------------------
    // Source modport
    // --------------------------------------------------

    // The source generates valid data and observes
    // whether the receiver is ready to accept it.
    modport source (
        input  aclk,
        input  aresetn,
        input  tready,

        output tdata,
        output tkeep,
        output tlast,
        output tvalid
    );

    // --------------------------------------------------
    // Sink modport
    // --------------------------------------------------

    // The sink receives data and controls backpressure
    // through the TREADY signal.
    modport sink (
        input  aclk,
        input  aresetn,
        input  tdata,
        input  tkeep,
        input  tlast,
        input  tvalid,

        output tready
    );

    // --------------------------------------------------
    // Monitor modport
    // --------------------------------------------------

    // A passive monitor observes all interface signals
    // without driving any of them.
    modport monitor (
        input aclk,
        input aresetn,
        input tdata,
        input tkeep,
        input tlast,
        input tvalid,
        input tready
    );

endinterface
