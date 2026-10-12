@tool
extends Node3D
class_name Tren
## Clase base genérica para formaciones ferroviarias sobre un Path3D.
##
## Cada coche calcula su orientación siguiendo los bogies delantero y trasero
## muestreados directamente sobre la curva del Path3D para un trazado curvo realista.
##
## Admite circulación bidireccional (Ascendente / Descendente) invirtiendo el sentido
## de avance, con ajuste dinámico de cabeceras, andenes y orientación de coches.
##
## Ejecutable en el editor (@tool) para previsualización y animación en tiempo real.
## Permite arrastrar el tren en el editor 3D y ajustarlo automáticamente
## a la vía al soltar el mouse, tal como las estaciones.
## Compatible con Godot 4.x / 4.7

## Estado operativo publicado para UI, estadísticas y futuros controladores.
## La dirección local de un Path3D no forma parte de este estado: el servicio
## actual siempre representa la ida Constitución → Bosques.
enum EstadoOperacion {
	EN_TERMINAL_INICIAL,
	EN_MARCHA,
	DETENIDO_EN_ESTACION,
	ESPERANDO_RESERVA,
	DETENIDO_POR_EVENTO,
	FINALIZADO_EN_BOSQUES,
	INCOMPLETO,
}

signal velocidad_cambiada(kmh: float)
signal parada_alcanzada(indice_parada: int)
signal marcha_reanudada()
signal seleccionado() ## Emitida al hacer clic izquierdo sobre algún coche de la formación.
signal eliminado() ## Emitida justo antes de destruirse, para que cámara/HUD suelten la referencia.
signal ruta_actualizada(destino: String, distancia_m: float)
signal ruta_error(motivo: String)
signal pasajeros_cambiados(actuales: int, capacidad: int, suben: int, bajan: int, intercambio_activo: bool)
signal parametros_prueba_cambiados(velocidad_factor: float, aceleracion_factor: float, frenado_factor: float)
signal opciones_switch_cambiadas()
## Señales de integración. Entregan instantáneas, nunca nodos ni detalles de
## ruteo/reservas, para que los consumidores no dependan del núcleo ferroviario.
signal estado_operacion_cambiado(datos_tren: Dictionary)
signal llego_a_estacion(datos_tren: Dictionary, datos_estacion: Dictionary)
signal salio_de_estacion(datos_tren: Dictionary, datos_estacion: Dictionary)
signal recorrido_finalizado(datos_tren: Dictionary)
signal recorrido_incompleto(datos_tren: Dictionary, motivo: String)
signal evento_temporal_finalizado(datos_tren: Dictionary)

@export_group("Previsualización en Editor")
## Si está activo, el tren se desplaza y simula su marcha dentro del visor del editor 3D.
@export var animar_en_editor: bool = false:
	set(v):
		animar_en_editor = v
		if Engine.is_editor_hint():
			set_process(true)
			if animar_en_editor:
				_detenido = false
				_espera = 0.0
				_debe_invertir_en_salida = false
				_buscar_proxima_parada(true)
				_aceleracion_actual = 0.0
			else:
				_vel = 0.0
				_detenido = false
				_debe_invertir_en_salida = false
				_avance = avance_inicial
				if is_inside_tree() and _cuerpos.size() > 0:
					_ubicar(0.0)

## Pulsador para forzar la reconstrucción de la formación en el editor.
@export var regenerar: bool = false:
	set(v):
		regenerar = false
		if is_inside_tree():
			_reconstruir()

@export_group("Vinculación a la Vía")
## La traza (Path3D) sobre la cual circula la formación.
@export var traza: Path3D:
	set(v):
		if traza != null and is_instance_valid(traza) and traza.curve != null:
			if traza.curve.changed.is_connected(_on_curva_cambiada):
				traza.curve.changed.disconnect(_on_curva_cambiada)
		traza = v
		if traza != null and is_instance_valid(traza) and traza.curve != null:
			if not traza.curve.changed.is_connected(_on_curva_cambiada):
				traza.curve.changed.connect(_on_curva_cambiada)
		if is_inside_tree() and not _transicion_de_ruta:
			_reconstruir()
			_recalcular_paradas_dinamicas()

## Si está activo, el tren se ajusta automáticamente a la traza al moverlo en el editor 3D.
@export var alinear_a_via: bool = true:
	set(v):
		var se_acaba_de_activar: bool = not alinear_a_via and v
		alinear_a_via = v
		if is_inside_tree() and alinear_a_via:
			if se_acaba_de_activar:
				_snap_a_posicion_actual()
			elif _cuerpos.size() > 0:
				_ubicar(0.0)

## Posición métrica inicial sobre la curva (en metros).
@export var avance_inicial: float = 0.0:
	set(v):
		avance_inicial = v
		_avance = avance_inicial
		_reiniciar_historial_recorrido()
		if is_inside_tree():
			if traza != null and is_instance_valid(traza) and traza.curve != null and traza.curve.point_count >= 2:
				_ajustando_transform = true
				global_position = traza.to_global(traza.curve.sample_baked(_avance))
				_ajustando_transform = false
			if _cuerpos.size() == 0:
				_reconstruir()
			else:
				_ubicar(0.0)

## Pulsá este botón en el Inspector para forzar el ajuste del tren al punto más cercano de la vía.
@export var alinear_a_posicion_actual: bool = false:
	set(v):
		if v:
			alinear_a_posicion_actual = false
			if is_inside_tree():
				alinear_a_via = true
				_snap_a_posicion_actual()

@export var cantidad_coches: int = 7:
	set(v):
		cantidad_coches = maxi(1, v)
		if is_inside_tree():
			_reconstruir()

@export_group("Dirección y Marcha")
## Si está activo, el tren circula en reversa / sentido decreciente (-) de la vía.
@export var invertir_sentido: bool = false:
	set(v):
		invertir_sentido = v
		if is_inside_tree() and not _transicion_de_ruta:
			_buscar_proxima_parada(true)

## Valor inicial operativo. Es intencionalmente editable desde el Inspector:
## cada formación puede usar un límite específico sin alterar su itinerario.
@export var velocidad_max_kmh: float = 50.0
@export var aceleracion: float = 0.8          ## m/s²
@export var desaceleracion: float = 1.0        ## m/s²
@export var tiempo_parada: float = 20.0        ## segundos en estación
@export_range(0.0, 600.0, 0.5) var demora_salida_inicial: float = 0.0
@export_range(1.0, 180.0, 0.5) var tiempo_parada_servicio: float = 3.0
@export var sentido_local_inicio_invertido: bool = true

@export_group("Pasajeros")
## Capacidad total de pasajeros de la formación.
@export_range(0, 100000, 1) var capacidad_pasajeros: int = 500

## Pasajeros actualmente dentro de la formación.
var pasajeros_actuales: int = 0

## Cantidad de pasajeros que suben o bajan en cada tanda.
@export_range(1, 100, 1) var cantidad_pasajeros_por_tanda: int = 6

## Segundos entre cada paso del embarque o desembarque.
@export var intervalo_pasajeros: float = 0.15

## % de pasajeros a bordo que bajan en una parada intermedia yendo en el
## sentido "directo" (`invertir_sentido = false`). Bajo a propósito: en la
## línea real, casi todos los que van hacia la cabecera principal viajan
## hasta el final, muy pocos bajan antes. Como el % se aplica parada tras
## parada, el efecto se compone -- con este rango (2-4%), después de ~12
## paradas llega vivo hasta el final ~70% de quien subió al principio.
@export_range(0.0, 1.0, 0.01) var porcentaje_bajada_directo_min: float = 0.02
@export_range(0.0, 1.0, 0.01) var porcentaje_bajada_directo_max: float = 0.04

## Igual que arriba, pero en sentido "inverso" (`invertir_sentido = true`).
## Alto a propósito: de vuelta la gente se reparte mucho más entre estaciones.
@export_range(0.0, 1.0, 0.01) var porcentaje_bajada_inverso_min: float = 0.15
@export_range(0.0, 1.0, 0.01) var porcentaje_bajada_inverso_max: float = 0.25

@export_group("Detección de Paradas")
## Servicio ordenado que decide la siguiente estación. Vacío conserva el modo
## anterior de detectar paradas sobre la traza actual.
@export var servicio: ServicioFerroviario
## Detecta automáticamente las estaciones en la escena y calcula su progreso métrico en la traza.
@export var autodetectar_estaciones: bool = true:
	set(v):
		autodetectar_estaciones = v
		if is_inside_tree():
			_recalcular_paradas_dinamicas()

## Distancia lateral máxima (en metros) para considerar que una estación pertenece a esta traza.
@export var distancia_maxima_via: float = 45.0:
	set(v):
		distancia_maxima_via = maxf(1.0, v)
		if is_inside_tree():
			_recalcular_paradas_dinamicas()

@export var paradas: PackedFloat32Array = PackedFloat32Array() ## Progresos en metros

@export_group("Modo de Detención")
## Modo de parada en estaciones:
## - Cabina en Poste: La trompa de la cabina delantera activa se alinea exactamente con el Poste de Parada de la estación.
## - Centro de Formación: El punto medio de la formación completa se centra respecto al andén.
@export_enum("Cabina en Poste", "Centro de Formación") var modo_detencion: int = 0

@export_group("Dimensiones Ferroviarias")
@export var paso: float = 26.0:                ## Distancia entre centros de coches (m)
	set(v):
		paso = v
		if is_inside_tree() and _cuerpos.size() > 0:
			_ubicar(0.0)

@export var semi_bogie: float = 8.90:          ## Distancia del centro al bogie (m)
	set(v):
		semi_bogie = v
		if is_inside_tree() and _cuerpos.size() > 0:
			_ubicar(0.0)

@export var radio_rueda: float = 0.43          ## Radio de rueda para rodadura (m)

@export_group("Modelos de Coche")
@export var escena_coche_motriz: PackedScene:
	set(v):
		escena_coche_motriz = v
		if is_inside_tree():
			_reconstruir()

@export var escena_coche_remolcado: PackedScene:
	set(v):
		escena_coche_remolcado = v
		if is_inside_tree():
			_reconstruir()

@export_group("Eliminación")
## Pulsador de prueba: elimina el tren en runtime. Provisorio hasta que exista
## el sistema de eventos adversos, que va a llamar a `eliminar()` directamente.
@export var eliminar_ahora: bool = false:
	set(v):
		eliminar_ahora = false
		if is_inside_tree() and not Engine.is_editor_hint():
			eliminar()

var _cuerpos: Array[Node3D] = []
var _ruedas: Array[Array] = []

var _eliminado: bool = false
var _procesando_pasajeros: bool = false
## Será asignado por SimulacionController en la fase 3. Cero identifica una
## formación aún no registrada, sin exponer get_instance_id() como contrato.
var _id_operativo: int = 0
## Seteado externamente por EstadisticasRetraso (Persona 5); Tren no lo calcula.
var retraso_externo_s: float = 0.0
var _estado_operacion: EstadoOperacion = EstadoOperacion.EN_TERMINAL_INICIAL
var _resultado_recorrido: String = "en_curso"
var _motivo_resultado: String = ""
var _estado_previo_evento: EstadoOperacion = EstadoOperacion.EN_TERMINAL_INICIAL
var _tiempo_evento_restante: float = 0.0
var _motivo_evento: String = ""

var _avance: float = 0.0
var _vel: float = 0.0
var _idx_parada: int = 0
var _detenido: bool = false
var _espera: float = 0.0
var _datos_paradas: Array[Dictionary] = []
var _debe_invertir_en_salida: bool = false
## Identificador de la última estación atendida. Evita que una actualización de
## estaciones la vuelva a elegir como destino justo al reanudar la marcha.
var _id_parada_atendida: int = 0
var _tiene_proxima_parada: bool = true
## Evita que los setters de `traza` y `invertir_sentido` reconstruyan la
## formación con el avance del tramo anterior durante un cambio automático.
var _transicion_de_ruta: bool = false

var _ajustando_transform: bool = false
var _pendiente_snap: bool = false
var _tiempo_ultimo_movimiento: int = 0

var _frenando_estacion: bool = false
var _dispersion_parada: float = 0.0
var _desaceleracion_actual: float = 0.0
var _aceleracion_actual: float = 0.0
var _servicio_ferroviario: ServicioFerroviario
var _indice_servicio: int = 0
var _direccion_servicio: int = 1
var _ruta_segmentos: Array[String] = []
## Pasos dirigidos de la ruta vigente. Conservan el sentido local de cada
## Path3D y evitan que una búsqueda por nombre elija otra rama repetida.
var _ruta_pasos: Array[Dictionary] = []
var _indice_paso_ruta: int = 0
var _distancia_ruta: float = -1.0
## La métrica de la ruta no depende de la velocidad: el destino y la cabecera
## se expresan en el mismo odómetro ferroviario.
var _odometro_ferroviario: float = 0.0
var _odometro_destino_ruta: float = -1.0
## Sólo registra movimiento real de servicio. No contiene permanencias en
## estación, esperas por reserva, eventos ni pausa global.
var _metros_marcha: float = 0.0
var _segundos_marcha: float = 0.0
## Estados de tramo ya recorridos. Los coches que quedan detrás de la cabecera
## consultan esta historia, no el estado actual de una aguja.
var _historial_recorrido: Array[Dictionary] = []
var _factor_velocidad_prueba: float = 1.0
var _factor_aceleracion_prueba: float = 1.0
var _factor_frenado_prueba: float = 1.0
var _parada_servicio_activa: bool = false
var _ruta_invalida: bool = false
## Reintentos de _actualizar_ruta_servicio() cuando no encuentra vía
## transitable al partir: casi siempre es una aguja momentáneamente ocupada
## por otro tren, no una desconexión real -- ver docs/reporte_final.md.
var _reintentos_ruta_servicio: int = 0
var _tiempo_hasta_reintento_ruta: float = 0.0
const MAX_REINTENTOS_RUTA_SERVICIO: int = 20
const INTERVALO_REINTENTO_RUTA_S: float = 0.5
## Cierre terminal de un servicio sólo ida. No equivale a eliminar el nodo:
## queda disponible para métricas, pero no vuelve a planificar ni reservar vías.
var _servicio_finalizado: bool = false
var _error_ruta_emitido: bool = false
var _ultimo_suben: int = 0
var _ultimo_bajan: int = 0
## Punto concreto elegido dentro del área multi-vía de la próxima estación.
## Se mantiene durante toda la aproximación para no cambiar de andén a mitad
## de la ruta y se invalida si el usuario edita la estación.
var _objetivo_servicio_resuelto: Dictionary = {}
var _indice_objetivo_resuelto: int = -1
## La primera parada del servicio es el origen ya atendido. Este estado evita
## que el inicio vuelva a planificarse como un viaje hacia la terminal.
var _origen_servicio_inicializado: bool = false
var _ultimo_diagnostico_ruta: String = ""
var _desvios_switch: Dictionary = {}
## El HUD sólo lee esta instantánea. La validez de cada rama se completa en
## frames posteriores para que seleccionar un tren nunca ejecute todo el
## itinerario Constitución–Bosques de una vez.
var _opciones_switch_cache: Array[Dictionary] = []
var _trabajos_validacion_switch: Array[Dictionary] = []
var _indice_trabajo_validacion_switch: int = 0
var _limite_switches_hud: int = 2
var _trabajos_switch_resueltos: int = 0
var _microsegundos_switch_acumulados: int = 0
var _opciones_switch_sucias := true
var _opciones_switch_activas := false
var _reserva_inicial_lista: bool = false
var _esperando_reserva: bool = false


