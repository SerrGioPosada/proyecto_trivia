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
      {:crear_partida, usuario, tema, preguntas, tiempo} ->
        tema = String.downcase(String.trim(tema))

        if usuario_en_partida?(estado, usuario) do
          {:reply, {:error, "ya esta en una partida"}, estado}
        else
          nivel =
            Trivia.Persistencia.stream_historial()
            |> Trivia.Nivel.calcular_nivel(usuario, tema)

          {n_bas, n_inter, n_av} =
            Trivia.BancoPreguntas.calcular_reparto(nivel, preguntas)

          requeridas_por_nivel = [
            basico: n_bas,
            intermedio: n_inter,
            avanzado: n_av
          ]

          id = generar_id(estado)

          with {:ok, :suficientes_preguntas} <-
                 Trivia.BancoPreguntas.validar_disponibilidad_tema(tema, requeridas_por_nivel),
               {:ok, partida} <-
                 Trivia.Structs.Partida.nuevo(id, usuario, tema, nivel, preguntas, tiempo) do
            {:reply, {:ok, id, nivel}, Map.put(estado, id, partida)}
          else
            {:error, razon} -> {:reply, {:error, razon}, estado}
          end
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

  def usuario_en_partida?(estado, usuario) do
    Enum.any?(estado, fn {_id, partida} ->
      usuario in partida.jugadores
    end)
  end
end
