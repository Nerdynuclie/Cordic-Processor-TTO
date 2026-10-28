`default_nettype none
module CORDIC(
    // CLOCK AND ACTIVE LOW RESET
    input wire CLK,
    input wire RSTn,

    // CONTROL INPUTS
    input wire START, // STARTS THE TRANSACTION
    input wire ANG_MUL, // 1 : ANGLE CALCULATION, 0 : MULTIPLICATION

    // DATA INPUT : ANGLE OR {MULTIPLIER/MULTIPLICAND}
    input wire [7:0] DATA_IN,

    // CONTROL OUTPUTS
    output reg BUSY,
    output reg DONE,
    output reg ERROR,

    //ENABLE OUTPUT
    output wire [7:0] ENABLE,

    //DATA OUTPUT
    output reg [7:0] DATA_OUT
);

    assign ENABLE = 8'b00111000; // START ANG_MUL BUSY DONE ERROR RESERVED

    // STATE REGISTER DECLARATION
    reg [1:0] PS, NS;

    // STATE NAME DECLARATION
    localparam IDLE = 2'd0;
    localparam LOAD_INPUT = 2'd1;
    localparam CORDIC_OPERATION = 2'd2;
    localparam TRANS_DONE = 2'd3;

    // CORDIC ALGORITHM REGISTERS
    reg signed [15:0] X;
    reg signed [15:0] Y;
    reg signed [15:0] Z;

    // QUADRANT REGISTER
    reg [1:0] QUAD;

    // COUNT REGISTER
    reg [3:0] ITR_CNT;

    // ANG_MUL REGISTER
    reg AM;

    // LUT REGISTER
    reg [13:0] ARCTAN;

    // CONTROL SIGNAL LOGIC
    always @(*) begin
        ERROR = START && (PS != IDLE);
        BUSY = (((PS == IDLE) && START) || (PS == LOAD_INPUT) || (PS == CORDIC_OPERATION));
        DONE = (PS == TRANS_DONE);
    end

    // Look Up Table For ARCTAN values based on the iteration
    always @(*) begin
        case (ITR_CNT)
            0:  ARCTAN = 14'h2000; // 45.000000 degrees
            1:  ARCTAN = 14'h12E4; // 26.565051 degrees
            2:  ARCTAN = 14'h09FB; // 14.036243 degrees
            3:  ARCTAN = 14'h0511; //  7.125016 degrees
            4:  ARCTAN = 14'h028B; //  3.576335 degrees
            5:  ARCTAN = 14'h0146; //  1.789911 degrees
            6:  ARCTAN = 14'h00A3; //  0.895174 degrees
            7:  ARCTAN = 14'h0051; //  0.447614 degrees
            8:  ARCTAN = 14'h0029; //  0.223811 degrees
            9:  ARCTAN = 14'h0014; //  0.111906 degrees
            10: ARCTAN = 14'h000A; //  0.055953 degrees
            11: ARCTAN = 14'h0005; //  0.027976 degrees
            12: ARCTAN = 14'h0003; //  0.013988 degrees
            13: ARCTAN = 14'h0001; //  0.006994 degrees
            14: ARCTAN = 14'h0001; //  0.003497 degrees
            15: ARCTAN = 14'h0000; //  0.001749 degrees
            default: ARCTAN = 14'h0000;
        endcase
    end

    wire LAST = (ITR_CNT == 4'd15);

    wire signed [15:0] X_SRA = X >>> ITR_CNT;
    wire signed [15:0] Y_SRA = Y >>> ITR_CNT;
    wire [15:0] X_SLL = X << (4'd14 - ITR_CNT);

    wire X_NEG = AM && LAST;
    wire [15:0] XA = X_NEG ? 16'd0 : X;
    wire [15:0] XB = X_NEG ? X : Y_SRA;
    wire XADD = X_NEG ? 1'b0 : Z[15];
    wire [15:0] X_RES;
    addsub U_X (.opa(XA), .opb(XB), .addsub_bar(XADD), .result(X_RES));

    wire Y_NEG = AM && LAST;
    wire [15:0] YA = Y_NEG ? 16'd0 : Y;
    wire [15:0] YB = AM ? (LAST ? Y : X_SRA) : (LAST ? X : X_SLL);
    wire YADD = Y_NEG ? 1'b0 : ~Z[15];
    wire [15:0] Y_RES;
    addsub U_Y (.opa(YA), .opb(YB), .addsub_bar(YADD), .result(Y_RES));

    wire LD_FIX = (PS == LOAD_INPUT) && (ITR_CNT == 4'd3) && AM && QUAD[0];
    wire [15:0] ZA = LD_FIX ? 16'h4000 : Z;
    wire [15:0] ZB = LD_FIX ? {2'd0, Z[13:0]} : AM ? {2'd0, ARCTAN} : (16'h4000 >> ITR_CNT);
    wire [15:0] Z_RES;
    addsub U_Z (.opa(ZA), .opb(ZB), .addsub_bar(~LD_FIX & Z[15]), .result(Z_RES));

    // COUNTER LOGIC
    always @(posedge CLK or negedge RSTn) begin
        if(!RSTn) begin
            ITR_CNT <= 4'd0;
        end
        else begin
            if((PS != NS) || (PS == IDLE)) begin
                ITR_CNT <= 4'd0;
            end
            else begin
                ITR_CNT <= ITR_CNT + 4'd1;
            end
        end
    end

    // PRESENT STATE LOGIC
    always @(posedge CLK or negedge RSTn) begin
        if(!RSTn) begin
            PS <= IDLE;
        end
        else begin
            PS <= NS;
        end
    end

    // NEXT STATE LOGIC
    always @(*) begin
        case(PS)
            IDLE : begin
                NS = START ? LOAD_INPUT : IDLE;
            end
            LOAD_INPUT : begin
                NS = (ITR_CNT == 4'd3) ? CORDIC_OPERATION : LOAD_INPUT;
            end
            CORDIC_OPERATION : begin
                NS = (ITR_CNT == 4'd15) ? TRANS_DONE : CORDIC_OPERATION;
            end
            TRANS_DONE : begin
                NS = AM ? (ITR_CNT == 4'd4) ? IDLE : TRANS_DONE : (ITR_CNT == 4'd2) ? IDLE : TRANS_DONE ;
            end
            default : NS = IDLE;
        endcase
    end

    // OUTPUT LOGIC
    always @(posedge CLK or negedge RSTn) begin
        if(!RSTn) begin
            X <= 16'd0;
            Y <= 16'd0;
            Z <= 16'd0;

            QUAD <= 2'd0;

            DATA_OUT <= 8'd0;

            AM <= 1'd0;
        end
        else begin
            case(PS)
                IDLE : begin
                    if(START) begin
                        AM <= ANG_MUL;
                    end
                    Y <= 16'd0;
                    DATA_OUT <= 8'd0;
                end
                LOAD_INPUT : begin
                    if(AM) begin
                        case(ITR_CNT)
                            0 : begin
                                Z[7:0] <= DATA_IN;
                            end
                            1 : begin
                                Z[15:8] <= DATA_IN;
                            end
                            2 : begin
                                QUAD <= Z[15:14];
                            end
                            3 : begin
                                Z <= QUAD[0] ? Z_RES : {2'd0, Z[13:0]};
                                X <= 16'sd9949;  // 0.6072529 in Q14
                                Y <= 16'sd0;
                            end
                            default : begin

                            end
                        endcase
                    end
                    else begin
                        case(ITR_CNT)
                            0 : begin
                                X[7:0] <= DATA_IN;
                            end
                            1 : begin
                                Z[7:0] <= DATA_IN;
                            end
                            2 : begin
                                X <= {{8{X[7]}},X[7:0]};
                            end
                            3 : begin
                                Z <= {{8{Z[7]}},Z[7:0]};
                            end
                            default : begin

                            end
                        endcase
                    end
                end
                CORDIC_OPERATION : begin
                    if(AM) begin
                        if(LAST) begin
                            if(QUAD[1]) Y <= Y_RES;
                            if(QUAD[1] ^ QUAD[0]) X <= X_RES;
                        end
                        else begin
                            X <= X_RES;
                            Y <= Y_RES;
                            Z <= Z_RES;
                        end
                    end
                    else begin
                        if(LAST) begin
                            Y <= |Z ? Y_RES : Y;
                        end
                        else begin
                            Y <= Y_RES;
                            Z <= Z_RES;
                        end
                    end
                end
                TRANS_DONE : begin
                    case(ITR_CNT)
                        // SENDING COS VALUE IF AM = 1
                        0 : begin
                            DATA_OUT <= AM ? X[7:0] : Y[7:0];
                        end
                        1 : begin
                            DATA_OUT <= AM ? X[15:8] : Y[15:8];
                        end
                        // SENDING SIN VALUE IF AM = 1
                        2 : begin
                            DATA_OUT <= AM ? Y[7:0] : 8'd0;
                        end
                        3 : begin
                            DATA_OUT <= AM ? Y[15:8] : 8'd0;
                        end
                        default : begin
                            DATA_OUT <= 8'd0;
                        end
                    endcase
                end
                default : begin

                end
            endcase
        end
    end
endmodule