func _ready() -> void:
	add_to_group("trenes")
	set_notify_transform(true)
	set_process(true)

	if traza == null:
		_autodetectar_traza()

	if traza != null and is_instance_valid(traza) and traza.curve != null:
		if not traza.curve.changed.is_connected(_on_curva_cambiada):
			traza.curve.changed.connect(_on_curva_cambiada)

	# Una formación puesta a mano en la terminal no debe saltar al poste de la
	# estación al iniciar. Cuando no está alineada automáticamente, su transform
	# de escena es la fuente de verdad y se proyecta una sola vez sobre *su propia*
	# traza. Así conserva la vía elegida por el editor y luego sólo avanza por la
	# red física.
	_resolver_avance_inicial_runtime()
	_reiniciar_historial_recorrido()
	_reconstruir()
	_resolver_servicio()
	if _inicializar_origen_servicio():
		return
	_recalcular_paradas_dinamicas()
	_buscar_proxima_parada()
	_actualizar_ruta_servicio()

	# En el editor la red puede terminar de cargar después: reintentar diferido para
	# que la formación aparezca sobre la vía sin asignarla a mano.
	if traza == null and Engine.is_editor_hint():
		call_deferred("_autodetectar_y_reconstruir")


## Resuelve el punto ferroviario inicial sin escribir propiedades exportadas.
## `avance_inicial` sigue siendo autoritativo para formaciones alineadas a la
## vía; las colocadas manualmente conservan la posición que tienen en la escena.
func _resolver_avance_inicial_runtime() -> void:
	_avance = avance_inicial
	if Engine.is_editor_hint() or alinear_a_via or traza == null or traza.curve == null:
		return
	var largo: float = traza.curve.get_baked_length()
	if largo <= 0.0:
		return
	var punto_local: Vector3 = traza.to_local(global_position)
	_avance = clampf(traza.curve.get_closest_offset(punto_local), 0.0, largo)


## Ajustes temporales de pruebas. Nunca modifican las propiedades exportadas,
## por lo que la geometría y las distancias del itinerario quedan intactas.
func establecer_factores_prueba(velocidad_factor: float, aceleracion_factor: float, frenado_factor: float) -> void:
	_factor_velocidad_prueba = clampf(velocidad_factor, 1.0, 3.0)
	_factor_aceleracion_prueba = clampf(aceleracion_factor, 1.0, 10.0)
	_factor_frenado_prueba = clampf(frenado_factor, 1.0, 10.0)
	parametros_prueba_cambiados.emit(_factor_velocidad_prueba, _factor_aceleracion_prueba, _factor_frenado_prueba)


## El HUD activa la evaluación diferida sólo para la formación seleccionada.
## Así una flota grande no calcula rutas alternativas que el jugador no ve.
func activar_opciones_switch(activa: bool) -> void:
	_opciones_switch_activas = activa
	if activa:
		_opciones_switch_sucias = true
	else:
		# El panel está cerrado: no dejamos trabajo de ruteo oculto consumiendo
		# tiempo de simulación. Se reconstruye recién al volver a abrirlo.
		if _servicio_ferroviario != null:
			for trabajo: Dictionary in _trabajos_validacion_switch:
				var clave: String = str(trabajo.get("clave_continuidad", ""))
				if not clave.is_empty():
					_servicio_ferroviario.cancelar_continuidad_pendiente(clave, get_instance_id())
		_opciones_switch_cache.clear()
		_trabajos_validacion_switch.clear()
		_indice_trabajo_validacion_switch = 0


func configurar_tiempos_servicio(demora_salida: float, espera_estaciones: float) -> void:
	demora_salida_inicial = maxf(0.0, demora_salida)
	tiempo_parada_servicio = maxf(1.0, espera_estaciones)
	if _origen_servicio_inicializado and _detenido and _indice_servicio == 0:
		_espera = tiempo_parada_servicio + demora_salida_inicial


## Ajusta el avance de una cabecera para que toda la formación quede dentro del
## tramo inicial. El marcador representa la posición deseada de la cabecera;
## si la cola no entraría, se desplaza sólo lo necesario hacia el interior.
func avance_inicial_ajustado_a_formacion(avance_deseado: float, sentido_invertido: bool) -> float:
	if traza == null or traza.curve == null:
		return avance_deseado
	var largo: float = traza.curve.get_baked_length()
	if largo <= 0.0:
		return avance_deseado
	var cola: float = float(maxi(0, cantidad_coches - 1)) * paso + semi_bogie
	var minimo: float = semi_bogie if sentido_invertido else cola
	var maximo: float = largo - cola if sentido_invertido else largo - semi_bogie
	# Un tramo excepcionalmente corto no puede contener la formación completa;
	# centrarla evita que quede por completo fuera de la vía y conserva el snap.
	if minimo > maximo:
		return largo * 0.5
	return clampf(avance_deseado, minimo, maximo)


## Indica si la cabecera o la cola todavía ocupa un puesto de despacho.
func ocupa_puesto_instancia(path: Path3D, avance_puesto: float) -> bool:
	if traza != path or traza == null:
		return false
	var alcance: float = float(maxi(0, cantidad_coches - 1)) * paso + semi_bogie + 3.0
	return absf(_avance - avance_puesto) <= alcance


func factores_prueba() -> Dictionary:
	return {"velocidad": _factor_velocidad_prueba, "aceleracion": _factor_aceleracion_prueba, "frenado": _factor_frenado_prueba}


func velocidad_maxima_efectiva_kmh() -> float:
	return velocidad_max_kmh * _factor_velocidad_prueba


func aceleracion_efectiva() -> float:
	return aceleracion * _factor_aceleracion_prueba


func desaceleracion_efectiva() -> float:
	return desaceleracion * _factor_frenado_prueba


func velocidad_media_marcha_kmh() -> float:
	return (_metros_marcha / _segundos_marcha) * 3.6 if _segundos_marcha > 0.0 else 0.0


func obtener_coche_principal() -> Node3D:
	return _cuerpos[0] if not _cuerpos.is_empty() and is_instance_valid(_cuerpos[0]) else null


func _reiniciar_historial_recorrido() -> void:
	_historial_recorrido.clear()
	_odometro_ferroviario = 0.0
	if traza != null and is_instance_valid(traza) and traza.curve != null:
		_historial_recorrido.append({"odometro": 0.0, "traza": traza, "avance": _avance, "invertido": invertir_sentido})


func _registrar_inicio_tramo() -> void:
	if traza == null or not is_instance_valid(traza) or traza.curve == null:
		return
	_historial_recorrido.append({"odometro": _odometro_ferroviario, "traza": traza, "avance": _avance, "invertido": invertir_sentido})
	var conservar_desde: float = _odometro_ferroviario - (paso * float(cantidad_coches) + semi_bogie * 2.0 + 30.0)
	while _historial_recorrido.size() > 1 and float(_historial_recorrido[1].get("odometro", 0.0)) < conservar_desde:
		_historial_recorrido.pop_front()


func _actualizar_distancia_ruta() -> void:
	if _odometro_destino_ruta >= 0.0:
		_distancia_ruta = maxf(0.0, _odometro_destino_ruta - _odometro_ferroviario)


## Cambia el estado público una sola vez por transición. El motivo se incluye
## sólo en la instantánea de esa transición; no se persiste como detalle de ruta.
func _establecer_estado(nuevo_estado: EstadoOperacion, motivo: String = "") -> bool:
	if _estado_operacion == nuevo_estado:
		return false
	_estado_operacion = nuevo_estado
	var datos: Dictionary = obtener_resumen_operativo()
	datos["motivo"] = motivo
	estado_operacion_cambiado.emit(datos)
	return true


func _nombre_estado_operacion() -> String:
	match _estado_operacion:
		EstadoOperacion.EN_TERMINAL_INICIAL:
			return "EN_TERMINAL_INICIAL"
		EstadoOperacion.EN_MARCHA:
			return "EN_MARCHA"
		EstadoOperacion.DETENIDO_EN_ESTACION:
			return "DETENIDO_EN_ESTACION"
		EstadoOperacion.ESPERANDO_RESERVA:
			return "ESPERANDO_RESERVA"
		EstadoOperacion.DETENIDO_POR_EVENTO:
			return "DETENIDO_POR_EVENTO"
		EstadoOperacion.FINALIZADO_EN_BOSQUES:
			return "FINALIZADO_EN_BOSQUES"
		EstadoOperacion.INCOMPLETO:
			return "INCOMPLETO"
	return "DESCONOCIDO"


## Convierte una estación o un objetivo de parada en datos seguros para UI.
func _resumen_estacion(estacion: Variant) -> Dictionary:
	var nodo: Node
	if estacion is Dictionary:
		nodo = (estacion as Dictionary).get("nodo") as Node
	elif estacion is Node:
		nodo = estacion as Node
	var nombre: String = ""
	var id: String = ""
	if nodo != null and is_instance_valid(nodo):
		nombre = str(nodo.get("nombre_estacion")) if "nombre_estacion" in nodo else nodo.name
		id = str(nodo.call("obtener_id_edicion")) if nodo.has_method("obtener_id_edicion") else nodo.name
	elif estacion is Dictionary:
		nombre = str((estacion as Dictionary).get("nombre", ""))
		id = str((estacion as Dictionary).get("id", ""))
	return {"id": id, "nombre": nombre}


## Punto de entrada de la futura fase 3. No se valida contra instance_id para
## que el controlador pueda usar una secuencia propia por nivel.
func asignar_id_operativo(id_operativo: int) -> void:
	_id_operativo = maxi(0, id_operativo)


func obtener_id_operativo() -> int:
	return _id_operativo


func obtener_estado_operacion() -> int:
	return _estado_operacion


func detener_por_evento(motivo: String, duracion_s: float) -> bool:
	if Engine.is_editor_hint() or _eliminado or _servicio_finalizado or _ruta_invalida:
		return false
	if _estado_operacion in [EstadoOperacion.DETENIDO_POR_EVENTO, EstadoOperacion.INCOMPLETO, EstadoOperacion.FINALIZADO_EN_BOSQUES]:
		return false
	if motivo.strip_edges().is_empty() or not is_finite(duracion_s) or duracion_s <= 0.0:
		return false
	_estado_previo_evento = _estado_operacion
	_tiempo_evento_restante = duracion_s
	_motivo_evento = motivo.strip_edges()
	_vel = 0.0
	# Al reanudar se vuelve a evaluar la distancia de frenado desde velocidad
	# cero; conservar el frenado anterior podría completar una parada lejana.
	_frenando_estacion = false
	_aceleracion_actual = 0.0
	_desaceleracion_actual = 0.0
	velocidad_cambiada.emit(0.0)
	_establecer_estado(EstadoOperacion.DETENIDO_POR_EVENTO, _motivo_evento)
	return true


func reanudar_por_evento() -> bool:
	if _eliminado or _ruta_invalida or _servicio_finalizado or _estado_operacion != EstadoOperacion.DETENIDO_POR_EVENTO:
		return false
	_tiempo_evento_restante = 0.0
	_motivo_evento = ""
	_establecer_estado(_estado_previo_evento)
	evento_temporal_finalizado.emit(obtener_resumen_operativo())
	return true


func finalizar_incompleto(motivo: String) -> bool:
	if Engine.is_editor_hint() or _eliminado or _servicio_finalizado or _ruta_invalida or motivo.strip_edges().is_empty():
		return false
	_tiempo_evento_restante = 0.0
	_motivo_evento = ""
	_detener_por_ruta_invalida(motivo.strip_edges())
	return true


func obtener_resumen_operativo() -> Dictionary:
	return {
		"id": _id_operativo,
		"nombre": name,
		"estado": _estado_operacion,
		"estado_nombre": _nombre_estado_operacion(),
		"servicio": _servicio_ferroviario.name if _servicio_ferroviario != null else "",
		"sentido": "ida",
		"estacion_proxima": proxima_estacion_nombre(),
		"distancia_m": distancia_a_proxima_estacion(),
		"velocidad_kmh": velocidad_actual(),
		"pasajeros": pasajeros_actuales,
		"capacidad": capacidad_pasajeros,
		"retraso_s": retraso_externo_s,
		"resultado": _resultado_recorrido,
		"motivo_resultado": _motivo_resultado,
		"motivo_evento": _motivo_evento,
		"tiempo_evento_restante_s": _tiempo_evento_restante,
		"velocidad_media_marcha_kmh": velocidad_media_marcha_kmh(),
	}


## Inmoviliza una formación de servicio ante un itinerario inconsistente. El
## objetivo lógico no se borra: HUD y diagnóstico conservan la estación que no
## pudo alcanzarse. La señal se emite una única vez por incidente.
func _detener_por_ruta_invalida(motivo: String) -> void:
	if _servicio_finalizado:
		return
	_ruta_invalida = true
	_procesando_pasajeros = false
	_detenido = true
	_parada_servicio_activa = false
	_espera = 0.0
	_vel = 0.0
	_aceleracion_actual = 0.0
	_desaceleracion_actual = 0.0
	_frenando_estacion = false
	_esperando_reserva = false
	_distancia_ruta = -1.0
	_odometro_destino_ruta = -1.0
	activar_opciones_switch(false)
	_tiempo_evento_restante = 0.0
	_motivo_evento = ""
	var red: Node = _obtener_red()
	if red != null and red.has_method("liberar_reservas_tren"):
		red.call("liberar_reservas_tren", get_instance_id())
	velocidad_cambiada.emit(0.0)
	_resultado_recorrido = "incompleto"
	_motivo_resultado = motivo
	if _establecer_estado(EstadoOperacion.INCOMPLETO, motivo):
		recorrido_incompleto.emit(obtener_resumen_operativo(), motivo)
	if not _error_ruta_emitido:
		_error_ruta_emitido = true
		ruta_error.emit(motivo)


## Termina el servicio en su terminal de ida sin eliminar la formación. Liberar
## reservas antes de ocultarla permite que el siguiente tren alcance Bosques.
func _finalizar_servicio_en_terminal() -> void:
	if _servicio_finalizado:
		return
	_servicio_finalizado = true
	_detenido = true
	_parada_servicio_activa = true
	_espera = 0.0
	_vel = 0.0
	_aceleracion_actual = 0.0
	_desaceleracion_actual = 0.0
	_frenando_estacion = false
	_esperando_reserva = false
	_distancia_ruta = 0.0
	_odometro_destino_ruta = _odometro_ferroviario
	activar_opciones_switch(false)
	var red: Node = _obtener_red()
	if red != null and red.has_method("liberar_reservas_tren"):
		red.call("liberar_reservas_tren", get_instance_id())
	for cuerpo: Node3D in _cuerpos:
		if not is_instance_valid(cuerpo):
			continue
		var selector: Area3D = cuerpo.get_node_or_null("SelectorClic") as Area3D
		if selector != null:
			selector.input_ray_pickable = false
	visible = false
	velocidad_cambiada.emit(0.0)
	ruta_actualizada.emit(proxima_estacion_nombre(), 0.0)
	_resultado_recorrido = "finalizado_en_bosques"
	if _establecer_estado(EstadoOperacion.FINALIZADO_EN_BOSQUES, "Terminal Bosques alcanzada."):
		recorrido_finalizado.emit(obtener_resumen_operativo())
	set_process(false)


