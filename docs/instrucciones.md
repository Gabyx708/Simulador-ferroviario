# Instrucciones de colaboración

Esta guía es el punto de entrada para trabajar en el simulador ferroviario. El
nivel operativo actual es `res://levels/ramal_roca_main/ramal_roca_main.tscn` y
el servicio activo es exclusivamente **Constitución → Bosques**: tiene 16
estaciones, finaliza en Bosques y no inicia un recorrido de vuelta.

## Prioridad: pruebas con Godot

> **Al pedirle pruebas a un agente, incluí siempre la ruta exacta del ejecutable
> de Godot.** No asumas que `godot` está disponible en el `PATH` del agente.

Ejecutable vigente en este equipo:

```text
C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe
```

Ejemplo de pedido al agente:

> Ejecutá `tools/test_comandos_simulacion.gd` con Godot 4.7.2. Usá este
> ejecutable: `C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe`.

Comando headless equivalente, desde la raíz del repositorio:

```powershell
& 'C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_comandos_simulacion.gd
```

Si el ejecutable cambia, quien solicite la prueba debe proporcionar la nueva
ruta exacta junto con el nombre del script y el criterio de aceptación.

## Cómo está compuesto el simulador

| Componente | Función | Punto de entrada para compañeros |
| --- | --- | --- |
| `ServicioConstitucionBosques` | Itinerario dirigido de 16 paradas | Sólo consulta; no editar su ruteo. |
| `TrackNetwork` | Grafo de vías, switches y reservas FIFO | Ninguno; solicitar cambios a Diego. |
| `Tren` / `TrenCSR` | Movimiento, frenado, pasajeros y estados | Snapshots y señales públicas. |
| `Estacion` | Andenes, demanda y pasajeros | Snapshots publicados por el controlador. |
| `SimulacionController` | Fachada por nivel para flota y comandos | API obligatoria de integración. |
| HUD | Paneles, selección y controles de prueba | Consumir controlador; no calcular lógica ferroviaria. |

Las carpetas principales son `scenes/` (entidades), `levels/` (ensamblado),
`ui/` (interfaz), `tools/` (pruebas) y `docs/` (contratos y planes).

## Qué pedir según el cambio

- **UI, métricas, estaciones, reloj u eventos:** usar snapshots, señales y
  comandos de `SimulacionController`. Consultar primero
  [api_simulacion.md](api_simulacion.md).
- **Servicio, rutas, vías, switches, reservas, postes o física:** pedir una
  tarea explícita a Diego. No modificar `tren.gd`, `track_network.gd`,
  `servicio_ferroviario.gd` ni la geometría del nivel.
- **Documentación o pruebas:** indicar el archivo objetivo, el resultado
  esperado, la prueba que debe cambiar o ejecutarse y la ruta del ejecutable
  de Godot.

## Reglas de integración

No mover trenes con `global_position`, no forzar `invertir_sentido` y no leer
ni escribir rutas, reservas o switches internos. Usar los IDs operativos y los
comandos del controlador. Los factores individuales del panel de pruebas son
internos del HUD; no constituyen una API para otros sistemas.

## Documentos relacionados

- [API de simulación](api_simulacion.md): contrato técnico de integración.
- [Plan de Diego](plan_diego.md): núcleo ferroviario y fases cerradas.
- [Plan pendiente](plan_para_lo_pendiente.md): tareas por integrante.
- [Reloj, retraso y eventos](eventos_ferroviarios.md): reloj de simulación,
  cálculo de `retraso_s` y los 3 eventos de dominio (Persona 5).
- [Integración de switches y vías](integracion_switches_vias.md): diagnóstico
  especializado de infraestructura.
