`timescale 1ns / 1ps

// pwm_axi.sv
// Periferico PWM con interfaz AXI4-Lite. La parte AXI se hizo a partir de
// la plantilla de esclavo que genera Vivado. Aqui estan los registros y la
// saturacion, y se instancia pwm_core.
//
// Registros (offset):
//   0x00 Control/Estado: bit 0 enable (R/W), bits [2:1] freq_sel (R/W),
//                        bit 3 running (RO), [31:4] reservado (lee 0)
//   0x04 Duty/Referencia: bits [15:0] duty_ref en Q1.15 (R/W),
//                        [31:16] reservado (lee 0)
//   0x08 Tiempo muerto:  bits [7:0] dead_time en ciclos de reloj (R/W),
//                        [31:8] reservado (lee 0)
//   0x0C reservado (lee 0, las escrituras no hacen nada)

module pwm_axi #(
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 4,

    parameter int CLK_HZ = 100_000_000,
    parameter int F_SW0  = 100_000,
    parameter int F_SW1  = 80_000,
    parameter int F_SW2  = 125_000,
    parameter bit GATE_ACTIVE_HIGH = 1'b1,

    // limite de |duty_ref| en Q1.15 (0,95)
    parameter logic [15:0] M_MAX = 16'd31129,
    // tiempo muerto despues de reset y minimo permitido, en ciclos
    parameter logic [7:0] DT_RESET = 8'd20,
    parameter logic [7:0] DT_MIN   = 8'd10
) (
    // salidas hacia el puente H y el ADC
    output logic gate_a_h_o,
    output logic gate_a_l_o,
    output logic gate_b_h_o,
    output logic gate_b_l_o,
    output logic pwm_trigger_o,

    // interfaz AXI4-Lite (esclavo)
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

    // los registros son de 32 bits, por eso no se usan los 2 bits bajos
    // de la direccion
    localparam int ADDR_LSB = 2;

    // ---------------------------------------------------------------
    // Registros del periferico
    // ---------------------------------------------------------------
    logic               enable_q;
    logic [1:0]         freq_sel_q;
    logic signed [15:0] duty_ref_q;
    logic [7:0]         dead_time_q;
    logic               running;

    // ---------------------------------------------------------------
    // Canal de escritura (AW, W y B)
    // ---------------------------------------------------------------
    logic                          awready_q, wready_q, bvalid_q;
    logic [C_S_AXI_ADDR_WIDTH-1:0] awaddr_q;
    logic                          aw_en_q;   // 1 cuando se puede aceptar otra escritura

    assign S_AXI_AWREADY = awready_q;
    assign S_AXI_WREADY  = wready_q;
    assign S_AXI_BVALID  = bvalid_q;
    assign S_AXI_BRESP   = 2'b00;   // siempre OKAY

    // AWREADY sube cuando llegan AWVALID y WVALID y no hay otra escritura
    // pendiente
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

    // WREADY igual que AWREADY
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

    // la escritura se hace en el ciclo en que se aceptan AW y W
    logic escribir;
    assign escribir = awready_q && S_AXI_AWVALID && wready_q && S_AXI_WVALID;

    // aplica WSTRB: solo cambian los bytes que tienen su bit en 1
    function automatic logic [31:0] con_strobe(input logic [31:0] viejo,
                                              input logic [31:0] nuevo,
                                              input logic [3:0]  strb);
        logic [31:0] r;
        for (int i = 0; i < 4; i++)
            r[i*8 +: 8] = strb[i] ? nuevo[i*8 +: 8] : viejo[i*8 +: 8];
        return r;
    endfunction

    // satura duty_ref a [-M_MAX, M_MAX]
    function automatic logic signed [15:0] saturar_duty(input logic signed [15:0] d);
        if (d > $signed(M_MAX))
            return $signed(M_MAX);
        else if (d < -$signed(M_MAX))
            return -$signed(M_MAX);
        else
            return d;
    endfunction

    // satura el tiempo muerto para que no baje de DT_MIN
    function automatic logic [7:0] saturar_dt(input logic [7:0] t);
        if (t < DT_MIN)
            return DT_MIN;
        else
            return t;
    endfunction

    // dato de cada registro con WSTRB aplicado
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
                    // running (bit 3) es de solo lectura, no se guarda
                    enable_q   <= dato_ctrl[0];
                    freq_sel_q <= dato_ctrl[2:1];
                end
                2'd1: duty_ref_q  <= saturar_duty(dato_duty[15:0]);
                2'd2: dead_time_q <= saturar_dt(dato_dt[7:0]);
                default: ;  // 0x0C reservado
            endcase
        end
    end

    // BVALID sube despues de escribir y baja cuando llega BREADY
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

    // ---------------------------------------------------------------
    // Canal de lectura (AR y R)
    // ---------------------------------------------------------------
    logic                          arready_q, rvalid_q;
    logic [C_S_AXI_ADDR_WIDTH-1:0] araddr_q;
    logic [31:0]                   rdata_q;

    assign S_AXI_ARREADY = arready_q;
    assign S_AXI_RVALID  = rvalid_q;
    assign S_AXI_RDATA   = rdata_q;
    assign S_AXI_RRESP   = 2'b00;   // siempre OKAY

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

    // el dato que se lee depende de la direccion
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

    // ---------------------------------------------------------------
    // Nucleo del PWM
    // ---------------------------------------------------------------
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
