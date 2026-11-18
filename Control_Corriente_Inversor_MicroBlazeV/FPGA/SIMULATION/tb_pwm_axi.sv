// tb_pwm_axi.sv
// Testbench autoverificable de pwm_axi. Hace de maestro AXI4-Lite y prueba
// los registros, la saturacion, WSTRB, AW y W en ciclos distintos y que el
// PWM arranque y se apague desde los registros, y que pwm_trigger_o salga
// en el valle. Tambien sirve para la simulacion post-implementacion.

`timescale 1ns / 1ps

module tb_pwm_axi;

    localparam logic [3:0] REG_CTRL = 4'h0;
    localparam logic [3:0] REG_DUTY = 4'h4;
    localparam logic [3:0] REG_DT   = 4'h8;
    localparam logic [3:0] REG_RES  = 4'hC;

    localparam logic [15:0] M_MAX = 16'd31129;
    // diferencia esperada entre los ciclos de a_h despues y antes del disparo
    // (es el tiempo muerto, 20 ciclos)
    localparam int DIF_TRIG = 20;

    logic clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    logic        aresetn;
    logic [3:0]  awaddr;
    logic [2:0]  awprot;
    logic        awvalid, awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid, wready;
    logic [1:0]  bresp;
    logic        bvalid, bready;
    logic [3:0]  araddr;
    logic [2:0]  arprot;
    logic        arvalid, arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid, rready;

    logic a_h, a_l, b_h, b_l, trig;

    pwm_axi dut (
        .gate_a_h_o    (a_h),
        .gate_a_l_o    (a_l),
        .gate_b_h_o    (b_h),
        .gate_b_l_o    (b_l),
        .pwm_trigger_o (trig),
        .S_AXI_ACLK    (clk),
        .S_AXI_ARESETN (aresetn),
        .S_AXI_AWADDR  (awaddr),
        .S_AXI_AWPROT  (awprot),
        .S_AXI_AWVALID (awvalid),
        .S_AXI_AWREADY (awready),
        .S_AXI_WDATA   (wdata),
        .S_AXI_WSTRB   (wstrb),
        .S_AXI_WVALID  (wvalid),
        .S_AXI_WREADY  (wready),
        .S_AXI_BRESP   (bresp),
        .S_AXI_BVALID  (bvalid),
        .S_AXI_BREADY  (bready),
        .S_AXI_ARADDR  (araddr),
        .S_AXI_ARPROT  (arprot),
        .S_AXI_ARVALID (arvalid),
        .S_AXI_ARREADY (arready),
        .S_AXI_RDATA   (rdata),
        .S_AXI_RRESP   (rresp),
        .S_AXI_RVALID  (rvalid),
        .S_AXI_RREADY  (rready)
    );

    // ---------------------------------------------------------------
    // Conteo de resultados
    // ---------------------------------------------------------------
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

    // revisa que no haya solape en ninguna pierna
    int solape = 0;
    always @(negedge clk) begin
        if ((a_h && a_l) || (b_h && b_l)) solape++;
    end

    // en la post-implementacion las salidas cambian entre flancos, entonces
    // tambien se revisa cada vez que cambia una compuerta
    int solape_continuo = 0;
    always @(a_h, a_l, b_h, b_l) begin
        if ((a_h && a_l) || (b_h && b_l)) solape_continuo++;
    end

    // con m = 0, cuando sale trig tienen que estar encendidos los de arriba
    int trig_vistos = 0;
    int trig_fuera  = 0;
    always @(negedge clk) begin
        if (aresetn === 1'b1 && trig === 1'b1) begin
            trig_vistos++;
            if (!(a_h && b_h && !a_l && !b_l)) trig_fuera++;
        end
    end

    // mide un pulso alto de a_h: ciclos antes y despues del ciclo de trig
    task automatic medir_centro(output int antes, output int despues);
        do @(negedge clk); while (a_h);
        do @(negedge clk); while (!a_h);
        antes = 0;
        while (!trig) begin antes++; @(negedge clk); end
        despues = 0;
        @(negedge clk);
        while (a_h) begin despues++; @(negedge clk); end
    endtask

    // cuenta los ciclos con alguna salida en X despues del reset
    int ciclos_x = 0;
    always @(negedge clk) begin
        if (aresetn === 1'b1 && $isunknown({a_h, a_l, b_h, b_l, trig})) ciclos_x++;
    end

    // ---------------------------------------------------------------
    // Tareas del maestro AXI4-Lite
    // modo 0: AW y W juntos, modo 1: AW primero, modo 2: W primero
    // ---------------------------------------------------------------
    logic [1:0] ultimo_bresp;

    task automatic escribir(input logic [3:0] dir, input logic [31:0] dato,
                            input logic [3:0] strb = 4'hF, input int modo = 0);
        bit aw_ok, w_ok;
        @(negedge clk);
        awaddr = dir;
        wdata  = dato;
        wstrb  = strb;
        aw_ok  = 0;
        w_ok   = 0;
        case (modo)
            1: begin awvalid = 1'b1; repeat (3) @(negedge clk); wvalid = 1'b1; end
            2: begin wvalid  = 1'b1; repeat (3) @(negedge clk); awvalid = 1'b1; end
            default: begin awvalid = 1'b1; wvalid = 1'b1; end
        endcase
        // espera los dos handshakes
        while (!(aw_ok && w_ok)) begin
            @(posedge clk);
            if (awvalid && awready) aw_ok = 1;
            if (wvalid && wready)   w_ok  = 1;
            @(negedge clk);
            if (aw_ok) awvalid = 1'b0;
            if (w_ok)  wvalid  = 1'b0;
        end
        // respuesta de escritura
        bready = 1'b1;
        do @(posedge clk); while (!bvalid);
        ultimo_bresp = bresp;
        @(negedge clk);
        bready = 1'b0;
    endtask

    logic [1:0] ultimo_rresp;

    task automatic leer(input logic [3:0] dir, output logic [31:0] dato);
        @(negedge clk);
        araddr  = dir;
        arvalid = 1'b1;
        do @(posedge clk); while (!arready);
        @(negedge clk);
        arvalid = 1'b0;
        rready  = 1'b1;
        do @(posedge clk); while (!rvalid);
        dato = rdata;
        ultimo_rresp = rresp;
        @(negedge clk);
        rready = 1'b0;
    endtask

    // lee un registro y lo compara con lo esperado
    task automatic revisar_reg(input logic [3:0] dir, input logic [31:0] esperado, input string msg);
        logic [31:0] d;
        leer(dir, d);
        revisar(d == esperado, $sformatf("%s: leido 0x%08h, esperado 0x%08h", msg, d, esperado));
    endtask

    // mide los ciclos entre dos disparos del PWM
    task automatic medir_periodo(output int ciclos);
        do @(negedge clk); while (!trig);
        ciclos = 0;
        do begin @(negedge clk); ciclos++; end while (!trig);
    endtask

    // ---------------------------------------------------------------
    // Secuencia de pruebas
    // ---------------------------------------------------------------
    initial begin
        logic [31:0] d;
        int c;
        bit todo_apagado;

        aresetn = 1'b0;
        awaddr = '0; awprot = '0; awvalid = 1'b0;
        wdata  = '0; wstrb  = '0; wvalid  = 1'b0;
        bready = 1'b0;
        araddr = '0; arprot = '0; arvalid = 1'b0;
        rready = 1'b0;

        // 20 ciclos de reset porque en la post-implementacion el GSR dura
        // los primeros 100 ns
        repeat (20) @(negedge clk);
        aresetn = 1'b1;
        repeat (5) @(negedge clk);

        // --- valores despues de reset ---
        revisar_reg(REG_CTRL, 32'h0000_0000, "reset: Control/Estado");
        revisar_reg(REG_DUTY, 32'h0000_0000, "reset: duty_ref");
        revisar_reg(REG_DT,   32'h0000_0014, "reset: dead_time = 20");
        revisar_reg(REG_RES,  32'h0000_0000, "reset: registro reservado 0x0C");
        revisar(ultimo_rresp == 2'b00, "RRESP = OKAY");

        // --- running es de solo lectura ---
        escribir(REG_CTRL, 32'h0000_0008);   // intenta poner running = 1
        revisar(ultimo_bresp == 2'b00, "BRESP = OKAY");
        revisar_reg(REG_CTRL, 32'h0000_0000, "escribir running con enable = 0 no lo cambia");

        // --- freq_sel se lee igual a lo escrito, bits reservados en 0 ---
        escribir(REG_CTRL, 32'hFFFF_FFF4);   // freq_sel = 10, enable = 0, resto en 1
        revisar_reg(REG_CTRL, 32'h0000_0004, "freq_sel = 10 y bits reservados leen 0");
        escribir(REG_CTRL, 32'h0000_0000);

        // --- duty_ref y su saturacion ---
        escribir(REG_DUTY, 32'h0000_4000);   // 0,5
        revisar_reg(REG_DUTY, 32'h0000_4000, "duty_ref = +0,5");
        escribir(REG_DUTY, 32'h0000_C000);   // -0,5
        revisar_reg(REG_DUTY, 32'h0000_C000, "duty_ref = -0,5");
        escribir(REG_DUTY, {16'd0, M_MAX});
        revisar_reg(REG_DUTY, {16'd0, M_MAX}, "duty_ref = +M_MAX se acepta");
        escribir(REG_DUTY, 32'h0000_7FFF);   // casi +1, fuera de rango
        revisar_reg(REG_DUTY, {16'd0, M_MAX}, "duty_ref > M_MAX se satura a +M_MAX");
        escribir(REG_DUTY, 32'h0000_8000);   // -1, fuera de rango
        revisar_reg(REG_DUTY, {16'd0, 16'(-$signed(M_MAX))}, "duty_ref < -M_MAX se satura a -M_MAX");
        escribir(REG_DUTY, 32'hABCD_4000);   // bits altos reservados
        revisar_reg(REG_DUTY, 32'h0000_4000, "duty_ref ignora los bits [31:16]");

        // --- WSTRB: solo cambia el byte bajo ---
        escribir(REG_DUTY, 32'h0000_1234);
        escribir(REG_DUTY, 32'h0000_00AB, 4'b0001);
        revisar_reg(REG_DUTY, 32'h0000_12AB, "WSTRB = 0001 solo cambia el byte bajo");
        escribir(REG_DUTY, 32'h0000_5600, 4'b0000);
        revisar_reg(REG_DUTY, 32'h0000_12AB, "WSTRB = 0000 no cambia nada");

        // --- dead_time y su saturacion ---
        escribir(REG_DT, 32'h0000_0000);
        revisar_reg(REG_DT, 32'h0000_000A, "dead_time = 0 se satura a DT_MIN = 10");
        escribir(REG_DT, 32'h0000_0005);
        revisar_reg(REG_DT, 32'h0000_000A, "dead_time = 5 se satura a DT_MIN = 10");
        escribir(REG_DT, 32'h0000_00C8);
        revisar_reg(REG_DT, 32'h0000_00C8, "dead_time = 200 se acepta");
        escribir(REG_DT, 32'h0000_01FF);
        revisar_reg(REG_DT, 32'h0000_00FF, "dead_time ignora los bits [31:8]");

        // --- AW y W en ciclos distintos ---
        escribir(REG_DT, 32'h0000_0019, 4'hF, 1);
        revisar_reg(REG_DT, 32'h0000_0019, "AW llega 3 ciclos antes que W");
        escribir(REG_DT, 32'h0000_001A, 4'hF, 2);
        revisar_reg(REG_DT, 32'h0000_001A, "W llega 3 ciclos antes que AW");

        // --- registro reservado ---
        escribir(REG_RES, 32'hFFFF_FFFF);
        revisar(ultimo_bresp == 2'b00, "escritura a 0x0C responde OKAY");
        revisar_reg(REG_RES, 32'h0000_0000, "0x0C sigue leyendo 0");
        revisar_reg(REG_DT, 32'h0000_001A, "escribir 0x0C no cambia los otros registros");

        // --- el PWM arranca desde los registros ---
        escribir(REG_DT,   32'h0000_0014);   // 20 ciclos
        escribir(REG_DUTY, 32'h0000_0000);   // m = 0
        escribir(REG_CTRL, 32'h0000_0001);   // enable, 100 kHz
        repeat (5) @(negedge clk);
        revisar_reg(REG_CTRL, 32'h0000_0009, "con enable = 1 running se lee en 1");
        medir_periodo(c);
        revisar(c == 1000, $sformatf("periodo a 100 kHz: %0d ciclos (esperado 1000)", c));
        // trig tiene que salir en la mitad del pulso alto de a_h
        begin : centro
            int antes, despues;
            medir_centro(antes, despues);
            revisar(despues - antes == DIF_TRIG,
                    $sformatf("trig cae en el valle: a_h lleva %0d ciclos antes del disparo y %0d despues (diferencia esperada %0d)",
                              antes, despues, DIF_TRIG));
        end

        escribir(REG_CTRL, 32'h0000_0003);   // freq_sel = 01, 80 kHz
        medir_periodo(c);                    // este puede ser el de transicion
        medir_periodo(c);
        revisar(c == 1250, $sformatf("periodo a 80 kHz desde el registro: %0d ciclos (esperado 1250)", c));

        escribir(REG_CTRL, 32'h0000_0005);   // freq_sel = 10, 125 kHz
        medir_periodo(c);
        medir_periodo(c);
        revisar(c == 800, $sformatf("periodo a 125 kHz desde el registro: %0d ciclos (esperado 800)", c));

        // --- se apaga desde el registro ---
        escribir(REG_CTRL, 32'h0000_0004);   // enable = 0
        @(negedge clk);
        revisar(!a_h && !a_l && !b_h && !b_l, "enable = 0 por AXI apaga las 4 compuertas");
        revisar_reg(REG_CTRL, 32'h0000_0004, "con enable = 0 running se lee en 0");
        todo_apagado = 1'b1;
        repeat (2000) begin
            @(negedge clk);
            if (a_h || a_l || b_h || b_l || trig) todo_apagado = 1'b0;
        end
        revisar(todo_apagado, "apagado no hay pulsos ni disparos");

        revisar(solape == 0, $sformatf("nunca hubo dos transistores de la misma pierna encendidos (%0d ciclos)", solape));
        revisar(solape_continuo == 0, $sformatf("tampoco hubo solape entre flancos (%0d veces)", solape_continuo));
        revisar(ciclos_x == 0, $sformatf("las salidas nunca quedaron en X (%0d ciclos)", ciclos_x));
        revisar(trig_vistos > 0 && trig_fuera == 0,
                $sformatf("con m = 0 trig siempre cayo con las dos compuertas de arriba encendidas (%0d de %0d fuera)", trig_fuera, trig_vistos));

        $display("");
        $display("==============================================");
        $display(" tb_pwm_axi: %0d pruebas, %0d fallas", pruebas, fallas);
        if (fallas == 0)
            $display(" RESULTADO: PASA");
        else
            $display(" RESULTADO: FALLA");
        $display("==============================================");
        $finish;
    end

    // por si algo se queda trabado (por ejemplo, un READY que nunca llega)
    initial begin
        #5ms;
        $display("[FAIL] tiempo limite de simulacion");
        $display(" RESULTADO: FALLA");
        $finish;
    end

endmodule
