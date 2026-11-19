// main.c
// Aplicacion de control de corriente del Proyecto 4.
//
// El lazo de control esta en control_isr.c. Aqui se leen los switches y
// botones cada 10 ms:
//   SW0        habilita el lazo de control (al bajarlo se borra una falla)
//   SW2..SW1   freq_sel del PWM (00 = 100 kHz, 01 = 80 kHz, 10 = 125 kHz)
//   SW4..SW3   amplitud de la referencia (00 = 0,2 A, 01 = 0,5 A, 1x = 1,0 A)
//   SW15       1 = corriente del ADC, 0 = planta simulada (sin etapa de potencia)
//   SW14       emulador RC en el XADC (solo sin la etapa de potencia)
//   SW13       lazo abierto: m = seno de amplitud fija, sin el PR
//              (SW4..SW3 da 0,1 / 0,25 / 0,5)
//   SW12       con SW13, m constante en vez de seno
//   BTNC       exporta por UART el buffer de muestras en texto tipo CSV
//   LED0 lazo habilitado, LED1 falla, LED2 exportando, LED3 modo emulador,
//   LED4 lazo abierto
// Cada segundo se imprimen los tiempos de la ISR, el bit running del PWM y
// la lectura del ADC.

#include "xparameters.h"
#include "xgpio.h"
#include "xil_printf.h"
#include "sleep.h"
#include "pwm_driver.h"
#include "control_isr.h"

#define GPIO_LEDS_SW_BASE  XPAR_AXI_GPIO_0_BASEADDR
#define GPIO_BTN_BASE      XPAR_AXI_GPIO_1_BASEADDR
#define PWM_BASE_MAIN      XPAR_PWM_0_BASEADDR

#define CANAL_LEDS      1
#define CANAL_SWITCHES  2
#define CANAL_BOTONES   1
#define BTN_CENTRO      0x01U

static XGpio gpio_leds_sw;
static XGpio gpio_btn;

// manda el buffer por UART, de la muestra mas vieja a la mas nueva.
// Mientras tanto la ISR sigue controlando pero no guarda muestras.
// Como esto dura unos segundos, se sigue revisando SW0 para que el lazo
// se pueda apagar aunque se este exportando
static void exportar(void)
{
    u32 inicio, cantidad, n, pos;

    control_congelado = 1;

    if (control_lleno) {
        inicio = control_indice;          // la mas vieja es la que sigue
        cantidad = CONTROL_N_BUFFER;
    } else {
        inicio = 0;
        cantidad = control_indice;
    }

    xil_printf("INICIO,Ts_us=%d,N=%d\r\n", CONTROL_TS_US, cantidad);
    xil_printf("n,iref_mA,i_mA,duty_q15\r\n");
    for (n = 0; n < cantidad; n++) {
        pos = inicio + n;
        if (pos >= CONTROL_N_BUFFER)
            pos -= CONTROL_N_BUFFER;
        xil_printf("%d,%d,%d,%d\r\n", n,
                   control_buffer[pos].iref_ma,
                   control_buffer[pos].i_ma,
                   control_buffer[pos].duty_q15);

        // si se baja SW0 a media exportacion, el lazo se apaga igual
        if ((XGpio_DiscreteRead(&gpio_leds_sw, CANAL_SWITCHES) & 0x1U) == 0U)
            control_habilitado = 0;
    }
    xil_printf("FIN\r\n");

    // el buffer empieza de cero otra vez
    control_indice = 0;
    control_lleno = 0;
    control_congelado = 0;
}

