// full
// `include "fir-dev/bram/bram11.v"
`include "FIR_Logic.v"
`timescale 1ns / 100ps
module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11,
    parameter IDLE        =  0,
    parameter WAIT        =  0,
    parameter TRAN          =  1,
    parameter Received_Address = 1 ,
    parameter WORK        =  2
)
(
    // write chennel / addr write chennel
    output  reg                     awready,
    output  reg                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    // R / AR
    output  reg                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  reg                     rvalid,
    output  reg [(pDATA_WIDTH-1):0] rdata,    

    // ss : stream slave  /  sm : stream master
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  reg                     ss_tready, 

    input   wire                     sm_tready, 
    output  reg                     sm_tvalid, 
    output  reg [(pDATA_WIDTH-1):0] sm_tdata, 
    output  reg                     sm_tlast, 
    
    // bram for tap RAM
    output  reg [3:0]               tap_WE,
    output  reg                     tap_EN,
    output  reg [(pDATA_WIDTH-1):0] tap_Di,
    output  reg [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  reg [3:0]               data_WE,
    output  reg                     data_EN,
    output  reg [(pDATA_WIDTH-1):0] data_Di,
    output  reg [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
//begin
    // parameters //
    reg     [2:0]   FIR_STATE ; // IDEL / PP / WORK
    integer next_state_FIR ;
    
    reg ap_start , ap_idle , ap_done;
    reg [1:0] addr_reg_R;
    reg [3:0] tap_count , data_count ;
    reg AWW_STATE ;
    integer next_state_AWW ;
    reg ARR_STATE ;
    integer next_state_ARR ;
    reg [1:0] addr_reg_W;
    reg [31:0] data_length ;
    reg [1:0] WoR_tap ; // 10 : Write | 01 : Read | 00 : IDLE
    // parameters //

    // initial ap signals //
    initial begin
        ap_done = 0;
        ap_start = 0;
    end
    // initial ap signals //

    // ap_idle //
    initial begin
        ap_idle = 1 ;
    end
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            ap_idle <= 1'b1 ;
        end else begin
            if (ap_start) begin
                ap_idle <= 1'b0 ;
            end else if (ap_done) begin
                ap_idle <= 1'b1 ;
            end else begin
                ap_idle <= ap_idle ;
            end
        end
    end
    // ap_idle //

    // RAM pointer //
    // relocalization TFU
    // reg [3:0] tap_count , data_count ;
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n)begin
            tap_count <= 0 ;
            data_count <= 0 ;
        end else begin
            if (tap_EN) begin
                if (tap_count==4'b1010) begin
                    tap_count <= 4'b0000;
                end else begin
                    tap_count <= tap_count + 1'b1 ;
                end
            end
            

            if (data_EN) begin
                if (tap_count == 4'd10) begin
                    data_count <= data_count ; 
                    data_EN <= 1'b1 ;         // Latch ? 
                end else if (data_count == 4'b1010) begin
                    data_count <= 4'b0000;
                    data_EN <= 1'b0 ; 
                end else begin
                    data_count <= data_count + 1'b1 ;
                    data_EN <= 1'b0 ; 
                end
            end
        end
    end

    always @(*) begin
        tap_A = tap_count << 2 ;
        data_A = data_count << 2 ;
    end
    // RAM pointer //
    

    // FIR_FSM //
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            FIR_STATE <= IDLE ;
        end else begin
            FIR_STATE <= next_state_FIR ;
        end
    end

    always @(*) begin
        case (FIR_STATE)
            IDLE: begin
                next_state_FIR = (ap_start)? (WORK):(IDLE);
            end 
            WORK : begin
                next_state_FIR = (ap_done)? (IDLE):(WORK);
            end
            default: begin 
                next_state_FIR = IDLE ;
                // $display("default nextstate");
            end
        endcase
    end
    // FIR_FSM //

    // axi lite AW / W FSM //
    // reg AWW_STATE ;
    // integer next_state_AWW ;
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            AWW_STATE <= WAIT ;
        end else begin
            AWW_STATE <= next_state_AWW ;
        end
    end

    always @(*) begin
        if (FIR_STATE==IDLE) begin
            case (AWW_STATE)
                WAIT : begin
                    next_state_AWW = (awvalid) ? (Received_Address) : (WAIT);
                    awready = 1'b1 ;
                    wready  = 1'b0 ;
                end
                Received_Address : begin
                    next_state_AWW = (wvalid) ? (WAIT) : (Received_Address);
                    awready = 1'b0 ;
                    wready  = 1'b1 ;
                end  
                default: begin
                    next_state_AWW = WAIT ;
                    awready = 1'b1 ;
                    wready  = 1'b0 ;
                end
            endcase
        end else begin
            next_state_AWW = WAIT ;
        end
    end
    // axi lite AW / W FSM //

    // axi lite AR / R FSM //
    // reg ARR_STATE ;
    // integer next_state_ARR ;
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            ARR_STATE <= WAIT ;
        end else begin
            ARR_STATE <= next_state_ARR ;
        end
    end

    always @(*) begin
        case (ARR_STATE)
            WAIT :  begin
                next_state_ARR = (arvalid) ? (TRAN) : (WAIT) ;
                arready = 1'b1;
                rvalid = 1'b0;
            end
            TRAN :  begin
                next_state_ARR = (rready) ? (WAIT) : (TRAN) ;
                arready = 1'b0;
                rvalid = 1'b1;
                case (addr_reg_R)
                    2'd0 : rdata = {{29{1'b0}},ap_idle,ap_done,ap_start};
                    2'd1 : rdata = data_length ;
                    2'd2 : rdata = tap_Do ;
                    2'd3 : rdata = {{29{1'b0}},ap_idle,ap_done,ap_start}; // dont care
                    default: rdata = {{29{1'b0}},ap_idle,ap_done,ap_start};
                endcase
            end
            default: begin
                next_state_ARR = WAIT ;
                arready = 1'b1;
                rvalid = 1'b0;
            end
        endcase
    end

    // axi lite AR / R FSM //

    // address decoder (W)//
    // reg [1:0] addr_reg_W;
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n ) begin
            addr_reg_W <= 2'd3; // fail
        end else begin
            if (awvalid & awready) begin
                if (awaddr == 12'h00) begin // ap_start
                    addr_reg_W <= 2'd0 ;
                end
                else if (awaddr > 12'h0F && awaddr < 12'h15) begin
                    addr_reg_W <= 2'd1;
                end 
                else if (awaddr > 12'h1F && awaddr < 12'h100) begin
                    addr_reg_W <= 2'd2;
                end else begin
                    addr_reg_W <= 2'd3;
                end
            end
        end
    end
    // address decoder (W)//

    // address decoder (R)//
    // reg [1:0] addr_reg_R; // move to the top of this code .
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n ) begin
            addr_reg_R <= 2'd3; // fail
        end else begin
            if (arvalid & arready) begin
                if (awaddr == 12'h00) begin
                    addr_reg_R <= 2'd0 ;
                end
                else if (awaddr > 12'h0F && awaddr < 12'h15) begin
                    addr_reg_R <= 2'd1;
                end 
                else if (awaddr > 12'h1F && awaddr < 12'h100) begin
                    addr_reg_R <= 2'd2;
                end else begin
                    addr_reg_R <= 2'd3;
                end
            end
        end
    end
    // address decoder (R)//

    // store data (W)//
    // data_length //
    // reg [31:0] data_length ;

    always @(posedge axis_clk or negedge axis_rst_n) begin
        if(~axis_rst_n) begin
            data_length <= 32'd0 ;
        end
    end
    // tap ram 
    always @(*) begin
        // AXI-W
        if (FIR_STATE == IDLE) begin
            if (wready && wvalid) begin
                case (addr_reg_W)
                    2'd0 : begin // 0x00 //ap_start
                        if(wdata[0]==1'd1) begin
                            ap_start = 1 ;
                            $display("----- FIR kernel starts -----");
                        end else begin
                            ap_start = 0 ;
                        end
                    end
                    2'd1 : begin // 0x10-14
                        data_length = wdata ;
                    end
                    2'd2 : begin // 0x20-FF
                        tap_Di = wdata ;
                        // WoR_tap = 1'b1 ; // Write mode
                    end
                    // 2'd3 : begin // dont care

                    // end
                    // default: 
                endcase
            end 
        end else begin // FIR_STATE == WORK
            ap_start = (ap_start&ss_tvalid&ss_tready)? (0):(ap_start) ;
        end
    end
    // store data (W)//

    // always @(posedge axis_clk or negedge axis_rst_n) begin
    //     if (~axis_rst_n) begin

    //     end else begin
    //         if (wready && wvalid) begin
    //             case (addr_reg_W)
    //                 2'd0 : begin // 0x00
    //                     if(wdata[0]==1'd1) begin
    //                         ap_start <= 1 ;
    //                     end else begin
    //                         ap_start <= 0 ;
    //                     end
    //                 end
    //                 2'd1 : begin // 0x10-14
    //                     data_length <= wdata ;
    //                 end
    //                 2'd2 : begin // 0x20-FF
    //                     tap_Di <= wdata ;
    //                     tap_WE <= 4'b1111;
    //                     tap_EN <= 1'b1;
    //                     if (tap_count==4'b1010) begin
    //                         tap_count <= 4'b0000;
    //                     end else begin
    //                         tap_count <= tap_count + 1'b1 ;
    //                     end
    //                 end
    //                 // 2'd3 : begin // dont care

    //                 // end
    //                 // default: 
    //             endcase
    //         end    
    //     end
    // end
    // store data //


    // tap_ram //
    // bram11 tap_ram( .CLK(axis_clk),
    //                 .WE(tap_WE),
    //                 .EN(tap_EN),
    //                 .Di(tap_Di),
    //                 .Do(tap_Do),
    //                 .A(tap_A));
    // tap_ram //

    // tap_controller //
    // reg [1:0] WoR_tap ; // 10 : Write | 01 : Read | 00 : IDLE
    always @(*) begin
        if (WoR_tap[1]) begin  // Write
            tap_EN = 1'b1;
            tap_WE = 4'b1111 ;
        end 
        else if (WoR_tap[0]) begin      // Read
            tap_EN = 1'b1;
            tap_WE = 4'd0;
        end else begin
            tap_EN = 1'b0;
            tap_WE = 4'd0;
        end
    end
    // tap_controller //

    // WoR_tap mode controller //
    always @(*) begin
        if (FIR_STATE==IDLE) begin
            if (addr_reg_W == 2'd2 & addr_reg_R == 2'd2) begin
                WoR_tap = (wvalid & wready) ? (2'b10) : ((rvalid & rready) ? (2'b01) : (2'b00));
            end else if (addr_reg_W == 2'd2) begin
                WoR_tap = (wvalid & wready) ? (2'b10) : (2'b00) ;
            end 
            else if (addr_reg_R == 2'd2) begin
                WoR_tap = (rvalid & rready) ? (2'b01) : (2'b00) ;
            end
            else begin
                WoR_tap = 2'b00;
            end
        end else if (FIR_STATE==WORK) begin ///////////////// Be careful
            WoR_tap = 2'b01 ;
        end else begin // dont care
            WoR_tap = 2'b00;
        end
    end
    // WoR_tap mode controller //

    // AXI-Stream //
    reg Resetn_fir ;
    wire Done_fir ;
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin

        end else begin
            // ss_tready
            if (ap_start) begin
                data_WE <= 1'b1 ;
                data_EN <= 1'b1 ;
                data_count <= 4'd10;
                ss_tready <= 1'b1 ;
                data_Di <= ss_tdata ;
                Resetn_fir <= 1'b0 ; 
            end else if ((FIR_STATE==WORK)) begin // steady receive data
                ss_tready <= 1'b1 ;
                data_EN <= 1'b1 ;
                Resetn_fir <= 1'b1 ; 
            end else if (ap_done) begin
                data_EN <= 1'b0 ;
                ss_tready <= 1'b0 ;
                Resetn_fir <= 1'b0 ; 
            end else begin
                ss_tready <= 1'b0 ;
                Resetn_fir <= 1'b0 ; 
                data_EN <= 1'b0 ;
            end
            // I forget what i want to do here.
            // if ((FIR_STATE == WORK)&(ss_tvalid&ss_tready)) begin
                

            // end else begin

            // end
        end
    end
    // FIR kernel
    wire [31:0] Y ;
    reg [31:0] Y_reg ;
    FIR_Logic FIR_kernel(   .X(data_Do),
                            .tap(tap_Do),
                            .CLK(axis_clk),
                            .Y(Y),
                            .Resetn(Resetn_fir),
                            .Done(Done_fir)); 
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            Y_reg <= 32'd0;
        end else begin
            Y_reg <= (Done_fir)?(Y):(Y_reg) ;
        end
    end

    // axi stream sm 
    // output  wire                     sm_tvalid, 
    // output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    // output  wire                     sm_tlast, 
    reg Last ;
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            sm_tdata <= 32'd0 ;
            sm_tlast <= 1'd0 ;
            sm_tvalid <= 1'd0 ;
        end else begin
            if (ss_tlast) begin
                Last <= 1'b1 ;
            end
            if (Done_fir) begin     // sm_tvalid set
                if (Last) begin // last Y 
                    sm_tdata <= Y ;
                    sm_tvalid <= 1'd1 ;
                    sm_tlast <= 1'd1 ;
                end else begin      
                    sm_tdata <= Y ;
                    sm_tvalid <= 1'd1 ;
                end
            end else if (sm_tready) begin    // sm_tvalid reset
                sm_tvalid <= 1'b0 ;
                sm_tlast <= 1'd0 ;
            end 
            // else if () begin            // transfer failed

            // end
            else begin 
                sm_tvalid <= 1'b0 ;
                sm_tlast <= 1'd0 ;
            end
        end
    end

    // FIR kernel
    // AXI-Stream //

    // data_ram //
    // bram11 data_ram( .CLK(axis_clk),
    //                 .WE(data_WE),
    //                 .EN(data_EN),
    //                 .Di(data_Di),
    //                 .Do(data_Do),
    //                 .A(data_A));
    // data_ram //




    // axilite (AR)


    //axilite  (R)


    //axilite  (AW)


    //axilite  (W)


//end
endmodule

