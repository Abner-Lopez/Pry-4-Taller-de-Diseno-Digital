<h1 align="center">
  Informe técnico <br>
  Control de corriente en un inversor monofásico mediante un regulador PR discreto sobre MicroBlaze V
</h1>

<p align="center">
  EL3313 Taller de Diseño Digital — Proyecto 4 — II Semestre 2026 <br>
  Mariana Fallas Fallas · Justin Garita Serrano · Abner López Méndez · Jordi Segura Chinchilla
</p>

---

## Resumen

Se construyó en la Nexys 4 [16] un sistema embebido con un MicroBlaze V a 100 MHz que regula la corriente de un inversor monofásico en puente H. El procesador ejecuta en C un regulador proporcional-resonante discreto dentro de una rutina de interrupción cada 50 µs. Un periférico PWM propio, con interfaz AXI4-Lite, genera la modulación unipolar de las cuatro compuertas con tiempo muerto configurable y entrega el disparo que sincroniza el XADC con el valle de la portadora. Las muestras se guardan en un buffer circular y se exportan por la UART a la PC al presionar un botón, sin detener el lazo.

El PWM pasa sus dos testbenches autoverificables en Vivado 2025.2: `tb_pwm_core` con 60 pruebas y `tb_pwm_axi` con 37, este último también en la simulación post-implementación temporizada. El sistema completo cumple timing a 100 MHz. En la tarjeta se midió un periodo de lazo de 50,0 µs con la ISR ocupando el 21,5 % del periodo, y el lazo cerrado funcionó primero con una planta simulada en software y después con un emulador RC que pasa por el PWM y el XADC reales. Con el puente H, alimentado a 18 V y con una carga de 5,0 Ω y 197 µH, se logró la conmutación correcta de las dos piernas después de corregir la alimentación lógica de los drivers. Con el sensor de corriente conectado al XADC se cerró el lazo con la corriente real: con referencias sinusoidales de 50 Hz de 0,2 A, 0,5 A y 1,0 A pico, la fundamental de la corriente medida por el sensor quedó dentro del 0,3 % de la referencia y en fase con ella, y la corriente en la resistencia de la carga, medida con el osciloscopio, tuvo picos cercanos a la referencia.

---

## Contenido

