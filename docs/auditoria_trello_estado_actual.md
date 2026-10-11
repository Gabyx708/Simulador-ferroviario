# Auditoría: Trello, planes y estado actual del juego

Fecha de auditoría: 2026-10-11.

## Alcance y evidencia

Se revisaron las diez tarjetas de trabajo reales del export de Trello, los planes actuales, la escena principal, scripts, pruebas y el árbol de trabajo vigente. Se excluyeron las tarjetas guía predeterminadas de Trello.

Alcance operativo vigente: el servicio actual es exclusivamente **Plaza Constitución → Bosques**. Al llegar a Bosques, cada tren queda detenido y su recorrido finaliza. La vuelta no forma parte de esta etapa.

### Pruebas ejecutadas

- `[x]` `tools/test_servicio_ferroviario.gd`: aprobó con 16 estaciones, 15 enlaces, cuatro trenes iniciales, un quinto en cola y reservas FIFO.
- `[x]` `tools/test_distancia_invariante.gd`: aprobó; los multiplicadores de prueba no cambian la distancia ferroviaria al próximo poste.
- `[~]` `tools/test_recorrido_completo.gd`: existe y comprueba las 16 detenciones hasta Bosques, pero no obtuvo resultado final dentro del límite disponible de ejecución. No se lo toma como validación aprobada todavía.

La advertencia de Godot relativa a `user://logs/godot.log` pertenece al entorno de ejecución y no impidió que las dos pruebas aprobadas finalizaran correctamente.

## Resultado por tarjeta Trello

| Tarjeta | Estado verificado |
| --- | --- |
| Buenas normas y estándares | `[~]` La rama actual es `feature/recorrido-completo`; el cumplimiento de flujo de ramas y pull requests no se puede demostrar sólo desde el código. |
| Definición del trabajo | `[~]` La definición está documentada, pero todavía faltan eventos, reloj, horarios y métricas globales que pide el objetivo. |
| Mapa recorrido Bosques–Constitución | `[~]` La red y el servicio Constitución → Bosques están implementados. Falta aceptar el recorrido completo en ejecución continua. |
| El tren frena y carga pasajeros | `[~]` Frenado, descenso, ascenso gradual y capacidad existen. La descripción de Trello menciona Poisson y `RelojSimulacion`; actualmente la generación es acumulativa, por tasa fija y sin reloj global. |
| Modelación de la estación | `[~]` Estaciones, postes, pasajeros, tasa individual y MultiMesh existen. Faltan perfil de demanda por hora, próximo tren, espera acumulada y resúmenes públicos. |
| Modelación del tren | `[~]` Ocho de once subtareas del checklist están completas y tienen código. Siguen pendientes velocidad media 35–55 km/h, retraso y eventos. |
| Velocímetro / HUD | `[~]` Velocidad, selección, cámara, ocupación, destino e itinerario existen. Falta aceptación manual completa y el listado global detallado. |
| Modelación de interfaz de usuario | `[~]` Existen panel de trenes, pruebas, switches, alta de tren y tablero individual. Faltan pausa global, reloj/fecha, estaciones, métricas y eventos. |
| Video de presentación | `[x]` Finalizada en Trello; no requiere validación de código. |
| Instalación del ambiente | `[x]` Finalizada en Trello; Godot 4.7.2 ejecuta el proyecto. |

## Confirmaciones técnicas

- `[x]` `ServicioConstitucionBosques` contiene 16 paradas y usa `solo_ida = true` en `levels/ramal_roca_main/ramal_roca_main.tscn`.
- `[x]` La finalización unilateral está implementada por `ServicioFerroviario.finaliza_en()`.
- `[x]` Existen cuatro trenes iniciales colocados directamente en la escena para poder editarlos desde Godot.
- `[x]` `TrackNetwork` implementa reservas de secciones y switches con cola FIFO.
- `[x]` Las estaciones resuelven puntos de parada multi-vía usando postes proyectados sobre vías paralelas.
- `[x]` El velocímetro muestra velocidad, próxima estación, distancia, ocupación, flujo de pasajeros e itinerario para el tren seleccionado.
- `[ ]` No existe `SimulacionController`, `RelojSimulacion`, módulo de eventos ni módulo de estadísticas globales.
- `[ ]` No existe API pública de pausa ni factor global numérico de velocidad de simulación.
- `[~]` La velocidad máxima base actual es `90 km/h`; todavía no hay una métrica ni prueba de velocidad media operativa entre 35 y 55 km/h.
- `[~]` La generación actual de pasajeros usa `tasa_generacion_pasajeros * delta`; no hay perfil por hora, Poisson ni integración con reloj.

## Verificación de los planes

### `docs/plan_diego.md`

El plan coincide con la implementación y el alcance actual: servicio de ida, Bosques como final, publicación de estados, `SimulacionController`, comandos seguros, factor global numérico, medición de velocidad y pruebas.

- `[x]` Núcleo de ida y topología ferroviaria.
- `[~]` Recorrido continuo completo hasta Bosques: hay prueba, pero aún falta una ejecución aprobada de punta a punta.
- `[ ]` Estados públicos, controlador, pausa/factor global, comandos de eventos y media operativa.

### `docs/plan_para_lo_pendiente.md`

El reparto del trabajo es consistente con el código: Diego conserva el núcleo ferroviario; el resto del equipo debe consumir una API pública, no rutas ni variables internas.

Existe una única inconsistencia documental: permanecen referencias históricas a Bosques → Constitución dentro de la sección de Diego. El encabezado de alcance las declara fuera de la etapa actual, pero conviene marcarlas como historial u ocultarlas al limpiar el documento.

## Estado del árbol de trabajo

La auditoría se hizo sobre el estado vigente, incluidos cambios aún no consolidados en Git:

- `scenes/tracks/track_network.gd`
- `ui/components/velocimetro/velocimetro.tscn`
- `ui/screens/hud.gd`
- `ui/screens/hud.tscn`

Esos cambios suman 274 líneas agregadas y 43 eliminadas. Afectan red, HUD, velocímetro y switches; deben consolidarse en un commit antes de considerarlos una entrega estable para el equipo.

## Conclusión

El recorrido ferroviario dirigido Constitución → Bosques está avanzado y cuenta con validaciones estructurales y de distancia. La mayor brecha contra Trello no está en el trazado: está en la capa global de simulación. El siguiente bloque imprescindible es publicar `SimulacionController` y estados operativos, porque habilita reloj, horarios, demanda temporal, eventos, estadísticas y los paneles globales sin que el resto del equipo modifique el núcleo ferroviario.
