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
      _ ->
        {:reply, {:error, :peticion_desconocida}, estado}
    end
  end
end
