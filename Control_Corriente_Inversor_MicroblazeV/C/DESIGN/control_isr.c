// control_isr.c
// Rutina de interrupcion del lazo de control. Cada Ts lee la corriente,
// calcula el PR, escribe duty_ref y guarda la muestra en el buffer.
// La corriente puede salir del ADC o de un modelo de la carga RL, para
// probar sin la etapa de potencia (se escoge con SW15).
// Con SW14 se usa el emulador: un circuito RC en el XADC que hace de carga.
// En ese modo el PWM queda encendido aunque el lazo este apagado, por eso
// no se usa con el puente H conectado.

#include "xparameters.h"
#include "xtmrctr.h"
#include "xinterrupt_wrap.h"
#include "xil_io.h"
#include "pwm_driver.h"
#include "adc_driver.h"
#include "control_pr.h"
#include "control_isr.h"

// direcciones base (revisar nombres en xparameters.h)
#define PWM_BASE        XPAR_PWM_0_BASEADDR
#define TIMER_BASE      XPAR_AXI_TIMER_0_BASEADDR
#define ADC_BASE        XPAR_XADC_WIZ_0_BASEADDR
#define GPIO1_BASE      XPAR_AXI_GPIO_1_BASEADDR
#define GPIO2_DATA      0x8U        // registro de datos del canal 2 del AXI GPIO

#define CONTADOR_TIMER  0
// el AXI Timer cuenta TLR + 2 ciclos por periodo
#define TIMER_CARGA     ((XPAR_AXI_TIMER_0_CLOCK_FREQUENCY / 1000000U) * CONTROL_TS_US - 2U)

// ---------------------------------------------------------------
// Variables compartidas
// ---------------------------------------------------------------
volatile u32   control_habilitado = 0;
volatile u32   control_falla = 0;
volatile u32   control_congelado = 0;
volatile float control_amplitud = 0.2f;
volatile u32   control_freq_sel = PWM_FREQ_100KHZ;
volatile u32   control_indice = 0;
volatile u32   control_lleno = 0;
volatile u32   control_interrupciones = 0;
volatile u32   control_isr_max = 0;
volatile u32   control_lat_min = 0xFFFFFFFFU;
volatile u32   control_lat_max = 0;
volatile u32   control_usar_adc = 0;
volatile u32   control_emulador = 0;
volatile u32   control_emu_offset_mv = 0;
volatile u32   control_adc_mv = 0;
volatile u32   control_adc_nuevos = 0;
volatile u32   control_adc_sin_dato = 0;
volatile muestra_t control_buffer[CONTROL_N_BUFFER];

static XTmrCtr      timer;
static control_pr_t pr;
static float        tabla_seno[CONTROL_N_REF];
static u32          k_ref = 0;
static u32          estaba_habilitado = 0;
static float        i_adc = 0.0f;
static float        emu_offset = EMU_OFFSET_INICIAL;

// modelo de la carga RL: i[k+1] = a*i[k] + (1-a)*Vdc*m[k-1]/R
// con a = exp(-R*Ts/L), R = 10,3 ohm, L = 198 uH y Vdc = 18 V
#define PLANTA_A      0.07419859228f
#define PLANTA_B      (0.9258014077f * 18.0f / 10.3f)
static float i_sim = 0.0f;
static float m_anterior = 0.0f;

// ---------------------------------------------------------------
// Lectura de la corriente
// ---------------------------------------------------------------
// Lee el ADC si hay muestra nueva. Con el PWM corriendo la conversion la
// dispara pwm_trigger_o, y con el PWM apagado se pide por software
static float leer_corriente(u32 pwm_corriendo)
{
    u32 crudo;
    float v;

    if (adc_hay_dato(ADC_BASE)) {
        // primero se borra el aviso y despues se lee el dato, asi si termina
        // otra conversion en medio su aviso no se pierde
        adc_borrar_aviso(ADC_BASE);
        crudo = adc_leer_crudo(ADC_BASE);
        v = adc_a_voltios(crudo);
        control_adc_mv = (u32)(v * 1000.0f);
        if (control_emulador) {
            // con el lazo apagado m = 0, entonces lo que se lee es el
            // offset y se va promediando
            if (!estaba_habilitado)
                emu_offset += 0.01f * (v - emu_offset);
            control_emu_offset_mv = (u32)(emu_offset * 1000.0f);
            i_adc = (v - emu_offset) / EMU_GANANCIA;
        } else {
            i_adc = (v - SENSOR_OFFSET_V) / SENSOR_GANANCIA;
        }
        control_adc_nuevos++;
    } else {
        // no llego dato nuevo: se usa el anterior y se cuenta
        control_adc_sin_dato++;
    }

    if (!pwm_corriendo)
        adc_iniciar_software(ADC_BASE);

    if (control_usar_adc || control_emulador)
        return i_adc;
    else
        return i_sim;
}

