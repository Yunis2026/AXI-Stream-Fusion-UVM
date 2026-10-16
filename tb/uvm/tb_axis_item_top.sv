
/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : tb_axis_item_top.sv
 *
 * Description:
 *   UVM smoke test for AXI-Stream sequence items.
 *
 * Verification objectives:
 *   - Create an item using the UVM factory
 *   - Check transaction field assignments
 *   - Generate randomized transactions
 *   - Print transaction information
 */

`timescale 1ns/1ps

// --------------------------------------------------
// 1. UVM smoke test package
// --------------------------------------------------

package axis_item_smoke_pkg;

    import uvm_pkg::*;
    import axis_pkg::*;

    `include "uvm_macros.svh"

    // ----------------------------------------------
    // UVM test class
    // ----------------------------------------------

    class axis_item_smoke_test extends uvm_test;

        `uvm_component_utils(axis_item_smoke_test)

        // Constructor
        function new(
            string name = "axis_item_smoke_test",
            uvm_component parent = null
        );
            super.new(name, parent);
        endfunction

        // ------------------------------------------
        // Main test sequence
        // ------------------------------------------

        task run_phase(uvm_phase phase);

            axis_beat_item item;

            phase.raise_objection(this);

            `uvm_info(
                "AXIS_ITEM",
                "Starting AXI-Stream transaction smoke test",
                UVM_LOW
            )

            // --------------------------------------
            // Test 1: Factory creation
            // --------------------------------------

            item = axis_beat_item::type_id::create(
                "directed_item"
            );

            if (item == null) begin
                `uvm_fatal(
                    "AXIS_ITEM",
                    "UVM factory failed to create an item"
                )
            end

            `uvm_info(
                "AXIS_ITEM",
                "[PASS] Factory creation",
                UVM_LOW
            )

            // --------------------------------------
            // Test 2: Directed field assignment
            // --------------------------------------

            item.tdata = 32'h1234_5678;
            item.tkeep = 4'hF;
            item.tlast = 1'b1;

            if (
                item.tdata !== 32'h1234_5678 ||
                item.tkeep !== 4'hF ||
                item.tlast !== 1'b1
            ) begin
                `uvm_fatal(
                    "AXIS_ITEM",
                    "Directed transaction field mismatch"
                )
            end

            `uvm_info(
                "AXIS_ITEM",
                $sformatf(
                    "[PASS] Directed item: %s",
                    item.convert2string()
                ),
                UVM_LOW
            )

            // --------------------------------------
            // Test 3: Random transaction generation
            // --------------------------------------

            for (int i = 0; i < 5; i++) begin

                item = axis_beat_item::type_id::create(
                    $sformatf("random_item_%0d", i)
                );

                if (!item.randomize()) begin
                    `uvm_fatal(
                        "AXIS_ITEM",
                        "Transaction randomization failed"
                    )
                end

                `uvm_info(
                    "AXIS_ITEM",
                    $sformatf(
                        "Random item %0d: %s",
                        i,
                        item.convert2string()
                    ),
                    UVM_LOW
                )

            end

            `uvm_info(
                "AXIS_ITEM",
                "[PASS] Random transaction generation",
                UVM_LOW
            )

            // Final success marker for regression.
            `uvm_info(
                "AXIS_ITEM",
                "AXIS_ITEM_SMOKE_PASS",
                UVM_NONE
            )

            phase.drop_objection(this);

        endtask

    endclass

endpackage

// --------------------------------------------------
// 2. UVM simulation top
// --------------------------------------------------

module tb_axis_item_top;

    import uvm_pkg::*;
    import axis_item_smoke_pkg::*;

    initial begin

        // Start the factory-registered UVM test.
        run_test("axis_item_smoke_test");

    end

endmodule