## Reintenta detectar una vía (p. ej. desde la red topológica) y reconstruye la formación.
func _autodetectar_y_reconstruir() -> void:
	if traza != null or not is_inside_tree():
		return
	_autodetectar_traza()
	if traza == null or traza.curve == null:
		return
	if not traza.curve.changed.is_connected(_on_curva_cambiada):
		traza.curve.changed.connect(_on_curva_cambiada)
	_avance = avance_inicial
	_reconstruir()
	_recalcular_paradas_dinamicas()
	_buscar_proxima_parada()
	notify_property_list_changed()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_POST_ENTER_TREE:
			add_to_group("trenes")
			set_notify_transform(true)
			set_process(true)
			if traza == null:
				_autodetectar_traza()
			if traza != null and is_instance_valid(traza) and traza.curve != null:
				if not traza.curve.changed.is_connected(_on_curva_cambiada):
					traza.curve.changed.connect(_on_curva_cambiada)
			if alinear_a_via and traza != null and is_inside_tree() and traza.curve != null and traza.curve.point_count >= 2:
				if _cuerpos.size() > 0:
					_ubicar(0.0)

		NOTIFICATION_TRANSFORM_CHANGED:
			if _ajustando_transform or animar_en_editor:
				return
			if alinear_a_via and traza != null and is_instance_valid(traza) and traza.curve != null and Engine.is_editor_hint():
				_pendiente_snap = true
				_tiempo_ultimo_movimiento = Time.get_ticks_msec()


func _exit_tree() -> void:
	if is_in_group("trenes"):
		remove_from_group("trenes")
	if traza != null and is_instance_valid(traza) and traza.curve != null:
		if traza.curve.changed.is_connected(_on_curva_cambiada):
			traza.curve.changed.disconnect(_on_curva_cambiada)
	var red: Node = _obtener_red()
	if red != null and red.has_method("liberar_reservas_tren"):
		red.call("liberar_reservas_tren", get_instance_id())
	_limpiar()


func _autodetectar_traza() -> void:
	if get_parent() is Path3D:
		traza = get_parent()
		return

	var p: Node = get_parent()
	if p != null:
		var encontrada: Path3D = p.find_child("Traza", true, false) as Path3D
		if encontrada != null:
			traza = encontrada
			return
		if p.get_parent() != null:
			encontrada = p.get_parent().find_child("Traza", true, false) as Path3D
			if encontrada != null:
				traza = encontrada
				return

	# Red topológica (TrackNetwork): tomar un tramo troncal como vía inicial. Permite
	# ver/animar la formación en el editor sin asignar una traza a mano.
	traza = _segmento_inicial_de_red()


## Primer segmento disponible de la red topológica de la escena (prefiere un troncal
## conocido). Devuelve null si no hay TrackNetwork con segmentos.
func _segmento_inicial_de_red() -> Path3D:
	if not is_inside_tree():
		return null
	var red: Node = get_tree().get_first_node_in_group("track_network")
	if red == null:
		var raiz: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
		if raiz != null:
			red = raiz.find_child("TrackNetwork", true, false)
	if red == null or not ("paths" in red):
		return null
	var paths_v: Variant = red.get("paths")
	if not (paths_v is Dictionary):
		return null
	var dicc: Dictionary = paths_v as Dictionary
	if dicc.is_empty():
		return null
	for id_cand: String in ["seg_470", "seg_471", "seg_1", "seg_179"]:
		if dicc.has(id_cand) and dicc[id_cand] is Path3D:
			return dicc[id_cand] as Path3D
	for v: Variant in dicc.values():
		if v is Path3D and (v as Path3D).curve != null and (v as Path3D).curve.point_count >= 2:
			return v as Path3D
	return null


## Proyecta la posición 3D actual del tren sobre la curva de la vía y ajusta avance_inicial.
## Curva que el tren RECORRE: es la curva completa del tramo (el recorte automático
## es sólo para el render de la vía). Así el tren no salta sobre la zona del aparato.
func curva_recorrido() -> Curve3D:
	if traza == null or not is_instance_valid(traza):
		return null
	if "curva_original" in traza:
		var co: Variant = traza.get("curva_original")
		if co is Curve3D and (co as Curve3D).point_count >= 2:
			return co as Curve3D
	return traza.curve


## Proyecta la posición 3D actual del tren sobre la vía y ajusta avance_inicial.
## Si el tren pertenece a una red, busca la vía MÁS CERCANA de toda la red (incluidos
## los tramos de los switches) y se cambia a ella: permite soltarlo en cualquier vía.
func _snap_a_posicion_actual() -> void:
	if traza == null:
		_autodetectar_traza()
	if traza == null or not is_instance_valid(traza):
		return

	var red: Node = _obtener_red()
	if red != null and red.has_method("get_closest_segment") and red.has_method("get_segment_path"):
		var seg_id: String = str(red.call("get_closest_segment", global_position))
		if not seg_id.is_empty():
			var p: Path3D = red.call("get_segment_path", seg_id) as Path3D
			if p != null and p.curve != null and p.curve.point_count >= 2 and p != traza:
				traza = p

	if traza == null or not is_instance_valid(traza) or traza.curve == null or traza.curve.point_count < 2:
		return

	var pos_local: Vector3 = traza.to_local(global_position)
	avance_inicial = snappedf(traza.curve.get_closest_offset(pos_local), 0.1)
	_buscar_proxima_parada()
	notify_property_list_changed()


func _resolver_servicio() -> void:
	_servicio_ferroviario = servicio
	_objetivo_servicio_resuelto.clear()
	_indice_objetivo_resuelto = -1
	if _servicio_ferroviario != null:
		_indice_servicio = clampi(_servicio_ferroviario.indice_parada_inicial, 0, max(0, _servicio_ferroviario.cantidad_paradas() - 1))


## Posiciona una formación de servicio en su estación de origen. El sentido de
## la línea (ida) y el sentido local de cada Curve3D son conceptos distintos:
## aquí se prueba una vez cuál de los dos offsets locales conduce a la segunda
## estación, sin permitir esa prueba como una reversa durante la marcha.
func _inicializar_origen_servicio() -> bool:
	if Engine.is_editor_hint() or _origen_servicio_inicializado or not _usa_servicio() or _indice_servicio != 0:
		return false
	var red: Node = _obtener_red()
	if red == null or not red.has_method("planificar_ruta") or traza == null:
		return false
	var origen: Node = _parada_objetivo_servicio()
	if origen == null:
		return false
	var candidatos_origen: Array[Dictionary] = _candidatos_estacion_servicio(origen, red, true)
	var candidato_origen: Dictionary = {}
	for candidato: Dictionary in candidatos_origen:
		if candidato.get("traza") == traza:
			candidato_origen = candidato
			break
	if candidato_origen.is_empty():
		# El área multi-vía puede no incluir la traza configurada de la terminal
		# por un margen geométrico mínimo. Se proyecta el poste sobre la vía de
		# esta formación; nunca se copia el offset de una traza paralela.
		var offset_origen: float = _avance
		var poste_origen: Node3D = origen.get_node_or_null("PosteParadaIda") as Node3D
		if poste_origen != null and traza.curve != null:
			offset_origen = traza.curve.get_closest_offset(traza.to_local(poste_origen.global_position))
		candidato_origen = {"segmento": traza.name, "traza": traza, "offset": offset_origen, "offset_ida": offset_origen, "offset_vuelta": offset_origen}

	var siguiente: Node = _servicio_ferroviario.obtener_parada(1)
	var candidatos_siguiente: Array[Dictionary] = _candidatos_estacion_servicio(siguiente, red, true)
	var ruta_inicial: Dictionary = {}
	var sentido_local_invertido := false
	var sin_override: Array[String] = []
	# El sentido configurado en el Inspector representa la salida física de la
	# formación. TrackNetwork traduce internamente ese extremo si la curva fue
	# invertida durante una edición, pero el tren no debe partir al lado opuesto.
	var eleccion: Dictionary = _mejor_ruta_a_candidatos_desde(
		red, candidatos_siguiente, traza.name, _avance, sentido_local_inicio_invertido, sin_override
	)
	if not eleccion.is_empty():
		ruta_inicial = eleccion.get("ruta", {}) as Dictionary
		sentido_local_invertido = sentido_local_inicio_invertido
	if ruta_inicial.is_empty():
		_detener_por_ruta_invalida("No se puede salir de %s hacia %s." % [str(origen.get("nombre_estacion")), str(siguiente.get("nombre_estacion"))])
		return false

	invertir_sentido = sentido_local_invertido
	var objetivo_origen: Dictionary = _objetivo_desde_candidato(origen, candidato_origen)
	# El origen es una parada lógica ya atendida: se conserva exactamente el
	# avance con el que el diseñador dejó al tren, sin reanclarlo al poste.
	_reiniciar_historial_recorrido()
	_objetivo_servicio_resuelto = objetivo_origen
	_indice_objetivo_resuelto = _indice_servicio
	_datos_paradas = [objetivo_origen]
	paradas = PackedFloat32Array([float(objetivo_origen.get("offset", 0.0))])
	_idx_parada = 0
	_tiene_proxima_parada = true
	_distancia_ruta = 0.0
	_odometro_destino_ruta = _odometro_ferroviario
	_detenido = true
	_espera = maxf(tiempo_parada_servicio, 1.0) + maxf(0.0, demora_salida_inicial)
	_parada_servicio_activa = true
	_id_parada_atendida = int(objetivo_origen.get("id", 0))
	_origen_servicio_inicializado = true
	var largo_formacion: float = float(cantidad_coches - 1) * paso + 24.2
	_reserva_inicial_lista = bool(red.call("reservar_tramo_inicial", get_instance_id(), traza.name, _avance, invertir_sentido, _odometro_ferroviario, largo_formacion)) if red.has_method("reservar_tramo_inicial") else true
	_registrar_diagnostico_ruta(origen, candidato_origen, [traza.name], ruta_inicial, "origen")
	# Constitución también es una parada real: habilita el intercambio inicial
	# de pasajeros antes de que cada formación salga a Yrigoyen.
	_procesar_pasajeros_parada(origen, false, -1.0 if invertir_sentido else 1.0, _espera)
	parada_alcanzada.emit(_idx_parada)
	llego_a_estacion.emit(obtener_resumen_operativo(), _resumen_estacion(origen))
	return true


func _usa_servicio() -> bool:
	return _servicio_ferroviario != null and _servicio_ferroviario.cantidad_paradas() >= 2


func _parada_objetivo_servicio() -> Node:
	return _servicio_ferroviario.obtener_parada(_indice_servicio) if _usa_servicio() else null


func _datos_objetivo_servicio() -> Dictionary:
	if _indice_objetivo_resuelto == _indice_servicio and not _objetivo_servicio_resuelto.is_empty():
		return _objetivo_servicio_resuelto
	var estacion: Node = _parada_objetivo_servicio()
	if estacion == null or not ("traza" in estacion) or estacion.get("traza") == null:
		return {}
	var estacion_traza: Path3D = estacion.get("traza") as Path3D
	if estacion_traza == null:
		return {}
	var offset: float = float(estacion.get("progreso_en_via"))
	var nombre: String = str(estacion.get("nombre_estacion")) if "nombre_estacion" in estacion else estacion.name
	return {
		"id": estacion.get_instance_id(), "nodo": estacion, "traza": estacion_traza,
		"offset": offset, "offset_ida": estacion.call("obtener_offset_parada", true) if estacion.has_method("obtener_offset_parada") else offset,
		"offset_vuelta": estacion.call("obtener_offset_parada", false) if estacion.has_method("obtener_offset_parada") else offset,
		"nombre": nombre, "tiempo_espera": tiempo_parada_servicio,
		"es_terminal": _servicio_ferroviario.es_terminal(_indice_servicio),
		"es_terminal_ida": _servicio_ferroviario.es_terminal(_indice_servicio),
		"es_terminal_vuelta": _servicio_ferroviario.es_terminal(_indice_servicio)
	}


func _candidatos_estacion_servicio(estacion: Node, red: Node, sentido_ida: bool) -> Array[Dictionary]:
	var candidatos: Array[Dictionary] = []
	if estacion != null and estacion.has_method("obtener_puntos_parada_multivia"):
		candidatos = estacion.call("obtener_puntos_parada_multivia", red, sentido_ida) as Array[Dictionary]
	if not candidatos.is_empty():
		return candidatos
	# Compatibilidad con estaciones antiguas o una red aún no inicializada.
	var ancla: Path3D = estacion.get("traza") as Path3D if estacion != null and "traza" in estacion else null
	if ancla == null:
		return candidatos
	var offset: float = estacion.call("obtener_offset_parada", sentido_ida) if estacion.has_method("obtener_offset_parada") else float(estacion.get("progreso_en_via"))
	candidatos.append({"segmento": ancla.name, "traza": ancla, "offset": offset, "offset_ida": offset, "offset_vuelta": offset})
	return candidatos


## Devuelve únicamente los postes alcanzables antes de la primera decisión de
## vía. La comprobación es métrica: compartir el mismo Path3D no alcanza si el
## poste quedó detrás de la cabecera según el sentido local actual.
func _candidatos_adelante_en_corredor(candidatos: Array[Dictionary], corredor: Array[Dictionary]) -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	for paso: Dictionary in corredor:
		var segmento: String = str(paso.get("segmento", ""))
		var direccion: String = str(paso.get("direccion", "forward"))
		var desde: float = float(paso.get("desde", 0.0))
		var hasta: float = float(paso.get("hasta", 0.0))
		for candidato: Dictionary in candidatos:
			if str(candidato.get("segmento", "")) != segmento:
				continue
			var offset: float = float(candidato.get("offset", 0.0))
			var adelante: bool = offset >= desde - 0.05 and offset <= hasta + 0.05 if direccion == "forward" else offset <= desde + 0.05 and offset >= hasta - 0.05
			if not adelante:
				continue
			var copia: Dictionary = candidato.duplicate()
			copia["distancia_corredor"] = float(paso.get("distancia_inicio", 0.0)) + absf(offset - desde)
			copia["direccion_corredor"] = direccion
			resultado.append(copia)
	return resultado


## Construye una ruta dirigida sin aguja a partir del corredor inmediato. Se
## usa cuando el poste ya está delante de la formación sobre su propia vía.
func _ruta_directa_corredor(candidato: Dictionary, corredor: Array[Dictionary], sentido_invertido: bool) -> Dictionary:
	var pasos: Array[Dictionary] = []
	var segmentos: Array[String] = []
	var segmento_destino: String = str(candidato.get("segmento", ""))
	for paso: Dictionary in corredor:
		var paso_ruta: Dictionary = {"segmento": str(paso.get("segmento", "")), "direccion": str(paso.get("direccion", "forward"))}
		pasos.append(paso_ruta)
		segmentos.append(str(paso_ruta.get("segmento", "")))
		if str(paso.get("segmento", "")) == segmento_destino:
			return {
				"ok": true,
				"segmentos": segmentos,
				"pasos": pasos,
				"distancia_m": float(candidato.get("distancia_corredor", 0.0)),
				"cambios_aguja": 0,
				"forzada": false,
				"sentido_invertido": sentido_invertido,
			}
	return {}


func _objetivo_desde_candidato(estacion: Node, candidato: Dictionary) -> Dictionary:
	var destino_traza: Path3D = candidato.get("traza") as Path3D
	if estacion == null or destino_traza == null:
		return {}
	var offset: float = float(candidato.get("offset", 0.0))
	var nombre: String = str(estacion.get("nombre_estacion")) if "nombre_estacion" in estacion else estacion.name
	return {
		"id": estacion.get_instance_id(), "nodo": estacion, "traza": destino_traza,
		"offset": offset, "offset_ida": float(candidato.get("offset_ida", offset)),
		"offset_vuelta": float(candidato.get("offset_vuelta", offset)),
		"nombre": nombre, "tiempo_espera": tiempo_parada_servicio,
		"es_terminal": _servicio_ferroviario.es_terminal(_indice_servicio),
		"es_terminal_ida": _servicio_ferroviario.es_terminal(_indice_servicio),
		"es_terminal_vuelta": _servicio_ferroviario.es_terminal(_indice_servicio)
	}


