#ifndef ADC_DRIVER_H
#define ADC_DRIVER_H

#include "xil_types.h"
#include "xil_io.h"

#define ADC_REG_RESET     0x000U   // escribir 0xA reinicia el XADC
#define ADC_REG_ESTADO    0x004U   // bit 5 EOC, bit 7 BUSY (no se usa)
#define ADC_REG_CONVST    0x00CU   // escribir 1 empieza una conversion
#define ADC_REG_IPISR     0x060U   // banderas latcheadas, se borran escribiendo 1
#define ADC_REG_VAUX3     0x24CU   // dato del canal VAUX3 (0x240 + 3*4)

#define ADC_EOC           0x20U    // fin de conversion

// empieza una conversion por software. La conversion arranca con el flanco
// de subida de CONVST, por eso se escribe 1 y despues 0. Si se deja en 1
// tampoco funciona el disparo con pwm_trigger_o
static inline void adc_iniciar_software(UINTPTR base)
{
    Xil_Out32(base + ADC_REG_CONVST, 1U);
    Xil_Out32(base + ADC_REG_CONVST, 0U);
}

// devuelve 1 si llego una muestra nueva desde la ultima vez que se borro
static inline u32 adc_hay_dato(UINTPTR base)
{
    return (Xil_In32(base + ADC_REG_IPISR) & ADC_EOC) ? 1U : 0U;
}

// borra el aviso de muestra nueva
static inline void adc_borrar_aviso(UINTPTR base)
{
    Xil_Out32(base + ADC_REG_IPISR, ADC_EOC);
}

// lee el dato de 12 bits del canal VAUX3 (de 0 a 4095)
static inline u32 adc_leer_crudo(UINTPTR base)
{
    return (Xil_In32(base + ADC_REG_VAUX3) >> 4) & 0xFFFU;
}

// pasa el dato a voltios (0 a 1 V en modo unipolar)
static inline float adc_a_voltios(u32 crudo)
{
    return (float)crudo * (1.0f / 4096.0f);
}

#endif
