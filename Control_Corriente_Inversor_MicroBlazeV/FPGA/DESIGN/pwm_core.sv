`timescale 1ns / 1ps

module pwm_core #(
    parameter int CLK_HZ = 100_000_000,
    parameter int F_SW0  = 100_000,
    parameter int F_SW1  = 80_000,
    parameter int F_SW2  = 125_000,
    parameter bit GATE_ACTIVE_HIGH = 1'b1
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        enable_i,
    input  logic [1:0]  freq_sel_i,
    input  logic signed [15:0] duty_ref_i,
    input  logic [7:0]  dead_time_i,

    output logic        running_o,
    output logic        gate_a_h_o,
    output logic        gate_a_l_o,
    output logic        gate_b_h_o,
    output logic        gate_b_l_o,
    output logic        pwm_trigger_o
);

    localparam int P0 = CLK_HZ / (2 * F_SW0);
    localparam int P1 = CLK_HZ / (2 * F_SW1);
    localparam int P2 = CLK_HZ / (2 * F_SW2);

    logic [15:0]        p_q;
    logic [15:0]        umbral_a;
    logic [15:0]        umbral_b;
    logic [7:0]         dt_q;

    logic [15:0] p_nuevo;
    always_comb begin
        case (freq_sel_i)
            2'b01:   p_nuevo = 16'(P1);
            2'b10:   p_nuevo = 16'(P2);
            default: p_nuevo = 16'(P0);
        endcase
    end

    logic [16:0] m_mas_uno_a_q, m_mas_uno_b_q;
    logic [15:0] p_etapa1_q;
    logic [15:0] umbral_a_sig_q, umbral_b_sig_q;
    logic [15:0] p_etapa2_q;
    logic [32:0] prod_a, prod_b;

    assign prod_a = 33'(p_etapa1_q) * 33'(m_mas_uno_a_q);
    assign prod_b = 33'(p_etapa1_q) * 33'(m_mas_uno_b_q);

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            m_mas_uno_a_q  <= 17'd32768;
            m_mas_uno_b_q  <= 17'd32768;
            p_etapa1_q     <= 16'(P0);
            umbral_a_sig_q <= 16'(P0 / 2);
            umbral_b_sig_q <= 16'(P0 / 2);
            p_etapa2_q     <= 16'(P0);
        end else begin
            m_mas_uno_a_q  <= 17'($signed({duty_ref_i[15], duty_ref_i}) + 17'sd32768);
            m_mas_uno_b_q  <= 17'(17'sd32768 - $signed({duty_ref_i[15], duty_ref_i}));
            p_etapa1_q     <= p_nuevo;
            umbral_a_sig_q <= 16'(prod_a >> 16);
            umbral_b_sig_q <= 16'(prod_b >> 16);
            p_etapa2_q     <= p_etapa1_q;
        end
    end

    logic [15:0] cnt_q;
    logic        sube_q;
    logic        run_q;

    logic valle;
    assign valle = run_q && (cnt_q == 16'd0);

    always_ff @(posedge clk_i) begin
        if (!rst_ni || !enable_i) begin
            cnt_q  <= 16'd0;
            sube_q <= 1'b1;
            run_q  <= 1'b0;
            p_q      <= 16'(P0);
            umbral_a <= 16'(P0 / 2);
            umbral_b <= 16'(P0 / 2);
            dt_q     <= 8'd0;
        end else if (!run_q || cnt_q == 16'd0) begin
            run_q    <= 1'b1;
            p_q      <= p_etapa2_q;
            umbral_a <= umbral_a_sig_q;
            umbral_b <= umbral_b_sig_q;
            dt_q     <= dead_time_i;
            cnt_q  <= 16'd1;
            sube_q <= 1'b1;
        end else if (sube_q) begin
            if (cnt_q == p_q) begin
                sube_q <= 1'b0;
                cnt_q  <= cnt_q - 16'd1;
            end else begin
                cnt_q  <= cnt_q + 16'd1;
            end
        end else begin
            cnt_q <= cnt_q - 16'd1;
        end
    end

    assign running_o = run_q;

    logic ref_a, ref_b;
    assign ref_a = (cnt_q < umbral_a);
    assign ref_b = (cnt_q < umbral_b);

    logic       ref_a_q, ref_b_q;
    logic [7:0] dt_cnt_a_q, dt_cnt_b_q;
    logic       listo_a_q, listo_b_q;
    logic       listo_a, listo_b;

    assign listo_a = listo_a_q || (dt_cnt_a_q >= dt_q);
    assign listo_b = listo_b_q || (dt_cnt_b_q >= dt_q);

    always_ff @(posedge clk_i) begin
        if (!rst_ni || !enable_i || !run_q) begin
            ref_a_q    <= 1'b0;
            ref_b_q    <= 1'b0;
            dt_cnt_a_q <= 8'd0;
            dt_cnt_b_q <= 8'd0;
            listo_a_q  <= 1'b0;
            listo_b_q  <= 1'b0;
        end else begin
            ref_a_q <= ref_a;
            ref_b_q <= ref_b;

            if (ref_a != ref_a_q) begin
                dt_cnt_a_q <= 8'd0;
                listo_a_q  <= 1'b0;
            end else begin
                if (dt_cnt_a_q != 8'hFF)
                    dt_cnt_a_q <= dt_cnt_a_q + 8'd1;
                listo_a_q <= listo_a;
            end

            if (ref_b != ref_b_q) begin
                dt_cnt_b_q <= 8'd0;
                listo_b_q  <= 1'b0;
            end else begin
                if (dt_cnt_b_q != 8'hFF)
                    dt_cnt_b_q <= dt_cnt_b_q + 8'd1;
                listo_b_q <= listo_b;
            end
        end
    end

    logic a_h, a_l, b_h, b_l, trig;

    logic valle_q;
    always_ff @(posedge clk_i) begin
        if (!rst_ni || !enable_i)
            valle_q <= 1'b0;
        else
            valle_q <= valle;
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni || !enable_i || !run_q) begin
            a_h  <= 1'b0;
            a_l  <= 1'b0;
            b_h  <= 1'b0;
            b_l  <= 1'b0;
            trig <= 1'b0;
        end else begin
            a_h  <=  ref_a_q && listo_a;
            a_l  <= !ref_a_q && listo_a;
            b_h  <=  ref_b_q && listo_b;
            b_l  <= !ref_b_q && listo_b;
            trig <= valle_q;
        end
    end

    assign gate_a_h_o    = GATE_ACTIVE_HIGH ? a_h : !a_h;
    assign gate_a_l_o    = GATE_ACTIVE_HIGH ? a_l : !a_l;
    assign gate_b_h_o    = GATE_ACTIVE_HIGH ? b_h : !b_h;
    assign gate_b_l_o    = GATE_ACTIVE_HIGH ? b_l : !b_l;
    assign pwm_trigger_o = trig;

endmodule
