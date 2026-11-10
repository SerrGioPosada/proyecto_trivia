defmodule Trivia.GestorPartidas do
  use GenServer

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(estado_inicial) do
    {:ok, estado_inicial}
  end

  def handle_call(peticion, _desde, estado) do
    case peticion do
      # agregar operaciones
      {:crear_partida, usuario, tema, preguntas, tiempo} ->
        nivel = Trivia.Nivel.calcular_nivel(usuario, tema)
        id = generar_id()

        case Trivia.Structs.Partida.nuevo(id, usuario, tema, nivel, preguntas, tiempo) do
          {:ok, partida} ->
            nuevo_estado = Map.put(estado, id, partida)
            {:reply, {:ok, id, nivel}, nuevo_estado}

          {:error, razon} ->
            {:reply, {:error, razon}, estado}
            # se devuele el error
        end
    end
  end

  def generar_id(estado) do
    id = "P-#{:rand.uniform(999_999_999)}"

    if Map.has_key?(estado, id) do
      generar_id(estado)
    else
      id
    end
  end
end
