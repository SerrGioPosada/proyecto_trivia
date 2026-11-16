defmodule Trivia.BancoPreguntasTest do
  use ExUnit.Case
  alias Trivia.BancoPreguntas

  test "calculo de reparto de preguntas respeta porcentajes por nivel" do
    # Jugador básico con 5 preguntas: 30% intermedio = trunc(1.5) = 1, avanzado = 0, básico = 4
    assert BancoPreguntas.calcular_reparto(:basico, 5) == {4, 1, 0}

    # Jugador intermedio con 5 preguntas: 20% básico = 1, 20% avanzado = 1, intermedio = 3
    assert BancoPreguntas.calcular_reparto(:intermedio, 5) == {1, 3, 1}

    # Jugador avanzado con 10 preguntas: 30% intermedio = trunc(3.0) = 3, básico = 0, avanzado = 7
    assert BancoPreguntas.calcular_reparto(:avanzado, 10) == {0, 3, 7}
  end

  test "el reparto siempre suma el total de preguntas" do
    for nivel <- [:basico, :intermedio, :avanzado], total <- 1..20 do
      {b, i, a} = BancoPreguntas.calcular_reparto(nivel, total)
      assert b + i + a == total
    end
  end

  test "validar disponibilidad rechaza un tema que no existe en el banco" do
    assert {:error, mensaje} =
             BancoPreguntas.validar_disponibilidad_tema("tema_inexistente_xyz",
               basico: 1,
               intermedio: 0,
               avanzado: 0
             )

    assert mensaje =~ "no existe"
  end
end
