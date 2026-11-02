// -----------------------------------------------------------------------------
// Module: tlc_cache_controller
// Description: Synthesizable TileLink TL-C (Caching) Node Interface Controller.
//              Handles Channels A, B, C, D, and E for ASIC synthesis.
// -----------------------------------------------------------------------------

package tlc_param_pkg;
    // Protocol Width Definitions
    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned SIZE_WIDTH = 3;
    localparam int unsigned SOURCE_WIDTH = 4;
    localparam int unsigned SINK_WIDTH = 4;
    localparam int unsigned MASK_WIDTH = DATA_WIDTH / 8;

    // Cache Line Permissions (MSI Protocol States)
    typedef enum logic [1:0] {
        PARAM_INVALID  = 2'b00,
        PARAM_SHARED   = 2'b01,
        PARAM_MODIFIED = 2'b10
    } cache_perm_e;
endpackage

module tlc_cache_controller 
    import tlc_param_pkg::*;
(
    // Global Clock and Reset
    input  logic                    clk,
    input  logic                    rst_n,

    // Channel A: Outbound Master Requests
    output logic                    tl_a_valid,
    input  logic                    tl_a_ready,
    output logic [2:0]              tl_a_opcode,
    output logic [2:0]              tl_a_param,
    output logic [SIZE_WIDTH-1:0]   tl_a_size,
    output logic [SOURCE_WIDTH-1:0] tl_a_source,
    output logic [ADDR_WIDTH-1:0]   tl_a_address,
    output logic [MASK_WIDTH-1:0]   tl_a_mask,
    output logic [DATA_WIDTH-1:0]   tl_a_data,
    output logic                    tl_a_corrupt,

    // Channel B: Inbound Probe Requests (From Manager)
    input  logic                    tl_b_valid,
    output logic                    tl_b_ready,
    input  logic [2:0]              tl_b_opcode,
    input  logic [1:0]              tl_b_param, // Target permission
    input  logic [SIZE_WIDTH-1:0]   tl_b_size,
    input  logic [SOURCE_WIDTH-1:0] tl_b_source,
    input  logic [ADDR_WIDTH-1:0]   tl_b_address,
    input  logic [MASK_WIDTH-1:0]   tl_b_mask,
    input  logic [DATA_WIDTH-1:0]   tl_b_data,
    input  logic                    tl_b_corrupt,

    // Channel C: Outbound Probe Responses / Voluntary Releases
    output logic                    tl_c_valid,
    input  logic                    tl_c_ready,
    output logic [2:0]              tl_c_opcode,
    output logic [2:0]              tl_c_param,
    output logic [SIZE_WIDTH-1:0]   tl_c_size,
    output logic [SOURCE_WIDTH-1:0] tl_c_source,
    output logic [ADDR_WIDTH-1:0]   tl_c_address,
    output logic [DATA_WIDTH-1:0]   tl_c_data,
    output logic                    tl_c_corrupt,

    // Channel D: Inbound Grant / Access Acknowledgements
    input  logic                    tl_d_valid,
    output logic                    tl_d_ready,
    input  logic [2:0]              tl_d_opcode,
    input  logic [2:0]              tl_d_param,
    input  logic [SIZE_WIDTH-1:0]   tl_d_size,
    input  logic [SOURCE_WIDTH-1:0] tl_d_source,
    input  logic [SINK_WIDTH-1:0]   tl_d_sink,
    input  logic                    tl_d_denied,
    input  logic [DATA_WIDTH-1:0]   tl_d_data,
    input  logic                    tl_d_corrupt,

    // Channel E: Outbound Grant Acknowledgements
    output logic                    tl_e_valid,
    input  logic                    tl_e_ready,
    output logic [SINK_WIDTH-1:0]   tl_e_sink
);

    // -------------------------------------------------------------------------
    // Internal Registers & State Machinery
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_WAIT_GRANT,
        STATE_PROBE_ACK,
        STATE_GRANT_ACK
    } state_e;

    state_e current_state, next_state;

    // Internal Buffering for Handshaking Boundaries
    logic [SINK_WIDTH-1:0]   sink_reg;
    logic [ADDR_WIDTH-1:0]   probe_addr_reg;
    logic [SOURCE_WIDTH-1:0] probe_src_reg;

    // -------------------------------------------------------------------------
    // Synchronous State Reset and Transition (ASIC-Friendly Flops)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state  <= STATE_IDLE;
            sink_reg       <= '0;
            probe_addr_reg <= '0;
            probe_src_reg  <= '0;
        end else begin
            current_state <= next_state;
            
            // Sample incoming Sink ID during Channel D Grant to acknowledge on Channel E
            if (tl_d_valid && tl_d_ready && (tl_d_opcode == 3'h4 || tl_d_opcode == 3'h5)) begin
                sink_reg <= tl_d_sink;
            end
            
            // Sample probe context on Channel B hit
            if (tl_b_valid && tl_b_ready) begin
                probe_addr_reg <= tl_b_address;
                probe_src_reg  <= tl_b_source;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Next State Logic & Protocol FSM
    // -------------------------------------------------------------------------
    always_comb begin
        next_state = current_state;

        case (current_state)
            STATE_IDLE: begin
                if (tl_b_valid) begin
                    next_state = STATE_PROBE_ACK;
                end else if (tl_a_valid && tl_a_ready) begin
                    next_state = STATE_WAIT_GRANT;
                end
            end

            STATE_WAIT_GRANT: begin
                // Transition forward once Grant (Opcode 4 or 5) arrives
                if (tl_d_valid && tl_d_ready) begin
                    next_state = STATE_GRANT_ACK;
                end
            end

            STATE_PROBE_ACK: begin
                if (tl_c_valid && tl_c_ready) begin
                    next_state = STATE_IDLE;
                end
            end

            STATE_GRANT_ACK: begin
                if (tl_e_valid && tl_e_ready) begin
                    next_state = STATE_IDLE;
                end
            end

            default: next_state = STATE_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Channel Management & Combinational Output Assignment
    // -------------------------------------------------------------------------

    // --- Channel A Logic ---
    // Example configurations: Statically assigned or tied to top-level core request logic
    assign tl_a_opcode  = 3'h6; // AcquireBlock
    assign tl_a_param   = 3'h0; // NtoB (Grow permissions from Invalid to Shared)
    assign tl_a_size    = 3'h6; // 64-byte cache line block size
    assign tl_a_corrupt = 1'b0;

    // --- Channel B Logic ---
    // Accept incoming probe requests when we are structurally ready (Idle state)
    assign tl_b_ready   = (current_state == STATE_IDLE);

    // --- Channel C Logic ---
    // Respond to Manager Probes (ProbeAck / ProbeAckData)
    assign tl_c_valid   = (current_state == STATE_PROBE_ACK);
    assign tl_c_opcode  = 3'h3; // ProbeAck
    assign tl_c_param   = 3'h3; // Target validation parameter (e.g., TtoN)
    assign tl_c_size    = 3'h6; 
    assign tl_c_source  = probe_src_reg;
    assign tl_c_address = probe_addr_reg;
    assign tl_c_data    = '0;   // In structural ProbeAck without data payload
    assign tl_c_corrupt = 1'b0;

    // --- Channel D Logic ---
    // Ready to accept data/ack whenever we are explicitly expecting a transaction response
    assign tl_d_ready   = (current_state == STATE_WAIT_GRANT);

    // --- Channel E Logic ---
    // Final Broadcast Phase: Send GrantAck to the manager to finalize serialization point
    assign tl_e_valid   = (current_state == STATE_GRANT_ACK);
    assign tl_e_sink    = sink_reg;

endmodule