func _mejor_ruta_a_candidatos(red: Node, candidatos: Array[Dictionary], sentido_invertido: bool, override: Array[String]) -> Dictionary:
	if traza == null:
		return {}
	return _mejor_ruta_a_candidatos_desde(red, candidatos, traza.name, _avance, sentido_invertido, override)


## Selecciona por maniobras y después por metros de vía. Se conserva separado
## del estado del tren para poder resolver el sentido local de la salida inicial.
func _mejor_ruta_a_candidatos_desde(red: Node, candidatos: Array[Dictionary], segmento_origen: String, offset_origen: float, sentido_invertido: bool, override: Array[String], switches_forzados: Dictionary = {}) -> Dictionary:
	var mejor: Dictionary = {}
	var menor_agujas: int = 999999
	var menor_distancia: float = INF
	var ordenados: Array[Dictionary] = candidatos.duplicate()
	var referencia: Vector3 = traza.to_global(traza.curve.sample_baked(offset_origen, true)) if traza != null and traza.curve != null else global_position
	ordenados.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.get("punto_global", referencia) as Vector3).distance_squared_to(referencia) < (b.get("punto_global", referencia) as Vector3).distance_squared_to(referencia)
	)
	# Un área amplia puede tocar muchos segmentos cortos de la misma vía. Se
	# evalúan los candidatos físicos más cercanos; el punto actual conserva
	# prioridad absoluta y los overrides no quedan afectados por este límite.
	var limite: int = ordenados.size() if not override.is_empty() else mini(ordenados.size(), 12)
	for indice: int in limite:
		var candidato: Dictionary = ordenados[indice]
		var destino: Path3D = candidato.get("traza") as Path3D
		if destino == null:
			continue
		var ruta: Dictionary = red.call("planificar_ruta", segmento_origen, offset_origen, sentido_invertido, destino.name, float(candidato.get("offset", 0.0)), override, switches_forzados) as Dictionary
		if not bool(ruta.get("ok", false)):
			continue
		var agujas: int = int(ruta.get("cambios_aguja", 0))
		var distancia: float = float(ruta.get("distancia_m", INF))
		if mejor.is_empty() or agujas < menor_agujas or (agujas == menor_agujas and distancia < menor_distancia):
			mejor = {"ruta": ruta, "candidato": candidato}
			menor_agujas = agujas
			menor_distancia = distancia
	return mejor


func _registrar_diagnostico_ruta(estacion: Node, candidato: Dictionary, corredor: Array[String], ruta: Dictionary, fase: String) -> void:
	var nombre: String = str(estacion.get("nombre_estacion")) if estacion != null and "nombre_estacion" in estacion else "(sin estación)"
	var mensaje: String = "Ruta [%s]: estacion=%s poste=Ida corredor=%s candidato=%s agujas=%d sentido_local=%s" % [
		fase, nombre, ",".join(corredor), str(candidato.get("segmento", "")),
		int(ruta.get("cambios_aguja", 0)), "inverso" if invertir_sentido else "directo"
	]
	if mensaje != _ultimo_diagnostico_ruta:
		_ultimo_diagnostico_ruta = mensaje
		print(mensaje)


## Switches que aparecen en los pasos dirigidos hacia la próxima estación.
## Esta consulta es de lectura: nunca calcula rutas, por lo que es segura para
## el HUD y para la selección de formaciones.
func opciones_switch_proximos(limite: int = -1) -> Array[Dictionary]:
	if not _opciones_switch_activas:
		return []
	if limite < 0:
		limite = _limite_switches_hud
	if _opciones_switch_sucias:
		_reconstruir_opciones_switch_cache(limite)
	return _opciones_switch_cache


func ampliar_opciones_switch(cantidad: int = 2) -> void:
	var nuevo_limite: int = mini(6, _limite_switches_hud + maxi(1, cantidad))
	if nuevo_limite == _limite_switches_hud:
		return
	_limite_switches_hud = nuevo_limite
	_invalidar_opciones_switch()


func hay_mas_switches_disponibles() -> bool:
	return _opciones_switch_cache.size() >= _limite_switches_hud and _limite_switches_hud < 6


func estadisticas_calculo_switches() -> Dictionary:
	return {
		"trabajos_resueltos": _trabajos_switch_resueltos,
		"tiempo_promedio_ms": (float(_microsegundos_switch_acumulados) / float(_trabajos_switch_resueltos) / 1000.0) if _trabajos_switch_resueltos > 0 else 0.0,
		"pendientes": maxi(0, _trabajos_validacion_switch.size() - _indice_trabajo_validacion_switch),
	}


func _invalidar_opciones_switch() -> void:
	_opciones_switch_sucias = true
	_opciones_switch_cache.clear()
	_trabajos_validacion_switch.clear()
	_indice_trabajo_validacion_switch = 0


func _reconstruir_opciones_switch_cache(limite: int = 6) -> void:
	_opciones_switch_cache.clear()
	_trabajos_validacion_switch.clear()
	_indice_trabajo_validacion_switch = 0
	_opciones_switch_sucias = false
	var red: Node = _obtener_red()
	if red == null or not _usa_servicio() or _ruta_pasos.size() < 2:
		return
	var distancia := 0.0
	for indice: int in range(_indice_paso_ruta, _ruta_pasos.size() - 1):
		var paso: Dictionary = _ruta_pasos[indice]
		var path: Path3D = red.call("get_segment_path", str(paso.get("segmento", ""))) as Path3D
		if path == null or path.curve == null:
			break
		var largo: float = path.curve.get_baked_length()
		var invertido: bool = str(paso.get("direccion", "forward")) == "reversed"
		var extremo: String = "start" if invertido else "end"
		var opciones: Array[Dictionary] = red.call("get_opciones_siguientes", path.name, extremo) as Array[Dictionary]
		if opciones.size() > 1:
			var nodo_id: int = int(opciones[0].get("node_id", 0))
			var opciones_ui: Array[Dictionary] = []
			for opcion: Dictionary in opciones:
				var segmento_opcion: String = str(opcion.get("segment_id", ""))
				opciones_ui.append({
					"segmento": segmento_opcion,
					"nombre": str(red.call("nombre_opcion_switch", nodo_id, segmento_opcion)) if red.has_method("nombre_opcion_switch") else segmento_opcion,
					"estado": "pendiente",
					"valida": false,
					"seleccionada": str(_desvios_switch.get(nodo_id, _ruta_pasos[indice + 1].get("segmento", ""))) == segmento_opcion,
				})
			var seccion_indice: int = _opciones_switch_cache.size()
			_opciones_switch_cache.append({
				"nodo_id": nodo_id,
				"distancia_m": distancia + ((largo - _avance) if not invertido and indice == _indice_paso_ruta else (_avance if invertido and indice == _indice_paso_ruta else largo)),
				"segmento_actual": path.name,
				"segmento_elegido": str(_desvios_switch.get(nodo_id, _ruta_pasos[indice + 1].get("segmento", ""))),
				"opciones": opciones_ui,
			})
			for opcion_indice: int in opciones_ui.size():
				_trabajos_validacion_switch.append({"seccion": seccion_indice, "opcion": opcion_indice, "nodo": nodo_id, "segmento": str(opciones_ui[opcion_indice].get("segmento", ""))})
			if _opciones_switch_cache.size() >= limite:
				break
		if indice == _indice_paso_ruta:
			distancia += (largo - _avance) if not invertido else _avance
		else:
			distancia += largo
	opciones_switch_cambiadas.emit()


func _procesar_validacion_switch() -> void:
	if _opciones_switch_sucias:
		_reconstruir_opciones_switch_cache()
	if _indice_trabajo_validacion_switch >= _trabajos_validacion_switch.size():
		return
	# Un enlace de servicio por frame. Antes cada rama comprobaba de forma
	# sincrónica todas las estaciones hasta Bosques y frenaba el juego.
	var trabajo: Dictionary = _trabajos_validacion_switch[_indice_trabajo_validacion_switch]
	var seccion_indice: int = int(trabajo.get("seccion", -1))
	var opcion_indice: int = int(trabajo.get("opcion", -1))
	if seccion_indice < 0 or seccion_indice >= _opciones_switch_cache.size():
		_indice_trabajo_validacion_switch += 1
		return
	var seccion: Dictionary = _opciones_switch_cache[seccion_indice]
	var opciones: Array = seccion.get("opciones", []) as Array
	if opcion_indice < 0 or opcion_indice >= opciones.size():
		_indice_trabajo_validacion_switch += 1
		return
	var opcion: Dictionary = opciones[opcion_indice] as Dictionary
	var inicio_us: int = Time.get_ticks_usec()
	var resultado: Dictionary = _avanzar_validacion_switch(trabajo)
	_microsegundos_switch_acumulados += Time.get_ticks_usec() - inicio_us
	_trabajos_switch_resueltos += 1
	var termino: bool = bool(resultado.get("terminado", false))
	if termino:
		opcion["ruta_precalculada"] = resultado.get("ruta_precalculada", {})
		opcion["valida"] = bool(resultado.get("valida", false))
		opcion["estado"] = "lista" if bool(resultado.get("valida", false)) else "invalida"
		_indice_trabajo_validacion_switch += 1
	else:
		_trabajos_validacion_switch[_indice_trabajo_validacion_switch] = resultado
	opciones[opcion_indice] = opcion
	seccion["opciones"] = opciones
	_opciones_switch_cache[seccion_indice] = seccion
	# Mientras una ruta aún está pendiente el HUD ya muestra "calculando".
	# No se repinta toda la lista por cada estación validada.
	if termino:
		opciones_switch_cambiadas.emit()


func _avanzar_validacion_switch(trabajo: Dictionary) -> Dictionary:
	var red: Node = _obtener_red()
	if red == null or _objetivo_servicio_resuelto.is_empty():
		return {"terminado": true, "valida": false}
	if str(trabajo.get("fase", "inicio")) == "inicio":
		var restricciones: Dictionary = _desvios_switch.duplicate()
		restricciones[int(trabajo.get("nodo", 0))] = str(trabajo.get("segmento", ""))
		var objetivo: Dictionary = _objetivo_servicio_resuelto
		var destino: Path3D = objetivo.get("traza") as Path3D
		if destino == null:
			return {"terminado": true, "valida": false}
		var override: Array[String] = _servicio_ferroviario.override_para(_indice_servicio - _direccion_servicio, _indice_servicio)
		var ruta: Dictionary = red.call("planificar_ruta", traza.name, _avance, invertir_sentido, destino.name, float(objetivo.get("offset", 0.0)), override, restricciones) as Dictionary
		if not bool(ruta.get("ok", false)) or not _ruta_contiene_desvio(red, ruta, int(trabajo.get("nodo", 0)), str(trabajo.get("segmento", ""))):
			return {"terminado": true, "valida": false}
		var pasos: Array = ruta.get("pasos", []) as Array
		if pasos.is_empty():
			return {"terminado": true, "valida": false}
		var final: Dictionary = pasos.back() as Dictionary
		trabajo["ruta_precalculada"] = ruta
		trabajo["segmento_actual"] = str(final.get("segmento", ""))
		trabajo["offset_actual"] = float(objetivo.get("offset", 0.0))
		trabajo["invertido_actual"] = str(final.get("direccion", "forward")) == "reversed"
		trabajo["indice_siguiente"] = _indice_servicio + _direccion_servicio
		var clave: String = "%d|%s|%.2f|%s" % [_indice_servicio, str(final.get("segmento", "")), float(objetivo.get("offset", 0.0)), str(final.get("direccion", "forward"))]
		trabajo["clave_continuidad"] = clave
		var continuidad: Dictionary = _servicio_ferroviario.obtener_continuidad(clave)
		if continuidad.is_empty():
			continuidad = _servicio_ferroviario.iniciar_continuidad(clave, get_instance_id())
		trabajo["fase"] = "futuras" if int(continuidad.get("propietario", 0)) == get_instance_id() else "esperando_continuidad"
		return trabajo

	var clave_continuidad: String = str(trabajo.get("clave_continuidad", ""))
	var continuidad_actual: Dictionary = _servicio_ferroviario.obtener_continuidad(clave_continuidad)
	if str(continuidad_actual.get("estado", "")) == "valida":
		return {"terminado": true, "valida": true, "ruta_precalculada": trabajo.get("ruta_precalculada", {})}
	if str(continuidad_actual.get("estado", "")) == "invalida":
		return {"terminado": true, "valida": false}
	if str(trabajo.get("fase", "")) == "esperando_continuidad":
		return trabajo

	var indice: int = int(trabajo.get("indice_siguiente", _servicio_ferroviario.cantidad_paradas()))
	if indice < 0 or indice >= _servicio_ferroviario.cantidad_paradas():
		_servicio_ferroviario.actualizar_continuidad(clave_continuidad, {"estado": "valida"})
		return {"terminado": true, "valida": true, "ruta_precalculada": trabajo.get("ruta_precalculada", {})}
	var estacion: Node = _servicio_ferroviario.obtener_parada(indice)
	var candidatos: Array[Dictionary] = _candidatos_estacion_servicio(estacion, red, _direccion_servicio > 0)
	var sin_override: Array[String] = []
	var eleccion: Dictionary = _mejor_ruta_a_candidatos_desde(red, candidatos, str(trabajo.get("segmento_actual", "")), float(trabajo.get("offset_actual", 0.0)), bool(trabajo.get("invertido_actual", false)), sin_override, {})
	if eleccion.is_empty():
		_servicio_ferroviario.actualizar_continuidad(clave_continuidad, {"estado": "invalida"})
		return {"terminado": true, "valida": false}
	var ruta_futura: Dictionary = eleccion.get("ruta", {}) as Dictionary
	var candidato: Dictionary = eleccion.get("candidato", {}) as Dictionary
	var pasos_futuros: Array = ruta_futura.get("pasos", []) as Array
	if pasos_futuros.is_empty():
		_servicio_ferroviario.actualizar_continuidad(clave_continuidad, {"estado": "invalida"})
		return {"terminado": true, "valida": false}
	var final_futuro: Dictionary = pasos_futuros.back() as Dictionary
	trabajo["segmento_actual"] = str(final_futuro.get("segmento", ""))
	trabajo["offset_actual"] = float(candidato.get("offset", 0.0))
	trabajo["invertido_actual"] = str(final_futuro.get("direccion", "forward")) == "reversed"
	trabajo["indice_siguiente"] = indice + _direccion_servicio
	return trabajo


func _planificar_con_switch(nodo_id: int, segmento_elegido: String, aplicar: bool) -> Dictionary:
	var red: Node = _obtener_red()
	if red == null or _objetivo_servicio_resuelto.is_empty():
		return {}
	var restricciones: Dictionary = _desvios_switch.duplicate()
	restricciones[nodo_id] = segmento_elegido
	var objetivo: Dictionary = _objetivo_servicio_resuelto
	var destino: Path3D = objetivo.get("traza") as Path3D
	if destino == null:
		return {}
	var override: Array[String] = _servicio_ferroviario.override_para(_indice_servicio - _direccion_servicio, _indice_servicio)
	var ruta: Dictionary = red.call("planificar_ruta", traza.name, _avance, invertir_sentido, destino.name, float(objetivo.get("offset", 0.0)), override, restricciones) as Dictionary
	if not bool(ruta.get("ok", false)) or not _ruta_contiene_desvio(red, ruta, nodo_id, segmento_elegido):
		return {}
	if not _validar_paradas_restantes(red, ruta):
		return {}
	if aplicar:
		_desvios_switch[nodo_id] = segmento_elegido
		_aplicar_ruta_actualizada(ruta, objetivo)
	return ruta


