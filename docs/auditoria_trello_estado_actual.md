# Auditoría: Trello, planes y estado actual del juego

Fecha de auditoría: 2026-10-11.

## Alcance y evidencia

Se revisaron las diez tarjetas de trabajo reales del export de Trello, los planes actuales, la escena principal, scripts, pruebas y el árbol de trabajo vigente. Se excluyeron las tarjetas guía predeterminadas de Trello.

Alcance operativo vigente: el servicio actual es exclusivamente **Plaza Constitución → Bosques**. Al llegar a Bosques, cada tren queda detenido y su recorrido finaliza. La vuelta no forma parte de esta etapa.

### Pruebas ejecutadas

- `[~]` `tools/test_servicio_ferroviario.gd`: conserva la topología esperada, pero falla su validación geométrica porque Plaza Constitución no resuelve candidato para `PosteParadaIda`; queda fuera de aceptación.
- `[x]` `tools/test_distancia_invariante.gd`: aprobó; los multiplicadores y la edición de velocidad base no cambian la distancia ferroviaria al próximo poste.
- `[x]` `tools/test_recorrido_completo.gd`: aprobó la secuencia de 16 detenciones y la finalización en Bosques.
- `[x]` `tools/test_comandos_simulacion.gd`, `tools/test_hud_velocidad_simulacion.gd` y `tools/test_velocidad_operativa.gd`: aprobaron comandos seguros, slider global de 0.0× a 10.0× y media operativa de 35–55 km/h.

La advertencia de Godot relativa a `user://logs/godot.log` pertenece al entorno de ejecución y no impidió que las pruebas aprobadas finalizaran correctamente.

## Resultado por tarjeta Trello

| Tarjeta | Estado verificado |
| --- | --- |
| Buenas normas y estándares | `[~]` La rama actual es `feature/recorrido-completo`; el cumplimiento de flujo de ramas y pull requests no se puede demostrar sólo desde el código. |
| Definición del trabajo | `[~]` La definición está documentada, pero todavía faltan eventos, reloj, horarios y métricas globales que pide el objetivo. |
| Mapa recorrido Bosques–Constitución | `[~]` La red y el servicio Constitución → Bosques están implementados y el recorrido completo aprobó. La vuelta sigue fuera del alcance actual. |
| El tren frena y carga pasajeros | `[~]` Frenado, descenso, ascenso gradual y capacidad existen. La descripción de Trello menciona Poisson y `RelojSimulacion`; actualmente la generación es acumulativa, por tasa fija y sin reloj global. |
| Modelación de la estación | `[~]` Estaciones, postes, pasajeros, tasa individual y MultiMesh existen. Faltan perfil de demanda por hora, próximo tren, espera acumulada y resúmenes públicos. |
| Modelación del tren | `[~]` Velocidad media 35–55 km/h, estados y comandos seguros están implementados. Siguen pendientes retraso/horarios y eventos de dominio. |
| Velocímetro / HUD | `[~]` Velocidad, selección, cámara, ocupación, destino e itinerario existen; también slider global. Falta listado global detallado. |
| Modelación de interfaz de usuario | `[~]` Existen panel de trenes, pruebas, switches, alta y slider global. Faltan reloj/fecha, estaciones, métricas y eventos. |
| Video de presentación | `[x]` Finalizada en Trello; no requiere validación de código. |
| Instalación del ambiente | `[x]` Finalizada en Trello; Godot 4.7.2 ejecuta el proyecto. |

## Confirmaciones técnicas

- `[x]` `ServicioConstitucionBosques` contiene 16 paradas y usa `solo_ida = true` en `levels/ramal_roca_main/ramal_roca_main.tscn`.
- `[x]` La finalización unilateral está implementada por `ServicioFerroviario.finaliza_en()`.
- `[x]` Existen cuatro trenes iniciales colocados directamente en la escena para poder editarlos desde Godot.
- `[x]` `TrackNetwork` implementa reservas de secciones y switches con cola FIFO.
- `[x]` Las estaciones resuelven puntos de parada multi-vía usando postes proyectados sobre vías paralelas.
- `[x]` El velocímetro muestra velocidad, próxima estación, distancia, ocupación, flujo de pasajeros e itinerario para el tren seleccionado.
- `[x]` Existe `SimulacionController` por nivel con snapshots, IDs operativos, alta/baja, señales y comandos seguros. Reloj, eventos de dominio y estadísticas avanzadas siguen pendientes.
- `[x]` Existe API pública de pausa y factor global numérico; el HUD permite probar entre `0.0×` y `10.0×`.
- `[x]` La velocidad máxima nominal es `50 km/h`, editable por instancia, y la media operativa se validó entre 35 y 55 km/h.
- `[~]` La generación actual de pasajeros usa `tasa_generacion_pasajeros * delta`; no hay perfil por hora, Poisson ni integración con reloj.

## Verificación de los planes

### `docs/plan_diego.md`

El plan coincide con la implementación y el alcance actual: servicio de ida, Bosques como final, publicación de estados, `SimulacionController`, comandos seguros, factor global numérico, medición de velocidad y pruebas.

- `[x]` Núcleo de ida y topología ferroviaria.
- `[x]` Recorrido continuo completo hasta Bosques: validado por prueba de punta a punta.
- `[x]` Estados públicos, controlador, pausa/factor global, comandos de eventos y media operativa.

### `docs/plan_para_lo_pendiente.md`

El reparto del trabajo es consistente con el código: Diego conserva el núcleo ferroviario; el resto del equipo debe consumir una API pública, no rutas ni variables internas.

Las referencias a Bosques → Constitución se consideran trabajo futuro: el alcance vigente continúa siendo sólo ida hasta Bosques.

## Estado del árbol de trabajo

La auditoría se hizo sobre el árbol de trabajo vigente, que incluye fases 2–6,
el controlador, controles globales y documentación operativa aún pendientes de
consolidación en Git.

## Conclusión

El recorrido ferroviario dirigido Constitución → Bosques, los estados públicos,
el controlador, la pausa/factor global y la velocidad operativa están
implementados. La siguiente brecha contra Trello corresponde a reloj,
horarios, demanda temporal, eventos de dominio, estadísticas y paneles
globales. La única limitación ferroviaria conocida es la validación geométrica
de Plaza Constitución en `test_servicio_ferroviario.gd`.
