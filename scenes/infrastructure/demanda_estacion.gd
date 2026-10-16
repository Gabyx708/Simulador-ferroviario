@tool
extends Resource
class_name DemandaEstacion
## Perfil de demanda de pasajeros por estacion.

@export_group("Ritmo de simulación")
## Referencia de 30 minutos: cuatro formaciones cubren un ciclo de unas dos horas.
@export_range(60.0, 86400.0, 1.0, "suffix:s") var intervalo_formaciones: float = 1800.0
@export_range(0.0, 1.0, 0.01) var variacion: float = 0.15
## Escala los perfiles históricos de cada estación a un flujo por formación.
@export_range(0.0, 2.0, 0.01) var factor_subida_normal: float = 0.55
@export_range(0.0, 2.0, 0.01) var factor_bajada_normal: float = 0.42

@export_group("Promedios por formación: a Constitución")
@export_range(0, 100000, 1) var suben_a_constitucion: int = 0
@export_range(0, 100000, 1) var bajan_a_constitucion: int = 0

@export_group("Promedios por formación: a Bosques")
@export_range(0, 100000, 1) var suben_a_bosques: int = 0
@export_range(0, 100000, 1) var bajan_a_bosques: int = 0

func promedio_subida(hacia_constitucion: bool) -> int:
	return suben_a_constitucion if hacia_constitucion else suben_a_bosques


## La demanda de mañana se concentra hacia Constitución; la de tarde, hacia
## Bosques. Fuera del horario diurno quedan sólo viajes ocasionales.
func factor_horario(hora: int, hacia_constitucion: bool) -> float:
	var hora_dia: int = posmod(hora, 24)
	if hora_dia < 5 or hora_dia >= 23:
		return 0.08
	if hora_dia >= 6 and hora_dia < 9:
		return 2.0 if hacia_constitucion else 0.7
	if hora_dia >= 17 and hora_dia < 20:
		return 0.7 if hacia_constitucion else 2.0
	if hora_dia < 6 or hora_dia >= 20:
		return 0.55
	return 1.0


## Los promedios de subida regulan las llegadas a la estación, no el embarque.
func sortear_generacion(hacia_constitucion: bool, hora: int = 12) -> int:
	var promedio: float = float(promedio_subida(hacia_constitucion)) * factor_subida_normal * factor_horario(hora, hacia_constitucion)
	return _sortear_promedio(roundi(promedio))


func sortear_bajada(hacia_constitucion: bool, hora: int = 12) -> int:
	var base: int = bajan_a_constitucion if hacia_constitucion else bajan_a_bosques
	var promedio: float = float(base) * factor_bajada_normal * factor_horario(hora, hacia_constitucion)
	return _sortear_promedio(roundi(promedio))


func _sortear_promedio(promedio: int) -> int:
	var margen: float = clampf(variacion, 0.0, 1.0)
	var minimo: int = maxi(0, ceili(float(promedio) * (1.0 - margen)))
	var maximo: int = maxi(minimo, floori(float(promedio) * (1.0 + margen)))
	return randi_range(minimo, maximo)