int main(void)
{
    u32 sw, btn;
    u32 presionado = 0, ya_exportado = 0;
    u32 vueltas = 0;
    u32 leds;
    u32 sw0_antes = 0;
    int estado;

    xil_printf("\r\nProyecto 4 - control de corriente\r\n");
    xil_printf("SW0 lazo, SW2..1 frecuencia, SW4..3 amplitud, SW15 ADC/simulada, SW14 emulador, SW13 lazo abierto, SW12 m constante, BTNC exportar\r\n");

    if (XGpio_Initialize(&gpio_leds_sw, GPIO_LEDS_SW_BASE) != XST_SUCCESS ||
        XGpio_Initialize(&gpio_btn, GPIO_BTN_BASE) != XST_SUCCESS) {
        xil_printf("Error al iniciar los GPIO\r\n");
        return -1;
    }
    XGpio_SetDataDirection(&gpio_leds_sw, CANAL_LEDS, 0x0000);

    estado = control_isr_iniciar();
    if (estado != 0) {
        xil_printf("Error al iniciar el control (%d)\r\n", estado);
        return -1;
    }

    while (1) {
        sw  = XGpio_DiscreteRead(&gpio_leds_sw, CANAL_SWITCHES);
        btn = XGpio_DiscreteRead(&gpio_btn, CANAL_BOTONES);

        // SW0: habilita el lazo. Al bajarlo se borra la falla
        control_habilitado = sw & 0x1U;
        if (!control_habilitado)
            control_falla = 0;

        // al subir SW0 se reinician los tiempos medidos, asi isr_max y lat
        // corresponden solo a la operacion con el lazo activo
        if (control_habilitado && !sw0_antes)
            control_isr_reiniciar_tiempos();
        sw0_antes = control_habilitado;

        control_freq_sel = (sw >> 1) & 0x3U;
        control_usar_adc = (sw >> 15) & 0x1U;
        control_emulador = (sw >> 14) & 0x1U;
        control_lazo_abierto = (sw >> 13) & 0x1U;
        control_m_constante = (sw >> 12) & 0x1U;

        switch ((sw >> 3) & 0x3U) {
            case 0:  control_amplitud = 0.2f; break;
            case 1:  control_amplitud = 0.5f; break;
            default: control_amplitud = 1.0f; break;
        }
        // en lazo abierto m es la mitad de la amplitud: 0,1 / 0,25 / 0,5
        control_m_fijo = 0.5f * control_amplitud;

        // antirrebote del boton: 3 lecturas seguidas (30 ms) y se exporta
        // una sola vez por cada presion
        if (btn & BTN_CENTRO) {
            if (presionado < 3)
                presionado++;
        } else {
            presionado = 0;
            ya_exportado = 0;
        }

        leds = (control_habilitado ? 0x1U : 0U) | (control_falla ? 0x2U : 0U) |
               (control_emulador ? 0x8U : 0U) | (control_lazo_abierto ? 0x10U : 0U);
        XGpio_DiscreteWrite(&gpio_leds_sw, CANAL_LEDS, leds);

        if (presionado >= 3 && !ya_exportado) {
            XGpio_DiscreteWrite(&gpio_leds_sw, CANAL_LEDS, leds | 0x4U);
            exportar();
            ya_exportado = 1;
        }

        // cada segundo se imprimen los tiempos de la ISR (en ciclos de 10 ns)
        vueltas++;
        if (vueltas >= 100) {
            vueltas = 0;
            xil_printf("int=%d isr_max=%d lat=%d..%d falla=%d run=%d | %s adc=%d mV nuevos=%d sin_dato=%d",
                       control_interrupciones, control_isr_max,
                       control_lat_min, control_lat_max, control_falla,
                       pwm_running(PWM_BASE_MAIN),
                       control_lazo_abierto ? (control_m_constante ? "M_FIJO" : "ABIERTO") :
                       (control_emulador ? "EMU" : (control_usar_adc ? "ADC" : "SIM")),
                       control_adc_mv, control_adc_nuevos, control_adc_sin_dato);
            if (control_emulador)
                xil_printf(" offset=%d mV", control_emu_offset_mv);
            xil_printf("\r\n");
        }

        usleep(10000);
    }

    return 0;
}
