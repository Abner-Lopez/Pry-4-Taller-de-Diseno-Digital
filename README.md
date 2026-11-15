<h1 align="center">
  Proyecto 4 <br>
  EL-3313 Taller de Diseño Digital <br>
  Control de corriente en un inversor monofásico mediante un regulador PR discreto sobre MicroBlaze V
</h1>

<h3 align="center" style="color: #0366d6; letter-spacing: 1px;">
  Equipo de trabajo
</h3>

<p align="center">
  <b>Fallas Fallas Mariana | 2022080686 | mfallas@estudiantec.cr </b>
  <br>
  <b>Garita Serrano Justin | 2022437433 | jugarita@estudiantec.cr </b>
  <br>
  <b>López Méndez Abner | 2022273075 | ablopez@estudiantec.cr </b>
  <br>
  <b>Segura Chinchilla Jordi | 2022240646 | jorsegura@estudiantec.cr </b>
</p>

---

Proyecto 4 — EL3313 Taller de Diseño Digital, en conjunto con EL4201 Procesamiento Electrónico de Potencia. Instituto Tecnológico de Costa Rica, II Semestre 2026.

El sistema corre en una Nexys 4 (rev B). Un MicroBlaze V a 100 MHz ejecuta cada 50 µs una interrupción que lee la corriente con el XADC, calcula el regulador PR y actualiza el ciclo de trabajo de un periférico PWM propio con interfaz AXI4-Lite. El PWM genera la modulación unipolar con tiempo muerto para el puente H y el disparo de la conversión del ADC. Las muestras se guardan en un buffer circular y se exportan por UART al presionar un botón.

Documentos del proyecto: [documento de diseño](Control_Corriente_Inversor_MicroBlazeV/docs/diseño/) e [informe técnico](Control_Corriente_Inversor_MicroBlazeV/docs/informe/).

## Estructura del repositorio

```
Control_Corriente_Inversor_MicroBlazeV/
├── docs/
│   ├── diseño/          documento de diseño y sus figuras
│   └── informe/         informe técnico, figuras y reportes de Vivado
├── FPGA/
│   ├── DESIGN/          pwm_core.sv, pwm_axi.sv y pwm_bd.v (periférico PWM)
│   ├── SIMULATION/      tb_pwm_core.sv y tb_pwm_axi.sv (autoverificables)
│   ├── CONSTRAINTS/     nexys4_inversor.xdc (sistema) y pwm_axi_ooc.xdc (PWM solo)
│   ├── BLOCK_DESIGN/    sistema_microblaze.tcl (Block Design exportado de Vivado)
│   └── DOCUMENTATION/   documentación de los módulos de hardware y sus figuras
├── C/
│   ├── DESIGN/          aplicación de control y drivers (Vitis)
│   └── DOCUMENTATION/   documentación del software y sus figuras
└── PYTHON/
    ├── DESIGN/          graficar_muestras.py (recepción y graficación de muestras)
    └── DOCUMENTATION/   documentación del script y sus figuras
```

## Dependencias

- Vivado y Vitis 2025.2 (AMD).
- Tarjeta Nexys 4 (rev B), FPGA xc7a100tcsg324-1, con su cable USB.
- Python 3 con `pyserial` y `matplotlib`: `pip install pyserial matplotlib`.
- Un programa de terminal serie (PuTTY, Tera Term o el Serial Monitor de Vitis): 115200 baudios, 8 bits, sin paridad, 1 bit de parada.

Conviene trabajar en una carpeta con una ruta corta y sin espacios (por ejemplo `C:\p4`). Windows limita las rutas a 260 caracteres y Vivado crea carpetas temporales largas dentro del proyecto.

## Simulación del PWM

### Simulación RTL

