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
- [x] Estados ferroviarios publicados, transiciones, señales de llegada/salida y resultado.
- [x] `SimulacionController` por nivel con consultas, snapshots, resumen global inicial y administración de trenes.
- [x] El HUD usa la API del controlador para agregar trenes; conserva las señales de tren actuales.
- [x] Velocidad nominal editable de 50 km/h y media operativa validada entre 35 y 55 km/h.

`tools/test_servicio_ferroviario.gd` comprueba las 16 estaciones, los 15 enlaces, la flota y las reservas FIFO; en la corrida actual falla antes de completar porque Plaza Constitución no resuelve un candidato para `PosteParadaIda`.

## Fase 1 — Consolidar el servicio de ida

**Estado de implementación: completada.** La red además traduce los extremos
topológicos cuando una edición manual invierte los puntos de un `Path3D`; así el
tren conserva su sentido físico de marcha hacia Yrigoyen/Bosques.

- [x] Se conserva `solo_ida = true` en `ServicioConstitucionBosques`.
- [x] `PosteParadaIda` es el único poste operativo del servicio.
- [x] Ningún fallback convierte una conexión faltante en reversa operacional ni busca `PosteParadaVuelta`.
- [x] Al atender Bosques:
  - finaliza el intercambio de pasajeros;
  - la cabecera queda detenida en el poste de ida, con velocidad cero;
  - `Bosques` continúa como última estación publicada;
  - no se cambian `_direccion_servicio`, ruta ni sentido local;
  - el tren no se libera ni se reasigna como salida.
- [x] Ante una conexión de ida inexistente, el tren se detiene, conserva el diagnóstico y emite una única señal de ruta inválida.

### Validación

- [~] `test_servicio_ferroviario.gd` conserva el invariante `solo_ida`, pero su validación geométrica falla en Plaza Constitución y queda fuera de aceptación.
- [x] `test_recorrido_completo.gd` cubre la secuencia `Plaza Constitución → … → Bosques`.
- [x] `test_finalizacion_bosques.gd` cubre la terminal única y la no reanudación.
- [x] `test_ruta_invalida_ida.gd` cubre que una ruta faltante no invierte el sentido operativo.
- [~] Las pruebas de recorrido completo, ruta inválida y terminal pasaron en Godot 4.7.2. `test_servicio_ferroviario.gd` sigue fallando porque Plaza Constitución no resuelve un candidato para `PosteParadaIda`; la geometría queda como limitación conocida fuera de aceptación.

## Fase 2 — Estados ferroviarios públicos

**Estado de implementación: completada y probada en Godot 4.7.2.**

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

- [x] Cada cambio de estado emite una sola señal; ruta incompleta y cierre terminal tienen cobertura de emisión única.
- [x] El tren inicia en `EN_TERMINAL_INICIAL`, sale a `EN_MARCHA` y las paradas publican llegada/salida.
- [x] Bosques publica `FINALIZADO_EN_BOSQUES` y el servicio no se reanuda.
- [x] Los snapshots no contienen referencias a nodos ni datos privados de ruteo.
- [x] Las señales existentes del HUD se mantienen.
- [x] Pasaron `test_ruta_invalida_ida.gd`, `test_finalizacion_bosques.gd` y `test_recorrido_completo.gd`.

## Fase 3 — `SimulacionController`

**Estado de implementación: completada y probada en Godot 4.7.2.**

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

- [x] Registra los cuatro trenes de escena, trenes agregados y las 16 estaciones; asigna IDs operativos por nivel.
- [x] Eliminar un tren actualiza el registro y dispara la señal que usan HUD/cámara para soltar referencias.
- [x] Consultar resúmenes lee snapshots y contadores, sin pedir rutas, switches ni reservas.
- [x] `test_simulacion_controller.gd` pasó en Godot 4.7.2.

## Fase 4 — Comandos seguros para compañeros

**Estado: implementada.** `test_comandos_simulacion.gd` valida en Godot 4.7.2 pausa/factor, congelación del evento, reanudación automática/manual, comandos inválidos y finalización incompleta con liberación de reservas.

### Contrato de velocidad y pausa global

- El controlador conserva el factor activo y el último factor positivo. Hereda `Engine.time_scale` al entrar al árbol (normalmente `1.0`) y lo restaura al salir.
- `establecer_velocidad_simulacion(factor: float) -> bool` aceptará `factor >= 0`: cero pausará; un valor positivo reanudará y pasará a ser el nuevo factor de restauración. Rechazará valores negativos o no finitos sin cambiar el estado.
- `pausar_simulacion() -> void` fijará el factor activo a `0.0` y conservará el último factor positivo. `reanudar_simulacion() -> void` restaurará ese factor. Repetir una misma operación no emitirá señales duplicadas.
- `obtener_velocidad_simulacion() -> float` devolverá el factor activo y `esta_pausada() -> bool` será verdadero exactamente cuando el factor activo sea cero.
- El controlador aplicará el factor a `Engine.time_scale` y emitirá `velocidad_simulacion_cambiada(factor)` sólo si cambia el factor activo. Al salir del árbol, restaurará el factor que estaba vigente antes de tomar control.
- El factor global será independiente de los multiplicadores de prueba por tren. Los presets `normal=1.0`, `rápida=2.0` y `ultra=4.5` serán opcionales de UI y no formarán parte del modelo interno.

