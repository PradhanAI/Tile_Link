// -----------------------------------------------------------------------------
// Package: tlc_param_pkg
// Description: Expanded TileLink TL-C Configurations with Structural Cache Specs
// -----------------------------------------------------------------------------
package tlc_param_pkg;
    // TileLink Protocol Widths
    localparam int unsigned ADDR_WIDTH   = 32;
    localparam int unsigned DATA_WIDTH   = 64;
    localparam int unsigned SIZE_WIDTH   = 3;
    localparam int unsigned SOURCE_WIDTH = 4;
    localparam int unsigned SINK_WIDTH   = 4;
    localparam int unsigned MASK_WIDTH   = DATA_WIDTH / 8;

    // Cache Geometry Parameters (e.g., 4KB Direct-Mapped, 64-Byte Line)
    localparam int unsigned LINE_SIZE    = 64; // 64 Bytes per line
    localparam int unsigned NUM_LINES    = 64; // 64 Sets/Lines
    
    // Address Bit Slicing
    localparam int unsigned OFFSET_WIDTH = 6;  // log2(64)
    localparam int unsigned INDEX_WIDTH  = 6;  // log2(64)
    localparam int unsigned TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH; // 20 bits

    // Cache Line MSI States
    typedef enum logic [1:0] {
        STATE_M = 2'b11, // Modified (Read/Write, Dirty)
        STATE_S = 2'b01, // Shared (Read Only, Clean)
        STATE_I = 2'b00  // Invalid
    } msi_state_e;
endpackage

