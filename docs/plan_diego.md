# Plan de Diego: recorrido Constitución → Bosques y núcleo ferroviario

## Alcance

Diego mantiene el núcleo ferroviario y el servicio actual será exclusivamente **Constitución → Bosques**. Al llegar a Bosques, el tren queda detenido y el recorrido termina. Esta fase no incluye Bosques → Constitución, inversión de sentido ni servicios de vuelta.

Diego es el único responsable de modificar:

- `scenes/train/tren.gd`
- `scenes/tracks/track_network.gd`
- `scenes/services/servicio_ferroviario.gd`
- Topología, `Path3D`, estaciones físicas, switches, reservas y ruteo.

Los demás integrantes trabajarán sobre señales, resúmenes y comandos públicos; no modificarán el recorrido ni la física ferroviaria.

## Estado actual

- [x] Constitución → Bosques con 16 estaciones y 15 enlaces.
- [x] Servicio dirigido por estaciones, no por orden de `Path3D`.
- [x] Paradas multi-vía y frenado al poste sobre la vía de marcha.
- [x] Odómetro ferroviario y distancia a estación independientes de los multiplicadores de prueba.
- [x] Formación larga con transición suave de coches en agujas.
- [x] Cuatro trenes iniciales, reservas de secciones/switches y cola FIFO.
- [x] Bosques configurado como final del servicio mediante `solo_ida = true`.
- [~] Estados ferroviarios: existen internamente, pero no como API explícita.
- [~] Señales de tren para velocidad, pasajeros, ruta, parada, reanudación y eliminación; faltan estado operativo, finalización e incidente.
- [ ] API global de simulación para que el equipo no toque el núcleo.
- [ ] Validar velocidad media operativa entre 35 y 55 km/h.

La prueba `tools/test_servicio_ferroviario.gd` ya valida las 16 estaciones, los 15 enlaces, cuatro trenes iniciales, un quinto tren en cola y reservas FIFO.

## Fase 1 — Consolidar el servicio de ida

- Conservar `solo_ida = true` en `ServicioConstitucionBosques`.
- Mantener `PosteParadaIda` como único poste operativo del servicio.
- Verificar que ningún fallback de ruteo convierta una conexión faltante en una reversa operacional o una búsqueda hacia `PosteParadaVuelta`.
- Al atender Bosques:
  - Terminar intercambio de pasajeros.
  - Detener la cabecera en el poste de ida.
  - Mantener velocidad cero.
  - Conservar `Bosques` como próxima/última estación publicada.
  - No cambiar `_direccion_servicio`, ruta ni sentido local.
  - No liberar ni reasignar el tren como nueva salida.
- Si una conexión de ida no existe, detener el tren y emitir diagnóstico de ruta inválida; nunca intentar regresar para encontrar otra vía.

### Validación

- Ejecutar `test_servicio_ferroviario.gd` sin modificar su invariante `solo_ida`.
- Ejecutar recorrido completo y comprobar la secuencia `Plaza Constitución → … → Bosques`.
- Comprobar que Bosques es la última y única terminal operativa.
- Repetir con cuatro trenes y verificar que ninguno inicia una vuelta.

## Fase 2 — Estados ferroviarios públicos

Agregar un `enum EstadoOperacion` en `Tren`:

- `EN_TERMINAL_INICIAL`
- `EN_MARCHA`
- `DETENIDO_EN_ESTACION`
- `ESPERANDO_RESERVA`
- `DETENIDO_POR_EVENTO`
- `FINALIZADO_EN_BOSQUES`
- `INCOMPLETO`

Centralizar transiciones en `_establecer_estado(nuevo_estado, motivo)`.

Agregar señales públicas:

- `estado_operacion_cambiado(datos_tren)`
- `llego_a_estacion(datos_tren, datos_estacion)`
- `salio_de_estacion(datos_tren, datos_estacion)`
- `recorrido_finalizado(datos_tren)`
- `recorrido_incompleto(datos_tren, motivo)`

Agregar consultas seguras:

- `obtener_resumen_operativo() -> Dictionary`
- `obtener_estado_operacion() -> int`
- `obtener_id_operativo() -> int`

El resumen de tren tendrá: id, nombre, estado, servicio, sentido `ida`, estación próxima, distancia, velocidad, pasajeros, capacidad, retraso inicial `0` y resultado de recorrido.

### Validación

- Cada transición emite una sola señal.
- El tren inicia en `EN_TERMINAL_INICIAL` y sale a `EN_MARCHA`.
- Una parada intermedia usa `DETENIDO_EN_ESTACION`.
- Bosques pasa a `FINALIZADO_EN_BOSQUES` y permanece allí.
- El HUD actual sigue funcionando mediante sus señales existentes.

