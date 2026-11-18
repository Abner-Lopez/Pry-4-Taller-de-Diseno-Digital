import sys
import time
import serial
import matplotlib.pyplot as plt

puerto = sys.argv[1] if len(sys.argv) > 1 else "COM11"

with serial.Serial(puerto, 115200, timeout=30) as uart:
    print("Esperando la exportacion en " + puerto + "... (presione BTNC)")

    # se espera la linea de inicio, que trae el periodo de muestreo
    ts_us = None
    while ts_us is None:
        linea = uart.readline().decode(errors="ignore").strip()
        if linea == "":
            raise SystemExit("No llego nada en 30 s")
        if linea.startswith("INICIO"):
            campos = dict(c.split("=") for c in linea.split(",")[1:])
            ts_us = float(campos["Ts_us"])
            n_esperadas = int(campos["N"])
            print(linea)

    encabezado = uart.readline().decode(errors="ignore").strip()
    filas = []
    while True:
        linea = uart.readline().decode(errors="ignore").strip()
        if linea == "FIN" or linea == "":
            break
        filas.append([int(x) for x in linea.split(",")])

print("Muestras recibidas: %d de %d" % (len(filas), n_esperadas))

# se revisa que no falte ninguna: tienen que llegar N filas con n de 0 a N-1
if len(filas) != n_esperadas or any(f[0] != k for k, f in enumerate(filas)):
    print("AVISO: faltan muestras o vienen fuera de orden")

# se guarda tal cual llego
nombre = time.strftime("muestras_%Y%m%d_%H%M%S.csv")
with open(nombre, "w") as f:
    f.write(encabezado + "\n")
    for fila in filas:
        f.write(",".join(str(x) for x in fila) + "\n")
print("Guardado en " + nombre)

# grafica: referencia y corriente arriba, indice de modulacion abajo
t_ms  = [fila[0] * ts_us / 1000.0 for fila in filas]
iref  = [fila[1] / 1000.0 for fila in filas]
i     = [fila[2] / 1000.0 for fila in filas]
m     = [fila[3] / 32768.0 for fila in filas]

fig, (ax1, ax2) = plt.subplots(2, 1, sharex=True)
ax1.plot(t_ms, iref, label="referencia")
ax1.plot(t_ms, i, label="corriente")
ax1.set_ylabel("Corriente (A)")
ax1.legend()
ax1.grid(True)
ax2.plot(t_ms, m)
ax2.set_ylabel("Indice de modulacion m")
ax2.set_xlabel("Tiempo (ms)")
ax2.grid(True)
plt.show()
