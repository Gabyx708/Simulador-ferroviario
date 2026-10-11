# API pública de simulación ferroviaria

`SimulacionController` es un nodo hijo del nivel principal llamado
`SimulacionController`. Existe uno por nivel; registra los grupos `trenes` y
`estaciones`, asigna IDs operativos y publica snapshots seguros. Al abandonar
el nivel restaura el factor global de `Engine.time_scale` anterior.

Los sistemas externos deben obtener este nodo desde el nivel actual. No deben
manipular `Tren`, `Estacion`, `TrackNetwork`, rutas, reservas ni switches.

## Consultas

| Método | Resultado |
| --- | --- |
| `obtener_trenes() -> Array[Dictionary]` | Snapshots de trenes activos, ordenados por ID. |
| `obtener_tren(id: int) -> Dictionary` | Snapshot o `{}` si no existe. |
| `obtener_estaciones() -> Array[Dictionary]` | Snapshots de estaciones, ordenados por ID. |
| `obtener_estacion(id: String) -> Dictionary` | Snapshot o `{}` si no existe. |
| `obtener_resumen_global() -> Dictionary` | Totales disponibles de la simulación. |
| `obtener_velocidad_simulacion() -> float` | Factor global activo. |
| `esta_pausada() -> bool` | `true` sólo cuando el factor es `0.0`. |

Un tren publica `id`, `nombre`, `estado`, `estado_nombre`, `servicio`,
`sentido`, `estacion_proxima`, `distancia_m`, `velocidad_kmh`, `pasajeros`,
`capacidad`, `retraso_s`, `resultado`, motivos de resultado/evento,
`tiempo_evento_restante_s` y `velocidad_media_marcha_kmh`.

`retraso_s` lee `Tren.retraso_externo_s`, una variable pública que el propio
`Tren` no calcula: la mantiene `EstadisticasRetraso` (Persona 5,
`scenes/simulation/estadisticas_retraso.gd`), que la recalcula por tramo
usando `RelojSimulacion` y las señales `llego_a_estacion`/`salio_de_estacion`.
Es la única línea que Persona 5 toca en `tren.gd`; Diego dejó el proyecto y
delegó el mantenimiento de ese campo.

Una estación publica `id`, `nombre`, `activa`, pasajeros esperando/saliendo y
totales subidos/bajados. El resumen global publica pasajeros esperando, en
viaje y transportados; trenes activos, finalizados e incompletos; demora
promedio y concurrencia máxima.

`velocidad_media_marcha_kmh` usa metros realmente recorridos y segundos
simulados con movimiento durante `EN_MARCHA`; excluye estación, reserva,
evento, pausa, terminal e incompleto. Vale `0.0` antes del primer movimiento.

## Estados y señales

Estados públicos: `EN_TERMINAL_INICIAL`, `EN_MARCHA`,
`DETENIDO_EN_ESTACION`, `ESPERANDO_RESERVA`, `DETENIDO_POR_EVENTO`,
`FINALIZADO_EN_BOSQUES` e `INCOMPLETO`.

| Señal | Cuándo se emite |
| --- | --- |
| `tren_agregado(datos_tren)` / `tren_eliminado(id)` | Alta o baja registrada. |
| `tren_actualizado(datos_tren)` | Cambio público de estado, ruta o pasajeros. |
| `tren_llego_estacion(id, datos_estacion)` | Llegada efectiva a una estación. |
| `tren_reanudo(id)` | Salida o fin de una detención temporal. |
| `tren_finalizo(id, resultado)` | Bosques o recorrido incompleto. |
| `estacion_actualizada(datos_estacion)` | Cambian pasajeros de una estación. |
| `resumen_global_actualizado(datos)` | Cambia un dato agregado publicado. |
| `velocidad_simulacion_cambiada(factor)` | Cambia el factor global. |

## Comandos

| Método | Comportamiento |
| --- | --- |
| `agregar_tren() -> Dictionary` | Devuelve `ok`, `en_cola`, `tren` y `motivo`; el nivel conserva la geometría de despacho. |
| `eliminar_tren(id) -> bool` | Elimina sólo un tren registrado y activo. |
| `establecer_velocidad_simulacion(factor) -> bool` | Acepta números finitos `>= 0`; `0.0` pausa, positivos escalan el tiempo. Rechaza el resto sin cambiar estado. |
| `pausar_simulacion()` / `reanudar_simulacion()` | Pausa o restaura el último factor positivo. |
| `detener_tren_temporalmente(id, motivo, duracion_s) -> bool` | Detiene un tren válido, conserva ruta y reservas, y usa segundos simulados. |
| `reanudar_tren(id) -> bool` | Cancela un evento temporal válido y restaura el estado previo. |
| `finalizar_tren_incompleto(id, motivo) -> bool` | Detiene el tren, libera reservas y deja el snapshot disponible. |

Los comandos devuelven `false` ante IDs inexistentes, motivos vacíos, valores
inválidos o estados incompatibles. No habilitan reversa ni salida desde Bosques.

## Ejemplos de uso

```gdscript
var controlador: Node = get_tree().current_scene.get_node("SimulacionController")
var trenes: Array[Dictionary] = controlador.obtener_trenes()
controlador.establecer_velocidad_simulacion(2.0)
controlador.detener_tren_temporalmente(1, "Inspección", 30.0)
```

Para UI, conectarse a `tren_actualizado` y renderizar el snapshot. Para
estadísticas, consumir `obtener_resumen_global()` y
`resumen_global_actualizado`, sin leer nodos de tren/estación. Para eventos,
usar exclusivamente los tres comandos por tren.

## Límites actuales

`demora_promedio_s` permanece neutra en `SimulacionController` hasta que
Persona 3 arme el agregador de `EstadisticasSimulacion`; `retraso_s` por tren
ya es real (ver arriba). Demanda por hora y eventos de dominio siguen
pendientes de Persona 4 y Persona 5 respectivamente. El factor global ya está
disponible; el slider del HUD permite `0.0×–10.0×` y muestra **Pausada** en
cero.

Los sliders individuales de velocidad, aceleración y frenado son controles
internos del HUD. La velocidad nominal de cada CSR es `50 km/h` y puede
editarse por instancia en el Inspector; ninguno de esos ajustes altera ruta,
destino, poste ni distancia ferroviaria.
