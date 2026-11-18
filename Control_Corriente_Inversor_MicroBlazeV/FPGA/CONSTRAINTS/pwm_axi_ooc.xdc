# pwm_axi_ooc.xdc
# Se usa solo cuando pwm_axi es el top, para la simulacion
# post-implementacion del PWM. No va en el proyecto del sistema.

# reloj de 100 MHz en la entrada del bus AXI
create_clock -name clk -period 10.000 [get_ports S_AXI_ACLK]
