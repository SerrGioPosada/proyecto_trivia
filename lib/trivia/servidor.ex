defmodule Trivia.Servidor do
  use GenServer

  alias Trivia.{GestorJugadores, GestorPartidas}

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(estado_inicial) do
    {:ok, estado_inicial}
  end

  # JUGADORES

  def handle_call({:connect, usuario, clave, cliente_pid}, _desde, estado) do
    {:reply, GestorJugadores.conectar(usuario, clave, cliente_pid), estado}
  end

  def handle_call({:disconnect, usuario}, _desde, estado) do
    {:reply, GestorJugadores.desconectar(usuario), estado}
  end

  def handle_call({:score, usuario}, _desde, estado) do
    {:reply, GestorJugadores.consultar_score(usuario), estado}
  end

  def handle_call({:ranking, tema}, _desde, estado) do
    {:reply, GestorJugadores.consultar_ranking(tema), estado}
  end

  # PARTIDAS

  def handle_call({:crear_partida, usuario, tema, preguntas, tiempo, cliente_pid}, _desde, estado) do
    respuesta = GestorPartidas.crear_partida(usuario, tema, preguntas, tiempo, cliente_pid)
    {:reply, respuesta, estado}
  end

  def handle_call({:add_bot, id_partida, dificultad}, _desde, estado) do
    {:reply, GestorPartidas.agregar_bot(id_partida, dificultad), estado}
  end

  def handle_call({:start_game, id_partida}, _desde, estado) do
    {:reply, GestorPartidas.iniciar_partida(id_partida), estado}
  end

  def handle_call({:responder, id_partida, usuario, letra}, _desde, estado) do
    {:reply, GestorPartidas.responder(id_partida, usuario, letra), estado}
  end

  def handle_call({:leave_game, id_partida, usuario}, _desde, estado) do
    {:reply, GestorPartidas.abandonar_partida(id_partida, usuario), estado}
  end

  def handle_call(_peticion, _desde, estado) do
    {:reply, {:error, :peticion_desconocida}, estado}
  end
end