### Comandos por tren y resultados

- `detener_tren_temporalmente(id_tren: int, motivo: String, duracion_s: float) -> bool` aceptará sólo trenes registrados, activos y con motivo no vacío y duración finita mayor que cero. Rechazará estados terminales, incompletos, eliminados o ya detenidos por evento.
- Al aceptar una detención, `Tren` guardará el estado operativo previo y el tiempo restante; pondrá la velocidad en cero, mantendrá posición, ruta y reservas, y publicará `DETENIDO_POR_EVENTO`. No alterará la parada de estación que estuviera pendiente.
- La duración se medirá en segundos simulados: la pausa global congela el contador y la velocidad global lo escala. Al expirar, el tren restaura su estado operativo previo; si estaba en marcha, acelerará de nuevo desde la posición conservada.
- `reanudar_tren(id_tren: int) -> bool` reanudará sólo trenes en `DETENIDO_POR_EVENTO`, cancelará el tiempo restante y restaurará su estado previo. Intentos sobre otros estados devolverán `false`.
- `finalizar_tren_incompleto(id_tren: int, motivo: String) -> bool` aceptará sólo trenes registrados no eliminados ni finalizados. Detendrá el tren, publicará `INCOMPLETO`, emitirá una sola señal de resultado, liberará las reservas ferroviarias y rechazará cualquier reanudación posterior.
- Finalizar como incompleto no borrará el nodo: conservará el snapshot para consulta y estadísticas. Ninguno de estos comandos habilitará reversa, planificación alternativa ni salida desde Bosques.
- Todos los comandos rechazarán IDs inexistentes y estados incompatibles con `false`; no cambiarán nada al rechazarse. Los resultados y señales se publicarán mediante la API del controlador y los snapshots de fase 2.

### Validación de fase 4

- [x] Pausar y reanudar conserva el factor previo; factor cero equivale a pausa y un factor positivo restaura la marcha global.
- [x] Los valores negativos y no finitos se rechazan sin modificar factor ni emitir señal.
- [x] Una detención por evento congela el tren, mantiene posición/ruta/reservas, respeta el tiempo simulado y reanuda automáticamente una sola vez.
- [x] Pausar globalmente durante un evento congela su temporizador; reanudar globalmente permite que continúe.
- [x] Reanudar manualmente cancela el temporizador; comandos inválidos o duplicados no alteran el tren.
- [x] Finalizar incompleto libera todas las reservas, publica motivo/resultado una sola vez y no permite reanudación.
- [x] Trenes en Bosques, incompletos o eliminados no pueden recibir detenciones/reanudaciones incompatibles.
- [x] Los multiplicadores de prueba por tren permanecen independientes del factor global.
- [x] `test_recorrido_completo.gd` pasó y las señales existentes del HUD se conservan.

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

**Estado: implementada y probada en Godot 4.7.2.**

- [x] `50 km/h` es el valor nominal de `Tren` y `TrenCSR`; la propiedad sigue
  editable por instancia desde el Inspector, sin rango ni límite impuesto.
- [x] Los factores internos de prueba se conservan: velocidad hasta ×3 y
  aceleración/frenado hasta ×10.
- [x] `velocidad_media_marcha_kmh` mide metros efectivamente recorridos por
  segundos simulados de movimiento en `EN_MARCHA`; excluye estación, reserva,
  eventos, pausa, terminal e incompleto.
- [x] `test_velocidad_operativa.gd` valida la base editable y una media dentro
  del rango operativo de 35–55 km/h.

Los multiplicadores cambian la dinámica o el tiempo de recorrido, nunca la
ruta, el destino, el poste elegido ni la distancia ferroviaria.

## Fase 6 — Pruebas y documentación

**Estado: implementada.**

- [x] Se mantienen las regresiones de recorrido, terminal, ruta inválida,
  controlador, comandos y slider global del HUD.
- [x] `test_distancia_invariante.gd` cubre la nueva base de 50 km/h y confirma
  que la edición de velocidad desde runtime/Inspector no cambia la distancia.
- [x] `docs/api_simulacion.md` documenta snapshots, señales, comandos,
  velocidad global, métrica de marcha y restricciones de integración.
- [~] `test_servicio_ferroviario.gd` queda fuera de aceptación de estas fases:
  conserva el fallo geométrico conocido de `PosteParadaIda` en Constitución.

La guía de integración para el equipo está en `docs/api_simulacion.md`; las
instrucciones de trabajo y pruebas están en `docs/instrucciones.md`.

## Resultado esperado

Al finalizar, la simulación tendrá trenes que recorren exclusivamente Constitución → Bosques, se detienen definitivamente en Bosques y exponen una API estable. Los compañeros podrán implementar UI, métricas, estaciones, reloj y eventos sin modificar el recorrido ferroviario.
