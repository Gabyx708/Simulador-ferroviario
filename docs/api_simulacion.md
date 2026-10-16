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
| `obtener_horarios() -> Array[Dictionary]` | Horario previsto y llegadas reales por tren, también de trenes eliminados. |
| `obtener_velocidad_simulacion() -> float` | Factor global activo. |
| `esta_pausada() -> bool` | `true` sólo cuando el factor es `0.0`. |

Un tren publica `id`, `nombre`, `estado`, `estado_nombre`, `servicio`,
`sentido`, `estacion_proxima`, `distancia_m`, `velocidad_kmh`, `pasajeros`,
`capacidad`, `retraso_s`, `resultado`, `motivo_resultado`, `causa_resultado`,
`motivo_evento`, `tiempo_evento_restante_s` y `velocidad_media_marcha_kmh`.
El controlador le agrega la puntualidad respecto del horario previsto:
`horario_disponible`, `atrasado`, `puntualidad_nombre` ("En tiempo",
"Atrasado" o "Sin horario"), `retraso_horario_s`, `tiempo_recorrido_s`,
`tiempo_previsto_total_s`, `llegada_proxima_prevista_s` y `ciclo_horario`.

`sentido` es el sentido en que el tren va a circular: en una cabecera cambia al
llegar, antes de embarcar, porque la formación sale marcha atrás del mismo
andén. `distancia_m` vale `-1` cuando el tren no tiene ruta (por ejemplo,
`INCOMPLETO`).

El horario previsto cubre una ida y una vuelta. Como el servicio repite el
recorrido en bucle, al salir de Constitución hacia Yrigoyen empieza un ciclo
nuevo (`ciclo_horario` aumenta) tomando como base la llegada real a
Constitución; `tiempo_recorrido_s`, el atraso y las llegadas de
`obtener_horarios()` corresponden al ciclo en curso.

`retraso_s` lee `Tren.retraso_externo_s`, una variable pública que el propio
`Tren` no calcula: la mantiene `EstadisticasRetraso` (Persona 5,
`scenes/simulation/estadisticas_retraso.gd`), que la recalcula por tramo
usando `RelojSimulacion` y las señales `llego_a_estacion`/`salio_de_estacion`.
Es la única línea que Persona 5 toca en `tren.gd`; Diego dejó el proyecto y
delegó el mantenimiento de ese campo.

Una estación publica `id`, `nombre`, `activa`, `pasajeros_esperando`,
`pasajeros_saliendo`, `pasajeros_subidos_total`, `pasajeros_bajados_total` y
sus métricas de espera: `espera_total_completada_s`, `pasajeros_con_espera`,
`espera_promedio_s`, `espera_actual_total_s` y `espera_promedio_actual_s`.

El resumen global publica `pasajeros_esperando`, `pasajeros_en_viaje`,
`pasajeros_transportados`, `pasajeros_recorrido_completado`,
`pasajeros_interrumpidos`, `trenes_activos`, `trenes_finalizados`,
`trenes_incompletos`, `trenes_incompletos_evento`, `trenes_atrasados`,
`trenes_con_horario`, `tasa_demora_pct`, `demora_promedio_s`,
`espera_promedio_actual_s` y `concurrencia_maxima`. `trenes_finalizados`
cuenta sólo `FINALIZADO_IDA_VUELTA`; con el servicio en bucle del nivel
principal queda en `0`.

`velocidad_media_marcha_kmh` usa metros realmente recorridos y segundos
simulados con movimiento durante `EN_MARCHA`; excluye estación, reserva,
evento, pausa, terminal e incompleto. Vale `0.0` antes del primer movimiento.

## Estados y señales

Estados públicos: `EN_TERMINAL_INICIAL`, `EN_MARCHA`,
`DETENIDO_EN_ESTACION`, `ESPERANDO_RESERVA`, `DETENIDO_POR_EVENTO`,
`FINALIZADO_EN_BOSQUES`, `INCOMPLETO` y `FINALIZADO_IDA_VUELTA`.
`FINALIZADO_EN_BOSQUES` sólo aparece con `solo_ida` y `FINALIZADO_IDA_VUELTA`
sólo con `finalizar_al_volver`; el nivel principal no usa ninguno de los dos,
así que sus trenes circulan hasta quedar `INCOMPLETO` o ser eliminados.
`ESPERANDO_RESERVA` indica que el tren espera una aguja, una vía de uso común
o un andén en vía muerta que tiene otro tren, o que frena por un tren adelante.

