/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : apb_if.sv
 *
 * Description:
 *   Reusable APB3 interface for UVM verification.
 *
 * Features:
 *   - APB setup and access phases
 *   - Read and write transactions
 *   - PREADY handshake
 *   - PSLVERR error response
 */

interface apb_if (
    input logic pclk,
    input logic presetn
);

    // --------------------------------------------------
    // APB request signals
    // --------------------------------------------------

    logic        psel;
    logic        penable;
    logic        pwrite;

    logic [7:0]  paddr;
    logic [31:0] pwdata;

    // --------------------------------------------------
    // APB response signals
    // --------------------------------------------------

    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    // --------------------------------------------------
    // Master modport
    // --------------------------------------------------

    modport master (
        input  pclk,
        input  presetn,
        input  prdata,
        input  pready,
        input  pslverr,

        output psel,
        output penable,
        output pwrite,
        output paddr,
        output pwdata
    );

    // --------------------------------------------------
    // Slave modport
    // --------------------------------------------------

    modport slave (
        input  pclk,
        input  presetn,
        input  psel,
        input  penable,
        input  pwrite,
        input  paddr,
        input  pwdata,

        output prdata,
        output pready,
        output pslverr
    );

    // --------------------------------------------------
    // Passive monitor modport
    // --------------------------------------------------

    modport monitor (
        input pclk,
        input presetn,
        input psel,
        input penable,
        input pwrite,
        input paddr,
        input pwdata,
        input prdata,
        input pready,
        input pslverr
    );

endinterface