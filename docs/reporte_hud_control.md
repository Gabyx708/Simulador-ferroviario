# Reporte: HUD de control de simulación + eventos (Persona 2)

Ejecutado de forma autónoma en `feature/hud-control-simulacion` (desde `develop`,
mergeado localmente con `feature/reloj-horario-eventos`), sin push ni merge a
remoto ni a `develop`. Plan aprobado en `docs/plan_hud_control.md`, con los
ajustes y las decisiones tomadas de forma autónoma documentados ahí (§7).

## 1. Qué quedó implementado

### Backend (Etapa 0)

- `EstadisticasRetraso`: nueva señal `retraso_tramo_sumado(id_tren, aporte_s)`
  (se emite en cada llegada con tramo anterior, incluso si el aporte es 0) y
  `obtener_estaciones_recorridas(id_tren) -> int`.
- `GestorEventos`: cada evento disparado tiene un id único y acumula
  `trenes_afectados` (set) y `retraso_total_s` en vivo, escuchando la señal
  nueva de `EstadisticasRetraso`. Nuevos `obtener_zonas_activas()` y
  `nombre_tipo(tipo)`. `obtener_historial()` devuelve esos eventos
  enriquecidos. Teclas de debug movidas a **F1/F2/F3**, sólo en build de
  debug y nunca si hay un campo de texto con foco.

### `NavegacionPaneles` (Etapa 1)

3 botones redondos abajo-centro (⚙ control, ☰ métricas, ○ reservado) que
abren un panel tipo "bottom sheet" con animación de apertura. Sólo uno
abierto a la vez.

### `PanelControlSimulacion` (Etapa 2 — Panel 1)

- Reloj (día/hora simulada).
- Estado de flota (activos / a tiempo / retrasados / detenidos por evento /
  incompletos) + **demora promedio de la flota activa**, calculada en el
  panel iterando `obtener_trenes()`.
- Pausa/reanudar y slider de velocidad (reemplaza al slider viejo que vivía
  en "Pruebas de marcha", que se eliminó de `hud.tscn`/`hud.gd`).
- Formulario para generar los 3 eventos (falla eléctrica, piquete, avería)
  con dropdown de objetivo (estación o tren según el tipo) y duración.
