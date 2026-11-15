Proyecto Final – Programación 3
Sistema de Trivia Distribuida concurrente y tolerante a fallos en Elixir:
- Servidor centralizado de gestión de partidas y banco de preguntas.
- Clientes concurrentes interactuando mediante nodos distribuidos (Erlang Distribution).
Integrantes:
             Jhonatan Perilla Betancur
             Sergio Posada Garcia
             Sara Benjumea Gallego
Repositorio: (https://github.com/SerrGioPosada/proyecto_trivia.git)
Requisitos
- Elixir instalado (se comprueba con elixir --version).
- Dependencias del proyecto configuradas (incluye la librería Jason para serialización JSON).
- Ejecución mediante terminales separadas para el nodo servidor y los nodos clientes utilizando nodos distribuidos con `iex --sname`.
Estructura del repositorio
proyecto_trivia/
├── README.md
├── mix.exs                   Configuración y dependencias
├── data/
│   ├── questions.json        Banco de preguntas de la trivia
│   ├── users.json            Almacenamiento persistente de usuarios y claves
│   └── results.log           Historial perezoso (Streams) de resultados
└── lib/
    ├── trivia.ex             Módulo principal de la aplicación
    ├── application.ex        Árbol de supervisión principal
    ├── servidor.ex           GenServer central del servidor
    ├── cliente.ex            Interfaz interactiva de comandos de usuario
    ├── gestor_jugadores.ex   Control de sesiones y autenticación
    ├── gestor_partidas.ex    Creación y administración de salas
    ├── supervisor_partidas.ex Supervisores dinámicos de partidas
    ├── banco_preguntas.ex    Gestión y filtrado de preguntas
    ├── bot.ex                Lógica de bots concurrentes
    ├── receptor.ex           Recepción de eventos asíncronos en el cliente
    ├── persistencia.ex       Lectura y escritura mediante JSON y Streams
    └── structs/
        ├── partida.ex        Struct %Partida{}
        ├── pregunta.ex       Struct %Pregunta{}
        └── usuario.ex        Struct %Usuario{}
Sistema de Trivia Distribuida
Permite conectar múltiples jugadores de forma concurrente desde diferentes terminales/nodos, crear partidas temáticas, añadir jugadores controlados por la IA (bots), competir en tiempo real respondiendo preguntas por rondas, y almacenar los resultados históricos en archivos persistentes.
Ejecución del Servidor
Pararse en la raíz del proyecto y arrancar el nodo del servidor:
mix clean
mix compile
iex --sname servidor -S mix
Ejecución del Cliente
Pararse en otra terminal limpia en la misma ruta y arrancar un nodo cliente (ej. pedro):
iex --sname pedro -S mix
Una vez dentro de la consola IEx del cliente, conectarse al servidor con:
Trivia.Cliente.iniciar_cliente(:"servidor@pop-os")
Archivos de Datos y Persistencia
ArchivoTipoContenidodata/questions.jsonentradabanco de preguntas estructurado en formato JSONdata/users.jsonentraday salidalistado de credenciales y usuarios registradosdata/results.logsalidahistorial plano de partidas y puntajes procesado mediante StreamsEl sistema inicializa automáticamente la carpeta `data/` y sus archivos base si no existen. Los nombres de usuario y las claves se validan contra el almacenamiento persistente.
Cómo está resuelto
1. Arquitectura Distribuida y GenServers. El servidor central corre sobre un nodo (`servidor@pop-os`) y levanta un árbol de supervisión con procesos dedicados (`Trivia.GestorJugadores`, `Trivia.GestorPartidas`, `Trivia.BancoPreguntas`) que atienden solicitudes concurrentes de múltiples nodos clientes.
2. Interfaz de Comandos Interactiva (REPL). El cliente implementa un bucle de comandos (`Comando >`) donde el usuario interactúa mediante comandos de texto plano (`connect`, `create_game`, `add_bot`, `start_game`, `answer`).
3. Gestión de Sesiones. `Trivia.GestorJugadores` valida el registro y el inicio de sesión de los usuarios contra el archivo `data/users.json` decodificado y codificado de forma segura mediante la librería `Jason`.
4. Concurrencia y Bots. Cada partida en curso opera de forma concurrente, permitiendo agregar jugadores automáticos (`Trivia.Bot`) de diferentes niveles de dificultad que responden de forma autónoma a las preguntas de la ronda.
5. Procesamiento con Streams. El historial de puntajes e indicadores se maneja utilizando flujos perezosos (`Stream`) sobre el archivo de texto plano `data/results.log`, optimizando el uso de memoria RAM.
Comandos disponibles en el cliente (`Comando >`)
- `connect <usuario> <clave>`: Inicia sesión o registra al usuario en el sistema.
- `create_game tema=<tema> preguntas=<n> tiempo=<seg>`: Crea una nueva sala de trivia.
- `add_bot <facil|dificil>`: Agrega un jugador artificial a la sala actual.
- `start_game`: Da inicio a la partida y despliega las preguntas de manera interactiva.
- `answer <opcion>`: Envía la respuesta seleccionada (ej. `answer A`) antes de que expire el tiempo de la ronda.
Ejemplo de ejecución de una partida
=== Pregunta 1 de 5 - ciencia - Nivel básico ===
¿Cuál es el símbolo químico del agua?
A. H2O
B. CO2
C. NaCl
D. O2
Tiempo: 15 segundos

Respuesta > answer A
Respuesta registrada.

--- Cierre de Ronda 1 ---
Respuesta correcta: A
bot_1      +10  (total 10)
pedro      +10  (total 10)
bot_2      +10  (total 10)
Informe
El documento técnico del proyecto, diagramas de arquitectura de procesos distribuidos y pruebas de validación concurrente se entregan por separado.