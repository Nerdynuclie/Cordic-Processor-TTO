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
    reg [31:0] X;
    reg [31:0] Y;
    reg [15:0] Z;
    
    // QUADRANT REGISTER
    reg [1:0] QUAD;
    
    // COUNT REGISTER
    reg [3:0] ITR_CNT;
    
    // ANG_MUL REGISTER
    reg AM;
    
    // LUT REGISTER
    reg [15:0] ARCTAN;
    
    // Look Up Table For ARCTAN values based on the iteration
    always @(*) begin
        case (ITR_CNT)              // DEGREE
            0:ARCTAN = 16'h3244;    // 45
            1:ARCTAN = 16'h1DBB;    // 26.565
            2:ARCTAN = 16'h0FB9;    // 14.036
            3:ARCTAN = 16'h07F6;    // 7.125
            4:ARCTAN = 16'h03FF;    // 3.576
            5:ARCTAN = 16'h0200;    // 1.789
            6:ARCTAN = 16'h0100;    // 0.895
            7:ARCTAN = 16'h0080;    // 0.447
            8:ARCTAN = 16'h0040;    // 0.223
            9:ARCTAN = 16'h0020;    // 0.111
            10:ARCTAN =16'h0010;    // 0.055
            11:ARCTAN =16'h0008;    // 0.027
            12:ARCTAN =16'h0004;    // 0.013
            13:ARCTAN =16'h0002;    // 0.006
            14:ARCTAN =16'h0001;    // 0.003
            15:ARCTAN =16'h0001;    // 0.001
            default: ARCTAN = 16'h0000;
        endcase
    end
    
    // COUNTER LOGIC
    always @(posedge CLK or negedge RSTn) begin
        if(!RSTn) begin
            ITR_CNT <= 0;
        end
        else begin
            if((PS != NS) || (PS == IDLE)) begin
                ITR_CNT <= 0;
            end
            else begin
                ITR_CNT <= ITR_CNT + 1;
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
                NS = (ITR_CNT == 3) ? CORDIC_OPERATION : LOAD_INPUT;
            end
            CORDIC_OPERATION : begin
                NS = (ITR_CNT == 15) ? TRANS_DONE : CORDIC_OPERATION;
            end
            TRANS_DONE : begin
                NS = (ITR_CNT == 3) ? IDLE : TRANS_DONE;
            end
            default : NS = IDLE;
        endcase
    end
    
    // OUTPUT LOGIC
    always @(posedge CLK or negedge RSTn) begin
        if(!RSTn) begin
            X <= 0;
            Y <= 0;
            Z <= 0;
            
            QUAD <= 0;
            
            BUSY <= 0;
            DONE <= 0;
            ERROR <= 0;
            
            DATA_OUT <= 0;
            
            AM <= 0;
        end
        else begin
            case(PS)
                IDLE : begin
                    if(START) begin
                        BUSY <= 1;
                        AM <= ANG_MUL;
                    end
                    DONE <= 0;
                    X <= 0;
                    Y <= 0;
                    Z <= 0;
                    DATA_OUT <= 0;
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
                                if(QUAD[0]) Z <= 16'h4000 - {2'd0, Z[13:0]};
                                else Z <= {2'd0, Z[13:0]};
                                X <= 32'h00002C1B; // Constant starting point for X vector where X = 0.69
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
                                X[15:8] <= DATA_IN;
                            end
                            2 : begin
                                Z[7:0] <= DATA_IN;
                                X <= X << 14;
                            end
                            3 : begin
                                Z[15:8] <= DATA_IN;
                            end
                            default : begin
                            
                            end
                        endcase
                    end
                end
                CORDIC_OPERATION : begin
                    if(AM) begin
                        if(ITR_CNT == 15) begin
                            if(QUAD[1]) Y[15] <= 1;
                            if(QUAD[1] ^ QUAD[0]) X[15] <= 1;
                        end
                        else begin
                            if(Z[15]) begin // DIRECTION : -1
                                X <= X + (Y >>> ITR_CNT);
                                Y <= Y - (X >>> ITR_CNT);
                                Z <= Z + ARCTAN;
                            end
                            else begin // DIRECTION : 1
                                X <= X - (Y >>> ITR_CNT);
                                Y <= Y + (X >>> ITR_CNT);
                                Z <= Z - ARCTAN;
                            end
                        end
                    end
                    else begin
                        if(ITR_CNT == 15) begin
                            Y <= (Z != 0) ? Z[15] ? (Y - (X >>> 14)) : (Y + (X >>> 14)) : Y;
                        end
                        else begin
                            Y <= Z[15] ? (Y - (X >>> ITR_CNT)) : (Y + (X >>> ITR_CNT));
                            Z <= Z[15] ? (Z + (16'h4000 >>> ITR_CNT )) : (Z - (16'h4000 >>> ITR_CNT));
                        end
                    end
                end
                TRANS_DONE : begin
                    DONE <= 1;
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
                            DATA_OUT <= AM ? Y[7:0] : Y[23:16];
                        end
                        3 : begin
                            DATA_OUT <= AM ? Y[15:8] : Y[31:24];
                        end
                        default : begin
                            DATA_OUT <= 0;
                        end
                    endcase             
                end
                default : begin
                
                end
            endcase
        end
    end
endmodule
 
