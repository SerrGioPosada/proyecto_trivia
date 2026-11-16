defmodule Trivia.Servidor do
  use GenServer

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(estado_inicial) do
    Trivia.Persistencia.inicializar_almacenamiento()
    # Asegurar que GestorJugadores y GestorPartidas estén corriendo
    {:ok, estado_inicial}
  end

  def handle_call(peticion, _desde, estado) do
    case peticion do
      {:connect, usuario, clave, cliente_pid} ->
        respuesta = Trivia.GestorJugadores.conectar(usuario, clave, cliente_pid)
        {:reply, respuesta, estado}

      {:disconnect, usuario} ->
        # Sección 6.5: desconectarse con una partida abierta la termina.
        GenServer.call(Trivia.GestorPartidas, {:abandonar_usuario, usuario})
        respuesta = Trivia.GestorJugadores.desconectar(usuario)
        {:reply, respuesta, estado}

      {:score, usuario} ->
        respuesta = Trivia.GestorJugadores.consultar_score(usuario)
        {:reply, respuesta, estado}

      {:ranking, tema} ->
        respuesta = Trivia.GestorJugadores.consultar_ranking(tema)
        {:reply, respuesta, estado}

      {:crear_partida, usuario, tema, preguntas, tiempo, cliente_pid} ->
        respuesta =
          GenServer.call(
            Trivia.GestorPartidas,
            {:crear_partida, usuario, tema, preguntas, tiempo, cliente_pid}
          )

        {:reply, respuesta, estado}

      {:add_bot, id_partida, dificultad} ->
        respuesta = GenServer.call(Trivia.GestorPartidas, {:add_bot, id_partida, dificultad})
        {:reply, respuesta, estado}

      {:start_game, id_partida} ->
        respuesta = GenServer.call(Trivia.GestorPartidas, {:start_game, id_partida})
        {:reply, respuesta, estado}

      {:responder, id_partida, usuario, respuesta_letra} ->
        resultado =
          GenServer.call(
            Trivia.GestorPartidas,
            {:responder, id_partida, usuario, respuesta_letra}
          )

        {:reply, resultado, estado}

      {:leave_game, id_partida, usuario} ->
        respuesta = GenServer.call(Trivia.GestorPartidas, {:leave_game, id_partida, usuario})
        {:reply, respuesta, estado}

      _ ->
        {:reply, {:error, :peticion_desconocida}, estado}
    end
  end
end
