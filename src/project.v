module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    input  wire [1:0] uio_in,   // IOs: Input path
    output wire [2:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // // All output pins must be assigned. If not used, assign to 0.
  // assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  // assign uio_out = 0;
  // assign uio_oe  = 0;
    assign uio_in[5:0] = 6'd0;
    assign uio_out[1:0] = 2'd0;
    assign uio_out[7:6] = 2'd0;
  // // List all unused inputs to prevent warnings
  // wire _unused = &{ena, clk, rst_n, 1'b0};

  // Instantiate the CORDIC module
  CORDIC cordic_inst (
      .CLK(clk),
      .RSTn(rst_n),
      .START(uio_in[7]), // Connect uio_in[7] to START
      .ANG_MUL(uio_in[6]), // Connect uio_in[6] to ANG_MUL
      .DATA_IN(ui_in), // Connect ui_in to DATA_IN
      .BUSY(uio_out[5]), // Connect BUSY to uio_out[5]
      .DONE(uio_out[4]), // Connect DONE to uio_out[4]
      .ERROR(uio_out[3]), // Connect ERROR to uio_out[3]
      .ENABLE(uio_oe),
      .DATA_OUT(uo_out) // Connect DATA_OUT to uo_out
  );
