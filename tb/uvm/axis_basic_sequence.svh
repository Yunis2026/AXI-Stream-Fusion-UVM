/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : axis_basic_sequence.svh
 *
 * Description:
 *   Basic AXI-Stream UVM sequence.
 *
 * Features:
 *   - Generates a three-beat AXI-Stream packet
 *   - Uses the UVM factory for transaction creation
 *   - Uses start_item() and finish_item()
 *   - Sets TDATA, TKEEP and TLAST explicitly
 *
 * Packet contents:
 *   Beat 0: TDATA=0x000000A1, TKEEP=F, TLAST=0
 *   Beat 1: TDATA=0x000000A2, TKEEP=F, TLAST=0
 *   Beat 2: TDATA=0x000000A3, TKEEP=3, TLAST=1
 */

class axis_basic_sequence extends uvm_sequence #(axis_beat_item);

    `uvm_object_utils(axis_basic_sequence)

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------

    function new(
        string name = "axis_basic_sequence"
    );
        super.new(name);
    endfunction

    // --------------------------------------------------
    // Main sequence
    // --------------------------------------------------

    virtual task body();

        axis_beat_item req;

        // Generate one three-beat AXI-Stream packet.
        for (int i = 0; i < 3; i++) begin

            // Create each transaction through the
            // UVM factory.
            req = axis_beat_item::type_id::create(
                $sformatf("beat_%0d", i)
            );

            // Request permission from the sequencer.
            start_item(req);

            // Configure the transaction payload.
            req.tdata = 32'h0000_00A1 + i;

            // The final beat contains two valid bytes.
            req.tkeep = (i == 2) ? 4'h3 : 4'hF;

            // Assert TLAST only on the final beat.
            req.tlast = (i == 2);

            // Wait until the driver completes
            // the hardware transfer.
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