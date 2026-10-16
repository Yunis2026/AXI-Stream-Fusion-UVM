/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : apb_item.svh
 *
 * Description:
 *   UVM sequence item representing one APB transaction.
 *
 * Request fields:
 *   - write
 *   - addr
 *   - wdata
 *
 * Response fields:
 *   - rdata
 *   - slverr
 *
 * Response fields are populated by the APB driver
 * after a successful APB access handshake.
 */

class apb_item extends uvm_sequence_item;

    // --------------------------------------------------
    // Request fields
    // --------------------------------------------------

    rand bit        write;
    rand bit [7:0]  addr;
    rand bit [31:0] wdata;

    // --------------------------------------------------
    // Response fields
    // --------------------------------------------------

    logic [31:0] rdata;
    logic        slverr;

    // Register the transaction with the UVM factory.
    `uvm_object_utils(apb_item)

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------

    function new(string name = "apb_item");
        super.new(name);

        rdata  = '0;
        slverr = 1'b0;
    endfunction

    // --------------------------------------------------
    // String representation
    // --------------------------------------------------

    function string convert2string();

        return $sformatf(
            "WRITE=%0b ADDR=0x%02h WDATA=0x%08h RDATA=0x%08h PSLVERR=%0b",
            write,
            addr,
            wdata,
            rdata,
            slverr
        );

    endfunction

endclass