1. [Introducción](#1-introducción)
2. [Objetivos](#2-objetivos)
3. [Marco teórico](#3-marco-teórico)
4. [Enfoque de la solución](#4-enfoque-de-la-solución)
5. [Periférico PWM](#5-periférico-pwm)
6. [Control principal](#6-control-principal)
7. [Etapa de potencia](#7-etapa-de-potencia)
8. [Verificación por simulación](#8-verificación-por-simulación)
9. [Recursos y timing](#9-recursos-y-timing)
10. [Pruebas en la tarjeta](#10-pruebas-en-la-tarjeta)
11. [Análisis de resultados](#11-análisis-de-resultados)
12. [Problemas encontrados y soluciones](#12-problemas-encontrados-y-soluciones)
13. [Análisis crítico](#13-análisis-crítico)
14. [Conclusiones](#14-conclusiones)
15. [Referencias](#15-referencias)

---

## 1. Introducción

En este proyecto se construyó un sistema embebido en la Nexys 4 (Artix-7) que regula la corriente de un inversor monofásico en puente H. El procesador es un MicroBlaze V [3], [4] a 100 MHz que ejecuta en C un regulador proporcional-resonante (PR) cada 50 µs. Los periféricos se encargan de lo que necesita tiempos exactos: un PWM unipolar propio, con interfaz AXI4-Lite y tiempo muerto configurable, genera las cuatro compuertas del puente; el XADC mide la corriente sincronizado con la portadora del PWM; y la UART exporta las muestras a la PC.

El informe describe lo que se implementó y lo que se midió, desde la verificación del PWM en simulación hasta el lazo cerrado con la corriente real del puente H. El diseño completo, con los diagramas de niveles de la metodología de diseño modular [15], está en `docs/diseño/diseño.md`, y el detalle de cada módulo está en la carpeta `DOCS` de cada parte del repositorio.

---

## 2. Objetivos

1. Integrar en el Block Design un sistema MicroBlaze V a 100 MHz con Timer, XADC, UART, GPIO y un periférico propio.
2. Diseñar en SystemVerilog un PWM unipolar con interfaz AXI4-Lite, tiempo muerto configurable, tres frecuencias de conmutación y disparo para el ADC.
3. Implementar en C el regulador PR dentro de una rutina de interrupción periódica, con la ecuación entregada por el curso de potencia.
4. Guardar las muestras en un buffer circular y exportarlas por la UART sin afectar el lazo.
5. Verificar el PWM con testbenches autoverificables, en RTL y post-implementación, y medir el periodo y el jitter del lazo en la tarjeta.
6. Integrar la parte digital con la etapa de potencia y cerrar el lazo de corriente con la corriente real de la carga.

---

## 3. Marco teórico

### 3.1 Sistemas embebidos y tiempo real

Un lazo de control digital supone que la medición y la actualización del actuador ocurren cada $T_s$ exacto. Si el instante varía, la discretización del controlador deja de corresponder con lo que pasa en la planta. Por eso el lazo se ejecuta en una **rutina de interrupción (ISR)** disparada por un temporizador de hardware [8], y no en un ciclo del programa principal, cuyo tiempo depende de lo que haga el resto del código.

En una ISR periódica interesan tres tiempos:

- **Periodo**: tiempo entre dos entradas a la rutina. Lo fija el temporizador.
- **Latencia**: tiempo entre la petición de interrupción y el inicio de la rutina. Depende de lo que esté haciendo el procesador y del despacho de la interrupción.
- **Jitter**: variación del periodo de una interrupción a otra, causada por los cambios de latencia.

La rutina tiene que terminar antes de la siguiente interrupción y no puede tener esperas, como enviar por la UART. Lo lento se hace en el programa principal, que corre en el tiempo que sobra entre interrupciones. Las variables compartidas entre las dos partes se declaran `volatile` para que el compilador siempre las lea de memoria.

### 3.2 Interfaz AXI4-Lite

AXI4-Lite es la versión simple del bus AXI4 de ARM [5], [6]: transferencias de 32 bits, una a la vez, sin ráfagas. Tiene cinco canales independientes:

| Canal | Dirección | Contenido |
|---|---|---|
| AW | Maestro → esclavo | Dirección de escritura |
| W | Maestro → esclavo | Dato y `WSTRB` (qué bytes se escriben) |
| B | Esclavo → maestro | Respuesta de la escritura (`BRESP`) |
| AR | Maestro → esclavo | Dirección de lectura |
| R | Esclavo → maestro | Dato leído y respuesta (`RRESP`) |

Cada canal usa el mismo *handshake*: quien envía sube `VALID` y quien recibe sube `READY`; el dato pasa en el ciclo en que los dos están en 1. Quien envía no puede esperar a `READY` para subir `VALID`. AW y W son canales distintos, así que el esclavo tiene que aceptar la dirección y el dato aunque lleguen en ciclos diferentes.

### 3.3 PWM unipolar y tiempo muerto

En un puente H cada pierna tiene dos transistores que nunca deben conducir a la vez. En la modulación unipolar [10] las dos piernas se comparan con la misma portadora triangular, la pierna A con $+m$ y la B con $-m$:

$$d_A = \frac{1+m}{2}, \qquad d_B = \frac{1-m}{2}, \qquad \bar v_{AB} = V_{dc}\,(d_A - d_B) = V_{dc}\,m$$

La tensión entre las salidas toma tres niveles ($+V_{dc}$, 0 y $-V_{dc}$) y su componente principal de conmutación está en $2 f_{sw}$, el doble que en la bipolar. Eso baja el rizado de corriente para la misma frecuencia de los transistores.

Un transistor tarda en apagarse, así que si el otro de la pierna se enciende en el mismo instante hay un cortocircuito momentáneo de la fuente. El **tiempo muerto** es un retardo que se agrega al encendido de cada transistor después de que su complementario se apagó.

### 3.4 Muestreo sincronizado con el PWM

La corriente en la carga tiene un rizado a la frecuencia de conmutación. En una portadora triangular simétrica, la corriente pasa por su valor promedio en el centro de cada pulso, que es el pico o el valle de la portadora. Si la conversión del ADC [7], [17] arranca justo ahí, la muestra da el promedio sin necesidad de filtrar, y además queda lejos de los flancos de conmutación, donde hay más ruido.

### 3.5 Controlador PR discreto

Un PI no tiene error cero en régimen con una referencia sinusoidal. El regulador proporcional-resonante [14] agrega un término con ganancia infinita a la frecuencia de la referencia $\omega_0$:

$$C(s) = K_p + \frac{K_r\,s}{s^2 + \omega_0^2}$$

Para implementarlo en el procesador se discretiza con Tustin, $s = \frac{2}{T_s}\frac{z-1}{z+1}$. Tustin deforma el eje de frecuencias, así que se usa *prewarping* en $\omega_0$ para que la resonancia quede en 50 Hz. Queda una ecuación en diferencias de segundo orden:

$$y[n] = b_0\,e[n] + b_2\,e[n-2] - a_1\,y[n-1] - a_2\,y[n-2], \qquad a_1 = -2\cos(\omega_0 T_s),\ a_2 = 1$$

Con $a_2 = 1$ los polos quedan sobre el círculo unitario a la frecuencia $\omega_0$. La salida del controlador es $u[n] = K_p\,e[n] + y[n]$, en voltios, y el índice de modulación es $m = u/V_{dc}$, saturado a ±0,8 en el software. Con $K_p = 2$, $K_r = 3000$ y $T_s = 50$ µs los coeficientes son $b_0 = -b_2 = 0{,}07499691579$, $a_1 = -1{,}999753265$ y $a_2 = 1$.

El diseño del PR y sus ganancias son del curso de potencia (EL4201); en Taller se implementó la ecuación que entregó ese curso.

---

## 4. Enfoque de la solución

![nivel2_fpga](FIGURAS/nivel2_fpga.png)

*Figura 1: bloques del sistema dentro de la FPGA.*

El sistema reparte el trabajo así:

- **Hardware con tiempos exactos.** El PWM (`pwm_0`) genera la portadora, las compuertas con tiempo muerto y el disparo `pwm_trigger_o`. El XADC (`xadc_wiz_0`) convierte cuando llega ese disparo. El AXI Timer pide la interrupción cada 50 µs.
- **Software con el cálculo.** La ISR lee la corriente, calcula la referencia y el PR, escribe `duty_ref` y guarda la muestra. El programa principal lee los switches, maneja los LEDs y exporta por la UART.

Las decisiones principales fueron:

| Decisión | Razón |
|---|---|
| Un solo periférico propio, el PWM | Es lo que necesita tiempos de un ciclo de reloj; el resto se cubre con IP de AMD |
| `duty_ref` en Q1.15 con signo | Un solo valor $m$ da las dos piernas ($+m$ y $-m$) |
| Disparo del XADC y carga de registros en el valle | La muestra cae en el centro del pulso y ningún pulso se corta a la mitad |
| Saturación en hardware (±0,95 y tiempo muerto mínimo de 100 ns) | Evita que un valor fuera de rango escrito por el software deje una compuerta encendida todo el periodo o quite el tiempo muerto. El tiempo muerto que necesita el puente lo escribe el software |
| $T_s$ = 50 µs y PR en `float` con FPU | Deja tiempo de sobra para la ISR y el código del PR es fácil de seguir y de cambiar |
| Buffer congelado mientras se exporta | Lo que se envía es un bloque continuo que no cambia durante el envío |
| Emulador RC en el XADC | Permite cerrar el lazo pasando por el PWM y el XADC reales sin la etapa de potencia |

La tabla completa de decisiones, con las alternativas consideradas, está en la sección 12 del documento de diseño.

---

## 5. Periférico PWM

### 5.1 Interfaz

`pwm_axi` es el módulo superior del periférico. Se conecta al Block Design por medio de `pwm_bd.v`, una envoltura en Verilog sin lógica. Dentro de él se instancia `pwm_core`, que no conoce el protocolo AXI. El RTL está escrito en SystemVerilog con la separación entre lógica secuencial y combinacional de [1] y [2].

| Puerto | Dir. | Ancho | Descripción |
|---|---|---|---|
| `S_AXI_ACLK` | E | 1 | Reloj de 100 MHz |
| `S_AXI_ARESETN` | E | 1 | Reset síncrono, activo en bajo |
| `S_AXI_AW*`, `S_AXI_W*`, `S_AXI_B*`, `S_AXI_AR*`, `S_AXI_R*` | E/S | | Cinco canales AXI4-Lite, datos de 32 bits, dirección de 4 bits |
| `gate_a_h_o`, `gate_a_l_o` | S | 1 | Compuertas de la pierna A (arriba, abajo) |
| `gate_b_h_o`, `gate_b_l_o` | S | 1 | Compuertas de la pierna B (arriba, abajo) |
| `pwm_trigger_o` | S | 1 | Pulso de un ciclo en cada valle, hacia `convst_in` del XADC |

### 5.2 Registros

Dirección base `0x0001_0000` (asignada por Vivado).

| Offset | Bits | Campo | Acceso | Tras reset | Lectura | Escritura |
|---|---|---|---|---|---|---|
| `0x00` | 0 | `enable` | R/W | 0 | Último valor escrito | 1 arranca el PWM; 0 apaga las cuatro compuertas en el siguiente ciclo |
| | [2:1] | `freq_sel` | R/W | `00` | Último valor escrito | `00` = 100 kHz, `01` = 80 kHz, `10` = 125 kHz, `11` = 100 kHz; se aplica en el valle |
| | 3 | `running` | RO | 0 | 1 mientras la portadora cuenta | Se ignora |
| | [31:4] | — | — | 0 | 0 | Se ignora |
| `0x04` | [15:0] | `duty_ref` | R/W | 0 | Valor ya saturado | Q1.15 con signo; se satura a ±31129 (±0,95) y se aplica en el valle |
| | [31:16] | — | — | 0 | 0 | Se ignora |
| `0x08` | [7:0] | `dead_time` | R/W | 20 | Valor ya saturado | Ciclos de 10 ns; menos de 10 se satura a 10; se aplica en el valle |
| | [31:8] | — | — | 0 | 0 | Se ignora |
| `0x0C` | [31:0] | — | — | 0 | 0 | Se ignora |

Todas las respuestas son OKAY. `WSTRB` se respeta byte por byte y AW y W se aceptan en cualquier orden. Los registros se repiten dentro del rango de 4 kB porque solo se decodifican los bits [3:2] de la dirección. `duty_ref` y `freq_sel` pasan por dos registros antes de llegar a la portadora, así que una escritura hecha en los dos ciclos anteriores a un valle entra en el valle siguiente; `dead_time` se toma directo en el valle.

### 5.3 Estados

![estados_pwm_core](FIGURAS/estados_pwm_core.png)

*Figura 2: estados de la portadora en `pwm_core`.*

La portadora es un contador con tres estados. En APAGADO el contador está en 0 y las salidas apagadas; con `enable_i = 1` pasa a SUBIENDO, cuenta hasta $P$, pasa a BAJANDO y vuelve a 0, que es el valle. En el valle se cargan los valores nuevos de `duty_ref`, `freq_sel` y `dead_time` y sale `pwm_trigger_o`. Con `enable_i = 0` o `rst_ni = 0` vuelve a APAGADO desde cualquier estado. En `pwm_core.sv` los estados no son una enumeración: salen de dos registros, `run_q` (0 en APAGADO) y `sube_q` (1 en SUBIENDO, 0 en BAJANDO).

---

## 6. Control principal

![estados_control](FIGURAS/estados_control.png)

*Figura 3: estados del lazo de control y de la exportación.*

El lazo tiene tres estados. En APAGADO, $m = 0$ y el PWM está apagado. Con SW0 = 1 y sin falla pasa a ACTIVO; al entrar se ponen en cero los estados del PR para no arrancar con valores de una corrida anterior. Si la corriente medida supera 1,5 A pasa a FALLA: $m$ vuelve a 0, el PWM se apaga en la misma interrupción y se enciende LD1. En el modo emulador (SW14 = 1) el PWM se queda encendido con $m = 0$, porque el RC necesita la conmutación. Solo se sale de FALLA bajando SW0.

La exportación es independiente del lazo. Al presionar BTNC el programa principal congela el buffer, lo envía y lo libera; la ISR sigue controlando durante todo el envío.

La aplicación se compila en Vitis 2025.2 [9] sobre la plataforma exportada del Block Design. La secuencia completa de la ISR y del programa principal, con sus diagramas de flujo, está en la sección 8 del documento de diseño.

---

## 7. Etapa de potencia

La etapa de potencia la diseñó el curso EL4201. Los datos que usa la parte digital son:

| Parámetro | Valor |
|---|---|
| Alimentación del puente | $V_{dc} = 18$ V |
| Transistores | IRFZ44N [12], dos por pierna |
| Driver | IR2110 [11], uno por pierna |
| Carga | $R \approx 5{,}0\ \Omega$ (4,7 Ω más 0,3 Ω de las bobinas), $L \approx 197\ \mu H$ |
| Constante de tiempo | $\tau = L/R \approx 39{,}4\ \mu s$ |
| Sensor de corriente | ACS712-30A [13] (66 mV/A), con divisor de 8,2 kΩ y 2,0 kΩ hacia el XADC |
| Frecuencia de conmutación | 100 kHz nominal |

A 50 Hz la reactancia es de unos 62 mΩ, así que la carga se comporta casi como una resistencia. El índice de modulación necesario es $m = I_{pico}\,R / V_{dc}$:

| $I_{pico}$ | $m$ con 5,0 Ω | $m$ con 10,3 Ω |
|---|---|---|
| 0,2 A | 0,056 | 0,114 |
| 0,5 A | 0,139 | 0,286 |
| 1,0 A | 0,278 | 0,572 |

La carga cambió durante el proyecto: al inicio era de 10,3 Ω y 198 µH, y se bajó a 5,0 Ω y 197 µH (una resistencia de 4,7 Ω más las bobinas), que es la que se usó en las pruebas 7 y 8 con el puente. Las pruebas 5 y 6 de la sección 10 se hicieron con la carga anterior, así que el modelo de la planta simulada y la ganancia del emulador estaban calculados para 10,3 Ω; la última columna es la que corresponde a esas pruebas. El software actual ya usa la carga de 5,0 Ω.

En todos los casos el valor más alto queda por debajo del límite del software (0,8) y del hardware (0,95). El IR2110 no genera tiempo muerto, así que todo el tiempo muerto lo pone el PWM.

---

## 8. Verificación por simulación

### 8.1 Testbenches

Los dos testbenches son autoverificables: cada prueba imprime `[PASS]` o `[FAIL]` y al final se imprime el total de pruebas, las fallas y `RESULTADO: PASA` o `RESULTADO: FALLA`.

**`tb_pwm_core`** prueba el núcleo solo, sin AXI:

| Prueba | Criterio de paso |
|---|---|
| Periodo de cada `freq_sel` | 1000, 1250 y 800 ciclos entre disparos |
| Ancho de los pulsos con `duty_ref` = 0, ±0,5 y ±`M_MAX` (±31129) | Tiempo encendido igual al calculado con $P$, $m$ y el tiempo muerto; por ejemplo, con $m = 0$ el transistor de abajo de la pierna A queda encendido 481 ciclos a 100 kHz, 607 a 80 kHz y 381 a 125 kHz |
| Tiempos muertos de 10, 20, 50 y 255 ciclos | Cada encendido llega al menos `dead_time` ciclos después del apagado del complementario |
| Cambio de `duty_ref` o `freq_sel` a mitad de periodo | El valor nuevo solo aparece después de un valle |
| `pwm_trigger_o` | Un pulso de un ciclo por periodo |
| `enable_i` y reset a mitad de periodo | Las cuatro salidas se apagan en el siguiente ciclo y el PWM vuelve a arrancar |
| Monitor continuo | Nunca hay dos transistores de una pierna encendidos a la vez |

**`tb_pwm_axi`** prueba el periférico completo desde el bus, como lo usa el MicroBlaze V:

![nivel4_tb_pwm_axi](FIGURAS/nivel4_tb_pwm_axi.png)

*Figura 4: estructura de `tb_pwm_axi`.*

| # | Prueba | Criterio de paso |
|---|---|---|
| 1 | Valores después del reset | `0x00` = 0, `0x04` = 0, `0x08` = 20, `0x0C` = 0, `RRESP = OKAY` |
| 2 | `running` de solo lectura | Escribir el bit 3 no lo cambia |
| 3 | `freq_sel` y bits reservados | Se lee lo escrito; los reservados leen 0 |
| 4 | `duty_ref` | ±0,5 se guardan igual; `0x7FFF` y `0x8000` se saturan a ±`M_MAX` (±31129) |
| 5 | `WSTRB` | Con `0001` solo cambia el byte bajo; con `0000` nada |
| 6 | `dead_time` | 0 y 5 se saturan a 10; 200 se acepta |
| 7 | AW y W en ciclos distintos | La escritura funciona en los dos órdenes |
| 8 | Registro `0x0C` | Responde OKAY y no cambia los otros registros |
| 9 | Arranque | `running` = 1 y periodo de 1000, 1250 y 800 ciclos |
| 9b | Disparo en el valle | Con $m = 0$, el pulso alto de `gate_a_h_o` tiene 20 ciclos menos antes del ciclo del disparo que después (el tiempo muerto solo atrasa el encendido) |
| 10 | Apagado | Cuatro compuertas en 0, `running` = 0 y sin pulsos en 2000 ciclos |
| 11 | Monitores | Sin solape, sin salidas en X y disparo siempre con las compuertas de arriba encendidas |

En total `tb_pwm_axi` tiene 37 pruebas.

Resultados de la simulación RTL en Vivado 2025.2 (xsim):

| Testbench | Resultado | Fuente |
|---|---|---|
| `tb_pwm_core` | 60 pruebas, 0 fallas, `RESULTADO: PASA` | `reportes/resultado_tb_pwm_core.log` |
| `tb_pwm_axi` | 37 pruebas, 0 fallas, `RESULTADO: PASA` | `reportes/resultado_tb_pwm_axi.log` |

En la prueba 9b el pulso alto de `gate_a_h_o` tuvo 229 ciclos antes del ciclo del disparo y 249 después. La diferencia de 20 ciclos es el tiempo muerto, lo que muestra que el disparo cae en el valle. En la primera versión de esta prueba el conteo dependía del orden en que el simulador ejecuta dos bloques en el mismo flanco del reloj: en xsim daba 229 y 250 y la prueba fallaba aunque el PWM estaba bien. Se corrigió contando los ciclos dentro de la misma tarea que espera el disparo.

### 8.2 Simulación post-implementación temporizada

Para esta simulación `pwm_axi` se implementó solo, como módulo superior, con el reloj de 100 MHz definido en `pwm_axi_ooc.xdc`. Se usó el mismo `tb_pwm_axi` sobre la netlist con los retardos reales de la implementación. Aquí es donde más sirve el monitor `solape_continuo`, que revisa el solape cada vez que cambia una compuerta y no solo en los flancos del reloj: con los retardos de ruteo, un solape corto podría aparecer entre dos flancos.

| Resultado | Valor | Fuente |
|---|---|---|
| Simulación post-implementación temporizada (xsim 2025.2) | 37 pruebas, 0 fallas, `RESULTADO: PASA` | `reportes/resultado_tb_pwm_axi_postimpl.log` |

Con los retardos reales también se cumplió la prueba del disparo (229 ciclos antes y 249 después) y el monitor `solape_continuo` no encontró ningún solape entre flancos.

---

## 9. Recursos y timing

Los reportes son de Vivado 2025.2. Los del sistema completo son de la implementación del 2 de noviembre; los de `pwm_axi` solo, de la implementación del 19 de noviembre con el RTL final.

| Recurso | Sistema completo | `pwm_axi` solo | Disponible |
|---|---|---|---|
| LUT | 6482 (10,2 %) | 179 (0,3 %) | 63 400 |
| Registros | 4871 (3,8 %) | 213 (0,2 %) | 126 800 |
| BRAM (tiles) | 16 (11,9 %) | 0 | 135 |
| DSP | 8 (3,3 %) | 2 (0,8 %) | 240 |
| IOB | 49 (23,3 %) | — | 210 |

| Timing a 100 MHz | Sistema completo | `pwm_axi` solo |
|---|---|---|
| WNS (setup) | 0,392 ns | 3,760 ns |
| WHS (hold) | 0,030 ns | 0,171 ns |
| Rutas que fallan | 0 | 0 |

Fuentes: `reportes/utilizacion_sistema.rpt`, `reportes/timing_sistema.rpt`, `reportes/utilizacion_pwm_axi_impl.rpt` y `reportes/timing_pwm_axi_impl.rpt`.

Los 16 tiles de BRAM son los 64 kB de memoria local (cada tile guarda 4 kB). El programa, la biblioteca de punto flotante y el buffer de 12 000 bytes no caben en 32 kB, por eso se usaron 64 kB; como todo corre desde la memoria local, no se agregó caché. El PWM usa 2 DSP, uno por pierna, para la multiplicación $P\,(1 \pm m)$. En el sistema completo el slack de setup es pequeño (0,392 ns) pero positivo, y la ruta más larga está dentro del MicroBlaze V. En el PWM el margen es de 3,76 ns gracias a que el cálculo de los umbrales se partió en dos etapas registradas.

---

## 10. Pruebas en la tarjeta

Las pruebas 1 a 6 se hicieron en la Nexys 4 con el sistema completo (MicroBlaze V a 100 MHz, PWM, XADC, Timer, UART y GPIO), sin conectar el puente H. La prueba 7 es la integración del PWM con el puente y la prueba 8 cierra el lazo de corriente con la corriente real de la carga. Las señales de las pruebas 1 a 6 se midieron con un osciloscopio Agilent MSO-X 2002A, con los canales digitales y el canal analógico 1:

| Canal | Señal |
|---|---|
| D0, D1 | `gate_a_h_o`, `gate_a_l_o` (JA1, JA2) |
| D2, D3 | `gate_b_h_o`, `gate_b_l_o` (JA3, JA4) |
| D4 | `pwm_trigger_o` (JA7) |
| D5 | Pin de prueba (JA8), en 1 mientras corre la ISR |

Para cerrar el lazo sin la etapa de potencia se usaron dos modos: la planta simulada en software (SW15 = 0), que es un modelo discreto de la carga RL, y el emulador RC (SW14 = 1), donde JA1 y JA4 pasan por un filtro RC hasta un nodo que entra al XADC.

### 10.1 Prueba 1: PWM con $m = 0$

| Medición | 100 kHz | 80 kHz | 125 kHz |
|---|---|---|---|
| Periodo medido | 10,0 µs | 12,5 µs | 8,0 µs |
| Frecuencia (osciloscopio) | 100,0 kHz | 80,03 kHz | 125,0 kHz |
| Pulso alto de cada compuerta superior | 4,8 µs | 6,05 µs | 3,8 µs |
| Tiempo muerto | 198 a 199 ns | ≈ 200 ns | ≈ 200 ns |
| Solape en una pierna | Ninguno | Ninguno | Ninguno |
| `pwm_trigger_o` | 1 por periodo, en el valle | 1 por periodo, en el valle | 1 por periodo, en el valle |

![osc_m0_100khz](FIGURAS/osc_m0_100khz.png)

*Figura 5: compuertas con $m = 0$ a 100 kHz (D0 a D3, 5 µs/div). Las dos piernas son iguales.*

![osc_tiempo_muerto](FIGURAS/osc_tiempo_muerto.png)

*Figura 6: tiempo muerto a 100 ns/div. Cada compuerta se enciende unos 200 ns después de que se apaga la otra de su pierna.*

![osc_80_125khz](FIGURAS/osc_80_125khz.png)

*Figura 7: compuertas y `pwm_trigger_o` (D4) a 80 kHz (izquierda) y 125 kHz (derecha), con la frecuencia medida sobre D0.*

### 10.2 Prueba 2: modulación unipolar

Con el lazo activo a 100 kHz se tomaron tres capturas en instantes distintos del seno de 50 Hz. El índice de cada pierna se calcula con el pulso alto más el tiempo muerto: $m_A = 2\,(t_{D0} + t_{DT})/T - 1$ y $m_B = 1 - 2\,(t_{D2} + t_{DT})/T$.

| Captura | Pulso alto D0 | Pulso alto D2 | $m$ pierna A | $m$ pierna B |
|---|---|---|---|---|
| 1 | 5,33 µs | 4,23 µs | +0,11 | +0,11 |
| 2 | 4,29 µs | 5,28 µs | −0,10 | −0,10 |
| 3 | 7,17 µs | 2,40 µs | +0,47 | +0,48 |

![osc_modulacion](FIGURAS/osc_modulacion.png)

*Figura 8: compuertas con el lazo activo a 100 kHz, con `pwm_trigger_o` (D4) y el pin de la ISR (D5). Los pulsos de las dos piernas ya no son iguales porque $m \neq 0$.*

Al bajar SW0 las cuatro compuertas quedaron en 0 y `pwm_trigger_o` dejó de salir, mientras la ISR siguió corriendo cada 50 µs.

### 10.3 Prueba 3: temporización del lazo

| Medición | Resultado | Cómo se obtuvo |
|---|---|---|
| Periodo del lazo | 50,0 µs | Medición de periodo sobre JA8 |
| Variación del flanco del pin de la ISR | Al menos 500 ns | Persistencia infinita a 50 ns/div con retardo de 50 µs; la franja ocupó toda la ventana |
| Latencia de entrada a la ISR | 2,89 a 3,24 µs (289 a 324 ciclos) | Contador del Timer leído al entrar a la rutina (`lat=` en la terminal), durante unos 5,6 min (6,7 millones de interrupciones), con el lazo apagado |
| Duración máxima de la ISR desde el arranque | 11,66 µs (1166 ciclos) | Contador del Timer (`isr_max=` en la terminal), mismo ensayo |
| Duración de la ISR en operación normal | ≈ 10,75 µs (21,5 % de $T_s$) | Ancho del pulso en JA8 |
| Duración de la ISR durante la exportación | 8,57 µs (17 % de $T_s$) | Ancho del pulso en JA8 |

![osc_disparo_isr](FIGURAS/osc_disparo_isr.png)

*Figura 9: vista de 20 µs/div: un disparo (D4) en cada valle y un pulso de la ISR (D5) cada 50 µs, o sea cada 5 periodos de conmutación a 100 kHz.*

![osc_periodo_lazo](FIGURAS/osc_periodo_lazo.png)

*Figura 10: pin de la ISR (JA8) en el canal analógico, con la medición de periodo.*

![osc_jitter](FIGURAS/osc_jitter.png)

*Figura 11: flanco de subida del pin de la ISR con persistencia infinita, 50 ns/div y retardo de 50 µs. La franja de flancos ocupa toda la ventana.*

![osc_isr_exportacion](FIGURAS/osc_isr_exportacion.png)

*Figura 12: pulso del pin de la ISR durante la exportación.*

### 10.4 Prueba 4: emulador con el lazo apagado y exportación

Con SW14 = 1 y SW0 = 0 (PWM encendido con $m = 0$) se exportó el buffer con las tres amplitudes.

| Amplitud | Pico de `iref` | `i` | `duty_q15` | Muestras recibidas |
|---|---|---|---|---|
| 0,2 A | ±199 mA | 0 ± 3 mA | 0 | 2000, `iref` sin saltos |
| 0,5 A | ±499 mA | 0 ± 3 mA | 0 | 2000, `iref` sin saltos |
| 1,0 A | ±999 mA | 0 ± 3 mA | 0 | 2000, `iref` sin saltos |

### 10.5 Prueba 5: lazo cerrado con la planta simulada

Con SW15 = 0, SW14 = 0 y referencia de 1,0 A pico, con el modelo de la carga de 10,3 Ω.

![seguimiento_carga_simulada](FIGURAS/seguimiento_carga_simulada.png)

*Figura 13: lazo cerrado con la planta simulada (datos de `FIGURAS/muestras_carga_simulada.csv`).*

| Pico de `iref` | Pico de `i` | Error RMS | Error máximo | $m$ pico |
|---|---|---|---|---|
| ±999 mA | ±1000 mA | 0,5 mA | 1 mA | 0,572 |

### 10.6 Prueba 6: lazo cerrado con el emulador RC

Con SW14 = 1, SW15 = 1, SW0 = 1 y 100 kHz, con la ganancia del emulador calculada para la carga de 10,3 Ω. El error se calculó sobre las 2000 muestras de cada exportación; la amplitud del nodo del RC se midió con el canal analógico del osciloscopio.

![lazo_cerrado_emulador](FIGURAS/lazo_cerrado_emulador.png)

*Figura 14: lazo cerrado con el emulador para las tres amplitudes (datos de `FIGURAS/muestras_20261116_121617.csv`, `_121658.csv` y `_121718.csv`).*

| Amplitud | Pico de `iref` | Pico de `i` | Error RMS | Error máximo | $m$ pico | Nodo RC (DC / amplitud) |
|---|---|---|---|---|---|---|
| 0,2 A | ±199 mA | +202 / −203 mA | 1,9 mA | 6 mA | 0,117 | 0,450 V / 0,061 V |
| 0,5 A | ±499 mA | ±503 mA | 1,9 mA | 7 mA | 0,293 | 0,451 V / 0,149 V |
| 1,0 A | ±999 mA | ±1002 mA | 2,0 mA | 7 mA | 0,586 | 0,450 V / 0,294 V |

![osc_nodo_rc](FIGURAS/osc_nodo_rc.png)

*Figura 15: tensión en el nodo del RC con el lazo cerrado, para 0,2 A, 0,5 A y 1,0 A pico (de izquierda a derecha), a 200 mV/div y 5 ms/div.*

### 10.7 Prueba 7: integración con el puente H

El puente tiene dos IR2110 y cuatro IRFZ44N, con el bus de 18 V y la carga de 5,0 Ω y 197 µH. Las cuatro salidas de la FPGA (JA1 a JA4) van a HIN y LIN de los drivers. En las capturas, CH1 y CH2 son los puntos medios de las dos piernas medidos contra la tierra de la fuente, a 10 V/div (CH1 a 5 V/div en la figura 17), y M es la resta CH1 − CH2, que es la tensión en la carga. Estas capturas se tomaron con un osciloscopio GW Instek GDS-1202B. En esta prueba el objetivo fue conseguir que el puente conmutara correctamente con las señales de la FPGA; el cierre del lazo con la corriente real se presenta en la prueba 8.

**Referencia con el Arduino.** Antes de conectar la FPGA, el equipo de potencia probó el puente con un Arduino Leonardo: SPWM unipolar a 20 kHz, tiempo muerto de 1 µs y $m = 0{,}5$ fijo, con la lógica del IR2110 (VDD) a 5 V.

![puente_arduino](FIGURAS/puente_arduino.jpg)

*Figura 16: puntos medios del puente con el Arduino (20 ms/div).*

Las dos piernas conmutan de 0 al bus. A 20 ms/div no se distinguen los pulsos de 20 kHz, pero la resta muestra una envolvente de 50 Hz de unos 11,2 V de amplitud. Con esta prueba sí hubo consumo de corriente.

**FPGA con VDD = 5 V.** Se conectó la FPGA en lugar del Arduino, dejando VDD de los IR2110 en los 5 V del Arduino. El lazo estaba en el modo normal.

![puente_fpga_vdd5](FIGURAS/puente_fpga_vdd5.jpg)

*Figura 17: puntos medios del puente con la FPGA y VDD = 5 V (20 ms/div).*

Las piernas no conmutan completas: CH1 no llega a la tensión del bus (8,4 V de amplitud) y la resta no forma la SPWM. Tampoco hubo consumo de corriente. A 20 ms/div el osciloscopio toma una muestra cada 20 µs, mayor que el periodo de conmutación de 10 µs, así que las frecuencias que muestra la pantalla (22,96 kHz y 121 kHz) no son una medición válida de la conmutación.

**FPGA con VDD = 3,3 V.** Se alimentó VDD de los IR2110 con los 3,3 V del Pmod y VSS con la tierra de la FPGA.

![puente_fpga_vdd33](FIGURAS/puente_fpga_vdd33.jpg)

*Figura 18: puntos medios del puente con la FPGA y VDD = 3,3 V (5 µs/div).*

En esta captura el programa estaba en el modo de lazo abierto (SW13 = 1, descrito abajo) con $m$ pequeño. Las dos piernas conmutan completas y limpias, con 16,8 V de amplitud y pulsos de unos 5 µs, que corresponden a 100 kHz. Las dos piernas tienen casi el mismo ancho de pulso y la resta queda casi en cero (1,68 V, que es el *ringing* de varios voltios que hay en cada flanco), lo que corresponde a $m$ cercano a cero.

El modo de lazo abierto (SW13) se agregó al programa para probar el puente sin depender del sensor ni del PR: $m$ es un seno de 50 Hz con amplitud fija de 0,1, 0,25 o 0,5, o un valor constante con SW12.

### 10.8 Prueba 8: lazo cerrado con la corriente real

Con el puente H conmutando correctamente, se conectó la salida del sensor de corriente ACS712 [13] al XADC y se cerró el lazo con la corriente real de la carga. La salida del ACS712 (66 mV/A, centrada en unos 2,5 V) pasa por un divisor de 8,2 kΩ y 2,0 kΩ con un capacitor de 22 nF antes de JXADC1, lo que deja la corriente cero cerca de 0,49 V y una sensibilidad de 12,94 mV/A en la entrada del XADC. El divisor y el capacitor forman además un filtro con $\tau \approx 35$ µs (1,61 kΩ · 22 nF), que atenúa el rizado de conmutación y atrasa la medición unos 0,6° a 50 Hz. El programa del repositorio es el que se usó en las pruebas 1 a 7 y ya funcionaba con el lazo cerrado. Para la prueba 8 solo se ajustó a la etapa de potencia real, sin cambiar su estructura. Las constantes del sensor en `control_isr.h` pasaron de los valores supuestos de 0,5 V y 0,4 V/A a 0,4938 V, medido con corriente cero, y 0,01294 V/A, que sale de la hoja de datos y del divisor (0,066 · 2,0 / 10,2). Además, con el lazo apagado la ISR promedia la lectura del XADC y la usa como cero del sensor. El tiempo muerto se dejó en 200 ns, igual que en la prueba 7. El PR, el PWM y el resto del programa no cambiaron.

Las condiciones fueron: bus de 18 V, VDD de los IR2110 en 3,3 V, carga de 5,0 Ω y 197 µH, PWM a 100 kHz con 200 ns de tiempo muerto, lazo en el modo normal con el PR discreto (SW0 = 1, SW15 = 1, SW14 = 0 y SW13 = 0) y referencia sinusoidal de 50 Hz. Se probaron tres amplitudes de referencia, 0,2 A, 0,5 A y 1,0 A pico. La corriente se registró de dos formas: con la exportación del buffer por la UART (BTNC), que da la corriente según el sensor del lazo, y con el osciloscopio sobre la resistencia de 4,7 Ω de la carga, que no pasa por el sensor ni por el XADC.

**Datos exportados.** Cada exportación tiene 2000 muestras: 100 ms, que son cinco periodos de la referencia. En las figuras 19 a 21 se graficaron esos datos: arriba la referencia `iref` y la corriente `i` que midió el XADC, y abajo el índice de modulación que calculó el PR (`duty_q15` / 32768).

![lazo_real_0p2A](FIGURAS/lazo_real_0p2A.png)

*Figura 19: datos exportados con referencia de 0,2 A pico (datos de `FIGURAS/muestras_20261123_184402.csv`).*

![lazo_real_0p5A](FIGURAS/lazo_real_0p5A.png)

*Figura 20: datos exportados con referencia de 0,5 A pico (datos de `FIGURAS/muestras_20261123_184309.csv`).*

![lazo_real_1p0A](FIGURAS/lazo_real_1p0A.png)

*Figura 21: datos exportados con referencia de 1,0 A pico (datos de `FIGURAS/muestras_20261123_184110.csv`).*

Los valores de la tabla se calcularon sobre las 2000 muestras de cada exportación. La amplitud y la fase de la fundamental se obtuvieron ajustando por mínimos cuadrados un seno de 50 Hz más una constante; la constante es la componente continua. El error es `i` − `iref`.

| Referencia | Fundamental de `iref` | Fundamental de `i` | Desfase | Componente continua de `i` | Error RMS | Error máximo | Extremos de `i` | $m$ (fundamental / máximo) |
|---|---|---|---|---|---|---|---|---|
| 0,2 A | 199,4 mA | 199,0 mA | < 0,1° | −22 mA | 51 mA | 225 mA | +405 / −330 mA | 0,090 / 0,107 |
| 0,5 A | 499,4 mA | 498,4 mA | < 0,1° | −70 mA | 86 mA | 350 mA | +557 / −668 mA | 0,180 / 0,198 |
| 1,0 A | 999,4 mA | 999,3 mA | < 0,1° | +31 mA | 67 mA | 270 mA | +1230 / −1128 mA | 0,331 / 0,356 |

**Medición con el osciloscopio.** Se midió la tensión en la resistencia de 4,7 Ω con una punta en cada extremo y la resta CH1 − CH2 del osciloscopio, y se dividió entre 4,7 Ω para obtener la corriente. Las figuras 22 a 24 muestran 60 ms, que son tres periodos.

![osc_corriente_0p2A](FIGURAS/Experimental_200mA.png)

*Figura 22: corriente en la resistencia de 4,7 Ω medida con el osciloscopio, con referencia de 0,2 A pico.*

![osc_corriente_0p5A](FIGURAS/Experimental_500mA.png)

*Figura 23: corriente en la resistencia de 4,7 Ω medida con el osciloscopio, con referencia de 0,5 A pico.*

![osc_corriente_1p0A](FIGURAS/Experimental_1000mA.png)

*Figura 24: corriente en la resistencia de 4,7 Ω medida con el osciloscopio, con referencia de 1,0 A pico.*

Lectura de las gráficas (valores aproximados):

| Referencia | Periodos en 60 ms | Pico positivo | Pico negativo | Observaciones |
|---|---|---|---|---|
| 0,2 A | 3 | ≈ 0,22 A | ≈ −0,22 A | Niveles separados unos 0,044 A |
| 0,5 A | 3 | ≈ 0,5 A | ≈ −0,5 A | Picos aislados que llegan a ±0,7 A, cerca de los máximos y mínimos |
| 1,0 A | 3 | ≈ 1,0 a 1,2 A | ≈ −1,0 a −1,2 A | Niveles más finos respecto a la amplitud |

---

## 11. Análisis de resultados

### 11.1 PWM

Las tres frecuencias medidas coinciden con las calculadas: como $P$ es entero (500, 625 y 400), el periodo es exacto y la única diferencia es la resolución del osciloscopio (80,03 kHz). El pulso alto con $m = 0$ también coincide con lo esperado: medio periodo menos el tiempo muerto, $5 - 0{,}2 = 4{,}8$ µs a 100 kHz, $6{,}25 - 0{,}2 = 6{,}05$ µs a 80 kHz y $4 - 0{,}2 = 3{,}8$ µs a 125 kHz. El tiempo muerto no cambia con la frecuencia porque se cuenta en ciclos de reloj (20 × 10 ns). Los 198 a 199 ns medidos son los 200 ns programados dentro de la resolución de la medición.

En la prueba 2, las dos piernas dan el mismo $m$ en las tres capturas, con diferencias de 0,01: cuando el pulso de una pierna se ensancha, el de la otra se angosta lo mismo. Eso por sí solo también pasaría en una modulación bipolar. Lo que muestra que es unipolar es que los pulsos altos de las dos piernas quedan centrados en el mismo instante, el valle donde sale el disparo (figura 8); en la bipolar el pulso alto de la pierna B quedaría centrado en el pico de la portadora. En ninguna captura hubo solape.

El disparo cae en el valle de la portadora, que es el centro del pulso alto de las dos piernas. Respecto al pulso que se ve en D0, el disparo queda unos 100 ns antes del centro: el tiempo muerto solo retrasa el encendido de la compuerta y no el apagado, así que el pulso visible está corrido medio tiempo muerto hacia la derecha, pero el valle no se mueve. Es el mismo efecto que revisa la prueba 9b de `tb_pwm_axi`, donde la diferencia entre los ciclos antes y después del disparo es igual al tiempo muerto.

### 11.2 Temporización

El periodo de 50,0 µs coincide con la carga del Timer: el contador cuenta `TLR + 2` ciclos por periodo, así que con 4998 son 5000 ciclos de 10 ns. La ISR ocupa el 21,5 % del periodo, así que queda un margen amplio para el programa principal y para cambios en el PR. Durante la exportación la ISR dura menos (8,57 µs) porque no guarda la muestra.

El contador del Timer da la variación de la entrada a la rutina: la latencia fue de 289 a 324 ciclos durante unos 5,6 min, 350 ns entre el mínimo y el máximo. Viene de la instrucción que estaba ejecutando el procesador y del despacho que hacen el controlador de interrupciones y el driver del Timer antes de llamar a `rutina_control()`. El tiempo entre dos entradas seguidas es el periodo más la diferencia de sus latencias, así que puede quedar entre 49,65 µs y 50,35 µs, una franja de 700 ns (1,4 % del periodo). Por eso en el pin de prueba, visto con un retardo de 50 µs, la franja de flancos ocupó toda la ventana de 500 ns del osciloscopio. Hay que tomar en cuenta que la medición con el osciloscopio se hizo con el lazo activo y la del contador con el lazo apagado. Su efecto en el control es acotado, porque el PWM solo carga `duty_ref` en el valle: el jitter no cambia el ancho de los pulsos, solo decide si un valor escrito cerca de un valle entra en ese valle o en el siguiente.

La fase entre el Timer y el PWM depende del momento en que se habilita el PWM. A 100 kHz y 80 kHz el periodo del lazo es un número entero de periodos de conmutación (5 y 4), así que esa fase queda fija mientras el PWM esté encendido. A 125 kHz son 6,25 periodos y la posición de la ISR respecto al disparo cambia de una interrupción a otra, por eso la antigüedad de la muestra varía entre 0 y 8 µs.

### 11.3 Lazo de control con planta simulada y emulador

Con la planta simulada, el $m$ pico de 0,572 es igual al teórico de la sección 7 para 1,0 A con la carga de 10,3 Ω, porque el modelo usa los mismos $R$ y $V_{dc}$. El error es de 0,5 mA RMS y 1 mA de máximo. La exportación guarda la corriente en mA enteros, así que el error real está por debajo de lo que se puede ver con estos datos; con una planta sin ruido el PR lleva el error casi a cero, como se espera de un regulador resonante a 50 Hz.

Con el emulador RC el error sube a unos 2 mA RMS y 7 mA de máximo en las tres amplitudes. Ese valor es del mismo orden que el ruido de ±3 mA que se midió con el lazo apagado, así que el error queda al nivel del ruido de la medición. Que el error no crezca con la amplitud indica que el PR no está saturando ni perdiendo seguimiento.

El $m$ pico escala aproximadamente en proporción a la referencia (0,117, 0,293 y 0,586), pero queda entre 2 y 3 % por encima del teórico (0,586 frente a 0,572 en 1,0 A). La ganancia del emulador se calculó con los valores nominales del RC y no se midieron los componentes ni la ganancia del XADC, así que no se sabe de dónde viene esa diferencia; el PR la compensa subiendo $m$ hasta que la corriente medida sigue la referencia. La amplitud de la sinusoide medida en el nodo con el osciloscopio queda a 4 a 7 mV de la que se calcula del $m$ exportado (0,49 V · $m$ pico), una diferencia del orden de la resolución del osciloscopio a 200 mV/div, así que la medición del osciloscopio y la exportación por UART concuerdan.

### 11.4 Exportación

En todas las exportaciones llegaron las 2000 muestras. El campo `n` lo pone el ciclo que envía, así que por sí solo no demuestra que no falten muestras; eso se revisó con `iref`, que se calcula en la ISR. En las tres exportaciones de la prueba 8 los 2000 valores de `iref` coinciden con un seno ideal de 50 Hz muestreado cada 50 µs, con diferencias de 1 mA por el truncamiento a mA enteros, y los cruces por cero de subida están separados exactamente 400 muestras (20 ms). Si el buffer hubiera perdido o repetido una muestra, o si se hubiera escrito durante el envío, habría un salto en la fase de `iref`. Que la ISR no se salta interrupciones lo respalda la prueba 3: su duración máxima queda muy por debajo de los 50 µs y el XADC dio 6 725 076 muestras nuevas en 6 725 077 interrupciones. La exportación son unas 2000 líneas de unos 20 caracteres, unos 40 kB a 115 200 baud (≈ 11,5 kB/s), así que dura unos 3,5 s. Durante ese tiempo el lazo sigue cada 50 µs, como mostró la medición de la ISR en la prueba 3.

### 11.5 Integración con el puente H

**Conmutación irregular con VDD = 5 V.** En el IR2110 los umbrales de las entradas HIN y LIN dependen de VDD. La hoja de datos [11] solo garantiza $V_{IH} = 9{,}5$ V mínimo con VDD = 15 V, alrededor del 63 % de VDD, y no da el umbral para otros valores. Si se supone que el umbral escala con VDD, con VDD = 5 V queda en unos 3,2 V, y las salidas de la FPGA son de 3,3 V: el driver reconocería el pulso solo a veces, según el ruido y la caída en los cables. Con el Arduino no pasaba porque su lógica es de 5 V. En la segunda prueba se cambiaron dos cosas a la vez: VDD pasó a 3,3 V y VSS se unió con la tierra de la FPGA, y con eso las piernas conmutaron bien (figura 18). Como no se probó cada cambio por separado, la falla pudo venir del umbral, de la referencia de tierra o de las dos cosas. VDD = 3,3 V queda en el borde del rango recomendado (según la versión de la hoja de datos el mínimo es VSS + 3 V o VSS + 5 V), así que esta solución funcionó en la práctica pero sin margen garantizado; con más margen habría que usar un traductor de nivel o VDD = 5 V con un umbral verificado.

Con VDD tomado de la FPGA hay que cuidar el orden de encendido: primero la Nexys 4 programada, después los 12 V de los drivers y al final el bus. Si la FPGA se apaga o se reprograma con el bus encendido, las entradas de los drivers quedan sin control, y el IR2110 no impide que HIN y LIN estén en alto a la vez.

**Las dos piernas en alto al mismo tiempo.** En la modulación unipolar las dos piernas usan la misma portadora con $+m$ y $-m$. Con $m = 0$ las dos tienen el mismo ciclo de trabajo, sus pulsos coinciden y $V_{AB} = 0$. Que conduzcan a la vez los dos transistores de arriba es el estado cero de la unipolar y no es un cortocircuito, porque están en piernas distintas. La tensión en la carga es la diferencia entre las piernas: pulsos de ancho $m\,T_{sw}/2$ en cada medio periodo. Con $m = 0{,}056$, que es lo que pide la referencia de 0,2 A con la carga de 5 Ω, esos pulsos son de unos 0,28 µs y no se distinguen a 5 µs/div. Por eso con $m$ cercano a cero casi no hay corriente aunque el puente conmute bien.

**Tiempo muerto con los IRFZ44N.** Con $R_G = 12\ \Omega$ la hoja de datos [12] da $t_{d(off)} = 44$ ns, $t_f = 45$ ns y $t_{d(on)} = 12$ ns. El transistor que se apaga tarda unos 89 ns y el que se enciende empieza a conducir a los 12 ns, así que el mínimo es de unos 77 ns. El IR2110 apaga unos 25 ns antes de lo que enciende (94 ns frente a 120 ns típicos), lo que suma a favor. Con estos valores típicos, los 200 ns del PWM dan más del doble del mínimo, siempre que la resistencia de compuerta sea de ese orden, y con ese valor el puente funcionó en las pruebas 7 y 8. Los tiempos de la hoja de datos son típicos y no incluyen el cableado del montaje; si con otra resistencia de compuerta o con más corriente hiciera falta más tiempo muerto, `dead_time` es un registro y se puede subir desde el software sin tocar el hardware.

**Comparación con el Arduino.**

| | Arduino | FPGA |
|---|---|---|
| Frecuencia de conmutación | 20 kHz | 100 kHz |
| Portadora | Diente de sierra | Triangular simétrica |
| Tiempo muerto | 1 µs | 200 ns |
| $m$ | 0,5 fijo | Del PR, o fijo en lazo abierto |
| VDD del IR2110 | 5 V | 3,3 V |

La pérdida de tensión por el tiempo muerto es de unos $2\,t_{muerto}\,f_{sw}\,V_{dc}$, y da lo mismo en los dos: $2 \cdot 1\ \mu s \cdot 20\ \text{kHz} \cdot 18\ \text{V} = 2 \cdot 200\ \text{ns} \cdot 100\ \text{kHz} \cdot 18\ \text{V} \approx 0{,}72$ V. A 0,2 A con 5 Ω solo se necesita 1 V, así que en lazo abierto la corriente a esa amplitud debería salir mucho menor que la referencia y deformada en los cruces por cero. Es un valor máximo, porque supone que todo el tiempo muerto se pierde en cada flanco. En lazo cerrado el PR compensa la pérdida subiendo $m$ (sección 11.6).

***Ringing* en los flancos.** Los picos en cada conmutación vienen de la inductancia de los cables del puente, que resuena con las capacitancias de los transistores. Con 18 V no ponen en riesgo a los IRFZ44N (55 V), pero agregan ruido a la medición.

### 11.6 Lazo cerrado con la corriente real

En las tres amplitudes la fundamental de la corriente medida quedó dentro del 0,3 % de la referencia (199,0 frente a 199,4 mA, 498,4 frente a 499,4 mA y 999,3 frente a 999,4 mA) y con menos de 0,1° de desfase. Es lo que se espera del PR: su ganancia en 50 Hz es muy alta, así que en régimen lleva a cero el error de la componente de 50 Hz. Con esto la cadena PWM → puente H → sensor → XADC → ISR → PR → `duty_ref` funcionó con la etapa de potencia conectada. Los datos exportados son la corriente según el sensor del lazo, así que por sí solos no detectarían un error de calibración del sensor. Para eso sirve la medición con el osciloscopio, que no depende del sensor: sus picos, de unos 0,22, 0,5 y 1,0 a 1,2 A, quedan cerca de la referencia, con escalones de 0,044 A en 0,2 A y algo de ruido, de modo que la calibración del sensor no tiene un error grande. Con esa lectura visual no se puede verificar el 0,3 % de la fundamental, que sale solo de los datos del sensor. Tampoco el desfase de menos de 0,1° es el de la corriente real: el filtro del sensor atrasa la medición unos 0,6°.

El error RMS, de 51 a 86 mA, no viene de la fundamental sino de dos partes. La primera es una componente continua de −22, −70 y +31 mA, que cambia de una exportación a otra. En continua el PR solo tiene la ganancia $K_p$, y con $R = 5$ Ω la ganancia del lazo es $K_p/R = 0{,}4$, así que la continua casi no se corrige. El $m$ exportado lo muestra: su valor medio es +0,0075 con −70 mA y −0,0034 con +31 mA, que es $K_p \cdot i_{dc}/V_{dc}$ con el signo contrario. No se midió de dónde viene esa continua. En la prueba 8 el programa vuelve a medir el cero del sensor cada vez que el lazo está apagado, así que no es un offset que quedó de antes; puede ser una continua real en la corriente o un corrimiento del cero del sensor cuando el puente empieza a conmutar. En el segundo caso el lazo, al responder a una continua que no existe, mete en la carga una continua real de signo contrario, de unos 27 mA para el caso de −70 mA. La salida del ACS712 depende de su alimentación de 5 V, y no se midió si esa tensión cambia cuando el puente conmuta. En la entrada del XADC 70 mA son menos de 1 mV, unos cuatro pasos, pero equivalen al 14 % de la amplitud con 0,5 A.

La segunda parte es lo que queda después de quitar la fundamental y la continua: de 46 a 59 mA RMS. Una parte son armónicos de 50 Hz (del 2 al 10 suman 15, 22 y 34 mA RMS en 0,2, 0,5 y 1,0 A), que crecen con la amplitud; el resto, de 43 a 48 mA RMS, casi no cambia con la amplitud y es ruido de la medición. El ruido se ve como escalones y como valores aislados. En los datos exportados los escalones vienen de la resolución de la cadena: con 12,94 mV/A y un paso del XADC de 0,244 mV (1 V / 4096), cada paso equivale a unos 19 mA, y los niveles de `i` en las exportaciones están separados justo por ese valor. Se notan más en 0,2 A porque ahí el paso es una fracción mayor de la amplitud. Las gráficas del osciloscopio también tienen escalones, pero vienen de la resolución vertical del osciloscopio en la escala usada y no del XADC; por eso su separación (unos 0,044 A en 0,2 A) es distinta de los 19 mA de los datos exportados. La resolución del PWM es algo más fina: el umbral se compara con la portadora en ciclos de reloj, así que a 100 kHz el paso mínimo es $\Delta m = 2/P = 0{,}004$, que cambia la tensión media en la carga en unos 72 mV, unos 14 mA con 5 Ω.

Los valores aislados son de una sola muestra. Los extremos de `i` llegan a +405 mA con 0,2 A, −668 mA con 0,5 A y +1230 mA con 1,0 A, y los errores más grandes, de 225, 350 y 270 mA, aparecen en otras muestras aisladas que caen hacia abajo, lejos de los picos. No siguen la forma de la señal y son compatibles con ruido de conmutación en la medición, que el muestreo en el valle reduce pero no elimina. Su efecto en el control es pequeño: un error de 0,35 A sube la parte proporcional en $K_p \cdot 0{,}35 = 0{,}7$ V, que equivalen a $\Delta m \approx 0{,}04$ durante un periodo del lazo, y a la parte resonante le suma unos $b_0 \cdot 0{,}35 \approx 0{,}03$ V, que quedan como una pequeña oscilación de 50 Hz hasta que el lazo la corrige. En la curva de $m$ de las figuras 19 a 21 se ven como picos pequeños sobre la sinusoide. En la gráfica del osciloscopio de 0,5 A (figura 23) también aparecen picos aislados de hasta ±0,7 A, una vez por periodo cerca de los máximos y mínimos; con estos datos no se puede saber si son corriente real o ruido de conmutación en la medición del osciloscopio. La protección de 1,5 A revisa cada muestra, así que con 1,0 A el margen frente al mayor de esos valores fue de unos 0,27 A.

El índice de modulación que calculó el PR (fundamental de 0,090, 0,180 y 0,331) es mayor que el de la carga ideal de 5,0 Ω (0,056, 0,139 y 0,278, sección 7). La diferencia, de 0,03 a 0,05, es la tensión extra que el PR tuvo que dar por el tiempo muerto y por las caídas del circuito que no están en el modelo, como los transistores y los cables. En tensión son de 0,6 a 0,95 V, del mismo orden que la estimación máxima de 0,72 V de la sección 11.5 ($\Delta m \approx 0{,}04$). Como la diferencia crece un poco con la corriente, también hay caídas que dependen de ella, pero con estos datos no se puede separar cuánto se debe a cada causa. En todos los casos $|m|$ quedó por debajo de 0,36, lejos del límite del software (0,8) y del hardware (0,95), así que el PR no saturó.

El PR usó los mismos coeficientes que en las pruebas con la planta simulada y con el emulador; para la prueba 8 solo cambiaron las constantes del sensor y el ajuste de su cero. El error ya no se puede comparar con los 2 mA del emulador porque el sensor real tiene más ruido y menos resolución que el nodo del RC, pero la fundamental siguió la referencia en las tres amplitudes.

### 11.7 Correspondencia con el plan de validación

| Prueba del plan (diseño, sección 11) | Dónde está el resultado |
|---|---|
| 1. `tb_pwm_core` en RTL | Sección 8.1: 60 pruebas, 0 fallas |
| 2. `tb_pwm_axi` en RTL | Sección 8.1: 37 pruebas, 0 fallas |
| 3. `tb_pwm_axi` post-implementación | Sección 8.2: 37 pruebas, 0 fallas |
| 4. Síntesis e implementación | Sección 9 |
| 5. Registros del PWM desde C | Pruebas 1 y 2: las tres frecuencias, el tiempo muerto y el apagado se configuraron escribiendo los registros desde C; `run=` en la terminal cambia con SW0 |
| 6. Compuertas, tiempo muerto y disparo en los pines | Pruebas 1 y 2 |
| 7. XADC con los dos disparos | Con `pwm_trigger_o`: pruebas 4, 6 y 8. Por software, con el PWM apagado: en la terminal, 6 725 076 muestras nuevas en 6 725 077 interrupciones, y `sin_dato = 1`, que es la primera interrupción después del arranque |
| 8. Lazo cerrado con planta simulada y emulador | Pruebas 5 y 6 |
| 9. Exportación por UART | Pruebas 4 a 6 y 8 |
| 10. Periodo, duración de la ISR y jitter | Prueba 3 |
| 11. Integración con la etapa de potencia | Pruebas 7 y 8: el puente conmuta con la FPGA y el lazo se cerró con la corriente real del sensor |

---

## 12. Problemas encontrados y soluciones

| Problema | Tipo | Causa | Solución |
|---|---|---|---|
| La prueba 9b de `tb_pwm_axi` fallaba en xsim (229 ciclos antes del disparo y 250 después) aunque el PWM estaba bien | Testbench | El conteo se hacía en un bloque aparte que corría en el mismo flanco que la tarea que espera el disparo, y el resultado dependía del orden de ejecución del simulador | Se cuentan los ciclos dentro de la tarea `medir_centro`, sin contar el ciclo del disparo. Pasa 37 de 37 en RTL y post-implementación |
| Con la FPGA las piernas del puente conmutaban a medias y sin frecuencia estable | Integración | VDD de los IR2110 estaba en 5 V, con un umbral de entrada estimado en unos 3,2 V frente a salidas de 3,3 V, y VSS no estaba unido con la tierra de la FPGA | VDD se alimentó con los 3,3 V del Pmod y VSS con la tierra de la FPGA. Las piernas conmutaron completas (figura 18) |
| Con el puente conmutando bien no había corriente en la carga | Interpretación | Con $m$ cercano a cero las dos piernas tienen el mismo pulso (estado cero de la unipolar) y la tensión en la carga son pulsos de menos de 0,3 µs | Se agregó el modo de lazo abierto (SW13 y SW12) para fijar $m$ sin depender del sensor ni del PR, y después se cerró el lazo con la corriente real |
| El lazo no se podía cerrar con la corriente real | Integración | La salida del ACS712 (centrada en 2,5 V) no estaba en el rango de 0 a 1 V del XADC | Se agregó un divisor de 8,2 kΩ y 2,0 kΩ con 22 nF, en el programa de la prueba 8 se ajustaron las constantes del sensor a 0,4938 V y 0,01294 V/A, y se cerró el lazo |
| La carga cambió de 10,3 Ω a 5,0 Ω | Integración | Cambio en la etapa de potencia | Se recalcularon el modelo de la planta simulada, la ganancia del emulador y los $m$ esperados. Las pruebas 5 y 6 quedan con la carga anterior (sección 7) |
| La corriente medida tiene escalones, valores aislados y una componente continua | Medición | Resolución de la cadena sensor, acondicionamiento y XADC, y ruido de conmutación; el origen de la continua no se midió | No impide el seguimiento de la fundamental (sección 11.6); se dejan como mejoras el filtrado de la medición y averiguar de dónde viene la continua |

---

## 13. Análisis crítico

**Logros.**

- El sistema MicroBlaze V con todos sus periféricos funciona en la tarjeta a 100 MHz, con timing cerrado.
- El PWM genera las tres frecuencias exactas, el tiempo muerto programado sin solape y el disparo en el valle, verificado en simulación RTL, post-implementación y con el osciloscopio.
- La cadena digital completa (PWM → RC → XADC → ISR → PR → `duty_ref` → UART) funciona en lazo cerrado con un error del orden del ruido de la medición.
- El lazo de corriente se cerró con la etapa de potencia real: con el puente H a 18 V y la carga de 5,0 Ω, la fundamental de la corriente medida siguió las referencias de 0,2 A, 0,5 A y 1,0 A pico dentro del 0,3 % y en fase.
- La exportación no afecta el lazo y entrega bloques completos de 2000 muestras.

**Limitaciones.**

- La medición de la corriente real tiene pasos de unos 19 mA, un ruido de 43 a 48 mA RMS, armónicos de 15 a 34 mA RMS y valores aislados con errores de hasta 0,35 A, que se notan sobre todo con 0,2 A. También tiene una componente continua de hasta 70 mA que el PR no corrige.
- La fundamental, el error y el desfase se calcularon solo con los datos del sensor del lazo. La medición independiente con el osciloscopio se evaluó leyendo las gráficas, con una resolución de unos 0,04 A en 0,2 A. Con el lazo cerrado no se midieron las compuertas.
- No se probaron cambios de la amplitud de la referencia ni de la carga con el lazo funcionando, así que no hay datos del transitorio.
- Las pruebas con la planta simulada y con el emulador (5 y 6) se hicieron con la carga inicial de 10,3 Ω.
- El jitter se midió con persistencia en una ventana de 500 ns que quedó llena, así que el valor es una cota inferior. La latencia con el contador se midió con el lazo apagado.
- Los reportes de recursos y timing del sistema completo son de una implementación anterior a la versión final del RTL del PWM (sección 9).
- Mientras se exporta, la ISR no guarda muestras. El bloque exportado es continuo, pero los 3,5 s de la exportación no quedan registrados.
- El PR no tiene antiwindup: si $m$ se satura, la parte resonante sigue integrando.
- En el modo emulador el PWM queda encendido con $m = 0$ aun con el lazo apagado, porque el RC necesita la conmutación para dar el offset. Por eso ese modo no se usa con el puente conectado.

**Mejoras posibles.**

- Filtrar o promediar la medición de corriente, o mejorar la ganancia del acondicionamiento, para reducir los escalones y los valores aislados.
- Agregar al PWM una entrada de falla o un *watchdog* que apague las compuertas si el software deja de escribir `duty_ref`.
- Agregar antiwindup al PR.
- Medir la latencia con el lazo activo y durante más tiempo, y guardar `lat_min` y `lat_max` junto con cada exportación.
- Disparar la captura del buffer un tiempo fijo después de un evento (un cambio de amplitud o de carga), para que el transitorio quede dentro de la ventana.
- Medir la continua de la corriente con el osciloscopio para saber si es real o de la medición y, si es real, acordar con el diseño del controlador cómo corregirla.
- Repetir las pruebas 5 y 6 con la carga final, y calcular la fundamental también sobre los datos del osciloscopio para compararla con la del sensor.

---

## 14. Conclusiones

- El MicroBlaze V, el PWM propio, el XADC sincronizado, el PR discreto y la exportación por UART funcionaron juntos sobre el puente H, con la corriente de la carga siguiendo la referencia sinusoidal de 50 Hz.
- Dividir el trabajo entre hardware y software según los tiempos que necesita cada parte funcionó: el PWM y el XADC resuelven lo que pasa en nanosegundos, y al procesador le quedan unos 35 µs libres de cada periodo de 50 µs, con la latencia y la duración máximas medidas con el lazo apagado.
- Cargar los registros del PWM solo en el valle hace que el jitter de la ISR no deforme los pulsos; solo puede atrasar un periodo de conmutación la aplicación de un valor nuevo.
- Sincronizar el XADC con el valle de la portadora da muestras en el centro del pulso, lejos de los flancos. Con el emulador, el error del lazo quedó al nivel del ruido de la medición, y con la corriente real la fundamental siguió la referencia dentro del 0,3 %.
- El periodo, el ancho de pulso y el tiempo muerto medidos en la tarjeta coincidieron con los calculados. En la prueba 2 las dos piernas dieron el mismo $m$, y en la prueba 6 el $m$ quedó entre 2 y 3 % por encima del teórico y la exportación por UART concordó con el osciloscopio.
- El emulador RC permitió probar la cadena completa antes de tener la etapa de potencia. El PR verificado con la planta simulada y con el emulador funcionó con la planta real con los mismos coeficientes. La lección es preparar desde el inicio una forma de probar el sistema sin depender de la otra parte del proyecto.
- En la integración, el problema principal fue la interfaz eléctrica con el driver y no el PWM: con VDD = 5 V las piernas conmutaban a medias, y la falla desapareció al alimentar VDD con 3,3 V y unir VSS con la tierra de la FPGA. Comparar con la prueba del Arduino ayudó a ubicar la falla. Conviene revisar los niveles lógicos y las tierras entre las dos partes antes de energizar.
- La resolución, el ruido y el cero de la medición de corriente limitan la precisión con corrientes pequeñas, y son el punto que más conviene mejorar, junto con el antiwindup y el *watchdog* del PWM.

---

## 15. Referencias

[1] D. M. Harris y S. L. Harris, *Digital Design and Computer Architecture: RISC-V Edition*. Cambridge, MA, EE. UU.: Morgan Kaufmann, 2022.

[2] P. P. Chu, *FPGA Prototyping by SystemVerilog Examples: Xilinx MicroBlaze MCS SoC Edition*. Hoboken, NJ, EE. UU.: Wiley, 2018.

[3] AMD, *MicroBlaze V Embedded Design Tutorial*, UG1711.

[4] AMD, *MicroBlaze V Processor Reference Guide*, UG1629.

[5] AMD, *Vivado Design Suite: AXI Reference Guide*, UG1037.

[6] ARM, *AMBA AXI and ACE Protocol Specification*, IHI 0022.

[7] AMD, *7 Series FPGAs and Zynq-7000 SoC XADC Dual 12-Bit 1 MSPS Analog-to-Digital Converter User Guide*, UG480.

[8] AMD, *AXI Timer LogiCORE IP Product Guide*, PG079.

[9] AMD, *Vitis Unified Software Platform Documentation*, UG1416.

[10] D. W. Hart, *Power Electronics*. Nueva York, NY, EE. UU.: McGraw-Hill, 2011.

[11] International Rectifier, *IR2110(S)/IR2113(S) High and Low Side Driver*, hoja de datos.

[12] International Rectifier, *IRFZ44N HEXFET Power MOSFET*, hoja de datos.

[13] Allegro MicroSystems, *ACS712: Fully Integrated, Hall-Effect-Based Linear Current Sensor IC*, hoja de datos.

[14] R. Teodorescu, F. Blaabjerg, M. Liserre y P. C. Loh, "Proportional-resonant controllers and filters for grid-connected voltage-source converters," *IEE Proceedings - Electric Power Applications*, vol. 153, n.º 5, pp. 750-762, 2006.

[15] M. A. Hernández R., "Diseño modular," Laboratorio de Diseño Lógico, Escuela de Ingeniería Electrónica, Instituto Tecnológico de Costa Rica, Cartago, Costa Rica, s.f.

[16] Digilent Inc., *Nexys 4 FPGA Board Reference Manual*. [En línea]. Disponible: https://digilent.com/reference/programmable-logic/nexys-4/reference-manual

[17] AMD, *XADC Wizard LogiCORE IP Product Guide*, PG091.
