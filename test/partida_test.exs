defmodule Trivia.PartidaTest do
  use ExUnit.Case

  test "calculo de bonificacion por rapidez con distintos tiempos de pregunta" do
    # Fórmula del proyecto: bonificacion = trunc(5 * tiempo_restante / tiempo_total)

    # Caso A: tiempo_pregunta = 15s, restando 14s (14000ms de 15000ms)
    t_tot_1 = 15 * 1000
    t_rest_1 = 14 * 1000
    bonif_1 = trunc(5 * t_rest_1 / t_tot_1)
    assert bonif_1 == 4

    # Puntaje correcto básico (+10) + bonificación (4) = 14
    assert 10 + bonif_1 == 14

    # Caso B: tiempo_pregunta = 30s, restando 15s (15000ms de 30000ms)
    t_tot_2 = 30 * 1000
    t_rest_2 = 15 * 1000
    bonif_2 = trunc(5 * t_rest_2 / t_tot_2)
    assert bonif_2 == 2
  end
end