// se llama una vez por periodo despues de escribir el duty nuevo
static void avanzar_planta(float m)
{
    i_sim = PLANTA_A * i_sim + PLANTA_B * m_anterior;
    m_anterior = m;
}

// pasa un float a entero de 16 bits con signo, recortando
static s16 a_s16(float x)
{
    if (x > 32767.0f) return 32767;
    if (x < -32768.0f) return -32768;
    return (s16)x;
}

// ---------------------------------------------------------------
// Rutina de interrupcion
// ---------------------------------------------------------------
static void rutina_control(void *referencia, u8 numero_contador)
{
    u32 t_entrada, t_salida, latencia, duracion;
    float iref, i, m;
    s16 duty;
    u32 activo;

    (void)referencia;
    (void)numero_contador;

    // el timer cuenta hacia abajo desde TIMER_CARGA, asi que lo que ya
    // bajo es el tiempo desde que se pidio la interrupcion
    t_entrada = XTmrCtr_GetValue(&timer, CONTADOR_TIMER);
    Xil_Out32(GPIO1_BASE + GPIO2_DATA, 1U);   // pin de prueba arriba

    // 1. corriente
    i = leer_corriente(estaba_habilitado || control_emulador);

    // 2. proteccion: si se pasa del limite se apaga y queda en falla
    // en el emulador solo se revisa con el lazo activo, porque al entrar
    // al modo el ADC lee 0 V y eso parece una sobrecorriente
    if ((!control_emulador || estaba_habilitado) &&
        (i > CONTROL_I_MAX || i < -CONTROL_I_MAX))
        control_falla = 1;

    // 3. referencia de 50 Hz desde la tabla
    iref = control_amplitud * tabla_seno[k_ref];
    k_ref++;
    if (k_ref >= CONTROL_N_REF)
        k_ref = 0;

    activo = control_habilitado && !control_falla;
    if (activo) {
        // al habilitar se arranca con el PR en cero
        if (!estaba_habilitado)
            control_pr_reiniciar(&pr);
        m = control_pr_paso(&pr, iref - i);
    } else {
        m = 0.0f;
    }
    estaba_habilitado = activo;

    pwm_duty(PWM_BASE, m);
    // la ISR tambien escribe el control para que una falla apague el PWM
    // en este mismo periodo
    pwm_control(PWM_BASE, activo || control_emulador, control_freq_sel);
    avanzar_planta(activo ? m : 0.0f);

    // 4. muestra al buffer circular
    if (!control_congelado) {
        duty = a_s16(m * 32768.0f);
        control_buffer[control_indice].iref_ma  = a_s16(iref * 1000.0f);
        control_buffer[control_indice].i_ma     = a_s16(i * 1000.0f);
        control_buffer[control_indice].duty_q15 = duty;
        control_indice++;
        if (control_indice >= CONTROL_N_BUFFER) {
            control_indice = 0;
            control_lleno = 1;
        }
    }

    control_interrupciones++;

    // 5. tiempos
    Xil_Out32(GPIO1_BASE + GPIO2_DATA, 0U);   // pin de prueba abajo
    t_salida = XTmrCtr_GetValue(&timer, CONTADOR_TIMER);
    latencia = TIMER_CARGA - t_entrada;
    duracion = t_entrada - t_salida;
    if (duracion > control_isr_max) control_isr_max = duracion;
    if (latencia < control_lat_min) control_lat_min = latencia;
    if (latencia > control_lat_max) control_lat_max = latencia;
}

// ---------------------------------------------------------------
// Configuracion
// ---------------------------------------------------------------
//pendiente: agregar funcion para reiniciar el PR y la planta al habilitar el lazo
