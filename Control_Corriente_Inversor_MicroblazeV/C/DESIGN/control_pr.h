// control_pr.h
// Controlador proporcional-resonante (PR) discreto.
// Los valores salen del modelo de PEDP (03_PuenteH_LazoCerrado), discretizado
// con Tustin y prewarping a Ts = 50 us.

#ifndef CONTROL_PR_H
#define CONTROL_PR_H

typedef struct {
    // estados del resonante
    float e1, e2;   // error una y dos muestras atras
    float y1, y2;   // salida del resonante una y dos muestras atras
} control_pr_t;

// pone los estados en cero (se usa al habilitar o despues de una falla)
void control_pr_reiniciar(control_pr_t *pr);

// calcula un paso del PR con el error de corriente (en A) y devuelve el
// indice de modulacion m ya saturado a +-PR_M_MAX
float control_pr_paso(control_pr_t *pr, float error);

#endif