func _ruta_contiene_desvio(red: Node, ruta: Dictionary, nodo_id: int, segmento_elegido: String) -> bool:
	var pasos: Array = ruta.get("pasos", []) as Array
	for indice: int in range(maxi(0, pasos.size() - 1)):
		var paso: Dictionary = pasos[indice] as Dictionary
		var path: Path3D = red.call("get_segment_path", str(paso.get("segmento", ""))) as Path3D
		if path == null:
			continue
		var extremo: String = "start" if str(paso.get("direccion", "forward")) == "reversed" else "end"
		var opciones: Array[Dictionary] = red.call("get_opciones_siguientes", path.name, extremo) as Array[Dictionary]
		if not opciones.is_empty() and int(opciones[0].get("node_id", 0)) == nodo_id and str((pasos[indice + 1] as Dictionary).get("segmento", "")) == segmento_elegido:
			return true
	return false


func _validar_paradas_restantes(red: Node, ruta_actual: Dictionary) -> bool:
	var ultimo: Dictionary = _objetivo_servicio_resuelto
	var pasos_actuales: Array = ruta_actual.get("pasos", []) as Array
	if pasos_actuales.is_empty():
		return false
	var paso_final: Dictionary = pasos_actuales.back() as Dictionary
	var segmento_actual: String = str(paso_final.get("segmento", ""))
	var offset_actual: float = float(ultimo.get("offset", 0.0))
	var invertido_actual: bool = str(paso_final.get("direccion", "forward")) == "reversed"
	for indice: int in range(_indice_servicio + _direccion_servicio, _servicio_ferroviario.cantidad_paradas(), _direccion_servicio):
		var estacion: Node = _servicio_ferroviario.obtener_parada(indice)
		var candidatos: Array[Dictionary] = _candidatos_estacion_servicio(estacion, red, _direccion_servicio > 0)
		var sin_override: Array[String] = []
		var eleccion: Dictionary = _mejor_ruta_a_candidatos_desde(red, candidatos, segmento_actual, offset_actual, invertido_actual, sin_override, {})
		if eleccion.is_empty():
			return false
		var ruta: Dictionary = eleccion.get("ruta", {}) as Dictionary
		var candidato: Dictionary = eleccion.get("candidato", {}) as Dictionary
		var pasos: Array = ruta.get("pasos", []) as Array
		if pasos.is_empty():
			return false
		var ultimo_paso: Dictionary = pasos.back() as Dictionary
		segmento_actual = str(ultimo_paso.get("segmento", ""))
		offset_actual = float(candidato.get("offset", 0.0))
		invertido_actual = str(ultimo_paso.get("direccion", "forward")) == "reversed"
	return true


func seleccionar_switch(nodo_id: int, segmento_elegido: String) -> bool:
	# Una orden del panel nunca puede ganar una reserva física de otra
	# formación. La opción se podrá volver a elegir cuando ésta se libere.
	if opcion_switch_reservada_por_otro(nodo_id, segmento_elegido):
		return false
	for seccion: Dictionary in _opciones_switch_cache:
		if int(seccion.get("nodo_id", 0)) != nodo_id:
			continue
		for opcion_raw: Variant in seccion.get("opciones", []):
			var opcion: Dictionary = opcion_raw as Dictionary
			if str(opcion.get("segmento", "")) != segmento_elegido:
				continue
			if str(opcion.get("estado", "pendiente")) != "lista" or not bool(opcion.get("valida", false)):
				return false
			var ruta: Dictionary = opcion.get("ruta_precalculada", {}) as Dictionary
			if ruta.is_empty():
				return false
			_desvios_switch[nodo_id] = segmento_elegido
			_aplicar_ruta_actualizada(ruta, _objetivo_servicio_resuelto)
			opciones_switch_cambiadas.emit()
			return true
	return false


func opcion_switch_reservada_por_otro(nodo_id: int, segmento_elegido: String) -> bool:
	var red: Node = _obtener_red()
	return red != null and red.has_method("recurso_reservado_por_otro") and bool(red.call("recurso_reservado_por_otro", get_instance_id(), segmento_elegido, nodo_id))


func _aplicar_ruta_actualizada(ruta: Dictionary, objetivo: Dictionary) -> void:
	_invalidar_opciones_switch()
	_ruta_segmentos.clear()
	_ruta_pasos.clear()
	for segmento: Variant in ruta.get("segmentos", []):
		_ruta_segmentos.append(str(segmento))
	for paso: Variant in ruta.get("pasos", []):
		if paso is Dictionary:
			_ruta_pasos.append((paso as Dictionary).duplicate())
	_indice_paso_ruta = 0
	for indice: int in _ruta_pasos.size():
		if str(_ruta_pasos[indice].get("segmento", "")) == traza.name:
			_indice_paso_ruta = indice
			break
	_distancia_ruta = float(ruta.get("distancia_m", -1.0))
	_odometro_destino_ruta = _odometro_ferroviario + _distancia_ruta if _distancia_ruta >= 0.0 else -1.0
	_actualizar_distancia_ruta()
	ruta_actualizada.emit(str(objetivo.get("nombre", "")), _distancia_ruta)


## Refresca el objetivo de frenado local y el itinerario global al siguiente andén.
func _actualizar_ruta_servicio() -> void:
	# El Inspector puede invocar esta ruta desde setters exportados mientras el
	# nodo y la red todavía se están reconfigurando. En el editor sólo hace falta
	# proyectar la formación sobre la curva; recalcular el itinerario del servicio
	# aquí deja cachés de switches a medio construir y dispara "Bad address index".
	# La planificación se resuelve normalmente al ejecutar la escena.
	if Engine.is_editor_hint():
		return
	if _servicio_finalizado or _ruta_invalida or not _usa_servicio() or traza == null:
		return
	var red: Node = _obtener_red()
	if red == null or not red.has_method("planificar_ruta"):
		return
	var objetivo: Dictionary = _datos_objetivo_servicio()
	var ruta: Dictionary = {}
	if _indice_objetivo_resuelto != _indice_servicio or _objetivo_servicio_resuelto.is_empty():
		var estacion: Node = _parada_objetivo_servicio()
		if estacion == null:
			return
		var override: Array[String] = _servicio_ferroviario.override_para(_indice_servicio - _direccion_servicio, _indice_servicio)
		# Constitución → Bosques siempre usa el poste de ida: invertir_sentido sólo
		# expresa la orientación del Path3D que se está recorriendo.
		var candidatos: Array[Dictionary] = _candidatos_estacion_servicio(estacion, red, _direccion_servicio > 0)
		var corredor: Array[Dictionary] = []
		if red.has_method("obtener_corredor_inmediato"):
			corredor = red.call("obtener_corredor_inmediato", traza.name, _avance, invertir_sentido) as Array[Dictionary]
		if corredor.is_empty():
			var largo_actual: float = traza.curve.get_baked_length() if traza.curve != null else _avance
			corredor.append({"segmento": traza.name, "direccion": "reversed" if invertir_sentido else "forward", "desde": _avance, "hasta": 0.0 if invertir_sentido else largo_actual, "distancia_inicio": 0.0})
		var candidatos_corredor: Array[Dictionary] = _candidatos_adelante_en_corredor(candidatos, corredor)
		# Si la estación está sobre la vía que ya se está recorriendo, no se cruza
		# ninguna aguja para perseguir otra proyección del mismo andén.
		var usar_corredor: bool = not candidatos_corredor.is_empty()
		var override_activo: Array[String] = []
		if not usar_corredor:
			override_activo = override
		var eleccion: Dictionary = {}
		if usar_corredor:
			candidatos_corredor.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("distancia_corredor", INF)) < float(b.get("distancia_corredor", INF)))
			var candidato_directo: Dictionary = candidatos_corredor[0]
			eleccion = {"ruta": _ruta_directa_corredor(candidato_directo, corredor, invertir_sentido), "candidato": candidato_directo}
		else:
			eleccion = _mejor_ruta_a_candidatos_desde(red, candidatos, traza.name, _avance, invertir_sentido, override_activo, _desvios_switch)
		# Un servicio sólo ida no puede convertir una falta de conexión hacia
		# adelante en una maniobra de retorno. Es preferible diagnosticar la vía
		# faltante que alejarse de la próxima estación.
		if eleccion.is_empty() and not _servicio_ferroviario.solo_ida:
			# Sólo ante una desconexión real se prueba el sentido inverso y, por lo
			# tanto, el poste opuesto de la misma estación.
			var inversos: Array[Dictionary] = _candidatos_estacion_servicio(estacion, red, _direccion_servicio < 0)
			eleccion = _mejor_ruta_a_candidatos_desde(red, inversos, traza.name, _avance, not invertir_sentido, override, _desvios_switch)
		if eleccion.is_empty():
			if _reintentos_ruta_servicio < MAX_REINTENTOS_RUTA_SERVICIO:
				# Casi siempre transitorio (una aguja que otro tren tiene
				# ocupada en este instante), no una desconexión real de la
				# red -- ver docs/reporte_final.md. Mismo patrón que la
				# reserva de salida unas líneas más arriba: reintentar en
				# vez de matar el servicio a la primera.
				_reintentos_ruta_servicio += 1
				_tiempo_hasta_reintento_ruta = INTERVALO_REINTENTO_RUTA_S
				return
			_detener_por_ruta_invalida("No existe vía de parada transitable para %s." % str(estacion.get("nombre_estacion")))
			return
		_reintentos_ruta_servicio = 0
		ruta = eleccion["ruta"] as Dictionary
		var candidato_elegido: Dictionary = eleccion["candidato"] as Dictionary
		objetivo = _objetivo_desde_candidato(estacion, candidato_elegido)
		var segmentos_corredor: Array[String] = []
		for paso_corredor: Dictionary in corredor:
			segmentos_corredor.append(str(paso_corredor.get("segmento", "")))
		_registrar_diagnostico_ruta(estacion, candidato_elegido, segmentos_corredor, ruta, "aproximacion")
		_objetivo_servicio_resuelto = objetivo
		_indice_objetivo_resuelto = _indice_servicio
		_ruta_segmentos.clear()
		for segmento: Variant in ruta.get("segmentos", []):
			_ruta_segmentos.append(str(segmento))
		_ruta_pasos.clear()
		for paso: Variant in ruta.get("pasos", []):
			if paso is Dictionary:
				_ruta_pasos.append((paso as Dictionary).duplicate())
		if _ruta_pasos.is_empty():
			for segmento: String in _ruta_segmentos:
				_ruta_pasos.append({"segmento": segmento, "direccion": ""})
		_indice_paso_ruta = 0
		for i: int in _ruta_pasos.size():
			if str(_ruta_pasos[i].get("segmento", "")) == traza.name:
				_indice_paso_ruta = i
				break
		_distancia_ruta = float(ruta.get("distancia_m", -1.0))
		_odometro_destino_ruta = _odometro_ferroviario + _distancia_ruta if _distancia_ruta >= 0.0 else -1.0
		var sentido_ruta: bool = bool(ruta.get("sentido_invertido", invertir_sentido))
		if invertir_sentido != sentido_ruta:
			invertir_sentido = sentido_ruta
	if objetivo.is_empty():
		return
	if not bool(ruta.get("ok", false)):
		ruta = {"ok": true}
	_ruta_invalida = false
	_actualizar_distancia_ruta()
	_invalidar_opciones_switch()
	ruta_actualizada.emit(str(objetivo.get("nombre", "")), _distancia_ruta)
	var destino_traza: Path3D = objetivo.get("traza") as Path3D
	if destino_traza == traza:
		_datos_paradas = [objetivo]
		paradas = PackedFloat32Array([float(objetivo["offset"])])
		_idx_parada = 0
		_tiene_proxima_parada = true
	else:
		_datos_paradas.clear()
		paradas = PackedFloat32Array()
		_tiene_proxima_parada = false


## Busca y asigna la estación objetivo más próxima según el sentido de circulación actual.
func _buscar_proxima_parada(ignorar_estacion_actual: bool = false) -> bool:
	if _usa_servicio():
		_actualizar_ruta_servicio()
		return _tiene_proxima_parada
	if paradas.size() == 0 or traza == null or not is_instance_valid(traza) or traza.curve == null:
		_tiene_proxima_parada = false
		return false
	var largo: float = traza.curve.get_baked_length()
	if largo <= 0.0:
		_tiene_proxima_parada = false
		return false

	var direccion: float = -1.0 if invertir_sentido else 1.0
	var mejor_idx: int = -1
	var menor_dist: float = INF

	for i: int in paradas.size():
		var info: Dictionary = _datos_paradas[i] if i < _datos_paradas.size() else {}
		var id_parada: int = int(info.get("id", 0))
		var es_parada_atendida: bool = _id_parada_atendida != 0 and id_parada == _id_parada_atendida
		if ignorar_estacion_actual and (i == _idx_parada or es_parada_atendida):
			continue
		# Elegir por el punto real donde se detiene la cabina, no por el centro
		# del andén. Así una parada recién completada no reaparece como destino.
		var objetivo: float = _calcular_avance_objetivo(info, direccion) if not info.is_empty() else float(paradas[i])
		var dist: float = fposmod((objetivo - _avance) * direccion, largo)
		if dist < menor_dist:
			menor_dist = dist
			mejor_idx = i

	if mejor_idx != -1:
		_idx_parada = mejor_idx
		_id_parada_atendida = 0
		_tiene_proxima_parada = true
		return true

	# Si no hay otra estación, el tren sigue circulando sin intentar frenar de
	# nuevo en la única estación disponible después de una vuelta completa.
	_tiene_proxima_parada = false
	return false


func _recalcular_paradas_dinamicas() -> void:
	if _usa_servicio():
		# La geometría de la red termina de sincronizarse después de _ready().
		# No debe convertir el origen ya detenido en un nuevo destino de ruta.
		if _origen_servicio_inicializado and _parada_servicio_activa and _detenido and _indice_servicio == 0:
			return
		_objetivo_servicio_resuelto.clear()
		_indice_objetivo_resuelto = -1
		_actualizar_ruta_servicio()
		return
	if not autodetectar_estaciones:
		return
	if traza == null or not is_instance_valid(traza) or traza.curve == null or traza.curve.point_count < 2:
		return

	var lista_estaciones: Array[Node] = []
	if is_inside_tree():
		lista_estaciones = get_tree().get_nodes_in_group("estaciones")

	if lista_estaciones.is_empty() and is_inside_tree():
		var raiz: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
		if raiz != null:
			_buscar_estaciones_recursivo(raiz, lista_estaciones)

	var paradas_nuevas: Array[Dictionary] = []
	for e: Node in lista_estaciones:
		if not is_instance_valid(e) or not (e is Node3D) or not e.is_inside_tree():
			continue
		if "activa" in e and not e.activa:
			continue

		# Si la estación está asignada a otra traza distinta, ignorarla
		if "traza" in e and e.traza != null and e.traza != traza:
			continue

		var offset_m: float = 0.0
		if "progreso_en_via" in e and e.progreso_en_via > 0.0 and "alinear_a_via" in e and e.alinear_a_via:
			offset_m = e.progreso_en_via
		else:
			var pos_local_calc: Vector3 = traza.to_local(e.global_position)
			offset_m = traza.curve.get_closest_offset(pos_local_calc)

		var pos_local: Vector3 = traza.to_local(e.global_position)
		var punto_curva: Vector3 = traza.curve.sample_baked(offset_m)

		if pos_local.distance_to(punto_curva) <= distancia_maxima_via:
			var nombre: String = e.nombre_estacion if "nombre_estacion" in e else e.name
			var tiempo: float = float(e.tiempo_espera) if "tiempo_espera" in e else tiempo_parada
			var terminal: bool = bool(e.es_terminal) if "es_terminal" in e else false
			var terminal_ida: bool = terminal
			var terminal_vuelta: bool = terminal
			if e.has_method("es_terminal_en_sentido"):
				terminal_ida = bool(e.call("es_terminal_en_sentido", true))
				terminal_vuelta = bool(e.call("es_terminal_en_sentido", false))
			var off_ida: float = offset_m
			var off_vuelta: float = offset_m
			if e.has_method("obtener_offset_parada"):
				off_ida = e.obtener_offset_parada(true)
				off_vuelta = e.obtener_offset_parada(false)
			elif "desfasaje_parada_ida" in e:
				off_ida = offset_m + float(e.desfasaje_parada_ida)
				off_vuelta = offset_m + float(e.desfasaje_parada_vuelta)

			paradas_nuevas.append({
				"id": e.get_instance_id(),
				"offset": snappedf(offset_m, 0.01),
				"offset_ida": snappedf(off_ida, 0.01),
				"offset_vuelta": snappedf(off_vuelta, 0.01),
				"nombre": nombre,
				"tiempo_espera": tiempo,
				"es_terminal": terminal,
				"es_terminal_ida": terminal_ida,
				"es_terminal_vuelta": terminal_vuelta,
				"nodo": e,
			})

	paradas_nuevas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["offset"]) < float(b["offset"]))

	_datos_paradas = paradas_nuevas
	var lista_offsets: Array[float] = []
	for p: Dictionary in paradas_nuevas:
		lista_offsets.append(p["offset"])
	paradas = PackedFloat32Array(lista_offsets)

	if paradas.size() > 0:
		_buscar_proxima_parada(_id_parada_atendida != 0)


