defmodule Trivia.Bot do
  use GenServer

  def start_link(opciones) do
    GenServer.start_link(__MODULE__, opciones)
  end

  def init(opciones) do
    nombre = Keyword.fetch!(opciones, :nombre)
    dificultad = Keyword.fetch!(opciones, :dificultad)
    partida_pid = Keyword.fetch!(opciones, :partida_pid)

    {:ok, %{nombre: nombre, dificultad: dificultad, partida_pid: partida_pid}}
  end

  def handle_info({:pregunta_bot, id_partida, pregunta, respuesta_correcta}, estado) do
    # Decidir respuesta y tiempo de reacción
    {letra_respuesta, delay_ms} =
      decidir_respuesta(pregunta, respuesta_correcta, estado.dificultad)

    Process.send_after(self(), {:enviar_respuesta, id_partida, letra_respuesta}, delay_ms)

    {:noreply, estado}
  end

  def handle_info({:enviar_respuesta, _id_partida, letra}, estado) do
    Trivia.Partida.responder(estado.partida_pid, estado.nombre, letra)
    {:noreply, estado}
  end

  def handle_info({:ronda_finalizada, _id, _res}, estado), do: {:noreply, estado}
  def handle_info({:partida_finalizada, _res}, estado), do: {:noreply, estado}
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
