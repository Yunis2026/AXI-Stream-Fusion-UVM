
/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : apb_route_regs.sv
 *
 * Description:
 *   APB3-compatible configuration register block.
 *   Controls the destination port of the AXI-Stream router.
 *
 * Register Map:
 *   Address 0x00 : ROUTE_SEL
 *       Bit 0 = 0 -> Output 0
 *       Bit 0 = 1 -> Output 1
 *       Bits [31:1] are reserved.
 *
 * Features:
 *   - Zero-wait-state APB transactions
 *   - Register read and write support
 *   - Error response for invalid addresses
 *   - Active-low asynchronous reset
 *   - Reserved register bits read as zero
 */

module apb_route_regs (
    input  logic        clk,
    input  logic        rst_n,

    // --------------------------------------------------
    // APB3 slave interface
    // --------------------------------------------------

    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [7:0]  paddr,

    // Only PWDATA[0] is implemented.
    // Upper bits are reserved and intentionally unused.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] pwdata,
    /* verilator lint_on UNUSEDSIGNAL */

    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    // --------------------------------------------------
    // Routing configuration output
    // --------------------------------------------------

    output logic        route_sel
);

    // --------------------------------------------------
    // 1. Register address definition
    // --------------------------------------------------

    localparam logic [7:0] ADDR_ROUTE_SEL = 8'h00;

    // --------------------------------------------------
    // 2. Internal APB control signals
    // --------------------------------------------------

    logic apb_write;
    logic addr_valid;

    // Decode the implemented register address.
    assign addr_valid = (paddr == ADDR_ROUTE_SEL);

    // --------------------------------------------------
    // 3. APB ready and error response
    // --------------------------------------------------

    // Zero-wait-state APB slave:
    // The slave is always ready to complete an access.
    assign pready = 1'b1;

    // Assert PSLVERR only during the access phase
    // when an unsupported address is selected.
    assign pslverr = psel &&
                     penable &&
                     !addr_valid;

    // --------------------------------------------------
    // 4. APB write enable
    // --------------------------------------------------

    // A register write is accepted only when:
    //   1. The slave is selected.
    //   2. The access phase is active.
    //   3. The transaction is a write.
    //   4. The slave is ready.
    //   5. The register address is valid.
    assign apb_write = psel &&
                       penable &&
                       pwrite &&
                       pready &&
                       addr_valid;

    // --------------------------------------------------
    // 5. ROUTE_SEL configuration register
    // --------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            // Default destination after reset:
            // Output 0.
            route_sel <= 1'b0;

        end
        else if (apb_write) begin

            // Update the routing configuration
            // using only bit 0 of APB write data.
            route_sel <= pwdata[0];

        end

        // Otherwise, retain the previous route.

    end

    // --------------------------------------------------
    // 6. APB read data multiplexer
    // --------------------------------------------------

    always_comb begin

        // Default read value for unsupported addresses.
        prdata = 32'h0000_0000;

        if (addr_valid) begin

            // Only ROUTE_SEL occupies bit 0.
            // Reserved upper bits always read as zero.
            prdata = {31'b0, route_sel};

        end

    end

endmodule
