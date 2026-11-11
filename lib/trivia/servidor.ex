defmodule Trivia.Servidor do
  use GenServer

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(estado_inicial) do
    {:ok, estado_inicial}
  end

  def handle_call(peticion, _desde, estado) do
    ase peticion do
      {:crear_partida, usuario, tema, preguntas, tiempo} ->
        respuesta =
          GenServer.call(
            Trivia.GestorPartidas,
            {:crear_partida, usuario, tema, preguntas, tiempo}
          )

        {:reply, respuesta, estado}

      _ ->
        {:reply, {:error, :peticion_desconocida}, estado}
    end
  end

  def crear_partida(usuario, tema, preguntas, tiempo) do
    GenServer.call(
      __MODULE__,
      {:crear_partida, usuario, tema, preguntas, tiempo}
    )
  end
end
