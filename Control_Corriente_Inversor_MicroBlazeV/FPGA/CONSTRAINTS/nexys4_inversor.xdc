## nexys4_inversor.xdc
## Pines de la Nexys 4 (rev B) para el sistema MicroBlaze V del Proyecto 4.
## Los nombres tienen que ser iguales a los puertos de sistema_microblaze_wrapper.

## Reloj de 100 MHz de la tarjeta
set_property PACKAGE_PIN E3 [get_ports clk100_i]
set_property IOSTANDARD LVCMOS33 [get_ports clk100_i]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports clk100_i]

## Boton CPU RESET (activo en bajo)
set_property PACKAGE_PIN C12 [get_ports cpu_resetn_i]
set_property IOSTANDARD LVCMOS33 [get_ports cpu_resetn_i]

## UART (puente USB-UART)
set_property PACKAGE_PIN C4 [get_ports uart_rxd]
set_property PACKAGE_PIN D4 [get_ports uart_txd]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_rxd uart_txd}]

## Botones: [0] centro, [1] arriba, [2] izquierda, [3] derecha, [4] abajo
set_property PACKAGE_PIN E16 [get_ports {buttons_tri_i[0]}]
set_property PACKAGE_PIN F15 [get_ports {buttons_tri_i[1]}]
set_property PACKAGE_PIN T16 [get_ports {buttons_tri_i[2]}]
set_property PACKAGE_PIN R10 [get_ports {buttons_tri_i[3]}]
set_property PACKAGE_PIN V10 [get_ports {buttons_tri_i[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {buttons_tri_i[*]}]

## Switches
set_property PACKAGE_PIN U9 [get_ports {switches_tri_i[0]}]
set_property PACKAGE_PIN U8 [get_ports {switches_tri_i[1]}]
set_property PACKAGE_PIN R7 [get_ports {switches_tri_i[2]}]
set_property PACKAGE_PIN R6 [get_ports {switches_tri_i[3]}]
set_property PACKAGE_PIN R5 [get_ports {switches_tri_i[4]}]
set_property PACKAGE_PIN V7 [get_ports {switches_tri_i[5]}]
set_property PACKAGE_PIN V6 [get_ports {switches_tri_i[6]}]
set_property PACKAGE_PIN V5 [get_ports {switches_tri_i[7]}]
set_property PACKAGE_PIN U4 [get_ports {switches_tri_i[8]}]
set_property PACKAGE_PIN V2 [get_ports {switches_tri_i[9]}]
set_property PACKAGE_PIN U2 [get_ports {switches_tri_i[10]}]
set_property PACKAGE_PIN T3 [get_ports {switches_tri_i[11]}]
set_property PACKAGE_PIN T1 [get_ports {switches_tri_i[12]}]
set_property PACKAGE_PIN R3 [get_ports {switches_tri_i[13]}]
set_property PACKAGE_PIN P3 [get_ports {switches_tri_i[14]}]
set_property PACKAGE_PIN P4 [get_ports {switches_tri_i[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {switches_tri_i[*]}]

## LEDs
set_property PACKAGE_PIN T8 [get_ports {leds_tri_o[0]}]
set_property PACKAGE_PIN V9 [get_ports {leds_tri_o[1]}]
set_property PACKAGE_PIN R8 [get_ports {leds_tri_o[2]}]
set_property PACKAGE_PIN T6 [get_ports {leds_tri_o[3]}]
set_property PACKAGE_PIN T5 [get_ports {leds_tri_o[4]}]
set_property PACKAGE_PIN T4 [get_ports {leds_tri_o[5]}]
set_property PACKAGE_PIN U7 [get_ports {leds_tri_o[6]}]
set_property PACKAGE_PIN U6 [get_ports {leds_tri_o[7]}]
set_property PACKAGE_PIN V4 [get_ports {leds_tri_o[8]}]
set_property PACKAGE_PIN U3 [get_ports {leds_tri_o[9]}]
set_property PACKAGE_PIN V1 [get_ports {leds_tri_o[10]}]
set_property PACKAGE_PIN R1 [get_ports {leds_tri_o[11]}]
set_property PACKAGE_PIN P5 [get_ports {leds_tri_o[12]}]
set_property PACKAGE_PIN U1 [get_ports {leds_tri_o[13]}]
set_property PACKAGE_PIN R2 [get_ports {leds_tri_o[14]}]
set_property PACKAGE_PIN P2 [get_ports {leds_tri_o[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds_tri_o[*]}]

## Pmod JA: salidas del PWM hacia los drivers del puente H y senales para
## el osciloscopio (pines segun el master XDC de la Nexys 4)
##   JA1 gate_a_h_o   JA2 gate_a_l_o   JA3 gate_b_h_o   JA4 gate_b_l_o
##   JA7 pwm_trigger_o   JA8 pin de prueba del lazo (prueba_tri_o)
set_property PACKAGE_PIN B13 [get_ports gate_a_h_o]
set_property PACKAGE_PIN F14 [get_ports gate_a_l_o]
set_property PACKAGE_PIN D17 [get_ports gate_b_h_o]
set_property PACKAGE_PIN E17 [get_ports gate_b_l_o]
set_property PACKAGE_PIN G13 [get_ports pwm_trigger_o]
set_property PACKAGE_PIN C17 [get_ports {prueba_tri_o*}]
set_property IOSTANDARD LVCMOS33 [get_ports {gate_a_h_o gate_a_l_o gate_b_h_o gate_b_l_o pwm_trigger_o prueba_tri_o*}]

## JXADC: entrada analogica del XADC, canal AD3 (pin 1 positivo, pin 7 negativo).
## Rango de entrada del XADC: 0 a 1 V (unipolar).
set_property PACKAGE_PIN A13 [get_ports vaux3_v_p]
set_property PACKAGE_PIN A14 [get_ports vaux3_v_n]
set_property IOSTANDARD LVCMOS33 [get_ports {vaux3_v_p vaux3_v_n}]

## Configuracion del banco
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
