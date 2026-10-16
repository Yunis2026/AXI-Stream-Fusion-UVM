/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : apb_agent.svh
 *
 * Description:
 *   Reusable active/passive APB UVM agent.
 *
 * Active mode:
 *   - Creates APB sequencer
 *   - Creates APB driver
 *   - Creates APB monitor
 *
 * Passive mode:
 *   - Creates APB monitor only
 */

class apb_agent extends uvm_agent;

    `uvm_component_utils(apb_agent)

    // --------------------------------------------------
    // Agent components
    // --------------------------------------------------

    apb_sequencer sequencer;
    apb_driver    driver;
    apb_monitor   monitor;

    // --------------------------------------------------
    // Agent operating mode
    // --------------------------------------------------

    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------

    function new(
        string name = "apb_agent",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    // --------------------------------------------------
    // Build phase
    // --------------------------------------------------

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        // Allow the parent test to configure whether
        // this agent actively drives APB transactions.
        void'(uvm_config_db#(uvm_active_passive_enum)::get(
            this,
            "",
            "is_active",
            is_active
        ));

        // Always create the passive monitor.
        monitor = apb_monitor::type_id::create(
            "monitor",
            this
        );

        // Create the driver and sequencer only when
        // the agent is configured as active.
        if (is_active == UVM_ACTIVE) begin

            sequencer = apb_sequencer::type_id::create(
                "sequencer",
                this
            );

            driver = apb_driver::type_id::create(
                "driver",
                this
            );

        end

    endfunction

    // --------------------------------------------------
    // Connect phase
    // --------------------------------------------------

    function void connect_phase(uvm_phase phase);

        super.connect_phase(phase);

        if (is_active == UVM_ACTIVE) begin

            // Connect the driver to its sequencer.
            driver.seq_item_port.connect(
                sequencer.seq_item_export
            );

        end

    endfunction

endclass