## Fase 3 — `SimulacionController`

Crear `scenes/simulation/simulacion_controller.gd` e instanciar `SimulacionController` como nodo del nivel `ramal_roca_main`. No será un autoload: cada nivel tendrá su propia flota y estado.

### API pública

- `obtener_trenes() -> Array[Dictionary]`
- `obtener_tren(id_tren: int) -> Dictionary`
- `obtener_estaciones() -> Array[Dictionary]`
- `obtener_estacion(id_estacion: String) -> Dictionary`
- `obtener_resumen_global() -> Dictionary`
- `agregar_tren() -> Dictionary`
- `eliminar_tren(id_tren: int) -> bool`

### Señales del controlador

- `tren_agregado(datos_tren)`
- `tren_eliminado(id_tren)`
- `tren_actualizado(datos_tren)`
- `tren_llego_estacion(id_tren, datos_estacion)`
- `tren_reanudo(id_tren)`
- `tren_finalizo(id_tren, resultado)`
- `estacion_actualizada(datos_estacion)`
- `resumen_global_actualizado(datos_resumen)`

### Resumen global inicial

Hasta que se implemente el módulo de estadísticas, devolver campos neutros y estables:

- pasajeros_esperando;
- pasajeros_en_viaje;
- pasajeros_transportados;
- trenes_activos;
- trenes_finalizados;
- trenes_incompletos;
- demora_promedio_s;
- concurrencia_maxima.

El controlador observará los grupos `trenes` y `estaciones`, conectará sus señales públicas y no leerá variables internas de ruta o de reservas.

### Validación

- Incluye los cuatro trenes de escena y los trenes agregados en runtime.
- Eliminar un tren actualiza el resumen y libera las referencias de HUD/cámara.
- Consultar resúmenes no inicia planificación de rutas ni cálculo de switches.

## Fase 4 — Comandos seguros para compañeros

Diego deja puntos de entrada seguros; los demás no manipulan trenes de forma directa.

- `pausar_simulacion()`
- `reanudar_simulacion()`
- `establecer_velocidad_simulacion(factor: float)`
- `obtener_velocidad_simulacion() -> float`
- `esta_pausada() -> bool`
- `velocidad_simulacion_cambiada(factor: float)`
- `detener_tren_temporalmente(id_tren, motivo, duracion)`
- `reanudar_tren(id_tren)`
- `finalizar_tren_incompleto(id_tren, motivo)`

Reglas:

- El factor es numérico y configurable por quien consuma la API: `1.0` es
  velocidad base, valores positivos aceleran o desaceleran y `0.0` pausa.
- La pausa global detiene la simulación sin destruir referencias del controlador.
- Los nombres `normal`, `rápida` y `ultra` no son estados técnicos: son presets
  opcionales de interfaz. Por ejemplo, `1.0`, `2.0` y `4.5`.
- El factor global es independiente de los multiplicadores de prueba por tren.
- Una detención externa conserva ruta, posición y reservas.
- Una finalización incompleta libera reservas y publica el resultado.
- Estos comandos no habilitan reversa ni salida desde Bosques.

## Fase 5 — Velocidad operativa

- Establecer velocidad máxima base de las formaciones en `50 km/h`.
- Conservar los multiplicadores de prueba existentes: velocidad hasta ×3 y aceleración/frenado hasta ×10.
- Medir `velocidad_media_marcha` con metros realmente recorridos durante `EN_MARCHA`, excluyendo estaciones, reservas y eventos.
- Exponer esa métrica en `obtener_resumen_operativo()`.
- Agregar una prueba que valide una media entre 35 y 55 km/h con valores base.

Los multiplicadores de prueba deben cambiar el tiempo de recorrido, nunca la ruta, el destino, el poste elegido ni la distancia ferroviaria.

## Fase 6 — Pruebas y documentación

- Mantener y ampliar `tools/test_servicio_ferroviario.gd` para validar estados y llegada final a Bosques.
- Mantener `tools/test_recorrido_completo.gd` como prueba de secuencia única Constitución → Bosques y detención final.
- Añadir pruebas de pausa, reanudación, evento temporal, recorrido incompleto y liberación de reservas.
- Crear `docs/api_simulacion.md` con la API pública, señales, resúmenes, comandos permitidos y restricciones de integración.

## Resultado esperado

Al finalizar, la simulación tendrá trenes que recorren exclusivamente Constitución → Bosques, se detienen definitivamente en Bosques y exponen una API estable. Los compañeros podrán implementar UI, métricas, estaciones, reloj y eventos sin modificar el recorrido ferroviario.
