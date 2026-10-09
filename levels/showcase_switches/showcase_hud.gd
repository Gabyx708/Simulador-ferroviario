class_name ShowcaseHUD
extends Control
## Panel de Control y HUD interactivo para el laboratorio de los 3 tipos de desvíos.
## Ofrece interfaz visual con indicadores de estado en tiempo real,
## botones de conmutación directa, lanzamiento de trenes y atajos de teclado.

signal conmutar_solicitado(tipo: String)
signal lanzar_tren_solicitado(tipo: String)
signal vista_solicitada(clave: String)

# Referencias a elementos de UI
var _lbl_estado_a: Label = null
var _lbl_estado_b: Label = null
var _lbl_estado_c: Label = null
var _lbl_estado_d: Label = null
var _lbl_estado_e: Label = null


func _ready() -> void:
	_construir_ui()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	match event.keycode:
		KEY_1:
			conmutar_solicitado.emit("tipo_a")
		KEY_2:
			conmutar_solicitado.emit("tipo_b")
		KEY_3:
			conmutar_solicitado.emit("tipo_c")
		KEY_4:
			conmutar_solicitado.emit("tipo_d")
		KEY_5:
			conmutar_solicitado.emit("tipo_e")
		KEY_F1:
			vista_solicitada.emit("tipo_a")
		KEY_F2:
			vista_solicitada.emit("tipo_b")
		KEY_F3:
			vista_solicitada.emit("tipo_c")
		KEY_F4:
			vista_solicitada.emit("tipo_d")
		KEY_F5:
			vista_solicitada.emit("tipo_e")
		KEY_F6:
			vista_solicitada.emit("general")
		KEY_T:
			lanzar_tren_solicitado.emit("todos")


## Actualiza el estado visual del indicador del desvío Tipo A.
func actualizar_estado_a(es_desviada: bool) -> void:
	if _lbl_estado_a == null:
		return
	if es_desviada:
		_lbl_estado_a.text = "DESVIADA (Curva)"
		_lbl_estado_a.modulate = Color(1.0, 0.65, 0.1) # Naranja
	else:
		_lbl_estado_a.text = "DIRECTA (Recta)"
		_lbl_estado_a.modulate = Color(0.2, 0.95, 0.3) # Verde


## Actualiza el estado visual del indicador del desvío Tipo B.
func actualizar_estado_b(es_derecha: bool) -> void:
	if _lbl_estado_b == null:
		return
	if es_derecha:
		_lbl_estado_b.text = "RAMA DERECHA"
		_lbl_estado_b.modulate = Color(1.0, 0.65, 0.1) # Naranja
	else:
		_lbl_estado_b.text = "RAMA IZQUIERDA"
		_lbl_estado_b.modulate = Color(0.2, 0.95, 0.3) # Verde


## Actualiza el estado visual del indicador del desvío Tipo C.
func actualizar_estado_c(es_via_b: bool) -> void:
	if _lbl_estado_c == null:
		return
	if es_via_b:
		_lbl_estado_c.text = "VÍA B (Activa)"
		_lbl_estado_c.modulate = Color(1.0, 0.65, 0.1) # Naranja
	else:
		_lbl_estado_c.text = "VÍA A (Activa)"
		_lbl_estado_c.modulate = Color(0.2, 0.95, 0.3) # Verde


## Actualiza el estado visual del indicador del desvío Tipo D.
func actualizar_estado_d(es_cruzada: bool) -> void:
	if _lbl_estado_d == null:
		return
	if es_cruzada:
		_lbl_estado_d.text = "CRUZADA (Enlace en H)"
		_lbl_estado_d.modulate = Color(1.0, 0.65, 0.1) # Naranja
	else:
		_lbl_estado_d.text = "DIRECTA (Paralelas)"
		_lbl_estado_d.modulate = Color(0.2, 0.95, 0.3) # Verde


## Actualiza el estado visual del indicador del escape doble en X / bretelle (Tipo E).
func actualizar_estado_e(modo: int) -> void:
	if _lbl_estado_e == null:
		return
	match modo:
		0:
			_lbl_estado_e.text = "PARALELAS (Directas)"
			_lbl_estado_e.modulate = Color(0.2, 0.95, 0.3) # Verde
		1:
			_lbl_estado_e.text = "CRUCE 1 ➔ 2 (Diag. A)"
			_lbl_estado_e.modulate = Color(1.0, 0.65, 0.1) # Naranja
		2:
			_lbl_estado_e.text = "CRUCE 2 ➔ 1 (Diag. B)"
			_lbl_estado_e.modulate = Color(0.2, 0.85, 1.0) # Celeste


