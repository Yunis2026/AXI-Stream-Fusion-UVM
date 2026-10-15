
/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : buffered_router.sv
 *
 * Description:
 *   Single-input, dual-output buffered AXI-Stream router.
 *
 * Features:
 *   - APB-controlled destination selection
 *   - Multi-beat AXI-Stream packet support
 *   - Packet-level route locking
 *   - Independent output FIFOs
 *   - Backpressure and handshake control
 *   - TDATA, TKEEP and TLAST preservation
 *   - Active-low asynchronous reset
 *
 * Routing policy:
 *   - The first accepted beat selects the destination.
 *   - All subsequent beats use the locked destination.
 *   - The accepted TLAST beat releases the packet lock.
 *   - An APB update cannot redirect an active packet.
 *
 * FIFO policy:
 *   - Push is rejected when the destination FIFO is full.
 *   - Full-state simultaneous push/pop is not supported.
 */

module buffered_router #(
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_DEPTH = 4
)(
    input logic clk,
    input logic rst_n,

    // --------------------------------------------------
    // APB3 slave interface
    // --------------------------------------------------

    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [7:0]  paddr,
    input  logic [31:0] pwdata,

    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    // --------------------------------------------------
    // AXI-Stream input interface
    // --------------------------------------------------

    input  logic [DATA_WIDTH-1:0]   s_axis_tdata,
    input  logic [DATA_WIDTH/8-1:0] s_axis_tkeep,
    input  logic                    s_axis_tlast,
    input  logic                    s_axis_tvalid,
    output logic                    s_axis_tready,

    // --------------------------------------------------
    // AXI-Stream output 0
    // --------------------------------------------------

    output logic [DATA_WIDTH-1:0]   m0_axis_tdata,
    output logic [DATA_WIDTH/8-1:0] m0_axis_tkeep,
    output logic                    m0_axis_tlast,
    output logic                    m0_axis_tvalid,
    input  logic                    m0_axis_tready,

    // --------------------------------------------------
    // AXI-Stream output 1
    // --------------------------------------------------

    output logic [DATA_WIDTH-1:0]   m1_axis_tdata,
    output logic [DATA_WIDTH/8-1:0] m1_axis_tkeep,
    output logic                    m1_axis_tlast,
    output logic                    m1_axis_tvalid,
    input  logic                    m1_axis_tready
);

    // --------------------------------------------------
    // 1. Internal parameters
    // --------------------------------------------------

    localparam int KEEP_WIDTH = DATA_WIDTH / 8;

    // Each FIFO entry stores the complete AXI-Stream
    // payload, including the packet boundary marker.
    localparam int FIFO_WIDTH =
        DATA_WIDTH + KEEP_WIDTH + 1;

    // --------------------------------------------------
    // 2. APB routing configuration
    // --------------------------------------------------

    logic route_sel;

    // Reuse the independently verified APB register block.
    apb_route_regs u_apb_regs (
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
    // 3. Packet routing controller
    // --------------------------------------------------

    // Indicates that the currently accepted packet
    // has not yet reached its accepted TLAST beat.
    logic in_packet;

    // Destination locked for the active packet.
    logic packet_route;

    // Effective destination of the current input beat.
    logic active_route;

    // Use the APB route for a new packet.
    // Use the stored route for an ongoing packet.
    assign active_route =
        in_packet ? packet_route : route_sel;

    // Input transfer occurs only after VALID/READY handshake.
    logic input_fire;

    assign input_fire =
        s_axis_tvalid && s_axis_tready;

    // Packet state changes only on accepted input beats.
    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            in_packet    <= 1'b0;
            packet_route <= 1'b0;
        end
        else if (input_fire) begin

            // Capture the route on the first accepted beat.
            // Nonblocking assignments preserve the old APB
            // value when an APB write occurs on the same edge.
            if (!in_packet) begin
                packet_route <= route_sel;
            end

            // TLAST terminates the input packet.
            // A single-beat packet never enters the
            // persistent in_packet state.
            in_packet <= !s_axis_tlast;

        end

        // Otherwise, retain the current packet state.

    end

    // --------------------------------------------------
    // 4. FIFO internal signals
    // --------------------------------------------------

    logic [FIFO_WIDTH-1:0] fifo_din;

    logic [FIFO_WIDTH-1:0] fifo0_dout;
    logic [FIFO_WIDTH-1:0] fifo1_dout;

    logic fifo0_full;
    logic fifo0_empty;

    logic fifo1_full;
    logic fifo1_empty;

    logic fifo0_push;
    logic fifo1_push;

    logic fifo0_pop;
    logic fifo1_pop;

    // Pack one complete AXI-Stream beat into a FIFO word.
    // Bit order: {TLAST, TKEEP, TDATA}
    assign fifo_din = {
        s_axis_tlast,
        s_axis_tkeep,
        s_axis_tdata
    };

    // --------------------------------------------------
    // 5. AXI-Stream input backpressure
    // --------------------------------------------------

    // The selected destination must have free space.
    // Disable input acceptance while reset is asserted.
    //
    // Conservative FIFO policy:
    // A currently full FIFO cannot accept an input beat,
    // even if its output is consumed in the same cycle.
    assign s_axis_tready =
        rst_n &&
        (active_route ? !fifo1_full : !fifo0_full);

    // Enqueue exactly one beat per accepted input transfer.
    // Only the selected destination receives the beat.
    assign fifo0_push =
        input_fire && !active_route;

    assign fifo1_push =
        input_fire && active_route;

    // --------------------------------------------------
    // 6. FIFO output 0
    // --------------------------------------------------

    sync_fifo #(
        .DATA_WIDTH(FIFO_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_fifo0 (
        .clk   (clk),
        .rst_n (rst_n),

        .push  (fifo0_push),
        .din   (fifo_din),

        .pop   (fifo0_pop),
        .dout  (fifo0_dout),

        .full  (fifo0_full),
        .empty (fifo0_empty)
    );

    // Valid data exists whenever FIFO 0 is non-empty.
    assign m0_axis_tvalid =
        rst_n && !fifo0_empty;

    // Remove an entry only after an output handshake.
    assign fifo0_pop =
        m0_axis_tvalid && m0_axis_tready;

    // Recover AXI-Stream fields from the FIFO entry.
    assign {
        m0_axis_tlast,
        m0_axis_tkeep,
        m0_axis_tdata
    } = fifo0_dout;

    // --------------------------------------------------
    // 7. FIFO output 1
    // --------------------------------------------------

    sync_fifo #(
        .DATA_WIDTH(FIFO_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_fifo1 (
        .clk   (clk),
        .rst_n (rst_n),

        .push  (fifo1_push),
        .din   (fifo_din),

        .pop   (fifo1_pop),
        .dout  (fifo1_dout),

        .full  (fifo1_full),
        .empty (fifo1_empty)
    );

    // Valid data exists whenever FIFO 1 is non-empty.
    assign m1_axis_tvalid =
        rst_n && !fifo1_empty;

    // Remove an entry only after an output handshake.
    assign fifo1_pop =
        m1_axis_tvalid && m1_axis_tready;

    // Recover AXI-Stream fields from the FIFO entry.
    assign {
        m1_axis_tlast,
        m1_axis_tkeep,
        m1_axis_tdata
    } = fifo1_dout;

endmodule
