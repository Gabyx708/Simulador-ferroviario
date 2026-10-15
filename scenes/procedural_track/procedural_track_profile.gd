@tool
class_name ProceduralTrackProfile
extends RefCounted
## Define perfiles transversales geométricos y constantes normalizadas para
## la generación de infraestructura ferroviaria procedural basada en el estándar T:ANE.

# Trocha métrica estándar (Roca = 1.676m Trocha Ancha, Estándar UIC = 1.435m)
const TROCHA_ROCA: float = 1.676
const TROCHA_ESTANDAR: float = 1.435
const TROCHA_MEDIA_DEFECTO: float = TROCHA_ROCA * 0.5 # 0.838 m

# Luz reglamentaria de pestaña (Flangeway de seguridad en gargantas de desvíos y cruces)
const LUZ_PESTANA: float = 0.045 # 45 mm

# Separación longitudinal estándar entre ejes de durmientes
const PASO_DURMIENTES: float = 0.65 # 65 cm

# Dimensiones normalizadas de durmiente de vía plena (Largo, Alto, Ancho)
const TAMANO_DURMIENTE: Vector3 = Vector3(2.60, 0.20, 0.26)

## Perfil transversal estandarizado de riel Vignole (tipo 50 kg/m - UIC).
## Centrado en X=0, con la superficie de rodadura superior en Y=0.
## Dimensiones: Altura = 150mm, Hongo = 70mm, Alma = 24mm, Patín = 120mm.
const PERFIL_RIEL: Array[Vector2] = [
	Vector2(-0.035, 0.000),  # Hongo superior izquierdo
	Vector2(0.035, 0.000),   # Hongo superior derecho
	Vector2(0.035, -0.035),  # Hongo lateral inferior derecho
	Vector2(0.012, -0.050),  # Alma superior derecha
	Vector2(0.012, -0.125),  # Alma inferior derecha
	Vector2(0.060, -0.145),  # Patín extremo derecho
	Vector2(0.060, -0.150),  # Patín base derecha
	Vector2(-0.060, -0.150), # Patín base izquierda
	Vector2(-0.060, -0.145), # Patín extremo izquierdo
	Vector2(-0.012, -0.125), # Alma inferior izquierda
	Vector2(-0.012, -0.050), # Alma superior izquierda
	Vector2(-0.035, -0.035), # Hongo lateral inferior izquierdo
]

## Perfil transversal de la cama de balasto (piedra partida).
## Sección trapezoidal con taludes exteriores y coronamiento bajo los durmientes.
## Base superior a Y=-0.28m, base inferior a Y=-0.65m, ancho superior ~4.0m, ancho base ~5.4m.
const PERFIL_BALASTO: Array[Vector2] = [
	Vector2(-2.70, -0.65), # Base inferior izquierda
	Vector2(2.70, -0.65),  # Base inferior derecha
	Vector2(2.00, -0.28),  # Hombro superior derecho
	Vector2(-2.00, -0.28), # Hombro superior izquierdo
]

## Perfil simplificado para contrarrieles protectores elevados (Check Rails).
const PERFIL_CONTRARRIEL: Array[Vector2] = [
	Vector2(-0.015, 0.025),
	Vector2(0.015, 0.025),
	Vector2(0.015, -0.125),
	Vector2(-0.015, -0.125),
]


## Devuelve un material PBR predeterminado si no se especifica uno externo.
static func obtener_material_defecto(tipo: String) -> Material:
	match tipo:
		"riel":
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = Color(0.72, 0.73, 0.75)
			mat.metallic = 0.90
			mat.roughness = 0.30
			return mat
		"balasto":
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = Color(0.38, 0.37, 0.35)
			mat.roughness = 0.92
			return mat
		"durmiente":
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = Color(0.24, 0.17, 0.12)
			mat.roughness = 0.85
			return mat
		"metal_oscuro":
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = Color(0.22, 0.23, 0.25)
			mat.metallic = 0.85
			mat.roughness = 0.40
			return mat
		_:
			return StandardMaterial3D.new()
