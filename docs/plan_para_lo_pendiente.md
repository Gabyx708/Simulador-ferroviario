**# Plan actualizado y verificado contra Trello y el proyecto**



**Leyenda:**



**- `\[x]` implementado**

**- `\[\~]` existe parcialmente o la base está lista, pero falta completar/validar**

**- `\[ ]` falta**



**La prueba \[test\_servicio\_ferroviario.gd](C:\\Users\\diego\\Boveda\\04-Facultad\\2026\\2C\\Programacion%20en%20tiempo%20real\\Nueva%20carpeta\\Simulador-ferroviario\\tools\\test\_servicio\_ferroviario.gd) pasó correctamente: 16 estaciones, 15 enlaces, cuatro trenes iniciales, quinto en cola y reservas FIFO.**



> **Alcance operativo vigente.** La simulación actual es exclusivamente Constitución → Bosques. Al llegar a Bosques, el tren queda detenido y el servicio finaliza. Las referencias históricas a vuelta, ambos sentidos o `PosteParadaVuelta` no forman parte de las tareas de los compañeros en esta etapa. El detalle de las tareas de Diego se conserva sin cambios en `docs/plan_diego.md`.



**## Regla de trabajo**



**Diego mantiene el núcleo ferroviario. Nadie más modifica:**



**- `tren.gd`**

**- `track\_network.gd`**

**- `servicio\_ferroviario.gd`**

**- Rutas, `Path3D`, switches, reservas, señales de marcha ni geometría de vías.**



**Diego entregará `SimulacionController`, la única API pública para el resto. Los compañeros usarán resúmenes, señales y comandos de alto nivel; no accederán a variables internas como `\_ruta\_pasos`, `\_avance`, `\_odometro\_ferroviario` o `\_desvios\_switch`.**



**## Diego — Recorrido completo y núcleo ferroviario**



**Tarjetas Trello: \*\*#9 Mapa\*\* y \*\*#11 Tren\*\***



**- `\[x]` Constitución → Bosques, 16 estaciones físicas y 15 conexiones.**

**- `\[x]` Ruteo por red, no por orden de `Path3D`.**

**- `\[x]` Paradas multi-vía, prioridad de parada en vía de marcha y frenado al poste.**

**- `\[x]` Cambios de aguja suaves por coche y odómetro ferroviario independiente de la velocidad.**

**- `\[x]` Cuatro trenes iniciales, reservas de tramos/switches y cola FIFO.**

**- `\[x]` Servicio dirigido, protección contra ciclos y retorno incorrecto en el sentido de ida.**

**- `\[x]` Aceleración, frenado, detención y carga/descarga progresiva de pasajeros.**

**- `\[x]` Velocidad actual, ocupación, pasajeros e itinerario del tren seleccionado.**

**- `\[x]` Eliminar tren.**

**- `\[\~]` Velocidad promedio 35–55 km/h: el Trello la marca visualmente como hecha, pero su checklist aún deja pendiente configurar y validar ese promedio real.**

**- `\[\~]` Bosques → Constitución: la clase genérica ya sabe invertir la dirección al llegar a una terminal si el servicio no es `solo\_ida`; está en \[tren.gd](C:\\Users\\diego\\Boveda\\04-Facultad\\2026\\2C\\Programacion%20en%20tiempo%20real\\Nueva%20carpeta\\Simulador-ferroviario\\scenes\\train\\tren.gd). Pero la escena configura `solo\_ida = true`, por lo que el juego termina en Bosques.**

**- `\[ ]` Configurar y validar el recorrido real de vuelta con `PosteParadaVuelta`.**

**- `\[ ]` Probar el ciclo completo Constitución → Bosques → Constitución.**

**- `\[ ]` Configurar límites operativos y prueba de velocidad promedio real entre 35 y 55 km/h.**

**- `\[ ]` Estados ferroviarios explícitos: `EN\_TERMINAL`, `EN\_MARCHA`, `DETENIDO\_EN\_ESTACION`, `ESPERANDO\_RESERVA`, `FINALIZADO`, `INCOMPLETO`.**

**- `\[\~]` Señales para HUD: ya existen velocidad, parada, reanudación, pasajeros, ruta, selección y eliminación; faltan señales de estado operativo, retraso, finalización e incidente.**

**- `\[ ]` `SimulacionController` o API global única para que otros módulos consulten trenes, estaciones y métricas sin tocar `Tren`.**

**- `\[ ]` Documentar la API ferroviaria para el equipo.**



**### Entrega obligatoria de Diego: `SimulacionController`**



**- `\[ ]` `obtener\_trenes()`, `obtener\_estaciones()`, `obtener\_tren(id)`, `obtener\_estacion(id)`.**

