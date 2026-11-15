
defmodule Trivia.SupervisorPartidas do
  use DynamicSupervisor

  @doc """
  Inicia el supervisor dinamico de partidas.
  """
  def start_link(opciones) do
    DynamicSupervisor.start_link(
      __MODULE__,
      opciones,
      name: __MODULE__
    )
  end

  @spec init(any()) ::
          {:ok,
           %{
             extra_arguments: list(),
             intensity: non_neg_integer(),
             max_children: :infinity | non_neg_integer(),
             period: pos_integer(),
             strategy: :one_for_one
           }}
  @doc """
  Inicializa la estrategia del supervisor.
  """
  def init(_opciones) do
    DynamicSupervisor.init(
      strategy: :one_for_one
    )
  end

  @doc """
  Inicia un nuevo proceso de partida.
  """
  def iniciar_partida(opciones) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Trivia.Partida, opciones}
    )
  end

  @doc """
  Termina un proceso de partida.
  """
  def terminar_partida(pid) do
    DynamicSupervisor.terminate_child(
      __MODULE__,
      pid
    )
  end

  @doc """
  Retorna los PID de las partidas activas.
  """
  def listar_partidas do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, pid, _tipo, _modulos} -> pid end)
  end

  @doc """
  Cuenta las partidas activas.
  """
  def cantidad_partidas do
  DynamicSupervisor.count_children(__MODULE__)
  |> Map.get(:active)
end
end