func _construir_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 1. Barra Superior con Título y Vistas Rápidas
	var panel_top: PanelContainer = PanelContainer.new()
	panel_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel_top.offset_left = 20.0
	panel_top.offset_top = 15.0
	panel_top.offset_right = -20.0
	panel_top.offset_bottom = 75.0
	var style_top: StyleBoxFlat = StyleBoxFlat.new()
	style_top.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	style_top.set_corner_radius_all(10)
	style_top.content_margin_left = 18.0
	style_top.content_margin_right = 18.0
	style_top.content_margin_top = 10.0
	style_top.content_margin_bottom = 10.0
	panel_top.add_theme_stylebox_override("panel", style_top)
	add_child(panel_top)

	var hbox_top: HBoxContainer = HBoxContainer.new()
	hbox_top.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel_top.add_child(hbox_top)

	var vbox_titulos: VBoxContainer = VBoxContainer.new()
	vbox_titulos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_top.add_child(vbox_titulos)

	var lbl_titulo: Label = Label.new()
	lbl_titulo.text = "🚄 LABORATORIO DE APARATOS DE VÍA — 5 TIPOS BÁSICOS"
	lbl_titulo.add_theme_font_size_override("font_size", 16)
	lbl_titulo.modulate = Color(0.95, 0.95, 1.0)
	vbox_titulos.add_child(lbl_titulo)

	var lbl_sub: Label = Label.new()
	lbl_sub.text = "Espadines cónicos flexibles • Corazón en V mecanizado • Cruce Diamante en X • Escape en H • Bretelle Doble en X"
	lbl_sub.add_theme_font_size_override("font_size", 11)
	lbl_sub.modulate = Color(0.7, 0.75, 0.85)
	vbox_titulos.add_child(lbl_sub)

	# Botones de Cámara Superior
	var hbox_camaras: HBoxContainer = HBoxContainer.new()
	hbox_camaras.add_theme_constant_override("separation", 6)
	hbox_top.add_child(hbox_camaras)

	_crear_boton_camara(hbox_camaras, "Vista General [F6]", "general")
	_crear_boton_camara(hbox_camaras, "Tipo A [F1]", "tipo_a")
	_crear_boton_camara(hbox_camaras, "Tipo B [F2]", "tipo_b")
	_crear_boton_camara(hbox_camaras, "Tipo C [F3]", "tipo_c")
	_crear_boton_camara(hbox_camaras, "Tipo D [F4]", "tipo_d")
	_crear_boton_camara(hbox_camaras, "Tipo E [F5]", "tipo_e")

	# 2. Panel Inferior con las 5 Tarjetas de Control
	var panel_bottom: PanelContainer = PanelContainer.new()
	panel_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel_bottom.offset_left = 15.0
	panel_bottom.offset_top = -165.0
	panel_bottom.offset_right = -15.0
	panel_bottom.offset_bottom = -15.0
	var style_bottom: StyleBoxFlat = StyleBoxFlat.new()
	style_bottom.bg_color = Color(0.05, 0.07, 0.10, 0.90)
	style_bottom.set_corner_radius_all(10)
	style_bottom.content_margin_left = 12.0
	style_bottom.content_margin_right = 12.0
	style_bottom.content_margin_top = 8.0
	style_bottom.content_margin_bottom = 8.0
	panel_bottom.add_theme_stylebox_override("panel", style_bottom)
	add_child(panel_bottom)

	var hbox_tarjetas: HBoxContainer = HBoxContainer.new()
	hbox_tarjetas.add_theme_constant_override("separation", 8)
	panel_bottom.add_child(hbox_tarjetas)

	# Tarjeta Bahía 1 (Tipo A)
	_lbl_estado_a = _crear_tarjeta_desvio(
		hbox_tarjetas,
		"BAHÍA 1: DESVÍO ESTÁNDAR (TIPO A)",
		"Recta + Curva Asimétrica",
		"tipo_a",
		"Tecla [1]"
	)
	actualizar_estado_a(false)

	# Tarjeta Bahía 2 (Tipo B)
	_lbl_estado_b = _crear_tarjeta_desvio(
		hbox_tarjetas,
		"BAHÍA 2: DESVÍO SIMÉTRICO EN Y (TIPO B)",
		"Bifurcación Equilátera (+/- θ/2)",
		"tipo_b",
		"Tecla [2]"
	)
	actualizar_estado_b(false)

	# Tarjeta Bahía 3 (Tipo C)
	_lbl_estado_c = _crear_tarjeta_desvio(
		hbox_tarjetas,
		"BAHÍA 3: DIAMOND CROSSING (TIPO C)",
		"Cruce de Vías en X a Nivel (15°)",
		"tipo_c",
		"Tecla [3]"
	)
	actualizar_estado_c(false)

	# Tarjeta Bahía 4 (Tipo D)
	_lbl_estado_d = _crear_tarjeta_desvio(
		hbox_tarjetas,
		"BAHÍA 4: ESCAPE EN H (TIPO D)",
		"Crossover entre 2 Vías Paralelas",
		"tipo_d",
		"Tecla [4]"
	)
	actualizar_estado_d(false)

	# Tarjeta Bahía 5 (Tipo E)
	_lbl_estado_e = _crear_tarjeta_desvio(
		hbox_tarjetas,
		"BAHÍA 5: ESCAPE EN X (TIPO E)",
		"Bretelle con Cruce Diamante",
		"tipo_e",
		"Tecla [5]"
	)
	actualizar_estado_e(0)


