/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : apb_basic_sequence.svh
 *
 * Description:
 *   Directed APB register verification sequence.
 *
 * Test coverage:
 *   - Reset default value
 *   - Valid register writes
 *   - Register readback
 *   - Invalid address detection
 *   - Invalid write protection
 *   - Reserved bit behavior
 */

class apb_basic_sequence extends uvm_sequence #(apb_item);

    `uvm_object_utils(apb_basic_sequence)

    // Number of successfully verified transactions.
    int unsigned checked_count = 0;

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------

    function new(string name = "apb_basic_sequence");
        super.new(name);
    endfunction

    // --------------------------------------------------
    // Execute and verify one APB transaction
    // --------------------------------------------------

    task automatic access(
        input string       test_name,
        input bit          write,
        input bit [7:0]    addr,
        input bit [31:0]   wdata,
        input bit          expected_error,
        input bit [31:0]   expected_rdata
    );

        apb_item req;

        // Create a transaction using the UVM factory.
        req = apb_item::type_id::create(
            $sformatf("apb_req_%0d", checked_count)
        );

        // Request permission from the sequencer.
        start_item(req);

        // Configure the APB request.
        req.write = write;
        req.addr  = addr;
        req.wdata = wdata;

        // Wait for the driver to complete the transfer.
        finish_item(req);

        // Verify the APB error response.
        if (req.slverr !== expected_error) begin

            `uvm_fatal(
                "APB_SEQ",
                $sformatf(
                    "%s: PSLVERR mismatch, expected=%0b actual=%0b",
                    test_name,
                    expected_error,
                    req.slverr
                )
            )

        end

        // Verify read data for read transactions.
        if (!write && req.rdata !== expected_rdata) begin

            `uvm_fatal(
                "APB_SEQ",
                $sformatf(
                    "%s: PRDATA mismatch, expected=0x%08h actual=0x%08h",
                    test_name,
                    expected_rdata,
                    req.rdata
                )
            )

        end

        checked_count++;

        `uvm_info(
            "APB_SEQ",
            $sformatf(
                "[PASS] %s",
                test_name
            ),
            UVM_LOW
        )

    endtask

    // --------------------------------------------------
    // Main directed sequence
    // --------------------------------------------------

    virtual task body();

        // A01: Read the reset default.
        access(
            "A01: Default ROUTE_SEL = 0",
            1'b0,
            8'h00,
            32'h0000_0000,
            1'b0,
            32'h0000_0000
        );

        // A02: Select Output 1.
        access(
            "A02: Write ROUTE_SEL = 1",
            1'b1,
            8'h00,
            32'h0000_0001,
            1'b0,
            32'h0000_0000
        );

        // A03: Read back Output 1 selection.
        access(
            "A03: Read ROUTE_SEL = 1",
            1'b0,
            8'h00,
            32'h0000_0000,
            1'b0,
            32'h0000_0001
        );

        // A04: Invalid writes must report an error.
        access(
            "A04: Invalid Address Write",
            1'b1,
            8'h04,
            32'h0000_0000,
            1'b1,
            32'h0000_0000
        );

        // A05: Invalid writes must not alter ROUTE_SEL.
        access(
            "A05: Verify Invalid Write Was Ignored",
            1'b0,
            8'h00,
            32'h0000_0000,
            1'b0,
            32'h0000_0001
        );

        // A06: Reserved upper bits must be ignored.
        access(
            "A06: Write Reserved Upper Bits",
            1'b1,
            8'h00,
            32'hFFFF_FFFE,
            1'b0,
            32'h0000_0000
        );

        // A07: Reserved bits read back as zero.
        access(
            "A07: Read Reserved Bits As Zero",
            1'b0,
            8'h00,
            32'h0000_0000,
            1'b0,
            32'h0000_0000
        );

        // A08: Explicitly select Output 0.
        access(
            "A08: Write ROUTE_SEL = 0",
            1'b1,
            8'h00,
            32'h0000_0000,
            1'b0,
            32'h0000_0000
        );

        // A09: Read back Output 0 selection.
        access(
            "A09: Read ROUTE_SEL = 0",
            1'b0,
            8'h00,
            32'h0000_0000,
            1'b0,
            32'h0000_0000
        );

        // A10: Invalid reads must report an error.
        access(
            "A10: Invalid Address Read",
            1'b0,
            8'h04,
            32'h0000_0000,
            1'b1,
            32'h0000_0000
        );

        // Explicit sequence completion marker.
        `uvm_info(
            "APB_SEQ",
            "APB_UVM_SEQUENCE_PASS",
            UVM_NONE
        )

    endtask

endclass