defmodule Trivia.Receptor do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    {:ok, state}
  end

  def handle_info({:nueva_pregunta, _id, pregunta}, state) do
    IO.puts(
      "\n═══ Pregunta #{pregunta.numero} de #{pregunta.total} - #{pregunta.tema} - Nivel #{pregunta.nivel} ═══"
    )

    IO.puts(pregunta.enunciado)
    Enum.each(pregunta.opciones, fn op -> IO.puts("  #{op}") end)
    IO.puts("Tiempo: #{pregunta.tiempo} segundos")
    IO.write("\nRespuesta > ")
    {:noreply, state}
  end

  def handle_info({:ronda_finalizada, _id, resultado}, state) do
    IO.puts("\n--- Cierre de Ronda #{resultado.pregunta} ---")
    IO.puts("Respuesta correcta: #{resultado.respuesta_correcta}")

    Enum.each(resultado.puntajes, fn {jugador, total} ->
      ronda_pts = Map.get(resultado.puntos_ronda, jugador, 0)
      signo = if ronda_pts >= 0, do: "+", else: ""

      IO.puts(
        "  #{String.pad_trailing(to_string(jugador), 10)} #{signo}#{ronda_pts}   (total #{total})"
      )
    end)

    IO.write("\nRespuesta > ")
    {:noreply, state}
  end

  def handle_info({:partida_reiniciada, id}, state) do
    IO.puts(
      "\n La partida #{id} falló y se reinició sin su progreso. Agrega los bots y ejecuta start_game para jugar de nuevo."
    )

    IO.write("\nComando > ")
    {:noreply, state}
  end

  def handle_info({:partida_finalizada, resultado}, state) do
    IO.puts(
      "\n═══ Fin de la partida #{resultado.id} (#{resultado.tema}, nivel #{resultado.nivel}) ═══"
    )

    IO.puts(String.pad_trailing("#    Jugador", 12) <> "Puntaje")

    resultado.ranking
    |> Enum.with_index(1)
    |> Enum.each(fn {{jugador, puntos}, idx} ->
      IO.puts("#{idx}    #{String.pad_trailing(to_string(jugador), 10)} #{puntos}")
    end)

    ganadores_str = Enum.join(resultado.ganadores, ", ")
    IO.puts("\nGanador(es): #{ganadores_str}")
    IO.write("\nComando > ")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
