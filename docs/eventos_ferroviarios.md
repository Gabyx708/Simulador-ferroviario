# Reloj, retraso y eventos ferroviarios (Persona 5)

Cubre lo que agrega Persona 5 sobre la base de `SimulacionController`
(Diego): reloj de simulación, cálculo real de `retraso_s` por tren, y los 3
eventos de dominio. Ningún archivo de este módulo toca `tren.gd`,
`track_network.gd` ni `servicio_ferroviario.gd`, salvo el cambio mínimo de
una línea documentado más abajo (autorizado porque Diego ya no está en el
proyecto).

Archivos: `scenes/simulation/reloj_simulacion.gd`,
`scenes/simulation/estadisticas_retraso.gd`,
`scenes/simulation/gestor_eventos.gd`,
`scenes/simulation/indicador_eventos.gd`. Los cuatro son nodos hijos del
nivel, hermanos de `SimulacionController`, instanciados en
`levels/ramal_roca_main/ramal_roca_main.tscn`.

## RelojSimulacion

Tiempo simulado y fecha/hora derivada. Usa `_process(delta)`: Godot ya
escala `delta` con `Engine.time_scale`, el mismo mecanismo que
`SimulacionController.establecer_velocidad_simulacion()` cambia -- se
congela solo en pausa (factor `0.0`) y corre más rápido con factores
mayores a `1.0`, sin leer nada del controlador.

- `tiempo_simulado_s() -> float`: segundos simulados transcurridos desde
  que el nivel arrancó. Monótono.
- `fecha_hora_simulada() -> Dictionary`: `{"dia", "hora", "minuto"}`.
- Señal `minuto_simulado_cambiado(dia, hora, minuto)`.

## EstadisticasRetraso

Calcula `retraso_s` real por tren, usando sólo señales públicas de `Tren`
(`llego_a_estacion`, `recorrido_incompleto`, `eliminado`) -- el mismo
patrón de conexión que usa `SimulacionController._conectar_tren()`.

**Mide llegada a llegada, no salida a llegada.** Si sólo se midiera el
viaje, una demora que agarra al tren ya parado en el andén (como un
incidente en estación) quedaría invisible, porque ocurre antes de que el tren salga.
Llegada a llegada la captura siempre.

El largo de cada tramo sale del **pico** de `distancia_a_proxima_estacion()`
(el mismo método público que usa el velocímetro) muestreado en cada
`_process()` -- no de `distancia_m` en el instante de salida, que resultó
ser un valor transitorio chico al medirlo (ver
`tools/diag_calibracion_retraso.gd`).

Fórmula por tramo:

```
tiempo_esperado = (pico_distancia / (velocidad_nominal_kmh/3.6)) * factor_calibracion_tiempo
diferencia = tiempo_real - tiempo_esperado
tolerancia = max(tolerancia_minima_s, tiempo_esperado * tolerancia_porcentual)
aporte = diferencia si diferencia > tolerancia, si no 0
retraso_acumulado += aporte   # nunca baja; es acumulado de todo el recorrido
```

`factor_calibracion_tiempo = 1.123`, medido contra una corrida limpia sin
eventos con `tools/diag_calibracion_retraso.gd` (3 tramos reales). Volver a
correr esa herramienta si cambia `velocidad_nominal_kmh` o la geometría de
los tramos.

- `obtener_retraso(id_tren: int) -> float`
- Señal `retraso_tren_actualizado(id_tren, retraso_s)`

### Cambio en `tren.gd` (autorizado, Diego ya no está en el proyecto)

`Tren.retraso_externo_s` (nueva variable, `0.0` por defecto) es seteada
externamente por `EstadisticasRetraso`; `Tren.obtener_resumen_operativo()`
ahora devuelve `"retraso_s": retraso_externo_s` en vez del literal `0.0`
anterior. Es el único cambio fuera de `scenes/simulation/`; ver
`docs/api_simulacion.md` para el detalle exacto. Persona 5 mantiene ese
campo de ahora en más.

### Limitación conocida

Si una instancia puntual de `Tren`/`TrenCSR` cambia su velocidad nominal
desde el Inspector, el cálculo de retraso para ese tren específico no se
entera (sigue usando `velocidad_nominal_kmh` del propio
`EstadisticasRetraso`, que es un único valor global). No se detectó forma
pública de leer la nominal por instancia sin tocar `tren.gd` más de lo
autorizado.

