// pwm_driver.h
// Funciones para manejar el PWM desde C. Los offsets tienen que ser los
// mismos de la tabla de registros.
//
//   0x00 Control/Estado: bit 0 enable, bits [2:1] freq_sel, bit 3 running (RO)
//   0x04 Duty/Referencia: bits [15:0] duty_ref en Q1.15 (de -1 a 1)
//   0x08 Tiempo muerto:  bits [7:0] dead_time en ciclos de 10 ns

#ifndef PWM_DRIVER_H
#define PWM_DRIVER_H

#include "xil_types.h"
#include "xil_io.h"

// offsets de los registros
#define PWM_REG_CTRL        0x00U
#define PWM_REG_DUTY        0x04U
#define PWM_REG_DT          0x08U

// campos del registro de control
#define PWM_CTRL_ENABLE     0x1U
#define PWM_CTRL_FREQ_SHIFT 1U
#define PWM_CTRL_FREQ_MASK  0x6U
#define PWM_CTRL_RUNNING    0x8U

// valores de freq_sel
#define PWM_FREQ_100KHZ     0U
#define PWM_FREQ_80KHZ      1U
#define PWM_FREQ_125KHZ     2U

// escribe enable y freq_sel juntos
static inline void pwm_control(UINTPTR base, u32 enable, u32 freq_sel)
{
    u32 valor = (enable & 0x1U) | ((freq_sel << PWM_CTRL_FREQ_SHIFT) & PWM_CTRL_FREQ_MASK);
    Xil_Out32(base + PWM_REG_CTRL, valor);
}

// devuelve 1 si el PWM esta generando
static inline u32 pwm_running(UINTPTR base)
{
    return (Xil_In32(base + PWM_REG_CTRL) & PWM_CTRL_RUNNING) ? 1U : 0U;
}

// escribe duty_ref ya en Q1.15. Si esta fuera de rango el hardware lo satura
static inline void pwm_duty_q15(UINTPTR base, s16 duty)
{
    Xil_Out32(base + PWM_REG_DUTY, (u32)(u16)duty);
}

// pasa un indice de modulacion m (de -1 a 1) a Q1.15 y lo escribe
static inline void pwm_duty(UINTPTR base, float m)
{
    float escalado = m * 32768.0f;
    s32 q;

    // se recorta para que quepa en 16 bits con signo
    if (escalado > 32767.0f)
        q = 32767;
    else if (escalado < -32768.0f)
        q = -32768;
    else
        q = (s32)escalado;

    pwm_duty_q15(base, (s16)q);
}

// tiempo muerto en ciclos de 10 ns (el hardware no deja bajar de su minimo)
static inline void pwm_tiempo_muerto(UINTPTR base, u32 ciclos)
{
    Xil_Out32(base + PWM_REG_DT, ciclos & 0xFFU);
}

#endif