**- `\[ ]` `obtener\_resumen\_global()` con valores neutros inicialmente.**

**- `\[ ]` `agregar\_tren()` y `eliminar\_tren(id)`.**

**- `\[ ]` Señales: `tren\_actualizado`, `tren\_llego\_estacion`, `tren\_reanudo`, `tren\_finalizo`, `estacion\_actualizada`, `resumen\_global\_actualizado`.**

**- `\[ ]` Comandos seguros: `pausar\_simulacion`, `reanudar\_simulacion`, `establecer\_velocidad\_simulacion(factor: float)`, `obtener\_velocidad\_simulacion`, `esta\_pausada`, `velocidad\_simulacion\_cambiada`, `detener\_tren\_temporalmente`, `reanudar\_tren`, `finalizar\_tren\_incompleto`.**

**- `\[ ]` Resúmenes de tren sin nodos internos: id, estado, servicio, sentido, próxima estación, distancia, velocidad, pasajeros, capacidad y retraso.**



**Conclusión: Diego tiene resuelta la mayor parte del trabajo complejo. Debe consolidar el servicio de ida y exponer una interfaz estable antes de que el resto conecte sus módulos.**



**## Persona 2 — Paneles y diseño de interfaz**



**Tarjeta Trello: \*\*#12 UI\*\***



**- `\[x]` HUD compacto, plegable y con estilo unificado con el velocímetro.**

**- `\[x]` Panel de trenes, pruebas de marcha y switches.**

**- `\[x]` Selección de tren, tablero individual, velocidad, ocupación, próxima estación e itinerario.**

**- `\[x]` Cámara cenital/trasera conectada al coche principal.**

**- `\[x]` Panel de switches con `CheckButton` e indicador 3D.**

**- `\[x]` Agregar tren desde Constitución y colocarlo en cola cuando no hay vía disponible.**

**- `\[x]` Eliminar el tren seleccionado.**

**- `\[\~]` Listado de trenes: hoy muestra principalmente el nombre y selección; no muestra velocidad, ocupación, estado y próxima estación en cada fila.**

**- `\[ ]` Panel global de pausa/play/aceleración.**

**- `\[ ]` Panel de fecha y hora simulada.**

**- `\[ ]` Listado de estaciones.**

**- `\[ ]` Panel de métricas globales.**

**- `\[ ]` UI para crear y cancelar eventos.**

**- `\[ ]` Botón explícito “Ir a tren”; hoy seleccionar un tren actualiza la cámara, pero no existe esa acción con nombre propio.**



**### Restricción de Persona 2**



**- `\[ ]` Consumir únicamente `SimulacionController`.**

**- `\[ ]` No calcular rutas, pasajeros, retrasos ni métricas dentro del HUD.**

**- `\[ ]` No modificar trenes, estaciones, switches ni vías.**



**Conclusión: el HUD individual está avanzado; falta el HUD de operación global.**



**## Persona 3 — Cálculos globales y estadísticas**



**Tarjeta Trello: \*\*#12 UI\*\*, apartado datos globales**



**- `\[x]` Cada estación ya conserva pasajeros esperando, pasajeros saliendo, históricos, subidos y bajados.**

**- `\[x]` Cada tren publica pasajeros actuales y capacidad.**

**- `\[ ]` `EstadisticasSimulacion` o estructura equivalente para centralizar cálculos.**

**- `\[ ]` Agregador global de pasajeros esperando, en viaje y transportados.**

**- `\[ ]` Conteo de trenes activos, finalizados e incompletos.**

**- `\[ ]` Tiempo de espera global y por estación.**

**- `\[ ]` Demora promedio.**

**- `\[ ]` Concurrencia actual y máxima por estación.**

**- `\[ ]` Emitir `resumen\_global\_actualizado` para que el HUD sólo muestre resultados.**

**- `\[ ]` Pruebas unitarias con trenes/estaciones simulados, sin cargar la red ferroviaria real.**



**### Restricción de Persona 3**



**- `\[ ]` Trabajar sobre `Dictionary` de resumen y señales públicas.**

**- `\[ ]` No acceder directamente a nodos `Tren`, `Estacion` o `TrackNetwork`.**

**- `\[ ]` No modificar física, rutas ni reservas.**



**Conclusión: hay datos de origen, pero todavía no existe el sistema que los agrupa y calcula.**



**## Persona 4 — Estaciones y demanda del servicio de ida**



**Tarjeta Trello: \*\*#10 Estación\*\***



**- `\[x]` Estaciones con nombre, postes de parada ida/vuelta, largo, ancho multi-vía y proyección sobre vías paralelas.**

**- `\[x]` Cantidad de personas esperando.**

**- `\[x]` Subida/bajada de pasajeros en tiempo real.**

