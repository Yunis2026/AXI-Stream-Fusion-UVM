# Toolchain and Dependencies

## Development Environment

- Platform: macOS on Apple Silicon
- IDE: Visual Studio Code
- RTL Simulator: Verilator 5.052
- UVM Library: CHIPS Alliance uvm-verilator, UVM 2020.3.2
- C++ Compiler: Apple Clang 21.0.0
- Build Tool: GNU Make 3.81

## UVM Smoke Test

The initial UVM smoke test successfully completed.

Verified capabilities:
- UVM test registration and creation
- UVM run phase execution
- Objection handling
- UVM reporting

Current limitations:
- Built with UVM_NO_DPI
- DPI-dependent functionality not yet verified
- Sequence, TLM, and virtual interface functionality not yet tested

## Dependency Source

https://github.com/chipsalliance/uvm-verilator

Exact dependency commit: To be recorded.
