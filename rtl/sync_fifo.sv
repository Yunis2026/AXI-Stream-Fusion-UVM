
/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : sync_fifo.sv
 *
 * Description:
 *   Parameterized synchronous FIFO for buffering AXI-Stream beats.
 *
 * Features:
 *   - Configurable data width and depth
 *   - Circular read/write pointers
 *   - Full and empty detection
 *   - Simultaneous push and pop support
 *   - Active-low asynchronous reset
 *
 * Notes:
 *   - Push is rejected when the FIFO is full.
 *   - Pop is rejected when the FIFO is empty.
 *   - Full-state push/pop bypass is not supported.
 *   - FIFO memory contents are not reset; validity is controlled
 *     by the occupancy counter.
 */

module sync_fifo #(
    parameter int DATA_WIDTH = 37,
    parameter int DEPTH      = 4
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // FIFO write interface
    input  logic                  push,
    input  logic [DATA_WIDTH-1:0] din,

    // FIFO read interface
    input  logic                  pop,
    output logic [DATA_WIDTH-1:0] dout,

    // FIFO status
    output logic                  full,
    output logic                  empty
);

    // -------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------

    // Pointer width must support all FIFO entries.
    localparam int PTR_WIDTH =
        (DEPTH > 1) ? $clog2(DEPTH) : 1;

    // Counter must represent values from 0 through DEPTH.
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);

    // -------------------------------------------------------
    // Internal storage and state
    // -------------------------------------------------------

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;

    logic [COUNT_WIDTH-1:0] count;

    // Accepted FIFO operations.
    logic push_valid;
    logic pop_valid;

    // -------------------------------------------------------
    // Full and empty detection
    // -------------------------------------------------------

    assign full  = (count == COUNT_WIDTH'(DEPTH));
    assign empty = (count == '0);

    // Reject writes when full and reads when empty.
    assign push_valid = push && !full;
    assign pop_valid  = pop  && !empty;

    // -------------------------------------------------------
    // FIFO read data
    // -------------------------------------------------------

    // The oldest entry is visible when FIFO is non-empty.
    // Output data is defined as zero when FIFO is empty.
    assign dout = empty ? '0 : mem[rd_ptr];

    // -------------------------------------------------------
    // Write pointer and memory update
    // -------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end
        else if (push_valid) begin

            // Store the accepted input data.
            mem[wr_ptr] <= din;

            // Wrap at the final FIFO entry.
            if (wr_ptr == PTR_WIDTH'(DEPTH - 1))
                wr_ptr <= '0;
            else
                wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // -------------------------------------------------------
    // Read pointer update
    // -------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
        end
        else if (pop_valid) begin

            // Advance only when a valid entry is consumed.
            if (rd_ptr == PTR_WIDTH'(DEPTH - 1))
                rd_ptr <= '0;
            else
                rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // -------------------------------------------------------
    // FIFO occupancy counter
    // -------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0;
        end
        else begin

            // Update occupancy based on accepted operations.
            case ({push_valid, pop_valid})

                // Push only: FIFO occupancy increases.
                2'b10: count <= count + 1'b1;

                // Pop only: FIFO occupancy decreases.
                2'b01: count <= count - 1'b1;

                // Both or neither: occupancy is unchanged.
                default: count <= count;

            endcase
        end
    end

endmodule