1. En Vivado: *Create Project* → *RTL Project* → parte `xc7a100tcsg324-1`.
2. *Add Sources* → *Add or create design sources*: `FPGA/DESIGN/pwm_core.sv` y `pwm_axi.sv`, sin marcar *Copy sources into project*.
3. *Add Sources* → *Add or create simulation sources*: `FPGA/SIMULATION/tb_pwm_core.sv` y `tb_pwm_axi.sv`.
4. En *Settings* → *Simulation* → *Simulation*, poner `xsim.simulate.runtime` en `all`.
5. En *Simulation Sources*, clic derecho sobre `tb_pwm_core` → *Set as Top* → *Run Simulation* → *Run Behavioral Simulation*.
6. En la consola Tcl aparece una línea `[PASS]` o `[FAIL]` por prueba y al final `RESULTADO: PASA` o `RESULTADO: FALLA`. Repetir con `tb_pwm_axi`.

Resultado esperado: `tb_pwm_core` 60 pruebas y `tb_pwm_axi` 35 pruebas, 0 fallas.

Para comprobar que los testbenches detectan errores, en *Settings* → *Simulation* → *Compilation* se agrega `FORZAR_FALLA` en *Verilog options* → *Defines*. Cada testbench debe dar una sola falla.

### Simulación post-implementación temporizada

Se hace con `pwm_axi` como top, sin el MicroBlaze V:

1. En el mismo proyecto de la simulación RTL, *Add Sources* → *Add or create constraints*: `FPGA/CONSTRAINTS/pwm_axi_ooc.xdc`.
2. `pwm_axi` como top de *Design Sources* y `tb_pwm_axi` como top de *Simulation Sources*.
3. *Settings* → *Synthesis* → *More Options*: `-mode out_of_context` (las salidas del PWM no van a pines en este proyecto).
4. *Run Implementation*.
5. *Run Simulation* → *Run Post-Implementation Timing Simulation*.

Resultado esperado: `tb_pwm_axi` 35 pruebas, 0 fallas, con los retardos del SDF cargados (el log lo indica con `SDF backannotation was successful`).

## Compilación del hardware

1. En Vivado: *Create Project* → *RTL Project* → parte `xc7a100tcsg324-1`. Lenguaje de destino: Verilog.
2. *Add Sources* → *Add or create design sources*: `FPGA/DESIGN/pwm_core.sv`, `pwm_axi.sv` y `pwm_bd.v`.
3. *Add Sources* → *Add or create constraints*: `FPGA/CONSTRAINTS/nexys4_inversor.xdc`. El archivo `pwm_axi_ooc.xdc` **no** va en este proyecto.
4. En la consola Tcl: `source <ruta del repo>/Control_Corriente_Inversor_MicroBlazeV/FPGA/BLOCK_DESIGN/sistema_microblaze.tcl`. Se crea el Block Design `sistema_microblaze` con el MicroBlaze V, la memoria local de 64 KB, el AXI INTC, el AXI Timer, la AXI UART Lite, los dos AXI GPIO, el XADC Wizard y el PWM (`pwm_0`).
5. En *Sources*, clic derecho sobre `sistema_microblaze` → *Create HDL Wrapper* → *Let Vivado manage wrapper* → *Set as Top*.
6. *Generate Bitstream*.
7. Con el diseño implementado abierto: *Report Utilization* y *Report Timing Summary*. Los reportes de referencia están en `Control_Corriente_Inversor_MicroBlazeV/docs/informe/reportes`.
8. *File* → *Export* → *Export Hardware* → *Include bitstream*. Se genera `sistema_microblaze.xsa`.

Mapa de direcciones que asigna el Block Design:

| Periférico | Dirección base | Tamaño |
|---|---|---|
| Memoria local (LMB) | `0x0000_0000` | 64 KB |
| PWM (`pwm_0`) | `0x0001_0000` | 4 KB |
| GPIO 0 (LEDs y switches) | `0x4000_0000` | 64 KB |
| GPIO 1 (botones y pin de prueba) | `0x4001_0000` | 64 KB |
| UART Lite | `0x4060_0000` | 64 KB |
| AXI INTC | `0x4120_0000` | 64 KB |
| AXI Timer | `0x41C0_0000` | 64 KB |
| XADC Wizard | `0x44A0_0000` | 64 KB |

## Compilación del software

