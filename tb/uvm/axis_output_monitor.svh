/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : axis_output_monitor.svh
 *
 * Description:
 *   Passive AXI-Stream output monitor.
 *
 * Responsibilities:
 *   - Observe TVALID/TREADY handshakes
 *   - Capture TDATA, TKEEP, and TLAST
 *   - Reconstruct AXI-Stream sequence items
 *   - Publish observed items through an analysis port
 *
 * The monitor never drives interface signals.
 */

class axis_output_monitor extends uvm_monitor;

    `uvm_component_utils(axis_output_monitor)

    // Physical interface handle.
    virtual axis_if vif;

    // Broadcast observed transactions to subscribers.
    uvm_analysis_port #(axis_beat_item) ap;

    // Number of observed hardware handshakes.
    int unsigned observed_count = 0;

    function new(
        string name = "axis_output_monitor",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    // --------------------------------------------------
    // Build phase
    // --------------------------------------------------

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        ap = new("ap", this);

        // Retrieve the interface assigned to this monitor.
        if (!uvm_config_db#(virtual axis_if)::get(
            this, "", "vif", vif
        )) begin
            `uvm_fatal(
                "AXIS_MON",
                "Failed to get AXI output virtual interface"
            )
        end

    endfunction

    // --------------------------------------------------
    // Run phase
    // --------------------------------------------------

    task run_phase(uvm_phase phase);

        axis_beat_item item;

        forever begin

            // Sample a transfer at the rising clock edge.
            @(posedge vif.aclk);

            // Ignore cycles during reset.
            if (vif.aresetn !== 1'b1)
                continue;

            // A transaction exists only on a handshake.
            if (vif.tvalid === 1'b1 &&
                vif.tready === 1'b1) begin

                // Create an observed transaction.
                item = axis_beat_item::type_id::create(
                    "observed_item"
                );

                // Capture the actual interface payload.
                item.tdata = vif.tdata;
                item.tkeep = vif.tkeep;
                item.tlast = vif.tlast;

                observed_count++;

                `uvm_info(
                    "AXIS_MON",
                    $sformatf(
                        "%s observed beat %0d: %s",
                        get_name(),
                        observed_count,
                        item.convert2string()
                    ),
                    UVM_LOW
                )

                // Publish to connected analysis subscribers.
                ap.write(item);

            end

        end

    endtask

endclass