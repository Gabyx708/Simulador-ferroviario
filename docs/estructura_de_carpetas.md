res://
├── assets/              # Archivos crudos (modelos, texturas, audios, fuentes etc etc)
├── common/              # Recursos y utilidades compartidas(materiales, shaders, codigo que no tiene logica de juego en si misma)
├── levels/              # Escenas de mapas y ensamblado de mundo
├── resources/           # Archivos de datos (warrior_stats.tres, item_data.res)
├── scenes/              # Entidades del juego (player.tcsn + .gd, enemy.tcsn + .gd, arma.tcsn + .gd etc)
├── systems/             # Lógica global y reglas de juego (combat_manager.gd, save_system.gd etc )
└── ui/                  # Interfaz de usuario y menús (main_menu.tscn, health_bar.tscn, pause_menu.gd)


Ejemplo:
res://
├── assets/
│   ├── audio/
│   │   ├── music/
│   │   └── sfx/
│   ├── models/
│   │   ├── environment/      # Rocas, árboles (archivos .glb)
│   │   └── characters/       # Mallas base sin scripts
│   └── textures/             # Texturas de ruido, gradientes, etc.
│
├── common/
│   ├── materials/
│   │   ├── m_metal_generic.tres
│   │   └── m_water_stylized.tres
│   ├── shaders/
│   │   └── outline_shader.gdshader
│   └── utils/
│       └── global_constants.gd
│
├── levels/
│   ├── level_01/
│   │   ├── level_01.tscn
│   │   └── level_01_environment.tres
│   └── main_menu_map.tscn
│
├── resources/
│   ├── item_data/            # Datos puros de objetos
│   │   ├── sword_iron.tres
│   │   └── potion_health.tres
│   └── player_stats/
│       └── default_stats.tres
│
├── scenes/
│   ├── player/
│   │   ├── player.tscn       # Escena principal
│   │   ├── player.gd         # Lógica de movimiento
│   │   └── camera_rig.tscn   # Sub-escena de cámara
│   ├── enemies/
│   │   └── slime/
│   │       ├── slime.tscn
│   │       └── slime.gd
│   └── interactables/
│       └── chest/
│           ├── chest.tscn
│           └── chest.gd
│
├── systems/
│   ├── combat/
│   │   └── damage_calculator.gd
│   ├── inventory/
│   │   └── inventory_manager.gd (AutoLoad)
│   └── save_system/
│       └── save_manager.gd
│
├── ui/
│   ├── components/           # Piezas pequeñas reusables
│   │   ├── health_bar.tscn
│   │   └── item_slot.tscn
│   └── screens/              # Menús completos
│       ├── hud.tscn
│       └── pause_menu.tscn
│
└── main.tscn                 # Escena inicial que lanza el juego