func _buscar_estaciones_recursivo(nodo: Node, resultado: Array[Node]) -> void:
	if nodo != self and (nodo.is_in_group("estaciones") or nodo.name.begins_with("Estacion")):
		if nodo is Node3D and not resultado.has(nodo):
			resultado.append(nodo)
	for h: Node in nodo.get_children():
		_buscar_estaciones_recursivo(h, resultado)


func _on_curva_cambiada() -> void:
	if is_inside_tree():
		if _cuerpos.size() > 0:
			_ubicar(0.0)
		_recalcular_paradas_dinamicas()


## Conmuta la circulación del tren a una nueva traza (Path3D) de forma continua (ej. al tomar un desvío).
## Transición MANUAL/editor: re-proyecta la posición actual sobre la nueva vía.
func cambiar_de_via(nueva_traza: Path3D) -> void:
	if nueva_traza == null or not is_instance_valid(nueva_traza) or nueva_traza.curve == null:
		return
	if nueva_traza == traza:
		return

	if traza != null and is_instance_valid(traza) and traza.curve != null:
		if traza.curve.changed.is_connected(_on_curva_cambiada):
			traza.curve.changed.disconnect(_on_curva_cambiada)

	traza = nueva_traza
	if traza.curve != null and not traza.curve.changed.is_connected(_on_curva_cambiada):
		traza.curve.changed.connect(_on_curva_cambiada)

	# Calcular nuevo avance métrico sobre la curva de la nueva vía
	var pos_local: Vector3 = traza.to_local(global_position)
	_avance = traza.curve.get_closest_offset(pos_local)
	avance_inicial = _avance
	_reiniciar_historial_recorrido()

	_recalcular_paradas_dinamicas()
	if _cuerpos.size() > 0:
		_ubicar(0.0)


## Transición de RUTEO: encadena el tramo actual con el siguiente conservando el avance
## y el sentido ya calculados. NO re-proyecta sobre `global_position` (la posición del
## nodo raíz está fija: los coches se mueven como hijos) porque eso provocaba saltos en
## cada switch. Es la clave de un recorrido continuo por la red.
func _continuar_en_via(nueva_traza: Path3D, nuevo_avance: float, sentido_invertido: bool) -> void:
	if nueva_traza == null or not is_instance_valid(nueva_traza) or nueva_traza.curve == null:
		return
	if traza != null and is_instance_valid(traza) and traza.curve != null and traza != nueva_traza:
		if traza.curve.changed.is_connected(_on_curva_cambiada):
			traza.curve.changed.disconnect(_on_curva_cambiada)
	_transicion_de_ruta = true
	traza = nueva_traza
	if traza.curve != null and not traza.curve.changed.is_connected(_on_curva_cambiada):
		traza.curve.changed.connect(_on_curva_cambiada)
	invertir_sentido = sentido_invertido
	_avance = clampf(nuevo_avance, 0.0, traza.curve.get_baked_length())
	_transicion_de_ruta = false
	if _usa_servicio():
		_actualizar_ruta_servicio()
	else:
		_recalcular_paradas_dinamicas()


func _limpiar() -> void:
	for c: Node3D in _cuerpos:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	_cuerpos.clear()
	_ruedas.clear()


func _reconstruir() -> void:
	_limpiar()

	if traza == null or not is_instance_valid(traza) or traza.curve == null or traza.curve.point_count < 2:
		return

	if not traza.is_inside_tree():
		return

	if escena_coche_motriz == null and escena_coche_remolcado == null:
		return

	_instanciar_formacion()
	_ubicar(0.0)


func _instanciar_formacion() -> void:
	for i: int in cantidad_coches:
		var es_cabecera: bool = (i == 0 or i == cantidad_coches - 1)
		var escena: PackedScene = escena_coche_motriz if es_cabecera else escena_coche_remolcado
		if escena == null:
			escena = escena_coche_motriz if escena_coche_motriz != null else escena_coche_remolcado

		var cuerpo: Node3D = escena.instantiate()
		cuerpo.name = "Coche_%d" % i
		# No asignamos owner para evitar inflar el .tscn con mallas estáticas
		add_child(cuerpo)
		_cuerpos.append(cuerpo)
		_agregar_selector_clic(cuerpo)

		var ejes: Array[Node3D] = []
		for hijo: Node in cuerpo.get_children():
			if hijo is Node3D and hijo.name.begins_with("Eje_"):
				ejes.append(hijo)
		_ruedas.append(ejes)


## Agrega un volumen invisible "pickeable" a un coche para poder seleccionar
## la formación completa con un clic en el viewport (ver señal `seleccionado`).
## No participa de la física real: solo habilita el picking del mouse.
func _agregar_selector_clic(cuerpo: Node3D) -> void:
	var selector := Area3D.new()
	selector.name = "SelectorClic"
	selector.input_ray_pickable = true
	selector.monitoring = false
	selector.monitorable = false
	selector.input_event.connect(_on_selector_input_event)

	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(3.2, 4.2, paso * 0.9)
	forma.shape = caja
	forma.position = Vector3(0.0, 2.1, 0.0)
	selector.add_child(forma)

	cuerpo.add_child(selector)