## GestorEventos

Dispara y resuelve los 3 eventos de dominio, todo vía los comandos que ya
existen en `SimulacionController` (`detener_tren_temporalmente`,
`reanudar_tren`, `finalizar_tren_incompleto`). No toca `Tren`,
`TrackNetwork` ni reservas directamente.

| | Falla eléctrica | Incidente en estación | Desperfecto mecánico |
| --- | --- | --- | --- |
| Alcance | Un tramo (identificado por su estación de salida) | Una estación puntual | Un único tren |
| Tipo | Zona activa, reanudable | Zona activa, reanudable | Inmediato, definitivo |
| Disparo | `disparar_falla_electrica(estacion_origen, duracion_s=-1)` | `disparar_incidente_en_estacion(estacion, duracion_s=-1)` | `disparar_desperfecto_mecanico(id_tren, motivo="...")` |
| Duración por defecto | `duracion_falla_electrica_s = 90.0` | `duracion_incidente_estacion_s = 120.0` | No aplica |
| Se aplica en | `salio_de_estacion` (nombre de origen == zona) | `llego_a_estacion` (nombre == zona) | Al llamar, sobre ese tren |
| Resolución | Automática al vencer, o `reanudar_tren` manual | Igual | Ninguna -- no se puede reanudar |
| Color | `COLOR_FALLA_ELECTRICA` (amarillo) | `COLOR_PIQUETE` (naranja, nombre interno conservado) | `COLOR_DESPERFECTO_MECANICO` (rojo), vía `color_evento_activo(id_tren)` |

### Datos preparados para el popup de incidente

Al disparar un incidente en estación, `evento_disparado` y
`obtener_historial()` incluyen estos campos en el diccionario del evento:

```gdscript
{
	"tipo_evento": "Incidente en estación",
	"perjudicado": "nombre de la estación afectada",
	"mensaje": "suceso aleatorio. Duración total configurada: 2 minutos."
}
```

El suceso se elige al azar de esta lista definida en `GestorEventos`:

- Descompensación de pasajero
- Emergencia Médica
- Arrollamiento o Accidente en Paso Peatonal de Estación
- Desprendimiento de Pantógrafo en Andén
- Medida de Fuerza Gremial por Agresión al Personal
- Invasión o Bloqueo de Vías por Protesta Social
- Un vendedor ambulante amenaza con cagar a palos a todo el mundo

La duración incluida en el mensaje es la duración total seleccionada en el
HUD, no el tiempo restante. El popup todavía no forma parte de esta
implementación; los datos ya quedan disponibles para conectarlo.
`disparar_piquete()` y los identificadores `PIQUETE` / `COLOR_PIQUETE` se
conservan por compatibilidad interna; el HUD y la etiqueta pública usan el
nombre nuevo.

### Zonas activas: lo importante

Mientras un evento de zona está activo, **cualquier tren que entre
mientras tanto** se detiene por el **tiempo restante** del evento (no una
duración fija desde que entra, y no sólo los trenes que ya estaban ahí al
disparar). Un segundo disparo sobre la misma estación/tramo mientras hay
uno activo se rechaza (`{"ok": false, "motivo": "..."}`) -- no se apila.

El efecto en los trenes que vienen detrás de uno detenido **es automático**:
lo da la reserva FIFO de `TrackNetwork` que ya existe (un tren detenido
mantiene su reserva de vía), no hace falta programar nada acá. Ver la nota
de alcance de bloqueo en la sección de Limitaciones.

### Desperfecto mecánico: qué hace en concreto

No elimina el tren. Lo deja parado donde se rompió, visible,
permanentemente (`_vel = 0.0` para siempre) -- libera sus reservas de vía
(`liberar_reservas_tren`), así que **no bloquea a los trenes de atrás**,
a diferencia de los eventos de zona. Queda como snapshot consultable
(`INCOMPLETO`) hasta que alguien lo saque de servicio a mano con
`eliminar_tren()`, que es un comando aparte.

### Historial y color (para Persona 2)

- `obtener_historial() -> Array[Dictionary]`: todos los eventos disparados
  desde que arrancó el nivel, en memoria (no persiste entre sesiones).
