/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : apb_monitor.svh
 *
 * Description:
 *   Passive APB3 bus monitor.
 *
 * Responsibilities:
 *   - Observe completed APB transfers
 *   - Capture request and response fields
 *   - Publish transactions through an analysis port
 *   - Count reads, writes and error responses
 *
 * The monitor never drives APB signals.
 */

class apb_monitor extends uvm_monitor;

    `uvm_component_utils(apb_monitor)

    // Physical APB bus interface.
    virtual apb_if vif;

    // Publish observed transactions to subscribers.
    uvm_analysis_port #(apb_item) ap;

    // Verification statistics.
    int unsigned observed_count = 0;
    int unsigned read_count     = 0;
    int unsigned write_count    = 0;
    int unsigned error_count    = 0;

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------

    function new(
        string name = "apb_monitor",
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

        if (!uvm_config_db#(virtual apb_if)::get(
            this,
            "",
            "vif",
            vif
        )) begin
            `uvm_fatal(
                "APB_MON",
                "Failed to obtain APB virtual interface"
            )
        end

    endfunction

    // --------------------------------------------------
    // Run phase
    // --------------------------------------------------

    task run_phase(uvm_phase phase);

        apb_item observed;

        forever begin

            // Sample on the clock edge used by the DUT.
            @(posedge vif.pclk);

            // Ignore reset cycles.
            if (vif.presetn !== 1'b1) begin
                continue;
            end

            // An APB transfer completes only when
            // PSEL, PENABLE and PREADY are all asserted.
            if (
                vif.psel    === 1'b1 &&
                vif.penable === 1'b1 &&
                vif.pready  === 1'b1
            ) begin

                // Create a new transaction for every
                // completed transfer.
                observed = apb_item::type_id::create(
                    "observed"
                );

                // Capture the APB request.
                observed.write = vif.pwrite;
                observed.addr  = vif.paddr;
                observed.wdata = vif.pwdata;

                // Capture the APB response.
                observed.rdata  = vif.prdata;
                observed.slverr = vif.pslverr;

                // Update transaction statistics.
                observed_count++;

                if (observed.write) begin
                    write_count++;
                end
                else begin
                    read_count++;
                end

                if (observed.slverr) begin
                    error_count++;
                end

                `uvm_info(
                    "APB_MON",
                    $sformatf(
                        "Observed transfer %0d: %s",
                        observed_count,
                        observed.convert2string()
                    ),
                    UVM_LOW
                )

                // Broadcast the completed transaction.
                ap.write(observed);

            end

        end

    endtask

endclass