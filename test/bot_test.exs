defmodule Trivia.BotTest do
  use ExUnit.Case
  alias Trivia.Bot

  test "decision de un bot devuelve opcion valida (A-D) y retardo segun dificultad" do
    pregunta = %{
      nivel: :basico,
      tiempo: 15
    }

    respuesta_correcta = "B"

    # Dificultad fácil (40% a 90% de 15s -> 6000ms a 13500ms)
    {letra_facil, delay_facil} = Bot.decidir_respuesta(pregunta, respuesta_correcta, :facil)
    assert letra_facil in ["A", "B", "C", "D"]
    assert delay_facil >= 6000 and delay_facil <= 13500

    # Dificultad difícil (10% a 40% de 15s -> 1500ms a 6000ms)
    {letra_dificil, delay_dificil} = Bot.decidir_respuesta(pregunta, respuesta_correcta, :dificil)
    assert letra_dificil in ["A", "B", "C", "D"]
    assert delay_dificil >= 1500 and delay_dificil <= 6000
  end
end
