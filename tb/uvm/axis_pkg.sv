/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : axis_pkg.sv
 *
 * Description:
 *   Package containing reusable AXI-Stream UVM
 *   transactions, sequences, agents and scoreboards.
 */

package axis_pkg;

    // --------------------------------------------------
    // 1. UVM library
    // --------------------------------------------------

    import uvm_pkg::*;

    `include "uvm_macros.svh"

    // --------------------------------------------------
    // 2. Transaction definition
    // --------------------------------------------------

    `include "axis_beat_item.svh"

    // --------------------------------------------------
    // 3. Named analysis implementation declarations
    // --------------------------------------------------

    // Allow one scoreboard to receive transactions
    // from three independent AXI-Stream monitors.
    `uvm_analysis_imp_decl(_input)
    `uvm_analysis_imp_decl(_output0)
    `uvm_analysis_imp_decl(_output1)

    // --------------------------------------------------
    // 4. Sequence and sequencer
    // --------------------------------------------------

    `include "axis_sequencer.svh"
    `include "axis_basic_sequence.svh"

    // --------------------------------------------------
    // 5. AXI-Stream driver
    // --------------------------------------------------

    `include "axis_source_driver.svh"

    // --------------------------------------------------
    // 6. AXI-Stream monitor
    // --------------------------------------------------

    `include "axis_output_monitor.svh"

    // --------------------------------------------------
    // 7. Router scoreboard
    // --------------------------------------------------

    `include "axis_router_scoreboard.svh"

endpackage