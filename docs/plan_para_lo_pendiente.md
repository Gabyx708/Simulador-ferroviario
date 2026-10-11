# Plan actualizado y verificado contra Trello y el proyecto

Leyenda:

- `[x]` implementado
- `[~]` existe parcialmente o la base está lista, pero falta completar/validar
- `[ ]` falta

Godot 4.7.2 está disponible en el equipo. Pasaron `test_recorrido_completo.gd`, `test_finalizacion_bosques.gd`, `test_ruta_invalida_ida.gd`, `test_simulacion_controller.gd`, `test_comandos_simulacion.gd`, `test_hud_velocidad_simulacion.gd` y `test_velocidad_operativa.gd`. `test_servicio_ferroviario.gd` aún falla al validar que Plaza Constitución tenga candidato para `PosteParadaIda`; queda fuera de aceptación hasta que se revise esa geometría.

> Alcance operativo vigente. La simulación actual es exclusivamente Constitución → Bosques. Al llegar a Bosques, el tren queda detenido y el servicio finaliza. Las referencias históricas a vuelta, ambos sentidos o `PosteParadaVuelta` no forman parte de las tareas de los compañeros en esta etapa. El detalle actualizado de Diego está en `docs/plan_diego.md`.

## Regla de trabajo

Diego mantiene el núcleo ferroviario. Nadie más modifica:

- `tren.gd`
- `track_network.gd`
- `servicio_ferroviario.gd`
- Rutas, `Path3D`, switches, reservas, señales de marcha ni geometría de vías.

Diego ya entregó las fases 2–6: `SimulacionController`, estados públicos,
comandos seguros, velocidad operativa y documentación. Los compañeros usarán
resúmenes, señales y comandos de alto nivel. No accederán a variables internas
como `_ruta_pasos`, `_avance`, `_odometro_ferroviario` o `_desvios_switch`.

## Diego — Recorrido completo y núcleo ferroviario

Tarjetas Trello: **#9 Mapa** y **#11 Tren**

- `[x]` Constitución → Bosques, 16 estaciones físicas y 15 conexiones.
- `[x]` Ruteo por red, no por orden de `Path3D`.
- `[x]` Paradas multi-vía, prioridad de parada en vía de marcha y frenado al poste.
- `[x]` Cambios de aguja suaves por coche y odómetro ferroviario independiente de la velocidad.
- `[x]` Cuatro trenes iniciales, reservas de tramos/switches y cola FIFO.
- `[x]` Servicio dirigido, protección contra ciclos y retorno incorrecto en el sentido de ida.
- `[x]` Aceleración, frenado, detención y carga/descarga progresiva de pasajeros.
- `[x]` Velocidad actual, ocupación, pasajeros e itinerario del tren seleccionado.
- `[x]` Eliminar tren.
- `[x]` Estados ferroviarios públicos y señales de estado, llegada/salida, finalización e incompleto.
- `[x]` `SimulacionController` por nivel para consultas, snapshots, resumen global inicial, alta y baja de trenes.
- `[~]` La alta del HUD ya pasa por el controlador; migrar el resto de los paneles y consultas del HUD a la API es trabajo de integración pendiente.
- `[x]` Velocidad nominal de 50 km/h editable desde Inspector y promedio operativo validado entre 35–55 km/h.
- `[~]` Bosques → Constitución: la clase genérica ya sabe invertir la dirección al llegar a una terminal si el servicio no es `solo_ida`; está en [tren.gd](../scenes/train/tren.gd). Pero la escena configura `solo_ida = true`, por lo que el juego termina en Bosques.
- `[ ]` Configurar y validar el recorrido real de vuelta con `PosteParadaVuelta`.
- `[ ]` Probar el ciclo completo Constitución → Bosques → Constitución.
- `[x]` Configurar valor nominal editable y prueba de velocidad promedio real entre 35 y 55 km/h.
- `[x]` Estados ferroviarios: `EN_TERMINAL_INICIAL`, `EN_MARCHA`, `DETENIDO_EN_ESTACION`, `ESPERANDO_RESERVA`, `DETENIDO_POR_EVENTO`, `FINALIZADO_EN_BOSQUES`, `INCOMPLETO`.
- `[x]` Señales públicas de estado, llegada/salida, finalización e incompleto, conservando las señales que usa el HUD actual.
- `[x]` `SimulacionController` consulta trenes/estaciones/resumen y administra altas/bajas sin exponer detalles internos.
- `[x]` Comandos de pausa, velocidad global y operación temporal/incompleta: fase 4 implementada y probada con `test_comandos_simulacion.gd`.
- `[x]` Documentar la API ferroviaria para el equipo en `docs/api_simulacion.md`.