1. Abrir Vitis 2025.2 y escoger como workspace una carpeta vacía con ruta corta.
2. *File* → *New Component* → *Platform*: nombre `plataforma_p4`, *Hardware Design* = el `.xsa` exportado, sistema operativo `standalone`, procesador `microblaze_riscv_0`. Compilar la plataforma (*Build*).
3. *File* → *New Component* → *Application*: nombre `control_corriente`, plataforma `plataforma_p4`, dominio `standalone_microblaze_riscv_0`.
4. Clic derecho en `control_corriente/src` → *Import* → *Files*: de `C/DESIGN` se importan `main.c`, `control_isr.c`, `control_isr.h`, `control_pr.c`, `control_pr.h`, `pwm_driver.h` y `adc_driver.h`. Vitis los copia al workspace; la versión oficial es la del repositorio.
5. *Build*. Al final se imprime el tamaño del programa; texto, datos y bss juntos deben quedar por debajo de los 64 KB de la memoria local.

## Ejecución

1. Conectar la Nexys 4 por USB y encenderla. **No conectar la etapa de potencia** hasta que PEDP haya revisado las compuertas y el tiempo muerto con el puente desenergizado.
2. Abrir la terminal serie en el puerto COM de la tarjeta.
3. En Vitis, *Run* sobre `control_corriente`. La configuración de ejecución programa la FPGA con el bitstream de la plataforma y carga el programa.
4. La terminal muestra una línea por segundo con el número de interrupciones, la duración máxima de la ISR y la latencia (en ciclos de 10 ns), el estado de falla y la lectura del ADC.

| Control | Función |
|---|---|
| SW0 | Habilita el lazo (al bajarlo se borra la falla) |
| SW2..SW1 | `freq_sel`: 00 = 100 kHz, 01 = 80 kHz, 10 = 125 kHz |
| SW4..SW3 | Amplitud de la referencia: 00 = 0,2 A, 01 = 0,5 A, 1x = 1,0 A pico |
| SW15 | 1 = corriente leída con el XADC, 0 = carga RL simulada en el programa |
| SW14 | Modo emulador: la corriente se lee de un circuito RC conectado al XADC. Solo sin la etapa de potencia |
| BTNC | Exporta el buffer por UART |
| LD0 | Lazo habilitado |
| LD1 | Falla (corriente fuera del límite) |
| LD2 | Exportación en curso |
| LD3 | Modo emulador activo |

Pines usados: compuertas en el Pmod JA (JA1 `gate_a_h_o`, JA2 `gate_a_l_o`, JA3 `gate_b_h_o`, JA4 `gate_b_l_o`), JA7 `pwm_trigger_o`, JA8 pin de prueba que cambia en cada interrupción, y la entrada analógica en JXADC pin 1 (VAUX3P) y pin 7 (VAUX3N). La entrada del XADC trabaja de 0 a 1 V.

### Exportación y graficación de las muestras

1. Cerrar la terminal serie (el puerto solo lo puede usar un programa a la vez).
2. En `PYTHON/DESIGN`: `python graficar_muestras.py COMx`, con el puerto de la tarjeta.
3. Cuando diga `Esperando...`, presionar BTNC. Se reciben las muestras del buffer (hasta 2000), se guardan en un CSV en la misma carpeta y se grafican la referencia, la corriente y el índice de modulación.

## Flujo de trabajo

- `main`: rama principal del proyecto.
- `feature/<funcionalidad>`: una rama por funcionalidad, integrada a `main` mediante pull request revisado por otro integrante.
- Cada tarea tiene un *issue* asignado a un integrante.

## Referencias

- D. Harris y S. Harris. *Digital Design and Computer Architecture. RISC-V Edition*. Morgan Kaufmann, 2022.
- P. P. Chu. *FPGA Prototyping by SystemVerilog Examples*. Wiley, 2018.
- AMD. *MicroBlaze V Embedded Design Tutorial* (UG1711).
- AMD. *MicroBlaze Processor Reference Guide* (UG984).
- AMD. *Vivado Design Suite User Guide: Creating and Packaging Custom IP* (UG1118).
- AMD. *AXI Reference Guide* (UG1037).
- AMD. *Vitis Unified Software Platform Documentation* (UG1416).
