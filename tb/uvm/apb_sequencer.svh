/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : apb_sequencer.svh
 *
 * Description:
 *   UVM sequencer for APB read and write transactions.
 */

class apb_sequencer extends uvm_sequencer #(apb_item);

    `uvm_component_utils(apb_sequencer)

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------

    function new(
        string name = "apb_sequencer",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

endclass