func _on_selector_input_event(_camara: Node, evento: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if evento is InputEventMouseButton and evento.pressed and evento.button_index == MOUSE_BUTTON_LEFT:
		seleccionado.emit()


func _process(delta: float) -> void:
	if _eliminado or _servicio_finalizado:
		return
	if _tiempo_hasta_reintento_ruta > 0.0 and not Engine.is_editor_hint():
		_tiempo_hasta_reintento_ruta -= delta
		_vel = 0.0
		velocidad_cambiada.emit(0.0)
		if _tiempo_hasta_reintento_ruta <= 0.0:
			_actualizar_ruta_servicio()
		return
	if not Engine.is_editor_hint() and delta <= 0.0:
		return
	if _estado_operacion == EstadoOperacion.DETENIDO_POR_EVENTO and not Engine.is_editor_hint():
		_tiempo_evento_restante = maxf(0.0, _tiempo_evento_restante - delta)
		if _tiempo_evento_restante <= 0.0:
			reanudar_por_evento()
		return
	if not Engine.is_editor_hint() and _opciones_switch_activas:
		_procesar_validacion_switch()

	if Engine.is_editor_hint():
		if alinear_a_via and _pendiente_snap and not animar_en_editor:
			var clic_izq: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			var tiempo_pasado: int = Time.get_ticks_msec() - _tiempo_ultimo_movimiento
			# Cuando el usuario suelta el mouse tras arrastrar en el editor 3D
			if not clic_izq and tiempo_pasado > 60:
				_pendiente_snap = false
				_snap_a_posicion_actual()
		if not animar_en_editor:
			return

	if traza == null or not is_instance_valid(traza) or traza.curve == null:
		return

	var largo: float = traza.curve.get_baked_length()
	if largo <= 0.0:
		return
	if _usa_servicio() and _ruta_invalida:
		_vel = 0.0
		velocidad_cambiada.emit(0.0)
		return

	var direccion: float = -1.0 if invertir_sentido else 1.0

	if _detenido:
		_espera -= delta
		if _espera <= 0.0 and not _procesando_pasajeros:
			if _usa_servicio() and _parada_servicio_activa:
				if _origen_servicio_inicializado and not _reserva_inicial_lista:
					var red_origen: Node = _obtener_red()
					var largo_formacion: float = float(cantidad_coches - 1) * paso + 24.2
					if red_origen == null or not red_origen.has_method("reservar_tramo_inicial") or not bool(red_origen.call("reservar_tramo_inicial", get_instance_id(), traza.name, _avance, invertir_sentido, _odometro_ferroviario, largo_formacion)):
						_esperando_reserva = true
						_establecer_estado(EstadoOperacion.ESPERANDO_RESERVA, "Esperando reserva de salida.")
						_espera = 0.5
						return
					_reserva_inicial_lista = true
				if _servicio_ferroviario.finaliza_en(_indice_servicio, _direccion_servicio):
					# El servicio unidireccional concluye definitivamente en Bosques.
					_finalizar_servicio_en_terminal()
					return
				_detenido = false
				_esperando_reserva = false
				var estacion_salida: Dictionary = _resumen_estacion(_parada_objetivo_servicio())
				_establecer_estado(EstadoOperacion.EN_MARCHA)
				salio_de_estacion.emit(obtener_resumen_operativo(), estacion_salida)
				marcha_reanudada.emit()
				_parada_servicio_activa = false
				if _servicio_ferroviario.es_terminal(_indice_servicio):
					# El extremo 0 sale hacia el 1; el último sale hacia el anterior.
					_direccion_servicio = 1 if _indice_servicio == 0 else -1
				_indice_servicio = _servicio_ferroviario.siguiente_indice(_indice_servicio, _direccion_servicio)
				_objetivo_servicio_resuelto.clear()
				_indice_objetivo_resuelto = -1
				_actualizar_ruta_servicio()
			else:
				_detenido = false
				_establecer_estado(EstadoOperacion.EN_MARCHA)
				marcha_reanudada.emit()
				if _debe_invertir_en_salida:
					_debe_invertir_en_salida = false
					invertir_sentido = not invertir_sentido
				else:
					# Una estación no terminal debe seguir siendo una parada válida en
					# el siguiente paso por la línea. Si es la única de este tramo,
					# se conserva como destino para la próxima vuelta, sin invertir.
					var encontro_otra_parada: bool = _buscar_proxima_parada(true)
					if not encontro_otra_parada:
						_id_parada_atendida = 0
						_tiene_proxima_parada = true

			_aceleracion_actual = 0.0
		return

	var v_max: float = velocidad_maxima_efectiva_kmh() / 3.6

	if paradas.size() > 0 and _tiene_proxima_parada:
		var info_parada: Dictionary = _datos_paradas[_idx_parada] if _idx_parada < _datos_paradas.size() else {}
		var objetivo_avance: float = _calcular_avance_objetivo(info_parada, direccion)

		# El punto de detención es exactamente el poste configurado para este
		# sentido. No se introduce dispersión: el tren debe alinear su cabina con él.
		var objetivo_efectivo: float = objetivo_avance
		# Distancia con signo a lo largo de la traza para evitar desbordes modulares al cruzar la marca
		var diff: float = (objetivo_efectivo - _avance) * direccion
		var dist_con_signo: float = fposmod(diff + largo * 0.5, largo) - largo * 0.5
		var freno_efectivo: float = desaceleracion_efectiva()
		var dist_frenado_nominal: float = (_vel * _vel) / (2.0 * maxf(freno_efectivo, 0.01))

		var debe_frenar: bool = false
		if _frenando_estacion:
			# Si ya comenzó la aproximación, mantiene el frenado hasta detenerse por completo
			debe_frenar = (dist_con_signo >= -2.0)
		else:
			debe_frenar = (dist_con_signo > 0.0 and dist_con_signo <= dist_frenado_nominal + 3.0)

		if debe_frenar:
			_frenando_estacion = true
			_aceleracion_actual = 0.0
			# Curva de desaceleración continua y progresiva
			var dist_calc: float = maxf(dist_con_signo, 0.1)
			var desac_demandada: float = (_vel * _vel) / (2.0 * dist_calc)
			desac_demandada = clampf(desac_demandada, 0.0, freno_efectivo * 1.35)

			# Afloje final anti-sacudida (suavizado al aproximarse a 0 para confort de pasajeros)
			if _vel < 1.4 and dist_con_signo < 1.2:
				desac_demandada = minf(desac_demandada, maxf(0.35, freno_efectivo * 0.55))

			# Límite de sacudida (jerk limit): rampa suave sin saltos de aceleración
			_desaceleracion_actual = move_toward(_desaceleracion_actual, desac_demandada, 1.8 * delta)
			_vel = maxf(0.0, _vel - _desaceleracion_actual * delta)

			# Parada total natural: velocidad casi nula o alcance del punto de detención a paso de hombre
			var parada_completada: bool = false
			if _vel <= 0.03:
				parada_completada = true
			elif dist_con_signo <= 0.03 and _vel <= 0.5:
				parada_completada = true
			elif dist_con_signo < -0.3:
				parada_completada = true

			if parada_completada:
				_completar_parada_actual(info_parada, direccion, objetivo_avance)
				return
		else:
			_aplicar_aceleracion(delta, v_max)
	else:
		_aplicar_aceleracion(delta, v_max)

	velocidad_cambiada.emit(velocidad_actual())

	var paso_avance: float = _vel * delta
	# Ningún frame puede consumir más metros que los que separan a la cabecera
	# del poste objetivo. Esto evita saltar una parada si el frame cruza varios
	# Path3D con velocidad de prueba alta.
	if _tiene_proxima_parada and _distancia_ruta >= 0.0:
		paso_avance = minf(paso_avance, _distancia_ruta)
	# Cuando el objetivo ya está sobre el tramo actual, la referencia exacta es
	# la cabina, no el poste crudo. Esto es importante si el poste queda cerca
	# de una unión: la cabecera nunca debe atravesarla antes de terminar de
	# frenar, aun con una velocidad de prueba elevada.
	if paradas.size() > 0 and _tiene_proxima_parada and _idx_parada < _datos_paradas.size():
		var objetivo_local: float = _calcular_avance_objetivo(_datos_paradas[_idx_parada], direccion)
		var distancia_local: float = fposmod((objetivo_local - _avance) * direccion + largo * 0.5, largo) - largo * 0.5
		if distancia_local >= 0.0:
			paso_avance = minf(paso_avance, distancia_local)
	var net: Node = _obtener_red()
	var estaba_en_marcha: bool = _estado_operacion == EstadoOperacion.EN_MARCHA
	var recorrido_real: float = _avanzar_por_red(paso_avance, net)
	# La red informa cuántos metros se consumieron realmente. Acumular sólo si
	# el tren entró a este paso en marcha y hubo movimiento. La proporción evita
	# atribuir un frame entero al instante final de una aproximación corta.
	if estaba_en_marcha and recorrido_real > 0.0001 and paso_avance > 0.0001:
		_metros_marcha += recorrido_real
		_segundos_marcha += delta * clampf(recorrido_real / paso_avance, 0.0, 1.0)
	if net != null and net.has_method("actualizar_reservas_tren"):
		net.call("actualizar_reservas_tren", get_instance_id(), _odometro_ferroviario)
	_actualizar_distancia_ruta()
	if _tiene_proxima_parada and _distancia_ruta >= 0.0 and _distancia_ruta <= 0.01 and _idx_parada < _datos_paradas.size():
		_completar_parada_actual(_datos_paradas[_idx_parada], direccion, _avance)
		return
	_ubicar(recorrido_real)


## Cierra una detención tanto para el frenado normal como para el caso en que
## el avance de un frame llega exactamente al poste tras cruzar varios tramos.
func _completar_parada_actual(info_parada: Dictionary, direccion: float, objetivo_avance: float) -> void:
	_vel = 0.0
	_avance = objetivo_avance
	_detenido = true
	_frenando_estacion = false
	_desaceleracion_actual = 0.0
	_aceleracion_actual = 0.0

	if _datos_paradas.is_empty() or _datos_paradas.size() != paradas.size():
		_recalcular_paradas_dinamicas()
		info_parada = _datos_paradas[_idx_parada] if _idx_parada < _datos_paradas.size() else {}

	var sentido_ida_parada: bool = _direccion_servicio > 0 if _usa_servicio() else direccion > 0.0
	var clave_terminal: String = "es_terminal_ida" if sentido_ida_parada else "es_terminal_vuelta"
	var es_term: bool = bool(info_parada.get(clave_terminal, info_parada.get("es_terminal", false)))
	var tiempo_est: float = float(info_parada.get("tiempo_espera", tiempo_parada))
	_id_parada_atendida = int(info_parada.get("id", 0))
	_espera = maxf(tiempo_est, 1.0)
	_debe_invertir_en_salida = es_term
	_parada_servicio_activa = _usa_servicio()
	_procesar_pasajeros_parada(info_parada.get("nodo"), es_term, direccion, _espera)
	_establecer_estado(EstadoOperacion.DETENIDO_EN_ESTACION)
	parada_alcanzada.emit(_idx_parada)
	llego_a_estacion.emit(obtener_resumen_operativo(), _resumen_estacion(info_parada))
	_ubicar(0.0)


## Consume toda la distancia disponible, incluso si con una velocidad de prueba
## se atraviesan varios límites de segmento en el mismo frame.
func _avanzar_por_red(distancia: float, net: Node) -> float:
	var restante: float = maxf(0.0, distancia)
	var recorrido: float = 0.0
	var iteraciones: int = 0
	while restante > 0.0001 and iteraciones < 128:
		iteraciones += 1
		if traza == null or traza.curve == null:
			break
		var largo_actual: float = maxf(0.001, traza.curve.get_baked_length())
		var direccion_actual: float = -1.0 if invertir_sentido else 1.0
		var hasta_extremo: float = (largo_actual - _avance) if direccion_actual > 0.0 else _avance
		if restante < hasta_extremo - 0.0001:
			_avance += restante * direccion_actual
			_odometro_ferroviario += restante
			recorrido += restante
			restante = 0.0
			break

		# Alcanzar exactamente el extremo actual antes de elegir la continuación.
		var consumido: float = maxf(0.0, hasta_extremo)
		_avance = largo_actual if direccion_actual > 0.0 else 0.0
		_odometro_ferroviario += consumido
		recorrido += consumido
		restante -= consumido
		# Si el movimiento se agotó exactamente en un extremo, no atravesar una
		# unión por inercia. El llamador actualizará la distancia y podrá cerrar
		# una parada cuyo poste coincida con ese extremo.
		if restante <= 0.0001:
			break
		if net == null:
			if _usa_servicio():
				_detener_por_ruta_invalida("El itinerario dirigido perdió su red ferroviaria.")
			else:
				_vel = 0.0
			break
		var extremo: String = "end" if direccion_actual > 0.0 else "start"
		var opciones: Array = net.call("get_opciones_siguientes", traza.name, extremo) as Array
		if opciones.is_empty():
			if _usa_servicio():
				_detener_por_ruta_invalida("El itinerario no continúa desde %s." % traza.name)
			else:
				_vel = 0.0
			break
		var node_id: int = int((opciones[0] as Dictionary).get("node_id", 0))
		var proxima: Dictionary = {}
		if _usa_servicio() and not _ruta_pasos.is_empty():
			var esperado: String = ""
			var direccion_esperada: String = ""
			if _indice_paso_ruta < _ruta_pasos.size() and str(_ruta_pasos[_indice_paso_ruta].get("segmento", "")) == traza.name:
				if _indice_paso_ruta + 1 < _ruta_pasos.size():
					var paso_siguiente: Dictionary = _ruta_pasos[_indice_paso_ruta + 1]
					esperado = str(paso_siguiente.get("segmento", ""))
					direccion_esperada = str(paso_siguiente.get("direccion", ""))
			else:
				_detener_por_ruta_invalida("El tren abandonó el itinerario dirigido en %s." % traza.name)
				break
			for opcion: Dictionary in opciones:
				if str(opcion.get("segment_id", "")) == esperado and (direccion_esperada.is_empty() or str(opcion.get("direccion", "")) == direccion_esperada):
					proxima = opcion
					break
			if proxima.is_empty() and not esperado.is_empty():
				_detener_por_ruta_invalida("El itinerario no continúa desde %s hacia %s." % [traza.name, esperado])
				break
		if proxima.is_empty():
			proxima = net.call("get_switch_target", node_id, opciones, traza.name) as Dictionary
		var siguiente_id: String = str(proxima.get("segment_id", ""))
		var siguiente: Path3D = net.call("get_segment_path", siguiente_id) as Path3D
		if siguiente == null or siguiente.curve == null:
			if _usa_servicio():
				_detener_por_ruta_invalida("La continuación %s no existe en la red." % siguiente_id)
			else:
				_vel = 0.0
			break
		if net.has_method("solicitar_reserva_seccion"):
			var largo_formacion: float = float(cantidad_coches - 1) * paso + 24.2
			if not bool(net.call("solicitar_reserva_seccion", get_instance_id(), siguiente_id, node_id, _odometro_ferroviario, largo_formacion)):
				_esperando_reserva = true
				_vel = 0.0
				_establecer_estado(EstadoOperacion.ESPERANDO_RESERVA, "Esperando reserva de sección.")
				break
		_esperando_reserva = false
		if _estado_operacion == EstadoOperacion.ESPERANDO_RESERVA:
			_establecer_estado(EstadoOperacion.EN_MARCHA)
		if node_id > 0 and net.has_method("set_switch_target"):
			net.call("set_switch_target", node_id, siguiente_id, get_instance_id())
		var sentido_inverso: bool = str(proxima.get("direccion", "forward")) != "forward"
		var entrada: float = siguiente.curve.get_baked_length() if sentido_inverso else 0.0
		_continuar_en_via(siguiente, entrada, sentido_inverso)
		if _usa_servicio() and not _ruta_pasos.is_empty():
			_indice_paso_ruta += 1
		_registrar_inicio_tramo()
	return recorrido


## Aplica una curva de tracción ferroviaria realista con rampa de esfuerzo (jerk limit),
## potencia constante a media/alta velocidad y suavizado de llegada a velocidad crucero.
func _aplicar_aceleracion(delta: float, v_max: float) -> void:
	_frenando_estacion = false
	_desaceleracion_actual = 0.0

	# 1. Curva de esfuerzo de tracción (la fuerza decae suavemente con la velocidad por encima de 12 m/s)
	var factor_potencia: float = 1.0
	if _vel > 12.0:
		factor_potencia = 12.0 / _vel

	# 2. Suavizado progresivo al aproximarse a la velocidad crucero (gobernador de velocidad)
	var margen_vmax: float = clampf((v_max - _vel) / 3.0, 0.0, 1.0)
	var acel_demandada: float = aceleracion_efectiva() * factor_potencia * margen_vmax

	# 3. Rampa de tracción (Jerk limiter: 0.40 m/s³ para una salida progresiva y realista de andén)
	_aceleracion_actual = move_toward(_aceleracion_actual, acel_demandada, 0.40 * delta)
	_vel = clampf(_vel + _aceleracion_actual * delta, 0.0, v_max)


## Calcula el valor objetivo de `_avance` necesario para que la formación se detenga
## exactamente en la posición requerida según el sentido de circulación y modo de detención.
func _calcular_avance_objetivo(info_parada: Dictionary, direccion: float) -> float:
	var largo: float = traza.curve.get_baked_length() if traza and traza.curve else 1.0
	var offset_estacion: float = float(info_parada.get("offset", 0.0))
	var offset_poste: float = float(info_parada.get("offset_ida" if direccion > 0.0 else "offset_vuelta", offset_estacion))

	if modo_detencion == 1:
		# Modo: Centro de la formación en el centro de la estación
		var mitad_tren: float = float(cantidad_coches - 1) * paso * 0.5
		return fposmod(offset_estacion + mitad_tren, largo)

	# Modo 0 (por defecto): La nariz de la cabina delantera activa se clava en el Poste de Parada
	const MITAD_COCHE: float = 12.1 # Distancia del centro del coche motriz a su trompa
	if direccion > 0.0:
		# Sentido directo: La cabina delantera es Coche 0 (ubicada en _avance)
		# Trompa = _avance + MITAD_COCHE = offset_poste  ==>  _avance = offset_poste - MITAD_COCHE
		return fposmod(offset_poste - MITAD_COCHE, largo)
	else:
		# Sentido inverso: La cabina delantera es el último coche (Coche N-1)
		# Centro Coche N-1 = _avance - (N-1)*paso
		# Trompa Coche N-1 hacia atras = _avance - (N-1)*paso - MITAD_COCHE = offset_poste
		# ==> _avance = offset_poste + (N-1)*paso + MITAD_COCHE
		var distancia_cola: float = float(cantidad_coches - 1) * paso
		return fposmod(offset_poste + distancia_cola + MITAD_COCHE, largo)


## Red ferroviaria (TrackNetwork) que contiene la traza actual, si existe.
func _obtener_red() -> Node:
	if traza != null:
		var c: Node = traza.get_parent()
		while c != null:
			if c.has_method("get_opciones_siguientes"):
				return c
			c = c.get_parent()
	if is_inside_tree():
		return get_tree().get_first_node_in_group("track_network")
	return null


## Siguiente/previo tramo conectado a un extremo, con la dirección de recorrido.
## Devuelve {} si no hay continuación transitable.
func _vecino_ruta(path: Path3D, extremo: String) -> Dictionary:
	var net: Node = _obtener_red()
	if net == null or path == null:
		return {}
	var opciones: Array = net.call("get_opciones_siguientes", path.name, extremo) as Array
	if opciones.is_empty():
		return {}
	var node_id: int = int((opciones[0] as Dictionary).get("node_id", 0))
	var target: Dictionary = net.call("get_switch_target", node_id, opciones, path.name) as Dictionary
	var seg_id: String = str(target.get("segment_id", ""))
	if seg_id.is_empty():
		return {}
	var prox: Path3D = net.call("get_segment_path", seg_id) as Path3D
	if prox == null or prox.curve == null:
		return {}
	return {"path": prox, "direccion": str(target.get("direccion", "forward"))}


## Punto global a `dist` metros de la cabecera en el sentido de marcha (negativo = detrás).
## Encadena segmentos por la red (no se pliega dentro de un tramo): así una formación
## larga sobre tramos cortos entre switches sigue el trazado real sin doblarse.
func _punto_en_red(dist: float) -> Vector3:
	var odometro_muestra: float = _odometro_ferroviario + dist
	if odometro_muestra <= _odometro_ferroviario + 0.0001 and not _historial_recorrido.is_empty():
		for indice: int in range(_historial_recorrido.size() - 1, -1, -1):
			var estado: Dictionary = _historial_recorrido[indice]
			if odometro_muestra + 0.0001 < float(estado.get("odometro", 0.0)):
				continue
			var tramo: Path3D = estado.get("traza") as Path3D
			if tramo != null and is_instance_valid(tramo) and tramo.curve != null:
				var signo: float = -1.0 if bool(estado.get("invertido", false)) else 1.0
				var avance_historico: float = float(estado.get("avance", 0.0)) + (odometro_muestra - float(estado.get("odometro", 0.0))) * signo
				avance_historico = clampf(avance_historico, 0.0, tramo.curve.get_baked_length())
				return tramo.to_global(tramo.curve.sample_baked(avance_historico))
	return _punto_en_red_actual(dist)


## Muestra sólo lo que está por delante de la cabecera. Lo que ya recorrió la
## formación se resuelve en `_punto_en_red` con el historial inmutable.
func _punto_en_red_actual(dist: float) -> Vector3:
	if traza == null or not is_instance_valid(traza) or traza.curve == null:
		return global_position
	var path: Path3D = traza
	var av: float = _avance
	var inv: bool = invertir_sentido
	var restante: float = dist
	var iter: int = 0
	while iter < 96:
		iter += 1
		if path == null or path.curve == null:
			break
		var l: float = path.curve.get_baked_length()
		if l <= 0.001:
			break
		var dir: float = -1.0 if inv else 1.0
		var av_del: float = l if dir > 0.0 else 0.0
		var av_tra: float = 0.0 if dir > 0.0 else l
		var dist_del: float = (av_del - av) * dir
		var dist_tra: float = (av_tra - av) * dir
		if restante > dist_del:
			restante -= dist_del
			var vec: Dictionary = _vecino_ruta(path, "end" if dir > 0.0 else "start")
			if vec.is_empty():
				return path.to_global(path.curve.sample_baked(av_del))
			var dv: String = str(vec.get("direccion", "forward"))
			path = vec["path"] as Path3D
			inv = (dv != "forward")
			av = 0.0 if dv == "forward" else path.curve.get_baked_length()
		elif restante < dist_tra:
			restante -= dist_tra
			var vec2: Dictionary = _vecino_ruta(path, "start" if dir > 0.0 else "end")
			if vec2.is_empty():
				return path.to_global(path.curve.sample_baked(av_tra))
			var dv2: String = str(vec2.get("direccion", "forward"))
			path = vec2["path"] as Path3D
			# Retrocediendo, el vecino es el tramo PREVIO: se recorría con orientación inversa.
			inv = (dv2 == "forward")
			av = 0.0 if dv2 == "forward" else path.curve.get_baked_length()
		else:
			return path.to_global(path.curve.sample_baked(av + restante * dir))
	return path.to_global(path.curve.sample_baked(av))


func _ubicar(recorrido: float) -> void:
	if traza == null or not is_instance_valid(traza) or traza.curve == null:
		return

	var largo: float = traza.curve.get_baked_length()
	if largo <= 0.0:
		return

	for i: int in _cuerpos.size():
		# Distancia de cada bogie respecto a la cabecera (la cabecera está en _avance).
		var centro: float = -paso * float(i)
		var a: Vector3 = _punto_en_red(centro + semi_bogie)
		var b: Vector3 = _punto_en_red(centro - semi_bogie)
		if a.distance_squared_to(b) < 0.001:
			continue

		var cuerpo: Node3D = _cuerpos[i]
		cuerpo.global_position = (a + b) * 0.5

		# El último coche va de cola: mira para el otro lado.
		var es_cola: bool = (i == _cuerpos.size() - 1)
		var objetivo: Vector3 = b if es_cola else a
		cuerpo.look_at(objetivo, Vector3.UP)

		if recorrido != 0.0:
			var sentido_coche: float = -1.0 if es_cola else 1.0
			var angulo: float = sentido_coche * recorrido / radio_rueda
			if i < _ruedas.size():
				for r: Node3D in _ruedas[i]:
					r.rotate_x(angulo)


## Velocidad instantánea en km/h
func velocidad_actual() -> float:
	return _vel * 3.6


## True si el tren está detenido en una estación (o frenando para hacerlo).
func esta_detenido() -> bool:
	return _detenido or _frenando_estacion


## Indica que el servicio de ida terminó y la formación quedó retirada en
## Bosques. El nodo sigue existiendo para futuros módulos de estadísticas.
func servicio_finalizado() -> bool:
	return _servicio_finalizado


## Expone si una formación quedó detenida por una ruta inválida sin convertir
## este detalle interno en un estado público completo (eso pertenece a Fase 2).
func ruta_invalida() -> bool:
	return _ruta_invalida


## Nombre de la próxima parada a la que se dirige el tren, o cadena vacía
## si no hay paradas configuradas.
func proxima_estacion_nombre() -> String:
	if _usa_servicio():
		var objetivo: Dictionary = _datos_objetivo_servicio()
		return str(objetivo.get("nombre", ""))
	if _idx_parada >= _datos_paradas.size():
		return ""
	return String(_datos_paradas[_idx_parada].get("nombre", ""))


## Paradas que quedan en el sentido actual del servicio, para HUD y depuración.
func itinerario_estaciones() -> Array[String]:
	var resultado: Array[String] = []
	if _usa_servicio():
		var indice: int = _indice_servicio
		while indice >= 0 and indice < _servicio_ferroviario.cantidad_paradas():
			var estacion: Node = _servicio_ferroviario.obtener_parada(indice)
			if estacion != null:
				resultado.append(str(estacion.get("nombre_estacion")) if "nombre_estacion" in estacion else estacion.name)
			indice += _direccion_servicio
		return resultado
	for parada: Dictionary in _datos_paradas:
		resultado.append(str(parada.get("nombre", "")))
	return resultado


## Distancia en metros que falta recorrer hasta la próxima parada, siguiendo
## la vía en el sentido de circulación actual. Usa el mismo cálculo que el
## frenado real, así que coincide con el punto donde el tren se va a detener.
## Devuelve -1.0 si no hay traza o paradas configuradas.
func distancia_a_proxima_estacion() -> float:
	if _usa_servicio():
		return _distancia_ruta
	if traza == null or not is_instance_valid(traza) or traza.curve == null:
		return -1.0
	if _idx_parada >= _datos_paradas.size():
		return -1.0

	var largo: float = traza.curve.get_baked_length()
	if largo <= 0.0:
		return -1.0

	var direccion: float = -1.0 if invertir_sentido else 1.0
	var info_parada: Dictionary = _datos_paradas[_idx_parada]
	var objetivo_avance: float = _calcular_avance_objetivo(info_parada, direccion)
	var diff: float = (objetivo_avance - _avance) * direccion
	var dist_con_signo: float = fposmod(diff + largo * 0.5, largo) - largo * 0.5
	return maxf(0.0, dist_con_signo)


## True si a este tren ya se le llamó `eliminar()` (dejó de simular y está
## a la espera de que Godot lo libere de la escena).
func esta_eliminado() -> bool:
	return _eliminado


## Saca al tren de servicio: deja de moverse y procesar pasajeros, avisa por
## señal a quien lo estuviera siguiendo (cámara, HUD) para que suelte la
## referencia con gracia, y recién ahí se destruye. Es seguro llamarlo más
## de una vez.
func eliminar() -> void:
	if _eliminado:
		return
	_eliminado = true
	eliminado.emit()
	queue_free()


## Intervalo mínimo entre pasajeros, aunque haya muchísima gente para
## procesar en poco tiempo (nunca "instantáneo", pero tampoco irreal).
const INTERVALO_PASAJEROS_MINIMO: float = 0.02

## Fracción del tiempo de parada que se le puede dedicar al intercambio de
## pasajeros (deja un colchón antes de la salida real).
const MARGEN_TIEMPO_PASAJEROS: float = 0.85


## Orquesta el intercambio de pasajeros al llegar a una parada: primero
## bajan (todos, si es terminal; un % sorteado según el sentido si no), y
## recién cuando termina de bajar toda esa gente, sube lo que entre según
## el lugar libre. El ritmo (`intervalo`) se ajusta solo según cuánta gente
## hay y cuánto tiempo de parada real hay disponible. Si el embarque no termina
## dentro de ese tiempo, `_procesando_pasajeros` mantiene la formación detenida
## hasta vaciar su fila o completar la capacidad del tren.
## `estacion` se pasa como Node genérico a propósito: no depende de que la
## clase Estacion esté disponible en esta rama, solo de que tenga los
## métodos `embarcar_pasajeros`/`desembarcar_pasajeros` (acordado con el
## equipo, ver Trello).
func _intercambio_habilitado() -> bool:
	while _estado_operacion == EstadoOperacion.DETENIDO_POR_EVENTO and not _eliminado:
		await get_tree().process_frame
	return not _eliminado and not _ruta_invalida and not _servicio_finalizado


func _viaja_hacia_constitucion() -> bool:
	# El servicio ordena Constitución -> Bosques; la curva puede cambiar su sentido.
	return _direccion_servicio < 0 if _usa_servicio() else invertir_sentido


func _resolver_anden_embarque(estacion: Node) -> String:
	if estacion == null or not is_instance_valid(estacion) or not estacion.has_method("resolver_anden_pasajeros"):
		return ""
	# El nodo raíz no sigue a los coches: usar la posición actual sobre la vía.
	var punto_via: Vector3 = global_position
	if traza != null and is_instance_valid(traza) and traza.curve != null:
		punto_via = traza.to_global(traza.curve.sample_baked(_avance, true))
	var sentido_ida: bool = not _viaja_hacia_constitucion()
	return str(estacion.call("resolver_anden_pasajeros", punto_via, sentido_ida))


func _embarcar_pasajeros_del_anden(estacion: Node, cantidad: int, id_anden: String) -> int:
	if estacion.has_method("resolver_anden_pasajeros"):
		return maxi(0, int(estacion.call("embarcar_pasajeros", cantidad, id_anden, _viaja_hacia_constitucion())))
	return maxi(0, int(estacion.call("embarcar_pasajeros", cantidad)))


func _procesar_pasajeros_parada(estacion: Node, es_terminal_actual: bool, direccion: float, tiempo_disponible: float) -> void:
	if estacion == null or not is_instance_valid(estacion):
		return

	_procesando_pasajeros = true
	_ultimo_suben = 0
	_ultimo_bajan = 0
	pasajeros_cambiados.emit(pasajeros_actuales, capacidad_pasajeros, 0, 0, true)

	var id_anden: String = _resolver_anden_embarque(estacion)
	var bajan: int = pasajeros_actuales if es_terminal_actual else _calcular_bajan(estacion, direccion)
	var lugar_estimado: int = maxi(0, capacidad_pasajeros - (pasajeros_actuales - bajan))
	var cantidad_por_tanda: int = maxi(1, cantidad_pasajeros_por_tanda)
	var tandas_bajada_estimadas: int = ceili(float(bajan) / float(cantidad_por_tanda))
	var tandas_subida_estimadas: int = ceili(float(lugar_estimado) / float(cantidad_por_tanda))
	var intervalo: float = _calcular_intervalo_pasajeros(tandas_bajada_estimadas + tandas_subida_estimadas, tiempo_disponible)

	if bajan > 0:
		await bajar_pasajeros_escalonado(bajan, estacion, intervalo)

	if _eliminado or _ruta_invalida or not is_instance_valid(self):
		return
	if es_terminal_actual:
		# En Bosques todos descienden y el tren no vuelve a captar pasajeros
		# durante los segundos restantes de la parada terminal.
		_procesando_pasajeros = false
		pasajeros_cambiados.emit(pasajeros_actuales, capacidad_pasajeros, _ultimo_suben, _ultimo_bajan, false)
		return

	await _embarcar_mientras_en_parada(estacion, intervalo, id_anden)

	_procesando_pasajeros = false
	pasajeros_cambiados.emit(pasajeros_actuales, capacidad_pasajeros, _ultimo_suben, _ultimo_bajan, false)


## Embarca la fila del andén y destino correspondiente hasta completar el tren.
## Durante la espera nominal también recoge nuevos pasajeros; al vencerla,
## termina de embarcar la fila pendiente antes de permitir la salida.
func _embarcar_mientras_en_parada(estacion: Node, intervalo: float, id_anden: String = "") -> void:
	if estacion == null or not is_instance_valid(estacion):
		return
	if not estacion.has_method("embarcar_pasajeros"):
		return

	if id_anden.is_empty():
		id_anden = _resolver_anden_embarque(estacion)
	var intervalo_seguro: float = maxf(intervalo, INTERVALO_PASAJEROS_MINIMO)
	var abordaje_informado: bool = false
	while true:
		if not (await _intercambio_habilitado()):
			break
		if _eliminado or not is_instance_valid(self):
			break
		if not is_instance_valid(estacion):
			break

		var lugar_disponible: int = maxi(0, capacidad_pasajeros - pasajeros_actuales)
		if lugar_disponible <= 0:
			break

		var cantidad_tanda: int = mini(lugar_disponible, maxi(1, cantidad_pasajeros_por_tanda))
		var suben: int = mini(cantidad_tanda, _embarcar_pasajeros_del_anden(estacion, cantidad_tanda, id_anden))
		if suben > 0:
			pasajeros_actuales += mini(suben, lugar_disponible)
			_ultimo_suben += suben
			pasajeros_cambiados.emit(pasajeros_actuales, capacidad_pasajeros, _ultimo_suben, _ultimo_bajan, true)
			if not abordaje_informado:
				if estacion.has_method("registrar_abordaje_tren"):
					estacion.call("registrar_abordaje_tren", get_instance_id(), true)
				abordaje_informado = true

		if suben <= 0 and _espera <= 0.0:
			break
		var tiempo_entre_intentos: float = intervalo_seguro
		if suben <= 0:
			tiempo_entre_intentos = maxf(intervalo_seguro, 0.15)
		var demora: float = minf(tiempo_entre_intentos, _espera) if _espera > 0.0 else tiempo_entre_intentos
		await get_tree().create_timer(demora).timeout
	if abordaje_informado and is_instance_valid(estacion):
		if estacion.has_method("registrar_abordaje_tren"):
			estacion.call("registrar_abordaje_tren", get_instance_id(), false)


## Calcula el intervalo entre tandas para que todo el intercambio entre
## cómodo dentro del tiempo de parada, en vez de estirarlo: con poca gente
## se acerca al ritmo "ideal" (`intervalo_pasajeros`), con mucha gente se
## acelera para no atrasar al tren.
func _calcular_intervalo_pasajeros(total_pasos: int, tiempo_disponible: float) -> float:
	if total_pasos <= 0:
		return intervalo_pasajeros
	var margen: float = maxf(0.0, tiempo_disponible) * MARGEN_TIEMPO_PASAJEROS
	var intervalo_ajustado: float = margen / float(total_pasos)
	return clampf(intervalo_ajustado, INTERVALO_PASAJEROS_MINIMO, intervalo_pasajeros)


## Usa el promedio por destino cuando la estación tiene un perfil de demanda.
## Sin perfil, sortea el porcentaje de pasajeros que baja según el sentido y un factor
## propio de la estación (`factor_bajada`, ej. para nodos de combinación
## con otras líneas como Lanús o Temperley). Duck-typed: si la estación no
## tiene `factor_bajada`, usa 1.0 sin romper nada.
func _calcular_bajan(estacion: Node, direccion: float) -> int:
	if estacion.has_method("calcular_bajada_pasajeros"):
		var objetivo: int = int(estacion.call("calcular_bajada_pasajeros", _viaja_hacia_constitucion()))
		if objetivo >= 0:
			return mini(pasajeros_actuales, objetivo)
	var minimo: float = porcentaje_bajada_inverso_min if direccion < 0.0 else porcentaje_bajada_directo_min
	var maximo: float = porcentaje_bajada_inverso_max if direccion < 0.0 else porcentaje_bajada_directo_max
	var porcentaje: float = randf_range(minimo, maximo)
	if "factor_bajada" in estacion:
		porcentaje *= float(estacion.get("factor_bajada"))
	porcentaje = clampf(porcentaje, 0.0, 1.0)
	return roundi(pasajeros_actuales * porcentaje)


## Baja `cantidad` pasajeros en tandas de tamaño configurable, separadas por
## `intervalo` segundos, actualizando la estación en cada tanda.
func bajar_pasajeros_escalonado(cantidad: int, estacion: Node, intervalo: float = 0.15) -> void:
	if cantidad <= 0 or estacion == null or not is_instance_valid(estacion):
		return
	if not estacion.has_method("desembarcar_pasajeros"):
		return

	var restante: int = mini(cantidad, pasajeros_actuales)
	var maximo_por_tanda: int = maxi(1, cantidad_pasajeros_por_tanda)
	while restante > 0:
		if not (await _intercambio_habilitado()):
			return
		if _eliminado or not is_instance_valid(self):
			return
		if not is_instance_valid(estacion):
			return
		var cantidad_tanda: int = mini(restante, maximo_por_tanda)
		var bajan: int = mini(cantidad_tanda, maxi(0, int(estacion.call("desembarcar_pasajeros", cantidad_tanda))))
		if bajan <= 0:
			return
		pasajeros_actuales -= bajan
		_ultimo_bajan += bajan
		pasajeros_cambiados.emit(pasajeros_actuales, capacidad_pasajeros, _ultimo_suben, _ultimo_bajan, true)
		restante -= bajan
		if restante > 0 and intervalo > 0.0:
			await get_tree().create_timer(intervalo).timeout


## Sube hasta `cantidad` pasajeros en tandas de tamaño configurable (limitado
## por la capacidad libre y por cuánta gente le entregue la estación), separadas
## por `intervalo` segundos. Fire-and-forget: no hace falta esperarla.
func subir_pasajeros_escalonado(cantidad: int, estacion: Node, intervalo: float = 0.15, id_anden: String = "") -> void:
	if cantidad <= 0 or estacion == null or not is_instance_valid(estacion):
		return
	if not estacion.has_method("embarcar_pasajeros"):
		return

	if id_anden.is_empty():
		id_anden = _resolver_anden_embarque(estacion)
	var lugar_disponible: int = maxi(0, capacidad_pasajeros - pasajeros_actuales)
	var restante: int = mini(cantidad, lugar_disponible)
	var maximo_por_tanda: int = maxi(1, cantidad_pasajeros_por_tanda)
	while restante > 0:
		if not (await _intercambio_habilitado()):
			return
		if _eliminado or not is_instance_valid(self):
			return
		if not is_instance_valid(estacion):
			return
		lugar_disponible = maxi(0, capacidad_pasajeros - pasajeros_actuales)
		var cantidad_tanda: int = mini(restante, mini(lugar_disponible, maximo_por_tanda))
		if cantidad_tanda <= 0:
			return
		var suben: int = mini(cantidad_tanda, _embarcar_pasajeros_del_anden(estacion, cantidad_tanda, id_anden))
		if suben <= 0:
			return
		pasajeros_actuales += suben
		restante -= suben
		if restante > 0 and intervalo > 0.0:
			await get_tree().create_timer(intervalo).timeout
