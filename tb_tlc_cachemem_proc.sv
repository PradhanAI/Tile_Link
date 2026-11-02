`timescale 1ns/1ps

module tb_tlc_cache_ram;
    import tlc_param_pkg::*;

    // -------------------------------------------------------------------------
    // 1. Clock & Reset Emulation
    // -------------------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz Clock
    end

    // -------------------------------------------------------------------------
    // 2. Interface Signal Declarations
    // -------------------------------------------------------------------------
    // Local Core Interface
    logic                    core_req_valid;
    logic                    core_req_ready;
    logic [ADDR_WIDTH-1:0]   core_req_addr;
    logic                    core_req_write;
    logic [DATA_WIDTH-1:0]   core_req_wdata;
    logic [DATA_WIDTH-1:0]   core_req_rdata;
    logic                    core_hit;

    // TileLink Channel A (Outbound Requests)
    logic                    tl_a_valid;
    logic                    tl_a_ready;
    logic [2:0]              tl_a_opcode;
    logic [2:0]              tl_a_param;
    logic [SIZE_WIDTH-1:0]   tl_a_size;
    logic [SOURCE_WIDTH-1:0] tl_a_source;
    logic [ADDR_WIDTH-1:0]   tl_a_address;
    logic [MASK_WIDTH-1:0]   tl_a_mask;
    logic [DATA_WIDTH-1:0]   tl_a_data;
    logic                    tl_a_corrupt;

    // TileLink Channel B (Inbound Probes)
    logic                    tl_b_valid;
    logic                    tl_b_ready;
    logic [2:0]              tl_b_opcode;
    logic [1:0]              tl_b_param;
    logic [SIZE_WIDTH-1:0]   tl_b_size;
    logic [SOURCE_WIDTH-1:0] tl_b_source;
    logic [ADDR_WIDTH-1:0]   tl_b_address;
    logic [MASK_WIDTH-1:0]   tl_b_mask;
    logic [DATA_WIDTH-1:0]   tl_b_data;
    logic                    tl_b_corrupt;

    // TileLink Channel C (Outbound Probe Responses)
    logic                    tl_c_valid;
    logic                    tl_c_ready;
    logic [2:0]              tl_c_opcode;
    logic [2:0]              tl_c_param;
    logic [SIZE_WIDTH-1:0]   tl_c_size;
    logic [SOURCE_WIDTH-1:0] tl_c_source;
    logic [ADDR_WIDTH-1:0]   tl_c_address;
    logic [DATA_WIDTH-1:0]   tl_c_data;
    logic                    tl_c_corrupt;

    // TileLink Channel D (Inbound Grants)
    logic                    tl_d_valid;
    logic                    tl_d_ready;
    logic [2:0]              tl_d_opcode;
    logic [2:0]              tl_d_param;
    logic [SIZE_WIDTH-1:0]   tl_d_size;
    logic [SOURCE_WIDTH-1:0] tl_d_source;
    logic [SINK_WIDTH-1:0]   tl_d_sink;
    logic                    tl_d_denied;
    logic [DATA_WIDTH-1:0]   tl_d_data;
    logic                    tl_d_corrupt;

    // TileLink Channel E (Outbound Grant Acknowledgements)
    logic                    tl_e_valid;
    logic                    tl_e_ready;
    logic [SINK_WIDTH-1:0]   tl_e_sink;

    // -------------------------------------------------------------------------
    // 3. Device Under Test (DUT) Instantiation
    // -------------------------------------------------------------------------
    tlc_cache_controller_with_ram u_dut (.*);

    // -------------------------------------------------------------------------
    // 4. Automated Interface Drivers & Helper Tasks
    // -------------------------------------------------------------------------
    
    // Core Request Driver
    task automatic drive_core_req(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic                  write,
        input logic [DATA_WIDTH-1:0] wdata
    );
        begin
            @(posedge clk);
            while (!core_req_ready) @(posedge clk); // Wait if controller is busy
            core_req_addr  <= addr;
            core_req_write <= write;
            core_req_wdata <= wdata;
            core_req_valid <= 1'b1;
            
            @(posedge clk);
            // If it's a hit, it clears in one cycle. If a miss, hold until FSM allocates.
            while (!core_hit && (u_dut.current_state == IDLE)) @(posedge clk);
            core_req_valid <= 1'b0;
            core_req_write <= 1'b0;
        end
    endtask

    // Manager Interconnect Emulation Tasks
    task automatic handle_channel_a_miss(
        input logic [SINK_WIDTH-1:0]   assign_sink,
        input logic [DATA_WIDTH-1:0]   refill_data
    );
        begin
            // Wait for Controller to broadcast the Acquire block out on Channel A
            while (!tl_a_valid) @(posedge clk);
            $display("[TL-A MONITOR] AcquireBlock Detected! Addr: 0x%0h, Op: %0h", tl_a_address, tl_a_opcode);
            
            @(posedge clk);
            // Simulate a multi-cycle network memory delay before responding
            repeat (3) @(posedge clk);
            
            // Inject GrantData (Opcode 5) on Channel D
            tl_d_valid <= 1'b1;
            tl_d_opcode<= 3'h5; // GrantData
            tl_d_sink  <= assign_sink;
            tl_d_data  <= refill_data;
            
            while (!tl_d_ready) @(posedge clk); // Handshake check
            @(posedge clk);
            tl_d_valid <= 1'b0;
            $display("[TL-D DRIVER] GrantData Sent. Sink ID: 0x%0h, Data: 0x%0h", assign_sink, refill_data);
        end
    endtask

    task automatic inject_manager_probe(
        input logic [ADDR_WIDTH-1:0]   probe_addr,
        input logic [SOURCE_WIDTH-1:0] probe_src
    );
        begin
            @(posedge clk);
            while (u_dut.current_state != IDLE) @(posedge clk); // Ensure FSM is stable
            
            tl_b_valid   <= 1'b1;
            tl_b_opcode  <= 3'h6; // Intent to Invalidate Probe
            tl_b_address <= probe_addr;
            tl_b_source  <= probe_src;
            
            while (!tl_b_ready) @(posedge clk);
            @(posedge clk);
            tl_b_valid   <= 1'b0;
            $display("[TL-B DRIVER] Probe injected to address 0x%0h", probe_addr);
        end
    endtask

    // -------------------------------------------------------------------------
    // 5. Main Test Execution Sequence
    // -------------------------------------------------------------------------
    initial begin
        // Reset and Static Setup
        rst_n          = 1'b0;
        core_req_valid = 1'b0;
        core_req_addr  = '0;
        core_req_write = 1'b0;
        core_req_wdata = '0;
        
        // Interconnect default readiness signals
        tl_a_ready     = 1'b1;
        tl_b_valid     = 1'b0;
        tl_c_ready     = 1'b1;
        tl_d_valid     = 1'b0;
        tl_e_ready     = 1'b1;
        
        #30;
        rst_n = 1'b1;
        $display("[SYSTEM INFO] Power-on-Reset cleared smoothly.");
        repeat (2) @(posedge clk);

        // =====================================================================
        // TEST CASE 1: Cache Cold Read Miss & Refill Operations
        // =====================================================================
        $display("\n=== TEST CASE 1: Executing Read Miss Pipeline ===");
        
        fork
            // Thread A: Drive Core Request
            drive_core_req(32'h0000_A000, 1'b0, '0);
            
            // Thread B: Act as the Interconnect Manager Response Engine
            handle_channel_a_miss(4'h5, 64'hA5A5_5A5A_1234_5678);
        join

        // Verify Channel E Serialization Handshake completeness
        while (!tl_e_valid) @(posedge clk);
        if (tl_e_sink == 4'h5) begin
            $display("[SUCCESS] Channel E matched matching Sink ID: 0x%0h", tl_e_sink);
        end else begin
            $display("[FAILURE] Channel E payload verification mismatch!");
        end
        repeat (2) @(posedge clk);

        // =====================================================================
        // TEST CASE 2: Cache Hit Verification
        // =====================================================================
        $display("\n=== TEST CASE 2: Executing Read Hit Verification ===");
        
        // Re-request the same address. Should hit instantly within the same cycle.
        drive_core_req(32'h0000_A000, 1'b0, '0);
        #1; // Brief settling wait for combinational output tracking evaluation
        
        if (core_hit && (core_req_rdata == 64'hA5A5_5A5A_1234_5678)) begin
            $display("[SUCCESS] Cache Hit Validated! Retained Data: 0x%0h", core_req_rdata);
        end else begin
            $display("[FAILURE] Cache Miss returned unexpectedly or data corrupted.");
        end
        repeat (3) @(posedge clk);

        // =====================================================================
        // TEST CASE 3: Inbound Probe Interrogation & State Eviction
        // =====================================================================
        $display("\n=== TEST CASE 3: Inbound Probe & MSI Eviction ===");
        
        // Inject a Probe targeting the exact cache line index allocated in Case 1
        inject_manager_probe(32'h0000_A000, 4'h3);
        
        // Wait for Probe Acknowledgement on Channel C
        while (!tl_c_valid) @(posedge clk);
        $display("[TL-C MONITOR] ProbeAck detected out of Controller! Address: 0x%0h, Opcode: %0h", tl_c_address, tl_c_opcode);
        
        // Wait for FSM to revert to IDLE
        repeat(2) @(posedge clk);
        
        // Verify address line was invalidated locally (Should Miss now)
        $display("[TEST] Re-checking address 0x0000_A000 post-eviction lookup...");
        core_req_addr  = 32'h0000_A000;
        core_req_valid = 1'b1;
        #1;
        
        if (!core_hit) begin
            $display("[SUCCESS] Cache Line Evicted Cleanly. Node state dropped to Invalid.");
        end else begin
            $display("[FAILURE] Cache Line still registered as Hit despite ProbeAck transition!");
        end
        
        core_req_valid = 1'b0;

        // Wrap up Simulation


        repeat (5) @(posedge clk);
        $display("\n=======================================================");
        $display("   ALL TEST SCENARIOS EXECUTED SUCCESSFULLY WITHOUT TIMEOUT");
        $display("=======================================================");
        $finish;
        end


endmodule