- Feedback de eventos activos/recientes con su **impacto**: tipo, objetivo,
  cantidad de trenes afectados y retraso total generado (ej. "Piquete ·
  Hipólito Yrigoyen · 2 trenes · +4 min · 160s restantes") — que es el punto
  central para poder comparar eventos entre sí.

### `PanelMetricas` (Etapa 5 — Panel 2)

Sólo lectura, sin controles:

- Fila de totales: demora promedio de flota activa + incompletos.
- Tabla por tren: id/nombre, estado, retraso, estaciones recorridas.
- Tabla por evento: tipo, objetivo, trenes afectados, retraso total.

Pensado para que Persona 3 lo extienda: `_actualizar()` es el único punto de
refresco y cada tabla se reconstruye entera desde datos públicos en cada
llamada, sin estado acumulado propio.

## 2. Resultado de los tests

Todos los tests relevantes, corridos headless (Godot 4.7.2,
`--headless --path . -s res://tools/<test>.gd`), en verde:

| Test | Resultado |
| --- | --- |
| `test_estadisticas_retraso.gd` | OK |
| `test_gestor_eventos.gd` | OK |
| `test_indicador_eventos.gd` | OK |
| `test_atribucion_eventos.gd` (pedido explícitamente: retraso atribuido == retraso real) | OK |
| `test_navegacion_paneles.gd` | OK |
| `test_panel_control_simulacion.gd` | OK |
| `test_panel_metricas.gd` | OK |

No se avanzó de etapa con ningún test en rojo.

### Dos bugs reales encontrados y corregidos durante el testing de la Etapa 2

1. **`PanelControlSimulacion._resolver_nivel()` no debía depender de
   `get_tree().current_scene`.** Ese panel entra al árbol varios niveles por
   debajo de la raíz del nivel (HUD → NavegacionPaneles → panel), y
   `current_scene` puede no estar asignado todavía en ese momento — el mismo
   riesgo que ya documenta `hud.gd` en `_agregar_formacion`. Se resuelve
   subiendo por los ancestros hasta encontrar al que tiene
   `SimulacionController` como hijo. `PanelMetricas` usa el mismo mecanismo.
2. **`queue_free()` en vez de `free()` al refrescar listas.**
   `PanelControlSimulacion._actualizar_feedback()` y
   `PanelMetricas._vaciar_filas()` vaciaban las filas viejas con
   `queue_free()` (borrado diferido al próximo frame) y agregaban las nuevas
   en la misma llamada síncrona: las dos generaciones de filas coexistían
   como hijas hasta que terminara el frame. Con el refresco periódico cada
   0.5s de uso normal esto es invisible, pero rompía una lectura inmediata
   después de refrescar (p.ej. justo después de disparar un evento). Corregido
   usando `free()` inmediato en ambos (son `Label`/filas propias sin señales
   conectadas, así que es seguro).

### Advertencia no fatal observada en los tests

Al disparar una falla eléctrica que detiene a varios trenes a la vez,
aparecen en consola 1 línea `ERROR: Infinite loop detected. Check
set_loops() description for more info.` por tren detenido. Viene del Tween
de parpadeo de `IndicadorEventos` (trabajo de Persona 5, no de este HUD) y
no afecta el resultado de ningún test ni el comportamiento visible — queda
anotado como pendiente menor, ver sección 3.

## 3. Pendientes / limitaciones conocidas

- **Chequeo visual real en 1280×720 y 1920×1080**: no se puede verificar en
  este entorno headless. El código se escribió reusando la paleta y los
  patrones de anclaje ya existentes en `hud.gd`/`navegacion_paneles.gd`
  (`PRESET_CENTER_BOTTOM`, offsets fijos en píxeles, igual que el resto del
  HUD), pero falta abrir el proyecto y mirarlo. Ver sección 4 para el checklist
  manual.
- **Advertencia "Infinite loop detected" del Tween de parpadeo de
  `IndicadorEventos`** (Persona 5): no rompe nada, pero ensucia la consola
  cuando varios trenes quedan detenidos a la vez. Candidato a revisar si se
  retoma ese módulo.
- **Fragilidad conocida de la zona Lanús-Escalada-Banfield** con los 4
  trenes iniciales convergiendo (deadlock de reservas de switches,
  documentada en `docs/integracion_switches_vias.md`): no es un bug de este
  HUD, pero todos los tests de eventos de esta rama evitan esa zona a
  propósito (usan "Hipólito Yrigoyen" en vez de "Banfield").
- **`demora_promedio_s` de `obtener_resumen_global()` sigue en `0.0`** (no se
  tocó, es territorio de Persona 3/`EstadisticasSimulacion`); ambos paneles
  calculan su propio promedio iterando `obtener_trenes()`.
- El panel "reservado" (3er botón de `NavegacionPaneles`) sigue siendo un
  placeholder "Próximamente", como estaba previsto.

## 4. Cómo probarlo a mano

1. Abrir el proyecto en el editor de Godot y correr la escena principal
   (`levels/ramal_roca_main/ramal_roca_main.tscn`).
2. Abajo-centro de la pantalla van a aparecer 3 botones redondos (⚙ ☰ ○).
3. **Botón ⚙ (control)**: se abre el panel. Verificar:
   - El reloj y el estado de flota se actualizan solos.
   - Pausa/reanuda con el botón ⏸/▶; el slider cambia la velocidad real.
   - Elegir "Piquete" + una estación + duración y apretar "Disparar evento":
     debe aparecer en la lista de abajo con "0 trenes · +0s" al principio, y
     subir la cuenta de trenes/retraso cuando algún tren efectivamente pase
     por esa estación mientras el piquete sigue activo.
   - Repetir el disparo sobre la misma estación debe rechazarse mostrando el
     motivo en rojo ("Ya hay un evento activo...").
   - Elegir "Avería" + un tren: el tren queda incompleto (color rojo en el
     piso de la escena si está integrado `IndicadorEventos`) y aparece en el
     feedback como "1 tren · definitivo".
4. **Botón ☰ (métricas)**: se abre el panel de sólo lectura. Verificar que
   la tabla de trenes y la de eventos reflejen lo mismo que se disparó desde
   el panel de control (son la misma fuente de datos).
5. **Teclas F1/F2/F3** (sólo en build de debug): F1 falla eléctrica, F2
   piquete, F3 avería, cada una sobre la primera estación/tren disponible.
   No deben dispararse si hay un campo de texto con foco (p.ej. mientras se
   escribe en el `SpinBox` de duración).
