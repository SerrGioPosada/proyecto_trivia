defmodule Trivia.Servidor do
  use GenServer

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(estado_inicial) do
    {:ok, estado_inicial}
  end

  def handle_call(peticion, _desde, estado) do
    case peticion do
      {:crear_partida, usuario, tema, preguntas, tiempo, cliente_pid} ->
        respuesta =
          GenServer.call(
            Trivia.GestorPartidas,
            {:crear_partida, usuario, tema, preguntas, tiempo, cliente_pid}
          )

        {:reply, respuesta, estado}

      _ ->
        {:reply, {:error, :peticion_desconocida}, estado}
    end
  end

  def crear_partida(usuario, tema, preguntas, tiempo, cliente_pid) do
    GenServer.call(
      __MODULE__,
      {:crear_partida, usuario, tema, preguntas, tiempo, cliente_pid}
    )
  end
end
