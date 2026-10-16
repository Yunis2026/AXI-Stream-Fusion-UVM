/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : axis_source_driver.svh
 *
 * Description:
 *   UVM source driver for the AXI-Stream input interface.
 *
 * Responsibilities:
 *   - Receive sequence items from the sequencer
 *   - Drive TDATA, TKEEP, TLAST and TVALID
 *   - Wait for a successful TVALID/TREADY handshake
 *   - Keep the payload stable during backpressure
 *   - Acknowledge each completed item to the sequencer
 */

class axis_source_driver extends uvm_driver #(axis_beat_item);

    `uvm_component_utils(axis_source_driver)

    // Handle to the physical AXI-Stream interface.
    virtual axis_if vif;

    // Number of successfully transmitted beats.
    int unsigned driven_count = 0;

    function new(
        string name = "axis_source_driver",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    // --------------------------------------------------
    // Build phase: retrieve the virtual interface
    // --------------------------------------------------

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual axis_if)::get(
            this, "", "vif", vif
        )) begin
            `uvm_fatal(
                "AXIS_DRV",
                "Failed to get AXI virtual interface"
            )
        end
    endfunction

    // --------------------------------------------------
    // Run phase: consume and drive sequence items
    // --------------------------------------------------

    task run_phase(uvm_phase phase);

        axis_beat_item req;

        // Initialize the source interface to idle.
        vif.tdata  = '0;
        vif.tkeep  = '0;
        vif.tlast  = 1'b0;
        vif.tvalid = 1'b0;

        // Do not transmit until reset is released.
        wait (vif.aresetn === 1'b1);

        forever begin

            // Block until the sequencer supplies an item.
            seq_item_port.get_next_item(req);

            // Present the transaction before the next
            // rising edge to avoid testbench/DUT races.
            @(negedge vif.aclk);

            vif.tdata  = req.tdata;
            vif.tkeep  = req.tkeep;
            vif.tlast  = req.tlast;
            vif.tvalid = 1'b1;

            // Wait for the first rising edge where
            // the receiver accepts the transaction.
            do begin
                @(posedge vif.aclk);

                if (vif.aresetn !== 1'b1) begin
                    `uvm_fatal(
                        "AXIS_DRV",
                        "Reset asserted during an active transfer"
                    )
                end

            end while (vif.tready !== 1'b1);

            driven_count++;

            `uvm_info(
                "AXIS_DRV",
                $sformatf(
                    "Handshake %0d: %s",
                    driven_count,
                    req.convert2string()
                ),
                UVM_LOW
            )

            // Remove VALID after the accepted edge.
            // Do not change payload during a stall.
            @(negedge vif.aclk);
            vif.tvalid = 1'b0;

            // Inform the sequencer that this item
            // has completed its hardware handshake.
            seq_item_port.item_done();

        end

    endtask

endclass