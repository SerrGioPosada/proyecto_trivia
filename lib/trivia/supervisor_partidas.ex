defmodule Trivia.SupervisorPartidas do
  use DynamicSupervisor

  @doc """
  Inicia el supervisor dinámico de partidas.
  """
  def start_link(opciones) do
    DynamicSupervisor.start_link(__MODULE__, opciones, name: __MODULE__)
  end

  @impl true
  def init(_opciones) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Inicia un nuevo proceso de partida.
  """
  def iniciar_partida(opciones) do
    DynamicSupervisor.start_child(__MODULE__, {Trivia.Partida, opciones})
  end

  @doc """
  Termina un proceso de partida.
  """
  def terminar_partida(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
