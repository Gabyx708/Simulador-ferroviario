extends Node
class_name EstadisticasRetraso
## Calcula el retraso acumulado de cada tren a partir de datos públicos.
##
## No lee `_avance`, `_odometro_ferroviario` ni ninguna variable interna: usa
## las señales de integración que `Tren` ya expone para este fin
## (`llego_a_estacion`, `recorrido_incompleto`, `eliminado`), el mismo
## mecanismo que usa internamente `SimulacionController._conectar_tren()`.
## Se conecta directo a los trenes del grupo "trenes" porque el controlador
## no vuelve a publicar `distancia_m` en sus señales -- es el mismo patrón
## que ya usa `SimulacionController`, no un atajo nuevo.
##
## Mide LLEGADA a LLEGADA, no salida a llegada. Probado con un evento
## inducido mientras el tren ya estaba parado en el andén: si sólo se mide el
## viaje (salida->llegada), esa demora de andén queda invisible porque
## ocurre antes de que el tren salga. Llegada a llegada la captura siempre,
## sea demora de andén o de viaje -- que es lo único que le importa a un
## pasajero real.
##
## El largo de cada tramo sale del PICO de `distancia_a_proxima_estacion()`
## (método público, el mismo que usa el velocímetro del HUD) muestreado en
## cada `_process()`: apenas el tren arranca hacia la próxima estación esa
## distancia salta al largo real del tramo y baja monótono hasta llegar.
##
## Por tramo: tiempo_esperado = (pico_distancia / (velocidad_nominal/3.6) +
## tiempo_espera_tipico) * factor_calibracion_tiempo. Si (tiempo_real -
## tiempo_esperado) supera la tolerancia, esa diferencia completa se suma al
## acumulado del tren (no se resta la tolerancia).

signal retraso_tren_actualizado(id_tren: int, retraso_s: float)

## Velocidad nominal documentada de Tren/TrenCSR (ver plan_diego.md). Si una
## instancia puntual cambia su nominal por Inspector, este cálculo no se
## entera -- limitación conocida, ver docs/eventos_ferroviarios.md.
@export var velocidad_nominal_kmh: float = 50.0
## Medido en tools/diag_calibracion_retraso.gd contra una corrida sin eventos
## (3 tramos reales, llegada a llegada: Avellaneda->Gerli->Lanús->Escalada).
## Incluye tiempo de andén normal además de las rampas de aceleración/
## frenado. Promedio observado: 1.123 (rango 1.08-1.21).
@export var factor_calibracion_tiempo: float = 1.123
@export var tolerancia_minima_s: float = 20.0
@export var tolerancia_porcentual: float = 0.15

var _reloj: RelojSimulacion
var _pico_distancia: Dictionary = {}  ## id_tren -> float
var _tiempo_ultima_llegada: Dictionary = {}  ## id_tren -> float
var _retraso_acumulado: Dictionary = {}  ## id_tren -> float
var _trenes_conectados: Dictionary = {}  ## id_tren -> Tren


func _ready() -> void:
	_reloj = get_parent().get_node_or_null("RelojSimulacion") as RelojSimulacion
	get_tree().node_added.connect(_on_nodo_agregado)
	# Diferido: en el mismo frame en que esta escena entra al árbol, los
	# trenes del mismo lote todavía no corrieron su propio _ready() (que es
	# donde recién se suman al grupo "trenes"), así que un escaneo síncrono
	# acá encuentra 0 trenes. SimulacionController._registrar_grupos_iniciales
	# usa el mismo diferido por la misma razón.
	call_deferred("_registrar_trenes_iniciales")


func _registrar_trenes_iniciales() -> void:
	for nodo: Node in get_tree().get_nodes_in_group("trenes"):
		if nodo is Tren:
			_conectar_tren(nodo as Tren)


func _process(_delta: float) -> void:
	for id: int in _trenes_conectados:
		var tren: Tren = _trenes_conectados[id] as Tren
		if tren == null or not is_instance_valid(tren):
			continue
		var distancia: float = tren.distancia_a_proxima_estacion()
		if distancia > float(_pico_distancia.get(id, 0.0)):
			_pico_distancia[id] = distancia


func _on_nodo_agregado(nodo: Node) -> void:
	if nodo is Tren:
		call_deferred("_intentar_conectar", nodo.get_instance_id())


func _intentar_conectar(instance_id: int) -> void:
	var nodo: Node = instance_from_id(instance_id) as Node
	if nodo is Tren and nodo.is_in_group("trenes"):
		_conectar_tren(nodo as Tren)


func _conectar_tren(tren: Tren) -> void:
	if tren == null or not is_instance_valid(tren):
		return
	var id: int = tren.obtener_id_operativo()
	if id <= 0:
		# SimulacionController todavía no le asignó el ID operativo en este
		# frame; se reintenta en el próximo en vez de perder el tren.
		call_deferred("_conectar_tren", tren)
		return
	if _trenes_conectados.has(id):
		return
	_trenes_conectados[id] = tren
	_pico_distancia[id] = 0.0
	_retraso_acumulado[id] = 0.0
	tren.llego_a_estacion.connect(_on_llego_a_estacion.bind(id))
	tren.recorrido_incompleto.connect(_on_recorrido_incompleto.bind(id))
	tren.eliminado.connect(_on_tren_eliminado.bind(id))


func _on_llego_a_estacion(_datos_tren: Dictionary, _datos_estacion: Dictionary, id: int) -> void:
	if _reloj == null:
		return
	var t_ahora: float = _reloj.tiempo_simulado_s()
	var distancia_m: float = float(_pico_distancia.get(id, 0.0))
	var tiene_llegada_previa: bool = _tiempo_ultima_llegada.has(id)
	var t_anterior: float = float(_tiempo_ultima_llegada.get(id, t_ahora))
	_tiempo_ultima_llegada[id] = t_ahora
	_pico_distancia[id] = 0.0

	# La primera llegada de un tren no tiene tramo anterior con qué comparar.
	if not tiene_llegada_previa or distancia_m <= 0.0 or velocidad_nominal_kmh <= 0.0:
		return

	var tiempo_real: float = t_ahora - t_anterior
	var tiempo_esperado: float = (distancia_m / (velocidad_nominal_kmh / 3.6)) * factor_calibracion_tiempo
	var diferencia: float = tiempo_real - tiempo_esperado
	var tolerancia_efectiva: float = maxf(tolerancia_minima_s, tiempo_esperado * tolerancia_porcentual)

	var aporte: float = diferencia if diferencia > tolerancia_efectiva else 0.0
	if aporte <= 0.0:
		return

	var nuevo_total: float = float(_retraso_acumulado.get(id, 0.0)) + aporte
	_retraso_acumulado[id] = nuevo_total
	var tren: Tren = _trenes_conectados.get(id) as Tren
	if tren != null and is_instance_valid(tren):
		tren.retraso_externo_s = nuevo_total
	retraso_tren_actualizado.emit(id, nuevo_total)


func _on_recorrido_incompleto(_datos_tren: Dictionary, _motivo: String, id: int) -> void:
	_tiempo_ultima_llegada.erase(id)
	_pico_distancia.erase(id)


func _on_tren_eliminado(id: int) -> void:
	_tiempo_ultima_llegada.erase(id)
	_pico_distancia.erase(id)
	_retraso_acumulado.erase(id)
	_trenes_conectados.erase(id)


func obtener_retraso(id_tren: int) -> float:
	return float(_retraso_acumulado.get(id_tren, 0.0))
