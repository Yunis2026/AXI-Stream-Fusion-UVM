`timescale 1ns/1ps

module tb_uvm_top;

    import uvm_pkg::*;

    `include "uvm_macros.svh"
    `include "uvm_smoke_test.sv"

    initial begin
        run_test("uvm_smoke_test");
    end

endmodule