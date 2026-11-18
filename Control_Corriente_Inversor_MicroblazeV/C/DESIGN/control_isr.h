// control_isr.h
// Rutina de interrupcion del lazo de control y su configuracion.
// Cada Ts: leer corriente -> PR -> duty_ref -> guardar la muestra.

#ifndef CONTROL_ISR_H
#define CONTROL_ISR_H

#include "xil_types.h"

// periodo de muestreo
#define CONTROL_TS_US      50U
#define CONTROL_N_REF      400U     // muestras por ciclo de 50 Hz (1 / (50 Hz * Ts))

// buffer circular de muestras (2000 muestras = 100 ms = 5 ciclos de 50 Hz)
#define CONTROL_N_BUFFER   2000U

// corriente maxima antes de apagar el PWM
#define CONTROL_I_MAX      1.5f

// escala del sensor: i = (v_adc - OFFSET) / GANANCIA
#define SENSOR_OFFSET_V    0.5f
#define SENSOR_GANANCIA    0.4f

// escala del emulador RC: se escogio para que un mismo m dé la misma
// corriente que la carga real. El offset se ajusta solo con el lazo apagado
#define EMU_GANANCIA       0.282f
#define EMU_OFFSET_INICIAL 0.47f

// una muestra del buffer, en enteros para que ocupe menos
typedef struct {
    s16 iref_ma;    // referencia en mA
    s16 i_ma;       // corriente medida en mA
    s16 duty_q15;   // duty_ref que se escribio al PWM
} muestra_t;

// variables compartidas con el programa principal
extern volatile u32       control_habilitado;   // lo pone main con SW0
extern volatile u32       control_falla;        // la pone la ISR si se pasa de I_MAX
extern volatile u32       control_congelado;    // 1 mientras se exporta el buffer
extern volatile float     control_amplitud;     // amplitud de la referencia en A
extern volatile u32       control_freq_sel;     // freq_sel que pide main
extern volatile u32       control_indice;       // proxima posicion del buffer
extern volatile u32       control_lleno;        // 1 cuando el buffer ya dio una vuelta
extern volatile u32       control_interrupciones;
extern volatile u32       control_isr_max;      // duracion maxima de la ISR en ciclos
extern volatile u32       control_lat_min;      // latencia minima en ciclos
extern volatile u32       control_lat_max;      // latencia maxima en ciclos
extern volatile u32       control_usar_adc;     // 1 = corriente del ADC, 0 = planta simulada
extern volatile u32       control_emulador;     // 1 = emulador RC (sin la etapa de potencia)
extern volatile u32       control_emu_offset_mv;// offset aprendido del emulador en mV
extern volatile u32       control_adc_mv;       // ultima lectura del ADC en mV
extern volatile u32       control_adc_nuevos;   // cuantas muestras nuevas llegaron
extern volatile u32       control_adc_sin_dato; // cuantas veces la ISR no tuvo dato nuevo
extern volatile muestra_t control_buffer[CONTROL_N_BUFFER];

// configura el Timer, la interrupcion y el PWM. Devuelve 0 si todo salio bien
int control_isr_iniciar(void);

// reinicia las estadisticas de tiempo
void control_isr_reiniciar_tiempos(void);

#endif