**- `\[x]` Información de estación: pasajeros actuales, históricos, subidos y bajados.**

**- `\[x]` Tasa individual de generación de pasajeros mediante `tasa\_generacion\_pasajeros`.**

**- `\[x]` Pasajeros visuales optimizados con `MultiMesh`.**

**- `\[x]` El nivel actual opera exclusivamente Constitución → Bosques; Bosques es la terminal final del servicio.**

**- `\[ ]` Perfil de demanda según hora simulada.**

**- `\[ ]` Asociación visible entre cada estación y el servicio Constitución → Bosques.**

**- `\[ ]` Próximo tren de ida hacia Bosques en cada estación.**

**- `\[ ]` Tiempo de espera acumulado y concurrencia máxima por estación.**

**- `\[ ]` Datos resumidos para el listado de estaciones del HUD.**

**- `\[ ]` Pruebas de estación terminal e intermedia para el servicio de ida.**



**### Restricción de Persona 4**



**- `\[ ]` Puede editar configuración y datos de `Estacion`.**

**- `\[ ]` No modifica cómo un tren planifica o alcanza una estación.**

**- `\[ ]` Publica datos de estación hacia `SimulacionController`; no modifica el HUD directamente.**



**Conclusión: la infraestructura de estación está hecha; faltan las reglas de operación temporal y los datos del servicio de ida para el HUD.**



**## Persona 5 — Reloj, horarios y eventos**



**Tarjetas Trello: \*\*#11 Tren\*\* y \*\*#12 UI\*\***



**- `\[x]` Multiplicadores de prueba por tren: velocidad máxima hasta ×3 y aceleración/frenado hasta ×10.**

**- `\[x]` Demora inicial y tiempo de parada configurables por tren.**

**- `\[\~]` Eliminar tren ya existe, por lo que puede reutilizarse como consecuencia técnica de un desperfecto; falta el modelo de evento, su estado y sus métricas.**

**- `\[ ]` Pausa global de simulación.**

**- `\[ ]` Reloj de simulación.**

**- `\[ ]` Fecha simulada.**

**- `\[ ]` Factor numérico libre de velocidad global mediante `establecer_velocidad_simulacion(factor: float)`: `1.0` es base, un valor positivo acelera o desacelera y `0.0` pausa.**

**- `\[ ]` Presets opcionales de interfaz, no modos internos: normal `1.0`, rápida `2.0`, ultra `4.5`. Persona 5 podrá asociarlos al reloj de calendario: 1 hora = 3 minutos, 1,5 minutos y 40 segundos respectivamente.**

**- `\[ ]` Horario previsto por estación y servicio.**

**- `\[ ]` Cálculo de llegada real, retraso y estado “en tiempo / retrasado”.**

**- `\[ ]` Falla eléctrica.**

**- `\[ ]` Piquete.**

**- `\[ ]` Desperfecto mecánico.**

**- `\[ ]` Panel de comandos de eventos para Persona 2.**



**### Restricción de Persona 5**



**- `\[ ]` Crear eventos como datos y comandos de alto nivel.**

**- `\[ ]` Solicitar al controlador detener, reanudar o finalizar un tren.**

**- `\[ ]` No modificar posición, velocidad, ruta, reservas o switches directamente.**

**- `\[ ]` No acceder a variables internas de `Tren`.**



**Conclusión: esta área está prácticamente pendiente. Los controles de prueba actuales no reemplazan una simulación temporal global.**



**## Dependencias reales e integración**



**1. \*\*Diego\*\* completa el núcleo ferroviario de ida, estados y `SimulacionController`.**

**2. \*\*Persona 5\*\* crea reloj, horarios y eventos usando comandos seguros.**

**3. \*\*Persona 4\*\* conecta demanda y datos de las estaciones al reloj para el servicio de ida.**

**4. \*\*Persona 3\*\* agrega métricas globales desde los resúmenes públicos.**

**5. \*\*Persona 2\*\* conecta paneles, listados y controles al controlador.**



**## Criterio de protección del núcleo ferroviario**



**Una tarea de compañero está mal integrada si necesita:**



**- tocar `tren.gd`, `track\_network.gd` o `servicio\_ferroviario.gd`;**

**- acceder a `\_ruta\_pasos`, `\_avance`, `\_odometro\_ferroviario` o `\_desvios\_switch`;**

**- mover un tren con `global\_position`;**

**- forzar `invertir\_sentido`;**

**- modificar reservas o estados físicos de switches.**



**Toda interacción externa debe entrar por `SimulacionController`. Así los compañeros pueden avanzar con UI, cálculos, estaciones, reloj y eventos sin poner en riesgo el recorrido ferroviario validado.**
