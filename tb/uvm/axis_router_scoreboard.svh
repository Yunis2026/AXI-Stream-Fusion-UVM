/*
 * Project : AXI-Stream Fusion - UVM Verification Platform
 * File    : axis_router_scoreboard.svh
 *
 * Description:
 *   Reference-model scoreboard for one AXI-Stream input
 *   and two independent AXI-Stream outputs.
 *
 * Current test scope:
 *   - APB remains idle
 *   - Default route is Output 0
 *   - Three-beat packet verification
 *   - Independent input/output transaction comparison
 *
 * Future extensions:
 *   - APB configuration tracking
 *   - Dynamic packet routing
 *   - Reset-aware queue flushing
 *   - Randomized traffic verification
 */

class axis_router_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(axis_router_scoreboard)

    // --------------------------------------------------
    // 1. Analysis implementation ports
    // --------------------------------------------------

    // Receives accepted input transactions.
    uvm_analysis_imp_input #(
        axis_beat_item,
        axis_router_scoreboard
    ) input_imp;

    // Receives transactions from Output 0.
    uvm_analysis_imp_output0 #(
        axis_beat_item,
        axis_router_scoreboard
    ) output0_imp;

    // Receives transactions from Output 1.
    uvm_analysis_imp_output1 #(
        axis_beat_item,
        axis_router_scoreboard
    ) output1_imp;

    // --------------------------------------------------
    // 2. Expected transaction queues
    // --------------------------------------------------

    axis_beat_item expected_q0[$];
    axis_beat_item expected_q1[$];

    // --------------------------------------------------
    // 3. Independent reference-model state
    // --------------------------------------------------

    // The APB register defaults to Output 0.
    bit ref_route_sel = 1'b0;

    // Tracks packet-level routing state.
    bit ref_in_packet = 1'b0;
    bit ref_packet_route = 1'b0;

    // --------------------------------------------------
    // 4. Verification counters
    // --------------------------------------------------

    int unsigned input_count   = 0;
    int unsigned output0_count = 0;
    int unsigned output1_count = 0;
    int unsigned matched_count = 0;

    // --------------------------------------------------
    // 5. Constructor
    // --------------------------------------------------

    function new(
        string name = "axis_router_scoreboard",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    // --------------------------------------------------
    // 6. Build phase
    // --------------------------------------------------

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        input_imp = new("input_imp", this);

        output0_imp = new("output0_imp", this);

        output1_imp = new("output1_imp", this);

    endfunction

    // --------------------------------------------------
    // 7. Input transaction prediction
    // --------------------------------------------------

    // Called whenever the input monitor publishes
    // a successfully accepted AXI-Stream beat.
    function void write_input(axis_beat_item item);

        axis_beat_item expected_item;
        bit selected_route;

        // Select the locked destination for an active
        // packet or the APB route for a new packet.
        selected_route = ref_in_packet
                       ? ref_packet_route
                       : ref_route_sel;

        // Create an independent copy of the transaction.
        expected_item =
            axis_beat_item::type_id::create("expected_item");

        expected_item.copy(item);

        // Store the expected beat in the selected queue.
        if (selected_route == 1'b0) begin
            expected_q0.push_back(expected_item);
        end
        else begin
            expected_q1.push_back(expected_item);
        end

        // Lock the route when the first beat is accepted.
        if (!ref_in_packet) begin
            ref_packet_route = ref_route_sel;
        end

        // Release packet lock on an accepted TLAST beat.
        ref_in_packet = !item.tlast;

        input_count++;

        `uvm_info(
            "ROUTER_SB",
            $sformatf(
                "Input beat %0d predicted for Output %0d: %s",
                input_count,
                selected_route,
                item.convert2string()
            ),
            UVM_LOW
        )

    endfunction

    // --------------------------------------------------
    // 8. Output 0 transaction comparison
    // --------------------------------------------------

    // Called by the Output 0 monitor analysis port.
    function void write_output0(axis_beat_item actual);

        axis_beat_item expected;

        // An output transaction must have a matching
        // previously accepted input transaction.
        if (expected_q0.size() == 0) begin

            `uvm_fatal(
                "ROUTER_SB",
                "Unexpected Output 0 transaction"
            )

        end

        // Retrieve the oldest expected transaction.
        expected = expected_q0.pop_front();

        // Compare the complete AXI-Stream beat.
        if (
            actual.tdata !== expected.tdata ||
            actual.tkeep !== expected.tkeep ||
            actual.tlast !== expected.tlast
        ) begin

            `uvm_fatal(
                "ROUTER_SB",
                $sformatf(
                    "Output 0 mismatch: expected [%s], actual [%s]",
                    expected.convert2string(),
                    actual.convert2string()
                )
            )

        end

        output0_count++;
        matched_count++;

        `uvm_info(
            "ROUTER_SB",
            $sformatf(
                "[MATCH] Output 0 beat %0d: %s",
                output0_count,
                actual.convert2string()
            ),
            UVM_LOW
        )

    endfunction

    // --------------------------------------------------
    // 9. Output 1 transaction comparison
    // --------------------------------------------------

    // Called by the Output 1 monitor analysis port.
    function void write_output1(axis_beat_item actual);

        axis_beat_item expected;

        if (expected_q1.size() == 0) begin

            `uvm_fatal(
                "ROUTER_SB",
                "Unexpected Output 1 transaction"
            )

        end

        expected = expected_q1.pop_front();

        if (
            actual.tdata !== expected.tdata ||
            actual.tkeep !== expected.tkeep ||
            actual.tlast !== expected.tlast
        ) begin

            `uvm_fatal(
                "ROUTER_SB",
                $sformatf(
                    "Output 1 mismatch: expected [%s], actual [%s]",
                    expected.convert2string(),
                    actual.convert2string()
                )
            )

        end

        output1_count++;
        matched_count++;

        `uvm_info(
            "ROUTER_SB",
            $sformatf(
                "[MATCH] Output 1 beat %0d: %s",
                output1_count,
                actual.convert2string()
            ),
            UVM_LOW
        )

    endfunction

    // --------------------------------------------------
    // 10. End-of-test verification
    // --------------------------------------------------

    function void check_phase(uvm_phase phase);

        super.check_phase(phase);

        // No expected transactions should remain.
        if (
            expected_q0.size() != 0 ||
            expected_q1.size() != 0
        ) begin

            `uvm_error(
                "ROUTER_SB",
                "Expected queues are not empty at test end"
            )

        end

        // Every accepted input beat must be matched
        // to exactly one output beat in this smoke test.
        if (input_count != matched_count) begin

            `uvm_error(
                "ROUTER_SB",
                $sformatf(
                    "Input count=%0d, matched count=%0d",
                    input_count,
                    matched_count
                )
            )

        end

        `uvm_info(
            "ROUTER_SB",
            $sformatf(
                "Summary: input=%0d output0=%0d output1=%0d matched=%0d",
                input_count,
                output0_count,
                output1_count,
                matched_count
            ),
            UVM_LOW
        )

    endfunction

endclass