### Entrega de Diego: API pública y comandos de fase 4

- `[x]` Consultas, señales y resumen del controlador; IDs operativos asignados por nivel y snapshots sin nodos internos.
- `[x]` `agregar_tren()` y `eliminar_tren(id)` con resultado estable y preservación de la cola existente.
- `[x]` Comandos seguros de fase 4 con contrato de velocidad, pausa, evento temporal, estados incompatibles y liberación de reservas.

Conclusión: fases 2–6 implementadas. La limitación geométrica de Constitución
permanece registrada y fuera de aceptación hasta que se decida revisarla.

## Persona 2 — Paneles y diseño de interfaz

Tarjeta Trello: **#12 UI**

- `[x]` HUD compacto, plegable y con estilo unificado con el velocímetro.
- `[x]` Panel de trenes, pruebas de marcha y switches.
- `[x]` Selección de tren, tablero individual, velocidad, ocupación, próxima estación e itinerario.
- `[x]` Cámara cenital/trasera conectada al coche principal.
- `[x]` Panel de switches con `CheckButton` e indicador 3D.
- `[x]` Agregar tren desde Constitución y colocarlo en cola cuando no hay vía disponible.
- `[x]` Eliminar el tren seleccionado.
- `[~]` Listado de trenes: hoy muestra principalmente el nombre y selección; no muestra velocidad, ocupación, estado y próxima estación en cada fila.
- `[~]` Slider global de velocidad `0.0×–10.0×` disponible en Pruebas de marcha; faltan botones dedicados de pausa/play si la UI final los requiere.
- `[ ]` Panel de fecha y hora simulada.
- `[ ]` Listado de estaciones.
- `[ ]` Panel de métricas globales.
- `[ ]` UI para crear y cancelar eventos.
- `[ ]` Botón explícito “Ir a tren”; hoy seleccionar un tren actualiza la cámara, pero no existe esa acción con nombre propio.

### Restricción de Persona 2

- `[~]` Migrar todo consumo a `SimulacionController`: el botón de alta ya usa la API, pero selección y paneles individuales aún usan las señales/referencias actuales de trenes.
- `[ ]` No calcular rutas, pasajeros, retrasos ni métricas dentro del HUD.
- `[ ]` No modificar trenes, estaciones, switches ni vías.

Conclusión: el HUD individual está avanzado; falta el HUD de operación global.

## Persona 3 — Cálculos globales y estadísticas

Tarjeta Trello: **#12 UI**, apartado datos globales

- `[x]` Cada estación ya conserva pasajeros esperando, pasajeros saliendo, históricos, subidos y bajados.
- `[x]` Cada tren publica pasajeros actuales y capacidad.
- `[ ]` `EstadisticasSimulacion` o estructura equivalente para centralizar cálculos.
- `[ ]` Agregador global de pasajeros esperando, en viaje y transportados.
- `[ ]` Conteo de trenes activos, finalizados e incompletos.
- `[ ]` Tiempo de espera global y por estación.
- `[ ]` Demora promedio.
- `[ ]` Concurrencia actual y máxima por estación.
- `[ ]` Emitir `resumen_global_actualizado` para que el HUD sólo muestre resultados.
- `[ ]` Pruebas unitarias con trenes/estaciones simulados, sin cargar la red ferroviaria real.

### Restricción de Persona 3

- `[ ]` Trabajar sobre `Dictionary` de resumen y señales públicas.
- `[ ]` No acceder directamente a nodos `Tren`, `Estacion` o `TrackNetwork`.
- `[ ]` No modificar física, rutas ni reservas.

Conclusión: hay datos de origen, pero todavía no existe el sistema que los agrupa y calcula.

## Persona 4 — Estaciones y demanda del servicio de ida

Tarjeta Trello: **#10 Estación**

