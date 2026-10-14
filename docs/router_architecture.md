# Buffered AXI-Stream Router Architecture

## 1. Overview

The DUT is a single-input, dual-output AXI-Stream router
with APB-controlled routing and independent output FIFOs.

## 2. Hardware Configuration

- AXI-Stream data width: 32 bits
- TKEEP width: 4 bits
- FIFO payload width: 37 bits
- FIFO depth: 4 entries per output
- Number of inputs: 1
- Number of outputs: 2
- Clock domain: Single clock
- Reset: Active-low asynchronous reset

## 3. APB Configuration

Register address: 0x00
Register name: ROUTE_SEL

- Bit 0 = 0: Route to Output 0
- Bit 0 = 1: Route to Output 1
- Other bits are reserved and read as zero
- Reset value: 0

A valid APB write updates ROUTE_SEL during the access
phase when PSEL, PENABLE, PWRITE, and PREADY are asserted.

Unsupported addresses generate PSLVERR.

## 4. Packet Routing

- The destination is selected on the first accepted beat.
- The destination remains locked until the accepted TLAST beat.
- APB configuration changes do not redirect an active packet.
- The next packet uses the latest committed APB configuration.
- A single-beat packet starts and ends on the same handshake.
- Simultaneous APB updates and new packet handshakes use
  the previously committed route for that packet.

## 5. FIFO Behavior

- Each output has an independent synchronous FIFO.
- Each FIFO stores TDATA, TKEEP, and TLAST.
- Input handshakes enqueue one beat into the selected FIFO.
- Output handshakes dequeue one beat from the corresponding FIFO.
- Writes are rejected when the selected FIFO is full.
- Reads are rejected when the FIFO is empty.
- Simultaneous push/pop is supported when both operations
  are accepted.
- Full-state push/pop bypass is not supported.

## 6. AXI-Stream Requirements

- A transfer occurs only when TVALID and TREADY are high.
- TVALID and payload must remain stable while stalled.
- TLAST identifies the final beat of a packet.
- Packet routing must remain consistent.
- Per-output beat ordering must be preserved.
- Outputs may progress independently.

## 7. Reset Behavior

- Clear both FIFO occupancy states.
- Clear the active packet state.
- Reset routing configuration to Output 0.
- Discard all pending transactions.

## 8. Verification Objectives

- Basic routing to Output 0 and Output 1
- Single-beat and multi-beat packets
- FIFO full and empty behavior
- Randomized output backpressure
- Simultaneous input/output transfers
- APB updates during active packets
- Packet ordering and data integrity
- Reset with pending transactions
