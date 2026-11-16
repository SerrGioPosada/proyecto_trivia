defmodule Trivia.Bot do
  use GenServer

  @prefijo "bot_"

  # IDENTIDAD DE LOS BOTS (única fuente de verdad del prefijo reservado)

  @doc "Indica si un nombre de jugador corresponde a un bot."
  def es_bot?(nombre) when is_binary(nombre), do: String.starts_with?(nombre, @prefijo)
  def es_bot?(_), do: false

  @doc "Nombre del bot número `numero` (bot_1, bot_2, ...)."
  def nombre(numero) when is_integer(numero), do: @prefijo <> Integer.to_string(numero)

  @doc "Convierte la dificultad escrita por el usuario a atom, solo si es válida."
  def parsear_dificultad("facil"), do: {:ok, :facil}
  def parsear_dificultad("dificil"), do: {:ok, :dificil}
  def parsear_dificultad(_), do: {:error, "Dificultad inválida. Usa 'facil' o 'dificil'"}

  # INICIO DEL PROCESO

  @doc "Inicia el bot enlazado al proceso que lo llama."
  def start_link(opciones) do
    GenServer.start_link(__MODULE__, opciones)
  end

  @doc """
  Inicia el bot SIN enlazarlo al llamador. Lo usa GestorPartidas para que un
  fallo del bot no tumbe al gestor; el enlace real lo hace la Partida al
  registrarlo con `Partida.agregar_bot/3`.
  """
  def iniciar(opciones) do
    GenServer.start(__MODULE__, opciones)
  end

  def init(opciones) do
    nombre = Keyword.fetch!(opciones, :nombre)
    dificultad = Keyword.fetch!(opciones, :dificultad)
    partida_pid = Keyword.fetch!(opciones, :partida_pid)

    # Si la partida termina (por cualquier motivo) el bot se detiene solo
    Process.monitor(partida_pid)

    {:ok, %{nombre: nombre, dificultad: dificultad, partida_pid: partida_pid}}
  end

  def handle_info({:pregunta_bot, id_partida, pregunta, respuesta_correcta}, estado) do
    {letra_respuesta, delay_ms} =
      decidir_respuesta(pregunta, respuesta_correcta, estado.dificultad)

    Process.send_after(self(), {:enviar_respuesta, id_partida, letra_respuesta}, delay_ms)

    {:noreply, estado}
  end

  def handle_info({:enviar_respuesta, _id_partida, letra}, estado) do
    try do
      Trivia.Partida.responder(estado.partida_pid, estado.nombre, letra)
    catch
      # La partida pudo terminar justo antes de que el bot respondiera
      :exit, _ -> :ok
    end

    {:noreply, estado}
  end

  def handle_info({:DOWN, _ref, :process, pid, _razon}, %{partida_pid: pid} = estado) do
    {:stop, :normal, estado}
  end

  def handle_info(_msg, estado), do: {:noreply, estado}

  # LÓGICA DE DECISIÓN DEL BOT (Prueba ExUnit 6)
  def decidir_respuesta(pregunta, respuesta_correcta, dificultad) do
    acierta = calcular_acierto(pregunta.nivel, dificultad)
    tiempo_total_ms = pregunta.tiempo * 1000

    letra =
      if acierta do
        respuesta_correcta
      else
        # Escoger al azar una de las 3 opciones incorrectas
        ["A", "B", "C", "D"]
        |> List.delete(respuesta_correcta)
        |> Enum.random()
      end

    delay_ms = calcular_delay(dificultad, tiempo_total_ms)

    {letra, delay_ms}
  end

  defp calcular_acierto(nivel, :facil) do
    case nivel do
      :basico -> :rand.uniform(100) <= 40
      :intermedio -> :rand.uniform(100) <= 30
      :avanzado -> :rand.uniform(100) <= 20
    end
  end

  defp calcular_acierto(nivel, :dificil) do
    case nivel do
      :basico -> :rand.uniform(100) <= 80
      :intermedio -> :rand.uniform(100) <= 70
      :avanzado -> :rand.uniform(100) <= 60
    end
  end

  defp calcular_delay(:facil, tiempo_total_ms) do
    # Facil: entre el 40% y el 90% del tiempo
    min_ms = trunc(tiempo_total_ms * 0.4)
    max_ms = trunc(tiempo_total_ms * 0.9)
    Enum.random(min_ms..max_ms)
  end

  defp calcular_delay(:dificil, tiempo_total_ms) do
    # Dificil: entre el 10% y el 40% del tiempo
    min_ms = trunc(tiempo_total_ms * 0.1)
    max_ms = trunc(tiempo_total_ms * 0.4)
    Enum.random(min_ms..max_ms)
  end
end
