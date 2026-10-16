/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : axis_sequencer.svh
 *
 * Description:
 *   AXI-Stream sequencer that coordinates transaction
 *   delivery between sequences and the source driver.
 */

class axis_sequencer extends uvm_sequencer #(axis_beat_item);

    // Register this component with the UVM factory.
    `uvm_component_utils(axis_sequencer)

    // Constructor for a UVM component.
    function new(
        string name = "axis_sequencer",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

endclass