| Señal | Cuándo se emite |
| --- | --- |
| `tren_agregado(datos_tren)` / `tren_eliminado(id)` | Alta o baja registrada. |
| `tren_actualizado(datos_tren)` | Cambio público de estado, ruta o pasajeros. |
| `tren_llego_estacion(id, datos_estacion)` | Llegada efectiva a una estación. |
| `tren_reanudo(id)` | Salida o fin de una detención temporal. |
| `tren_finalizo(id, resultado)` | Fin del servicio (`solo_ida` en Bosques o `finalizar_al_volver` en Constitución) o recorrido incompleto. |
| `estacion_actualizada(datos_estacion)` | Cambian pasajeros de una estación. |
| `resumen_global_actualizado(datos)` | Cambia un dato agregado publicado. |
| `velocidad_simulacion_cambiada(factor)` | Cambia el factor global. |

## Comandos

| Método | Comportamiento |
| --- | --- |
| `agregar_tren() -> Dictionary` | Devuelve `ok`, `en_cola`, `tren` y `motivo`; el nivel conserva la geometría de despacho. Los puestos son los `Marker3D` de `MarcadoresDeInstancia/Constitucion` sobre vías que admiten ida (los andenes de vuelta quedan para las llegadas); si están todos ocupados, el tren queda en cola. |
| `eliminar_tren(id) -> bool` | Elimina sólo un tren registrado y activo. |
| `establecer_velocidad_simulacion(factor) -> bool` | Acepta números finitos `>= 0`; `0.0` pausa, positivos escalan el tiempo. Rechaza el resto sin cambiar estado. |
| `pausar_simulacion()` / `reanudar_simulacion()` | Pausa o restaura el último factor positivo. |
| `detener_tren_temporalmente(id, motivo, duracion_s) -> bool` | Detiene un tren válido, conserva ruta y reservas, y usa segundos simulados. |
| `detener_tren_por_averia(id, motivo) -> bool` | Detiene indefinidamente un tren averiado y conserva sus reservas hasta que el gestor finalice la avería. |
| `reanudar_tren(id) -> bool` | Cancela un evento temporal válido y restaura el estado previo. |
| `finalizar_tren_incompleto(id, motivo) -> bool` | Detiene el tren, libera reservas y deja el snapshot disponible. |

Los comandos devuelven `false` ante IDs inexistentes, motivos vacíos, valores
inválidos o estados incompatibles. Ninguno invierte la marcha ni cambia de vía:
la inversión en las cabeceras la hace el propio tren al terminar la parada.

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

Hay dos medidas de atraso y no son intercambiables:

- `retraso_s`: acumulado de `EstadisticasRetraso`, medido de llegada a llegada
  contra la distancia de cada tramo. Lo usan los indicadores y el detalle por
  tren del panel de métricas.
- `retraso_horario_s` / `atrasado`: diferencia contra el horario previsto
  (`MetricasServicio`), con tolerancia `tolerancia_horario_s` del controlador
  (1 s por defecto). Alimentan `trenes_atrasados`, `tasa_demora_pct` y
  `demora_promedio_s` del resumen global, y la etiqueta "En tiempo" o
  "Atrasado" del panel de trenes.

El horario previsto supone que cada tramo se recorre a `velocidad_horario_kmh`
sin esperas de reserva; con varias formaciones compartiendo vías es normal que
los trenes figuren "Atrasado" aunque `retraso_s` sea bajo. El factor global ya
está disponible; el slider del HUD permite `0.0×–10.0×` y muestra **Pausada**
en cero.

Los sliders individuales de velocidad, aceleración y frenado son controles
internos del HUD. La velocidad nominal de cada CSR es `50 km/h` y puede
editarse por instancia en el Inspector; ninguno de esos ajustes altera ruta,
destino, poste ni distancia ferroviaria.
