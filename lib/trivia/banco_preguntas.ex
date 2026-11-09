defmodule Trivia.BancoPreguntas do
  alias Trivia.Persistencia
  alias Trivia.Structs.Pregunta

  @doc """
  Carga todas las preguntas del archivo JSON y las convierte en structs de Pregunta.
  """
  def cargar_banco do
    case Persistencia.leer_banco_preguntas() do
      {:ok, lista_mapas} ->
        preguntas =
          Enum.map(lista_mapas, fn m ->
            %Pregunta{
              tema: m["tema"],
              nivel: String.to_atom(m["nivel"]),
              enunciado: m["enunciado"],
              opciones: m["opciones"],
              respuesta: m["respuesta"]
            }
          end)

        {:ok, preguntas}

      {:error, razon} ->
        {:error, razon}
    end
  end

  @doc """
  Verifica si un tema existe y si cuenta con suficientes preguntas para los niveles requeridos.
  """
  def validar_disponibilidad_tema(tema, requeridas_por_nivel) do
    with {:ok, preguntas} <- cargar_banco() do
      preguntas_tema = Enum.filter(preguntas, &(&1.tema == tema))

      if Enum.empty?(preguntas_tema) do
        {:error, "El tema '#{tema}' no existe en el banco de preguntas"}
      else
        resultado_niveles =
          Enum.all?(requeridas_por_nivel, fn {nivel, cantidad} ->
            disponibles = Enum.count(preguntas_tema, &(&1.nivel == nivel))
            disponibles >= cantidad
          end)

        if resultado_niveles do
          {:ok, :suficientes_preguntas}
        else
          {:error, "El tema no tiene suficientes preguntas de algún nivel para cubrir el sorteo"}
        end
      end
    end
  end

  @doc """
  Sortea las preguntas para una partida según el reparto porcentual,
  ordenándolas de menor a mayor nivel (básico -> intermedio -> avanzado).
  """
  def sortear_preguntas(tema, nivel_jugador, total_preguntas) do
    {n_basico, n_intermedio, n_avanzado} = calcular_reparto(nivel_jugador, total_preguntas)

    with {:ok, banco} <- cargar_banco() do
      filtradas = Enum.filter(banco, &(&1.tema == tema))

      basicas =
        filtradas |> Enum.filter(&(&1.nivel == :basico)) |> Enum.shuffle() |> Enum.take(n_basico)

      intermedias =
        filtradas
        |> Enum.filter(&(&1.nivel == :intermedio))
        |> Enum.shuffle()
        |> Enum.take(n_intermedio)

      avanzadas =
        filtradas
        |> Enum.filter(&(&1.nivel == :avanzado))
        |> Enum.shuffle()
        |> Enum.take(n_avanzado)

      preguntas_sorteadas = basicas ++ intermedias ++ avanzadas
      {:ok, preguntas_sorteadas}
    end
  end

  # FUNCIONES AUXILIARES DE REPARTO

  defp calcular_reparto(:basico, total) do
    n_inter = trunc(total * 30 / 100)
    n_av = 0
    n_bas = total - (n_inter + n_av)
    {n_bas, n_inter, n_av}
  end

  defp calcular_reparto(:intermedio, total) do
    n_bas = trunc(total * 20 / 100)
    n_av = trunc(total * 20 / 100)
    n_int = total - (n_bas + n_av)
    {n_bas, n_int, n_av}
  end

  defp calcular_reparto(:avanzado, total) do
    n_bas = 0
    n_inter = trunc(total * 30 / 100)
    n_av = total - (n_bas + n_inter)
    {n_bas, n_inter, n_av}
  end
end