- `color_evento_activo(id_tren: int) -> Color`: color del evento activo
  de ese tren, o `Color.TRANSPARENT` si no tiene ninguno. Este módulo no
  dibuja nada -- expone el dato para que el panel de Persona 2 pinte la
  fila o el ícono. Los íconos quedan del lado de Persona 2.
- Señales `evento_disparado(datos)` / `evento_finalizado(datos)`.

## IndicadorEventos (efecto visual provisorio)

Trabajo adicional fuera de las 5 etapas originales, pedido después de
probar que los eventos funcionaban pero no se veían. No modifica `Tren` ni
`Estacion`: les cuelga un `GPUParticles3D` como hijo visual, generado por
código (sin assets externos), escuchando las señales de `GestorEventos`.

| Evento | Efecto | Dónde | Dura |
| --- | --- | --- | --- |
| Falla eléctrica | Chispas amarillas | Arriba del tren que entra al tramo (simula el pantógrafo arqueando) | Hasta que ESE tren reanuda |
| Incidente en estación | Humo negro/naranja | En la estación afectada, no en un tren puntual | Mientras la zona esté activa |
| Desperfecto mecánico | Humo gris | Saliendo del tren roto | Permanente, como el evento |

`GestorEventos` expone una señal nueva para esto,
`tren_afectado_por_evento(id_tren, tipo)`, emitida recién cuando un tren
puntual entra a una zona activa -- al disparar la zona todavía no se sabe
qué tren va a entrar, así que `evento_disparado` solo no alcanza para saber
dónde colgar el efecto en los casos de falla eléctrica.

Es explícitamente provisorio: reemplaza el hueco visual mientras no existe
el panel de Persona 2, no un ícono final.

### Disparo manual (teclas de debug)

Con `teclas_debug_activas = true` (default): **1** dispara falla eléctrica
en la primera estación de la lista, **2** incidente en estación en la primera estación,
**3** desperfecto mecánico en el primer tren activo. Requiere foco en la
ventana del juego. Es un reemplazo provisorio hasta que exista el panel de
Persona 2 -- siempre apunta a "el primero disponible", no a uno elegido.

### Disparo aleatorio (presente pero desactivado)

El código para disparo automático por probabilidad (`aleatorio_activo`,
`falla_electrica_por_hora`, `incidente_estacion_por_hora`, `desperfecto_por_hora`,
todos `@export`) existe y fue decisión explícita del equipo dejarlo
**desactivado por defecto** (`aleatorio_activo = false`): por ahora el
disparo es manual únicamente -- vía teclas de debug hoy, vía el panel de
Persona 2 más adelante. Se puede activar desde el Inspector si en algún
momento se quiere complementar con disparo automático.

## Cómo probar

Con el proyecto corriendo en el editor (F5), clic en la ventana del juego
para el foco, y las teclas 1/2/3 descritas arriba. O headless, con los 3
scripts de test:

```powershell
<ruta-a-Godot>\Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/test_reloj_simulacion.gd
<ruta-a-Godot>\Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/test_estadisticas_retraso.gd
<ruta-a-Godot>\Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/test_gestor_eventos.gd
```

`tools/diag_calibracion_retraso.gd` no es un test de aceptación: es la
herramienta para recalcular `factor_calibracion_tiempo` si cambia la
velocidad nominal o la geometría de los tramos.

## Limitaciones conocidas

- **Distancia de bloqueo entre trenes no es realista.** La reserva de vía
  de `TrackNetwork` es por segmento completo (`solicitar_reserva_seccion`),
  y los segmentos existentes miden entre ~15m y ~3000m+ según de dónde
  vinieron en el dato original -- no fueron diseñados como bloques de
  señalización reales. Un tren detenido por un evento puede frenar al que
  viene detrás a una distancia muy variable, no a una distancia de frenado
  calculada. Arreglar esto es trabajo de infraestructura de vías
  (`track_network.gd`), fuera del alcance de Persona 5; quedó pendiente de
  decisión del equipo si vale la pena encararlo más adelante.
- Velocidad nominal por instancia no detectada (ver arriba).
- El historial de eventos vive sólo en memoria; se pierde al cerrar el
  nivel.