func _crear_tarjeta_desvio(padre: HBoxContainer, titulo: String, subtitulo: String, clave: String, atajo: String) -> Label:
	var panel_card: PanelContainer = PanelContainer.new()
	panel_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style_card: StyleBoxFlat = StyleBoxFlat.new()
	style_card.bg_color = Color(0.10, 0.12, 0.16, 0.90)
	style_card.border_width_left = 2
	style_card.border_color = Color(0.25, 0.45, 0.75, 0.8)
	style_card.set_corner_radius_all(6)
	style_card.content_margin_left = 8.0
	style_card.content_margin_right = 8.0
	style_card.content_margin_top = 7.0
	style_card.content_margin_bottom = 7.0
	panel_card.add_theme_stylebox_override("panel", style_card)
	padre.add_child(panel_card)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel_card.add_child(vbox)

	var lbl_t: Label = Label.new()
	lbl_t.text = titulo
	lbl_t.add_theme_font_size_override("font_size", 11)
	lbl_t.modulate = Color(0.9, 0.95, 1.0)
	lbl_t.clip_text = true
	vbox.add_child(lbl_t)

	var lbl_sub: Label = Label.new()
	lbl_sub.text = subtitulo
	lbl_sub.add_theme_font_size_override("font_size", 9)
	lbl_sub.modulate = Color(0.6, 0.65, 0.75)
	lbl_sub.clip_text = true
	vbox.add_child(lbl_sub)

	# Fila de Estado
	var hbox_st: HBoxContainer = HBoxContainer.new()
	vbox.add_child(hbox_st)

	var lbl_tag: Label = Label.new()
	lbl_tag.text = "Estado: "
	lbl_tag.add_theme_font_size_override("font_size", 10)
	hbox_st.add_child(lbl_tag)

	var lbl_val: Label = Label.new()
	lbl_val.text = "DIRECTA"
	lbl_val.add_theme_font_size_override("font_size", 10)
	hbox_st.add_child(lbl_val)

	# Fila de Botones
	var hbox_btns: HBoxContainer = HBoxContainer.new()
	hbox_btns.add_theme_constant_override("separation", 4)
	vbox.add_child(hbox_btns)

	var btn_conmutar: Button = Button.new()
	btn_conmutar.text = "Conmutar (%s)" % atajo
	btn_conmutar.add_theme_font_size_override("font_size", 10)
	btn_conmutar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_conmutar.pressed.connect(func() -> void: conmutar_solicitado.emit(clave))
	hbox_btns.add_child(btn_conmutar)

	var btn_tren: Button = Button.new()
	btn_tren.text = "▶ Tren"
	btn_tren.add_theme_font_size_override("font_size", 10)
	btn_tren.pressed.connect(func() -> void: lanzar_tren_solicitado.emit(clave))
	hbox_btns.add_child(btn_tren)

	return lbl_val


func _crear_boton_camara(padre: HBoxContainer, texto: String, clave: String) -> void:
	var btn: Button = Button.new()
	btn.text = texto
	btn.pressed.connect(func() -> void: vista_solicitada.emit(clave))
	padre.add_child(btn)
