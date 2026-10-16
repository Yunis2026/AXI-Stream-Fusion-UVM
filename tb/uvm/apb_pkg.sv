/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : apb_pkg.sv
 *
 * Description:
 *   Reusable APB UVM verification package.
 *
 * Components:
 *   - APB transaction
 *   - APB sequencer
 *   - APB driver
 *   - APB monitor
 *   - APB agent
 *   - Directed APB verification sequence
 */

package apb_pkg;

    // --------------------------------------------------
    // UVM library and macros
    // --------------------------------------------------

    import uvm_pkg::*;

    `include "uvm_macros.svh"

    // --------------------------------------------------
    // APB transaction
    // --------------------------------------------------

    `include "apb_item.svh"

    // --------------------------------------------------
    // APB sequencer
    // --------------------------------------------------

    `include "apb_sequencer.svh"

    // --------------------------------------------------
    // APB driver
    // --------------------------------------------------

    `include "apb_driver.svh"

    // --------------------------------------------------
    // APB monitor
    // --------------------------------------------------

    `include "apb_monitor.svh"

    // --------------------------------------------------
    // APB agent
    // --------------------------------------------------

    `include "apb_agent.svh"

    // --------------------------------------------------
    // APB directed sequence
    // --------------------------------------------------

    `include "apb_basic_sequence.svh"

endpackage