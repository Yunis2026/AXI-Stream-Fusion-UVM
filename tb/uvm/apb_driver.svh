/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : apb_driver.svh
 *
 * Description:
 *   APB3 master driver for UVM verification.
 *
 * Responsibilities:
 *   - Obtain APB transactions from the sequencer
 *   - Generate APB setup and access phases
 *   - Wait for PREADY
 *   - Capture PRDATA and PSLVERR
 *   - Return the completed transaction to the sequence
 *
 * The driver supports zero-wait and wait-state slaves.
 * Reset assertion during an active transaction is
 * treated as a fatal error in this initial smoke test.
 */

class apb_driver extends uvm_driver #(apb_item);

    `uvm_component_utils(apb_driver)

    // Physical APB interface handle.
    virtual apb_if vif;

    // Number of completed APB transactions.
    int unsigned completed_count = 0;

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------

    function new(
        string name = "apb_driver",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    // --------------------------------------------------
    // Build phase
    // --------------------------------------------------

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        if (!uvm_config_db#(virtual apb_if)::get(
            this,
            "",
            "vif",
            vif
        )) begin

            `uvm_fatal(
                "APB_DRV",
                "Failed to obtain APB virtual interface"
            )

        end

    endfunction

    // --------------------------------------------------
    // Drive one APB transaction
    // --------------------------------------------------

    task automatic drive_transfer(apb_item req);

        // ----------------------------------------------
        // SETUP PHASE
        // ----------------------------------------------

        // Drive all request signals on a falling edge.
        @(negedge vif.pclk);

        vif.psel    = 1'b1;
        vif.penable = 1'b0;
        vif.pwrite  = req.write;
        vif.paddr   = req.addr;
        vif.pwdata  = req.wdata;

        // ----------------------------------------------
        // ACCESS PHASE
        // ----------------------------------------------

        // Assert PENABLE in the next clock cycle.
        @(negedge vif.pclk);

        vif.penable = 1'b1;

        // Wait until the slave completes the access.
        do begin

            @(posedge vif.pclk);

            if (vif.presetn !== 1'b1) begin

                `uvm_fatal(
                    "APB_DRV",
                    "Reset asserted during APB transaction"
                )

            end

        end while (vif.pready !== 1'b1);

        // Sample the response at the successful
        // APB access clock edge.
        req.rdata  = vif.prdata;
        req.slverr = vif.pslverr;

        completed_count++;

        `uvm_info(
            "APB_DRV",
            $sformatf(
                "Completed APB transaction %0d: %s",
                completed_count,
                req.convert2string()
            ),
            UVM_LOW
        )

        // ----------------------------------------------
        // RETURN TO IDLE
        // ----------------------------------------------

        // Deassert PSEL/PENABLE after the access edge.
        @(negedge vif.pclk);

        vif.psel    = 1'b0;
        vif.penable = 1'b0;
        vif.pwrite  = 1'b0;

    endtask

    // --------------------------------------------------
    // Run phase
    // --------------------------------------------------

    task run_phase(uvm_phase phase);

        apb_item req;

        // Initialize the APB master interface.
        vif.psel    = 1'b0;
        vif.penable = 1'b0;
        vif.pwrite  = 1'b0;
        vif.paddr   = '0;
        vif.pwdata  = '0;

        // Wait until reset is released.
        wait (vif.presetn === 1'b1);

        forever begin

            // Retrieve the next request.
            seq_item_port.get_next_item(req);

            // Execute the complete APB transaction.
            drive_transfer(req);

            // Return control to the sequence.
            seq_item_port.item_done();

        end

    endtask

endclass