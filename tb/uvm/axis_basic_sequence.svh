/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : axis_basic_sequence.svh
 *
 * Description:
 *   Directed AXI-Stream sequence that generates
 *   one three-beat packet.
 *
 * Packet format:
 *   Beat 0: TDATA=0x000000A1, TKEEP=0xF, TLAST=0
 *   Beat 1: TDATA=0x000000A2, TKEEP=0xF, TLAST=0
 *   Beat 2: TDATA=0x000000A3, TKEEP=0x3, TLAST=1
 */

class axis_basic_sequence extends uvm_sequence #(axis_beat_item);

    // Register the sequence with the UVM factory.
    `uvm_object_utils(axis_basic_sequence)

    // Constructor for a UVM object.
    function new(string name = "axis_basic_sequence");
        super.new(name);
    endfunction

    // --------------------------------------------------
    // Sequence body
    // --------------------------------------------------

    virtual task body();

        axis_beat_item req;

        // Generate a three-beat AXI-Stream packet.
        for (int i = 0; i < 3; i++) begin

            // Create a new transaction through the factory.
            req = axis_beat_item::type_id::create(
                $sformatf("beat_%0d", i)
            );

            // Request permission to send this item.
            start_item(req);

            // Assign directed packet data.
            req.tdata = 32'h0000_00A1 + i;

            // The last beat contains two valid bytes.
            req.tkeep = (i == 2) ? 4'h3 : 4'hF;

            // Assert TLAST only on the final beat.
            req.tlast = (i == 2);

            // Send this transaction to the driver.
            finish_item(req);

            `uvm_info(
                "AXIS_SEQ",
                $sformatf(
                    "Generated beat %0d: %s",
                    i,
                    req.convert2string()
                ),
                UVM_LOW
            )

        end

    endtask

endclass