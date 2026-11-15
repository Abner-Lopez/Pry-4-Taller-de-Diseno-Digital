`timescale 1ns / 1ps

module pwm_axi #(
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 4,

    parameter int CLK_HZ = 100_000_000,
    parameter int F_SW0  = 100_000,
    parameter int F_SW1  = 80_000,
    parameter int F_SW2  = 125_000,
    parameter bit GATE_ACTIVE_HIGH = 1'b1,

    parameter logic [15:0] M_MAX = 16'd31129,
    parameter logic [7:0] DT_RESET = 8'd20,
    parameter logic [7:0] DT_MIN   = 8'd10
) (
    output logic gate_a_h_o,
    output logic gate_a_l_o,
    output logic gate_b_h_o,
    output logic gate_b_l_o,
    output logic pwm_trigger_o,

    input  logic                              S_AXI_ACLK,
    input  logic                              S_AXI_ARESETN,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  logic [2:0]                        S_AXI_AWPROT,
    input  logic                              S_AXI_AWVALID,
    output logic                              S_AXI_AWREADY,
    input  logic [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  logic                              S_AXI_WVALID,
    output logic                              S_AXI_WREADY,
    output logic [1:0]                        S_AXI_BRESP,
    output logic                              S_AXI_BVALID,
    input  logic                              S_AXI_BREADY,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  logic [2:0]                        S_AXI_ARPROT,
    input  logic                              S_AXI_ARVALID,
    output logic                              S_AXI_ARREADY,
    output logic [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output logic [1:0]                        S_AXI_RRESP,
    output logic                              S_AXI_RVALID,
    input  logic                              S_AXI_RREADY
);

    localparam int ADDR_LSB = 2;

    logic               enable_q;
    logic [1:0]         freq_sel_q;
    logic signed [15:0] duty_ref_q;
    logic [7:0]         dead_time_q;
    logic               running;

    logic                          awready_q, wready_q, bvalid_q;
    logic [C_S_AXI_ADDR_WIDTH-1:0] awaddr_q;
    logic                          aw_en_q;

    assign S_AXI_AWREADY = awready_q;
    assign S_AXI_WREADY  = wready_q;
    assign S_AXI_BVALID  = bvalid_q;
    assign S_AXI_BRESP   = 2'b00;

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            awready_q <= 1'b0;
            aw_en_q   <= 1'b1;
            awaddr_q  <= '0;
        end else begin
            if (!awready_q && S_AXI_AWVALID && S_AXI_WVALID && aw_en_q) begin
                awready_q <= 1'b1;
                aw_en_q   <= 1'b0;
                awaddr_q  <= S_AXI_AWADDR;
            end else if (S_AXI_BREADY && bvalid_q) begin
                aw_en_q   <= 1'b1;
                awready_q <= 1'b0;
            end else begin
                awready_q <= 1'b0;
            end
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            wready_q <= 1'b0;
        end else begin
            if (!wready_q && S_AXI_WVALID && S_AXI_AWVALID && aw_en_q)
                wready_q <= 1'b1;
            else
                wready_q <= 1'b0;
        end
    end

    logic escribir;
    assign escribir = awready_q && S_AXI_AWVALID && wready_q && S_AXI_WVALID;

    function automatic logic [31:0] con_strobe(input logic [31:0] viejo,
                                              input logic [31:0] nuevo,
                                              input logic [3:0]  strb);
        logic [31:0] r;
        for (int i = 0; i < 4; i++)
            r[i*8 +: 8] = strb[i] ? nuevo[i*8 +: 8] : viejo[i*8 +: 8];
        return r;
    endfunction

    function automatic logic signed [15:0] saturar_duty(input logic signed [15:0] d);
        if (d > $signed(M_MAX))
            return $signed(M_MAX);
        else if (d < -$signed(M_MAX))
            return -$signed(M_MAX);
        else
            return d;
    endfunction

    function automatic logic [7:0] saturar_dt(input logic [7:0] t);
        if (t < DT_MIN)
            return DT_MIN;
        else
            return t;
    endfunction

    logic [31:0] dato_ctrl, dato_duty, dato_dt;
    always_comb begin
        dato_ctrl = con_strobe({29'd0, freq_sel_q, enable_q}, S_AXI_WDATA, S_AXI_WSTRB);
        dato_duty = con_strobe({16'd0, duty_ref_q}, S_AXI_WDATA, S_AXI_WSTRB);
        dato_dt   = con_strobe({24'd0, dead_time_q}, S_AXI_WDATA, S_AXI_WSTRB);
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            enable_q    <= 1'b0;
            freq_sel_q  <= 2'b00;
            duty_ref_q  <= 16'sd0;
            dead_time_q <= DT_RESET;
        end else if (escribir) begin
            case (awaddr_q[C_S_AXI_ADDR_WIDTH-1:ADDR_LSB])
                2'd0: begin
                    enable_q   <= dato_ctrl[0];
                    freq_sel_q <= dato_ctrl[2:1];
                end
                2'd1: duty_ref_q  <= saturar_duty(dato_duty[15:0]);
                2'd2: dead_time_q <= saturar_dt(dato_dt[7:0]);
                default: ;
            endcase
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            bvalid_q <= 1'b0;
        end else begin
            if (escribir && !bvalid_q)
                bvalid_q <= 1'b1;
            else if (S_AXI_BREADY && bvalid_q)
                bvalid_q <= 1'b0;
        end
    end

    logic                          arready_q, rvalid_q;
    logic [C_S_AXI_ADDR_WIDTH-1:0] araddr_q;
    logic [31:0]                   rdata_q;

    assign S_AXI_ARREADY = arready_q;
    assign S_AXI_RVALID  = rvalid_q;
    assign S_AXI_RDATA   = rdata_q;
    assign S_AXI_RRESP   = 2'b00;

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            arready_q <= 1'b0;
            araddr_q  <= '0;
        end else begin
            if (!arready_q && S_AXI_ARVALID && !rvalid_q) begin
                arready_q <= 1'b1;
                araddr_q  <= S_AXI_ARADDR;
            end else begin
                arready_q <= 1'b0;
            end
        end
    end

    logic [31:0] dato_leido;
    always_comb begin
        case (araddr_q[C_S_AXI_ADDR_WIDTH-1:ADDR_LSB])
            2'd0:    dato_leido = {28'd0, running, freq_sel_q, enable_q};
            2'd1:    dato_leido = {16'd0, duty_ref_q};
            2'd2:    dato_leido = {24'd0, dead_time_q};
            default: dato_leido = 32'd0;
        endcase
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            rvalid_q <= 1'b0;
            rdata_q  <= 32'd0;
        end else begin
            if (arready_q && S_AXI_ARVALID && !rvalid_q) begin
                rvalid_q <= 1'b1;
                rdata_q  <= dato_leido;
            end else if (rvalid_q && S_AXI_RREADY) begin
                rvalid_q <= 1'b0;
            end
        end
    end

    pwm_core #(
        .CLK_HZ           (CLK_HZ),
        .F_SW0            (F_SW0),
        .F_SW1            (F_SW1),
        .F_SW2            (F_SW2),
        .GATE_ACTIVE_HIGH (GATE_ACTIVE_HIGH)
    ) u_pwm_core (
        .clk_i         (S_AXI_ACLK),
        .rst_ni        (S_AXI_ARESETN),
        .enable_i      (enable_q),
        .freq_sel_i    (freq_sel_q),
        .duty_ref_i    (duty_ref_q),
        .dead_time_i   (dead_time_q),
        .running_o     (running),
        .gate_a_h_o    (gate_a_h_o),
        .gate_a_l_o    (gate_a_l_o),
        .gate_b_h_o    (gate_b_h_o),
        .gate_b_l_o    (gate_b_l_o),
        .pwm_trigger_o (pwm_trigger_o)
    );

endmodule