- `[x]` Estaciones con nombre, postes de parada ida/vuelta, largo, ancho multi-vía y proyección sobre vías paralelas.
- `[x]` Cantidad de personas esperando.
- `[x]` Subida/bajada de pasajeros en tiempo real.
- `[x]` Información de estación: pasajeros actuales, históricos, subidos y bajados.
- `[x]` Tasa individual de generación de pasajeros mediante `tasa_generacion_pasajeros`.
- `[x]` Pasajeros visuales optimizados con `MultiMesh`.
- `[x]` El nivel actual opera exclusivamente Constitución → Bosques; Bosques es la terminal final del servicio.
- `[ ]` Perfil de demanda según hora simulada.
- `[ ]` Asociación visible entre cada estación y el servicio Constitución → Bosques.
- `[ ]` Próximo tren de ida hacia Bosques en cada estación.
- `[ ]` Tiempo de espera acumulado y concurrencia máxima por estación.
- `[ ]` Datos resumidos para el listado de estaciones del HUD.
- `[ ]` Pruebas de estación terminal e intermedia para el servicio de ida.

### Restricción de Persona 4

- `[ ]` Puede editar configuración y datos de `Estacion`.
- `[ ]` No modifica cómo un tren planifica o alcanza una estación.
- `[ ]` Publica datos de estación hacia `SimulacionController`; no modifica el HUD directamente.

Conclusión: la infraestructura de estación está hecha; faltan las reglas de operación temporal y los datos del servicio de ida para el HUD.

## Persona 5 — Reloj, horarios y eventos

Tarjetas Trello: **#11 Tren** y **#12 UI**

- `[x]` Multiplicadores de prueba por tren: velocidad máxima hasta ×3 y aceleración/frenado hasta ×10.
- `[x]` Demora inicial y tiempo de parada configurables por tren.
- `[~]` Eliminar tren ya existe, por lo que puede reutilizarse como consecuencia técnica de un desperfecto; falta el modelo de evento, su estado y sus métricas.
- `[x]` Pausa global de simulación mediante el controlador.
- `[ ]` Reloj de simulación.
- `[ ]` Fecha simulada.
- `[x]` Factor numérico libre de velocidad global mediante `establecer_velocidad_simulacion(factor: float)`: `1.0` es base, un valor positivo acelera o desacelera y `0.0` pausa.
- `[~]` Slider global libre `0.0×–10.0×` ya disponible; los presets visuales normal `1.0`, rápida `2.0` y ultra `4.5` y su vínculo con reloj siguen pendientes.
- `[ ]` Horario previsto por estación y servicio.
- `[ ]` Cálculo de llegada real, retraso y estado “en tiempo / retrasado”.
- `[ ]` Falla eléctrica.
- `[ ]` Piquete.
- `[ ]` Desperfecto mecánico.
- `[ ]` Panel de comandos de eventos para Persona 2.

### Restricción de Persona 5

- `[ ]` Crear eventos como datos y comandos de alto nivel.
- `[ ]` Solicitar al controlador detener, reanudar o finalizar un tren.
- `[ ]` No modificar posición, velocidad, ruta, reservas o switches directamente.
- `[ ]` No acceder a variables internas de `Tren`.

Conclusión: esta área está prácticamente pendiente. Los controles de prueba actuales no reemplazan una simulación temporal global.

## Dependencias reales e integración

1. **Diego** completó fases 2–6 y documentó la API; el candidato geométrico de Constitución queda como limitación conocida fuera de aceptación.
2. **Persona 5** crea reloj, horarios y eventos usando los comandos seguros de fase 4 ya disponibles.
3. **Persona 4** conecta demanda y datos de las estaciones al reloj para el servicio de ida.
4. **Persona 3** agrega métricas globales desde los resúmenes públicos.
5. **Persona 2** conecta paneles, listados y controles al controlador.

## Criterio de protección del núcleo ferroviario

Una tarea de compañero está mal integrada si necesita:

- tocar `tren.gd`, `track_network.gd` o `servicio_ferroviario.gd`;
- acceder a `_ruta_pasos`, `_avance`, `_odometro_ferroviario` o `_desvios_switch`;
- mover un tren con `global_position`;
- forzar `invertir_sentido`;
- modificar reservas o estados físicos de switches.

Toda interacción externa debe entrar por `SimulacionController`. Así los compañeros pueden avanzar con UI, cálculos, estaciones, reloj y eventos sin poner en riesgo el recorrido ferroviario validado.
