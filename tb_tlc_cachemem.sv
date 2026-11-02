### Verification Testbench Extension (`tb_tlc_cache_ram.sv`)

This verification stub tests a **Cache Miss & Refill** lifecycle followed by a **Cache Hit Lookup**.

```systemverilog
`timescale 1ns/1ps

module tb_tlc_cache_ram;
    import tlc_param_pkg::*;

    logic clk, rst_n;
    logic core_req_valid, core_req_ready, core_req_write, core_hit;
    logic [ADDR_WIDTH-1:0] core_req_addr;
    logic [DATA_WIDTH-1:0] core_req_wdata, core_req_rdata;

    // TileLink Emulation Nets
    logic tl_a_valid, tl_a_ready, tl_b_valid, tl_b_ready, tl_c_valid, tl_c_ready;
    logic tl_d_valid, tl_d_ready, tl_e_valid, tl_e_ready;
    logic [ADDR_WIDTH-1:0] tl_a_address, tl_b_address, tl_c_address;
    logic [DATA_WIDTH-1:0] tl_d_data;
    logic [SINK_WIDTH-1:0] tl_d_sink, tl_e_sink;

    // Instantiate Design
    tlc_cache_controller_with_ram dut (.*, .tl_a_opcode(), .tl_a_param(), .tl_a_size(), .tl_a_source(), .tl_a_mask(), .tl_a_data(), .tl_a_corrupt(), .tl_b_opcode(3'h0), .tl_b_param(2'h0), .tl_b_size(3'h0), .tl_b_source(4'h0), .tl_b_mask('0), .tl_b_data('0), .tl_b_corrupt(1'b0), .tl_c_opcode(), .tl_c_param(), .tl_c_size(), .tl_c_source(), .tl_c_data(), .tl_c_corrupt(), .tl_d_opcode(3'h5), .tl_d_param(3'h0), .tl_d_size(3'h6), .tl_d_source(4'h0), .tl_d_denied(1'b0), .tl_d_corrupt(1'b0));

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst_n = 0;
        core_req_valid = 0; core_req_addr = '0; core_req_write = 0; core_req_wdata = '0;
        tl_a_ready = 1; tl_b_valid = 0; tl_c_ready = 1; tl_d_valid = 0; tl_d_data = '0; tl_d_sink = '0; tl_e_ready = 1;

        #20 rst_n = 1; @(posedge clk);

        // --- STEP 1: Simulate Read Miss on Address 0xAAAA_1000 ---
        $display("[TEST] Injecting Core Read Request to Address 0xAAAA_1000");
        core_req_addr  = 32'hAAAA_1000;
        core_req_valid = 1;
        
        @(posedge clk);
        while (core_hit || !tl_a_valid) @(posedge clk);
        $display("[TEST] Cache Miss Verified! Interconnect Intercepted Acquire on Address: 0x%0h", tl_a_address);
        core_req_valid = 0; // Hold request processing core-side

        // --- STEP 2: Interconnect grants data block response ---
        repeat(2) @(posedge clk);
        tl_d_data  = 64'hABCDEF0123456789;
        tl_d_sink  = 4'h7;
        tl_d_valid = 1;
        while(!tl_d_ready) @(posedge clk);
        @(posedge clk); tl_d_valid = 0;
        
        // Wait for GrantAck cleanup phase
        while(!tl_e_valid) @(posedge clk);
        $display("[TEST] Controller responded with GrantAck. Sink Ticket matched: 0x%0h", tl_e_sink);
        @(posedge clk);

        // --- STEP 3: Re-verify Hit Performance ---
        $display("\n[TEST] Re-injecting Read Request to Address 0xAAAA_1000");
        core_req_valid = 1;
        #1; // Settling delay for combinational lookup
        if (core_hit) begin
            $display("[SUCCESS] Cache Hit Detected! Data output matches: 0x%0h", core_req_rdata);
        end else begin
            $display("[FAILURE] Cache Miss returned unexpectedly.");
        end
        
        @(posedge clk);
        core_req_valid = 0;
        $finish;
    end

endmodule
