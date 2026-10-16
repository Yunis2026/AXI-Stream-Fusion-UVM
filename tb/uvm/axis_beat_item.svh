
/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : axis_beat_item.svh
 *
 * Description:
 *   UVM sequence item representing one AXI-Stream beat.
 *
 * Each item contains:
 *   - TDATA
 *   - TKEEP
 *   - TLAST
 *
 * Handshake signals are not stored because they describe
 * transfer timing rather than transaction payload.
 *
 * This class targets the current 32-bit router DUT.
 */

class axis_beat_item extends uvm_sequence_item;

    // --------------------------------------------------
    // AXI-Stream transaction fields
    // --------------------------------------------------

    rand bit [31:0] tdata;
    rand bit [3:0]  tkeep;
    rand bit        tlast;

    // --------------------------------------------------
    // UVM factory registration and field automation
    // --------------------------------------------------

    `uvm_object_utils_begin(axis_beat_item)

        `uvm_field_int(tdata, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(tkeep, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(tlast, UVM_ALL_ON)

    `uvm_object_utils_end

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------

    function new(string name = "axis_beat_item");
        super.new(name);
    endfunction

    // --------------------------------------------------
    // Human-readable transaction information
    // --------------------------------------------------

    function string convert2string();

        return $sformatf(
            "TDATA=0x%08h TKEEP=0x%1h TLAST=%0b",
            tdata,
            tkeep,
            tlast
        );

    endfunction

endclass
