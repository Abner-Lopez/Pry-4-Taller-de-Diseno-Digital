// control_pr.c
// PR discreto:
//   y[n] = b0*e[n] + b2*e[n-2] - a1*y[n-1] - a2*y[n-2]   (parte resonante)
//   u[n] = Kp*e[n] + y[n]                                (tension en V)
//   m[n] = u[n] / Vdc, saturado a +-PR_M_MAX             (indice de modulacion)

#include "control_pr.h"

// valores del controlador
#define PR_KP     2.0f
#define PR_B0     0.07499691579f      // Tustin + prewarping, Ts = 50 us
#define PR_B2    -0.07499691579f
#define PR_A1    -1.999753265f
#define PR_A2     1.0f
#define PR_VDC    18.0f               // tension del bus DC
#define PR_M_MAX  0.8f                // limite del indice de modulacion

void control_pr_reiniciar(control_pr_t *pr)
{
    pr->e1 = 0.0f;
    pr->e2 = 0.0f;
    pr->y1 = 0.0f;
    pr->y2 = 0.0f;
}

float control_pr_paso(control_pr_t *pr, float error)
{
    float y, u, m;

    // parte resonante
    y = PR_B0 * error + PR_B2 * pr->e2 - PR_A1 * pr->y1 - PR_A2 * pr->y2;

    // se corren los estados para la siguiente muestra
    pr->e2 = pr->e1;
    pr->e1 = error;
    pr->y2 = pr->y1;
    pr->y1 = y;

    // proporcional mas resonante, y se pasa de voltios a indice de modulacion
    u = PR_KP * error + y;
    m = u / PR_VDC;

    // saturacion (el PWM tambien satura en hardware, esto es por si acaso)
    if (m > PR_M_MAX)
        m = PR_M_MAX;
    else if (m < -PR_M_MAX)
        m = -PR_M_MAX;

    return m;
}
