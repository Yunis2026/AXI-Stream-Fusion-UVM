class uvm_smoke_test extends uvm_test; // define a UVM test

    `uvm_component_utils(uvm_smoke_test) // Registering Components with the UVM Factory

    function new(           // create a component
        string name = "uvm_smoke_test",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase); // run_phase is the main entry point for the test

        phase.raise_objection(this); // prevent the test from ending prematurely 

        `uvm_info( // output UVM logs
            "FUSION_UVM",
            "Hello from AXI-Stream Fusion UVM!",
            UVM_LOW
        )

        phase.drop_objection(this); // tell the UVM that the test is completed

    endtask

endclass