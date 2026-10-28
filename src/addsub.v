`default_nettype none
module addsub(
    input wire [15:0] opa,
    input wire [15:0] opb,
    input wire addsub_bar,
    output wire [15:0] result
);

    assign result = addsub_bar ? (opa + opb) : (opa - opb);

endmodule
