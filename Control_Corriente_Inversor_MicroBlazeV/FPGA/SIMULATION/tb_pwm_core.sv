// tb_pwm_core.sv
// Testbench autoverificable de pwm_core. Prueba el periodo de cada
// freq_sel, el ancho de los pulsos, varios tiempos muertos, los cambios a
// mitad de periodo, el disparo y el apagado. Ademas vigila todo el tiempo
// que no haya solape en ninguna pierna.

`timescale 1ns / 1ps

module tb_pwm_core;

    localparam int CLK_HZ = 100_000_000;
    localparam int P0 = CLK_HZ / (2 * 100_000);
    localparam int P1 = CLK_HZ / (2 * 80_000);
    localparam int P2 = CLK_HZ / (2 * 125_000);

    localparam logic signed [15:0] M_MAX = 16'sd31129;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic        rst_n;
    logic        enable;
    logic [1:0]  freq_sel;
    logic signed [15:0] duty_ref;
    logic [7:0]  dead_time;

    logic running, a_h, a_l, b_h, b_l, trig;

    pwm_core #(.CLK_HZ(CLK_HZ)) dut (
        .clk_i         (clk),
        .rst_ni        (rst_n),
        .enable_i      (enable),
        .freq_sel_i    (freq_sel),
        .duty_ref_i    (duty_ref),
        .dead_time_i   (dead_time),
        .running_o     (running),
        .gate_a_h_o    (a_h),
        .gate_a_l_o    (a_l),
        .gate_b_h_o    (b_h),
        .gate_b_l_o    (b_l),
        .pwm_trigger_o (trig)
    );

    int pruebas = 0;
    int fallas  = 0;

    task automatic revisar(input bit ok, input string msg);
        pruebas++;
        if (ok) begin
            $display("[PASS] %s", msg);
        end else begin
            fallas++;
            $display("[FAIL] %s  (t = %0t)", msg, $time);
        end
    endtask

    int  solape_a = 0, solape_b = 0;
    int  dt_corto = 0;
    int  apagados_a = 0, apagados_b = 0;
    logic a_h_ant = 0, a_l_ant = 0, b_h_ant = 0, b_l_ant = 0;
    logic trig_ant = 0;
    int  trig_ancho_malo = 0;

    always @(negedge clk) begin
        if (a_h && a_l) solape_a++;
        if (b_h && b_l) solape_b++;

        if ((a_h && !a_h_ant) || (a_l && !a_l_ant)) begin
            if (apagados_a < dut.dt_q) begin
                dt_corto++;
                $display("[FAIL] pierna A: tiempo muerto de %0d ciclos, se esperaban %0d (t = %0t)",
                         apagados_a, dut.dt_q, $time);
            end
        end
        if ((b_h && !b_h_ant) || (b_l && !b_l_ant)) begin
            if (apagados_b < dut.dt_q) begin
                dt_corto++;
                $display("[FAIL] pierna B: tiempo muerto de %0d ciclos, se esperaban %0d (t = %0t)",
                         apagados_b, dut.dt_q, $time);
            end
        end
        apagados_a = (!a_h && !a_l) ? apagados_a + 1 : 0;
        apagados_b = (!b_h && !b_l) ? apagados_b + 1 : 0;

        if (trig && trig_ant) trig_ancho_malo++;

        a_h_ant  = a_h;
        a_l_ant  = a_l;
        b_h_ant  = b_h;
        b_l_ant  = b_l;
        trig_ant = trig;
    end

    function automatic int umbral(input int p, input int m);
        return (p * (m + 32768)) >>> 16;
    endfunction

    function automatic int esperado_bajo(input int p, input int m, input int dt);
        return 2 * p - (2 * umbral(p, m) - 1) - dt;
    endfunction

    task automatic esperar_trigger();
        do @(negedge clk); while (!trig);
    endtask

    task automatic medir(output int ciclos, output int on_al, output int on_bl);
        ciclos = 0; on_al = 0; on_bl = 0;
        do begin
            @(negedge clk);
            ciclos++;
            if (a_l) on_al++;
            if (b_l) on_bl++;
        end while (!trig);
    endtask

    task automatic probar_punto(input int p, input int m, input int dt, input string nombre);
        int c, al, bl;
        int esp_al, esp_bl;
        esperar_trigger();
        esperar_trigger();
        medir(c, al, bl);
        esp_al = esperado_bajo(p, m, dt);
        esp_bl = esperado_bajo(p, -m, dt);
        revisar(c == 2 * p, $sformatf("%s: periodo %0d ciclos (esperado %0d)", nombre, c, 2 * p));
        revisar(al == esp_al, $sformatf("%s: pierna A abajo encendida %0d ciclos (esperado %0d)", nombre, al, esp_al));
        revisar(bl == esp_bl, $sformatf("%s: pierna B abajo encendida %0d ciclos (esperado %0d)", nombre, bl, esp_bl));
    endtask

    initial begin
        int c, al, bl, c2, al2, bl2;
        int espera;
        bit todo_apagado;

        rst_n     = 1'b0;
        enable    = 1'b0;
        freq_sel  = 2'b00;
        duty_ref  = 16'sd0;
        dead_time = 8'd20;

        repeat (5) @(negedge clk);
        revisar(!a_h && !a_l && !b_h && !b_l && !trig && !running,
                "en reset las salidas y running estan en 0");
        rst_n = 1'b1;
        repeat (5) @(negedge clk);
        revisar(!a_h && !a_l && !b_h && !b_l && !running,
                "con enable = 0 las salidas siguen en 0");

        enable = 1'b1;
        @(negedge clk);
        @(negedge clk);
        revisar(running, "running sube al habilitar");

        probar_punto(P0, 0, 20, "freq_sel=00 (100 kHz), m=0");
        freq_sel = 2'b01;
        probar_punto(P1, 0, 20, "freq_sel=01 (80 kHz), m=0");
        freq_sel = 2'b10;
        probar_punto(P2, 0, 20, "freq_sel=10 (125 kHz), m=0");
        freq_sel = 2'b11;
        probar_punto(P0, 0, 20, "freq_sel=11 se toma como 00");
        freq_sel = 2'b00;

        duty_ref = 16'sd16384;
        probar_punto(P0, 16384, 20, "m=+0,5");
        duty_ref = -16'sd16384;
        probar_punto(P0, -16384, 20, "m=-0,5");
        duty_ref = M_MAX;
        probar_punto(P0, M_MAX, 20, "m=+M_MAX");
        duty_ref = -M_MAX;
        probar_punto(P0, -M_MAX, 20, "m=-M_MAX");
        freq_sel = 2'b10;
        probar_punto(P2, -M_MAX, 20, "m=-M_MAX a 125 kHz");
        freq_sel = 2'b00;
        duty_ref = 16'sd0;

        dead_time = 8'd10;
        probar_punto(P0, 0, 10, "dead_time=10 ciclos");
        dead_time = 8'd50;
        probar_punto(P0, 0, 50, "dead_time=50 ciclos");
        dead_time = 8'd255;
        probar_punto(P0, 0, 255, "dead_time=255 ciclos (maximo)");
        dead_time = 8'd20;
        probar_punto(P0, 0, 20, "dead_time vuelve a 20");

        esperar_trigger();
        fork
            medir(c, al, bl);
            begin
                repeat (300) @(negedge clk);
                duty_ref = 16'sd16384;
            end
        join
        medir(c2, al2, bl2);
        revisar(al == esperado_bajo(P0, 0, 20),
                $sformatf("cambio de duty a mitad de periodo: el periodo en curso sigue con m=0 (%0d ciclos)", al));
        revisar(al2 == esperado_bajo(P0, 16384, 20),
                $sformatf("cambio de duty a mitad de periodo: el siguiente usa m=0,5 (%0d ciclos)", al2));

        esperar_trigger();
        fork
            medir(c, al, bl);
            begin
                repeat (300) @(negedge clk);
                freq_sel = 2'b01;
            end
        join
        medir(c2, al2, bl2);
        revisar(c == 2 * P0, $sformatf("cambio de freq_sel a mitad de periodo: el periodo en curso dura %0d (esperado %0d)", c, 2 * P0));
        revisar(c2 == 2 * P1, $sformatf("cambio de freq_sel a mitad de periodo: el siguiente dura %0d (esperado %0d)", c2, 2 * P1));
        freq_sel = 2'b00;
        duty_ref = 16'sd0;

        esperar_trigger();
        repeat (237) @(negedge clk);
        enable = 1'b0;
        @(negedge clk);
        revisar(!a_h && !a_l && !b_h && !b_l, "enable 1 -> 0: las 4 compuertas se apagan en el siguiente ciclo");
        revisar(!running, "enable 1 -> 0: running baja");
        todo_apagado = 1'b1;
        repeat (3000) begin
            @(negedge clk);
            if (a_h || a_l || b_h || b_l || trig) todo_apagado = 1'b0;
        end
        revisar(todo_apagado, "con enable = 0 no hay pulsos ni disparos");

        enable = 1'b1;
        probar_punto(P0, 0, 20, "se vuelve a habilitar");

        esperar_trigger();
        repeat (123) @(negedge clk);
        rst_n = 1'b0;
        @(negedge clk);
        revisar(!a_h && !a_l && !b_h && !b_l && !running, "reset a mitad de periodo apaga todo");
        rst_n = 1'b1;
        probar_punto(P0, 0, 20, "despues del reset vuelve a funcionar");

        revisar(solape_a == 0, $sformatf("pierna A nunca tuvo los dos transistores encendidos (%0d ciclos con solape)", solape_a));
        revisar(solape_b == 0, $sformatf("pierna B nunca tuvo los dos transistores encendidos (%0d ciclos con solape)", solape_b));
        revisar(dt_corto == 0, $sformatf("siempre se respeto el tiempo muerto (%0d violaciones)", dt_corto));
        revisar(trig_ancho_malo == 0, "pwm_trigger_o siempre dura un ciclo");

        $display("");
        $display("==============================================");
        $display(" tb_pwm_core: %0d pruebas, %0d fallas", pruebas, fallas);
        if (fallas == 0)
            $display(" RESULTADO: PASA");
        else
            $display(" RESULTADO: FALLA");
        $display("==============================================");
        $finish;
    end

    initial begin
        #20ms;
        $display("[FAIL] tiempo limite de simulacion");
        $display(" RESULTADO: FALLA");
        $finish;
    end

endmodule
