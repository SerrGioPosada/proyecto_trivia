defmodule Trivia.BancoPreguntasTest do
  use ExUnit.Case
  alias Trivia.BancoPreguntas

  test "calculo de reparto de preguntas respeta porcentajes por nivel" do
    # Jugador básico con 5 preguntas: 30% intermedio = trunc(1.5) = 1, avanzado = 0, básico = 4
    assert BancoPreguntas.calcular_reparto(:basico, 5) == {4, 1, 0}

    # Jugador avanzado con 10 preguntas: 30% intermedio = trunc(3.0) = 3, básico = 0, avanzado = 7
    assert BancoPreguntas.calcular_reparto(:avanzado, 10) == {0, 3, 7}
  end
end
